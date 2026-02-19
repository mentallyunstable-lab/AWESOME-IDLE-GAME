extends Node
## resources.gd — Resource calculation engine.
##
## === TICK FLOW ===
## 1. TickEngine.game_tick(delta) -> _on_tick(delta)
## 2. _update_bandwidth() -> modifier pipeline -> GameState.set_resource()
## 3. _update_influence(delta) -> global efficiency + maintenance -> GameState
## 4. _update_detection_risk(delta) -> DR bands + momentum -> clamp 0-100
## 5. _update_energy(delta) -> Tier 1+ only
## 6. _update_degradation(delta) -> node failure system
## 7. resources_updated signal -> UI refreshes
##
## All calculations route through GameState.pipeline_apply().
##
## Slow tick:
## 1. _check_unlock_conditions() -> GameState.check_unlock_objectives()
## 2. _check_dr_thresholds() -> warnings or soft reset

signal resources_updated
signal risk_warning(level: float)
signal soft_reset_triggered

const INFLUENCE_CAP: float = 1000000.0

# === STRESS TEST STATE (TASK 17) ===
var _stress_test_active: bool = false
var _stress_test_elapsed: float = 0.0
var _stress_test_max_dr: float = 0.0
var _stress_test_max_nodes: int = 0
var _stress_test_errors: Array = []
var _stress_test_duration: float = 7200.0  # 2 hours simulated

func _ready() -> void:
	TickEngine.game_tick.connect(_on_tick)
	TickEngine.slow_tick.connect(_on_slow_tick)

func _on_tick(delta: float) -> void:
	if GameState.get_node_count() <= 0:
		return

	GameState.advance_game_clock(delta)
	GameState.update_district_loads()

	_update_bandwidth()
	_update_influence(delta)

	# Constraint dispatch loop (Phase 2 TASK 1) — iterate by priority order
	for constraint: Dictionary in GameState.get_all_constraints():
		if not constraint.get("active", false):
			continue
		_dispatch_constraint_update(constraint["id"], delta)

	_update_degradation(delta)

	# DR momentum tracking (TASK 7)
	GameState.update_dr_momentum(GameState.get_game_clock())

	# Sync constraint values back (Phase 2 TASK 1)
	GameState.update_constraints(delta)

	# Equilibrium detection (Phase 2 TASK 11)
	GameState.update_equilibrium(delta)

	# Stability logger during stress test (Phase 2 TASK 10)
	if _stress_test_active:
		GameState.update_stability_logger(delta)
		_stress_test_tick(delta)

	resources_updated.emit()

# === CONSTRAINT DISPATCH (Phase 2 TASK 1) ===

func _dispatch_constraint_update(constraint_id: String, delta: float) -> void:
	match constraint_id:
		"detection_risk":
			_update_detection_risk(delta)
		"energy":
			if GameState.tier >= 1:
				_update_energy(delta)
		"thermal_load":
			GameState.update_thermal_load(delta)
		_:
			# Unknown constraint — no-op (safe stub pattern)
			pass

func _on_slow_tick() -> void:
	_check_unlock_conditions()
	_check_dr_thresholds()

# === BANDWIDTH ===

func _update_bandwidth() -> void:
	var disable_mods := GameState.get_modifiers_for_effect("nodes_disabled")
	if GameState.pipeline_apply_bool_or(disable_mods):
		GameState.set_resource("bandwidth", 0.0)
		GameState.set_per_second("bandwidth", 0.0)
		return

	var raw_bw: float = GameState.get_node_total_bw()

	var bw_mods := GameState.get_modifiers_for_effect("bw_multiplier")
	var total_bw: float = GameState.pipeline_apply(raw_bw, bw_mods)
	total_bw = maxf(total_bw, 0.0)

	# Safe value clamp (Phase 2 TASK 4)
	total_bw = GameState.safe_value(total_bw, 0.0, 1000000.0)
	if _stress_test_active and (is_nan(total_bw) or is_inf(total_bw)):
		_stress_test_errors.append("BW NaN/Inf at t=%.1f" % _stress_test_elapsed)

	GameState.set_resource("bandwidth", total_bw)
	GameState.set_per_second("bandwidth", total_bw)

# === INFLUENCE ===
# Influence/sec = BW * efficiency * global_efficiency - maintenance

func _update_influence(delta: float) -> void:
	var cfg := GameConfig.get_tier_config(GameState.tier)
	var base_eff: float = cfg.get("base_efficiency", 0.05)
	var bw: float = GameState.get_resource("bandwidth")

	var eff_mods := GameState.get_modifiers_for_effect("efficiency")
	var total_eff: float = GameState.pipeline_apply(base_eff, eff_mods)

	# Global efficiency curve (TASK 1)
	var global_eff: float = GameState.calculate_global_efficiency()

	var inf_per_sec: float = bw * total_eff * global_eff
	inf_per_sec = maxf(inf_per_sec, 0.0)

	# Maintenance drain (TASK 3)
	var maintenance: float = GameState.calculate_maintenance_drain()
	inf_per_sec -= maintenance

	# If influence rate goes negative, trigger DR spike (TASK 3)
	if inf_per_sec < 0.0:
		var dr_spike: float = GameConfig.MAINTENANCE_DR_SPIKE_RATE * delta
		GameState.add_resource("detection_risk", dr_spike)

	# Safe value clamp (Phase 2 TASK 4)
	inf_per_sec = GameState.safe_value(inf_per_sec, -1000000.0, 1000000.0)
	if _stress_test_active and (is_nan(inf_per_sec) or is_inf(inf_per_sec)):
		_stress_test_errors.append("Inf NaN/Inf at t=%.1f" % _stress_test_elapsed)

	GameState.set_per_second("influence", inf_per_sec)
	GameState.add_resource("influence", inf_per_sec * delta)

	# Clamp influence >= 0 (TASK 3)
	if GameState.get_resource("influence") < 0.0:
		GameState.set_resource("influence", 0.0)

	# Safety cap
	if GameState.get_resource("influence") > INFLUENCE_CAP:
		GameState.set_resource("influence", INFLUENCE_CAP)

# === DETECTION RISK ===
# Nonlinear: dr_gain = pow(nodes, exponent) * gain_per_node * (1 - dr_reduction)
# DR bands affect behavior (TASK 5)
# DR momentum modifies gain (TASK 7)

func _update_detection_risk(delta: float) -> void:
	var cfg := GameConfig.get_tier_config(GameState.tier)
	var node_count: int = GameState.get_node_count()
	var gain_per_node: float = cfg.get("dr_gain_per_node", 0.02)
	var passive_decay: float = cfg.get("dr_passive_decay", 0.01)
	var dr_exponent: float = cfg.get("dr_scale_exponent", 1.12)

	var base_dr_gain: float = pow(float(node_count), dr_exponent) * gain_per_node

	# DR reduction from upgrades
	var dr_red_mods := GameState.get_modifiers_for_effect("dr_reduction")
	var total_reduction: float = GameState.pipeline_apply(0.0, dr_red_mods)
	var reduction_factor: float = maxf(0.0, 1.0 - total_reduction)

	var dr_gain: float = base_dr_gain * reduction_factor

	# Apply DR gain modifiers (silent mode, doctrine, momentum via pipeline)
	var dr_gain_mods := GameState.get_modifiers_for_effect("dr_gain")
	if dr_gain_mods.size() > 0:
		dr_gain = GameState.pipeline_apply(dr_gain, dr_gain_mods)

	# Degraded nodes add DR (TASK 4)
	var degraded_count: int = GameState.get_degraded_node_count()
	dr_gain += float(degraded_count) * GameConfig.DEGRADATION_DR_MODIFIER

	dr_gain = maxf(dr_gain, 0.0)

	# DR decay
	var decay_mods := GameState.get_modifiers_for_effect("dr_decay")
	var dr_decay: float = GameState.pipeline_apply(passive_decay, decay_mods)

	# DR momentum decay bonus (TASK 7)
	if GameState.dr_momentum_bonus < 0.0:
		dr_decay += absf(GameState.dr_momentum_bonus)

	dr_decay = maxf(dr_decay, 0.0)

	var current_dr: float = GameState.get_resource("detection_risk")
	var new_dr: float = current_dr + (dr_gain - dr_decay) * delta
	new_dr = clampf(new_dr, 0.0, 100.0)
	GameState.set_resource("detection_risk", new_dr)

	var net_rate: float = dr_gain - dr_decay
	GameState.set_per_second("detection_risk", net_rate)

# === DEGRADATION (TASK 4) ===

func _update_degradation(delta: float) -> void:
	GameState.tick_degradation(delta)

# === ENERGY (Tier 1+ resource) ===

func _update_energy(delta: float) -> void:
	var cfg := GameConfig.get_tier_config(GameState.tier)
	var node_count: int = GameState.get_node_count()
	var base_gen: float = cfg.get("energy_base_gen", 5.0)
	var drain_per_node: float = cfg.get("energy_per_node_drain", 0.3)

	# Generation
	var gen_mods := GameState.get_modifiers_for_effect("energy_gen")
	var total_gen: float = GameState.pipeline_apply(base_gen, gen_mods)
	if GameState.energy_gen_multiplier_bonus > 0.0:
		total_gen *= (1.0 + GameState.energy_gen_multiplier_bonus)

	# Drain
	var drain_mods := GameState.get_modifiers_for_effect("energy_drain")
	var total_drain_reduction: float = GameState.pipeline_apply(0.0, drain_mods)
	var effective_drain: float = drain_per_node * float(node_count) * maxf(0.0, 1.0 - total_drain_reduction)

	# District load energy multiplier (TASK 2)
	var districts := GameState.get_districts()
	for dist_id: String in districts.keys():
		var dist_mult: float = GameState.get_district_energy_multiplier(dist_id)
		var dist_spec_mult: float = GameState.get_district_spec_modifier(dist_id, "energy_modifier")
		var dist_node_count: int = GameState.get_district_node_count(dist_id)
		effective_drain += drain_per_node * float(dist_node_count) * (dist_mult * dist_spec_mult - 1.0)

	var energy_rate: float = total_gen - effective_drain

	# Overload check
	var prev_overload: bool = GameState.energy_overload
	GameState.energy_overload = energy_rate < 0.0

	GameState.set_per_second("energy", energy_rate)
	GameState.add_resource("energy", energy_rate * delta)

	if GameState.get_resource("energy") < 0.0:
		GameState.set_resource("energy", 0.0)

	GameState.update_stability(delta, energy_rate)

# === THRESHOLD CHECKS ===

func _check_dr_thresholds() -> void:
	var cfg := GameConfig.get_tier_config(GameState.tier)
	var dr: float = GameState.get_resource("detection_risk")
	var danger: float = cfg.get("dr_danger_threshold", 85.0)
	var reset_at: float = cfg.get("dr_soft_reset_threshold", 100.0)

	if dr >= reset_at:
		soft_reset_triggered.emit()
		# Route through unified collapse (Phase 2 TASK 3)
		GameState.trigger_collapse("dr_overflow", "current_tier")
		GameState.set_resource("bandwidth", 0.0)
		if GameState.resources.has("energy"):
			GameState.set_resource("energy", 0.0)
		GameState.energy_overload = false
		return

	if dr >= 50.0:
		risk_warning.emit(dr)

func _check_unlock_conditions() -> void:
	if GameState.check_unlock_condition():
		var cfg := GameConfig.get_tier_config(GameState.tier)
		var reward: String = cfg.get("unlock_reward", "")
		if reward != "" and not GameState.has_unlock(reward):
			GameState.achieve_unlock(reward)

# === TIME-TO-COLLAPSE ESTIMATOR (TASK 16) ===

func get_time_to_collapse() -> float:
	var dr: float = GameState.get_resource("detection_risk")
	var dr_rate: float = GameState.get_per_second("detection_risk")
	if dr_rate <= 0.0:
		return -1.0  # Not approaching collapse
	return (100.0 - dr) / dr_rate

# === STRESS TEST (TASK 17) ===

func start_stress_test() -> void:
	_stress_test_active = true
	_stress_test_elapsed = 0.0
	_stress_test_max_dr = 0.0
	_stress_test_max_nodes = 0
	_stress_test_errors.clear()
	# Clear stability log for fresh test (Phase 2 TASK 10)
	GameState.clear_stability_log()
	TickEngine.set_speed(10.0)
	print("[StressTest] === 2-HOUR SIMULATION STARTED (10x speed) ===")

func _stress_test_tick(delta: float) -> void:
	_stress_test_elapsed += delta

	var dr: float = GameState.get_resource("detection_risk")
	var nc: int = GameState.get_node_count()
	var inf: float = GameState.get_resource("influence")

	if dr > _stress_test_max_dr:
		_stress_test_max_dr = dr
	if nc > _stress_test_max_nodes:
		_stress_test_max_nodes = nc

	# Check for NaN/negative
	if is_nan(inf) or is_nan(dr):
		_stress_test_errors.append("NaN detected at t=%.1f" % _stress_test_elapsed)
		_stop_stress_test()
		return

	if inf < -0.01:
		_stress_test_errors.append("Negative influence: %.2f at t=%.1f" % [inf, _stress_test_elapsed])

	if _stress_test_elapsed >= _stress_test_duration:
		_stop_stress_test()

func _stop_stress_test() -> void:
	_stress_test_active = false
	TickEngine.set_speed(1.0)
	print("[StressTest] === 2-HOUR SIMULATION COMPLETE ===")
	print("  Simulated time: %.0f seconds" % _stress_test_elapsed)
	print("  Max DR: %.2f" % _stress_test_max_dr)
	print("  Max Nodes: %d" % _stress_test_max_nodes)
	print("  Stability snapshots: %d" % GameState.get_stability_log().size())
	print("  Equilibrium reached: %s" % ("YES" if GameState.is_in_equilibrium() else "NO"))
	print("  Errors: %d" % _stress_test_errors.size())
	for err: String in _stress_test_errors:
		print("    - %s" % err)
	if _stress_test_errors.size() == 0:
		print("  RESULT: PASS")
	else:
		print("  RESULT: FAIL")

func is_stress_testing() -> bool:
	return _stress_test_active

func get_stress_test_progress() -> float:
	if not _stress_test_active:
		return 0.0
	return _stress_test_elapsed / _stress_test_duration

# === DISPLAY HELPERS ===

func get_bandwidth_display() -> String:
	return "%.1f" % GameState.get_resource("bandwidth")

func get_influence_display() -> String:
	return "%.1f" % GameState.get_resource("influence")

func get_influence_rate() -> float:
	return GameState.get_per_second("influence")

func get_detection_risk_display() -> String:
	return "%.1f%%" % GameState.get_resource("detection_risk")

func get_dr_rate_display() -> String:
	var rate: float = GameState.get_per_second("detection_risk")
	if rate >= 0.0:
		return "+%.2f/s" % rate
	return "%.2f/s" % rate

func get_node_count() -> int:
	return GameState.get_node_count()

func get_max_nodes() -> int:
	return GameState.get_max_nodes()
