extends Node
## resources.gd — Resource calculation engine.
##
## === TICK FLOW ===
## 1. TickEngine.game_tick(delta) -> _on_tick(delta)
## 2. _update_bandwidth() -> modifier pipeline -> GameState.set_resource()
## 3. _update_influence(delta) -> modifier pipeline -> GameState.add_resource()
## 4. _update_detection_risk(delta) -> nonlinear scaling + pipeline -> clamp 0-100
## 5. _update_energy(delta) -> Tier 1+ only, hidden resource
## 6. resources_updated signal -> UI refreshes
##
## All calculations route through GameState.ModifierPipeline.apply().
## Upgrade modifiers are additive, event modifiers are multiplicative.
##
## Slow tick:
## 1. _check_unlock_conditions() -> GameState.check_unlock_objectives()
## 2. _check_dr_thresholds() -> warnings or soft reset

signal resources_updated
signal risk_warning(level: float)
signal soft_reset_triggered

const INFLUENCE_CAP: float = 1000000.0

func _ready() -> void:
	TickEngine.game_tick.connect(_on_tick)
	TickEngine.slow_tick.connect(_on_slow_tick)

func _on_tick(delta: float) -> void:
	if GameState.get_node_count() <= 0:
		return

	_update_bandwidth()
	_update_influence(delta)
	_update_detection_risk(delta)

	# Hidden energy resource (Tier 1+)
	if GameState.tier >= 1:
		_update_energy(delta)

	resources_updated.emit()

func _on_slow_tick() -> void:
	_check_unlock_conditions()
	_check_dr_thresholds()

# === BANDWIDTH ===
# BW = sum(node BW) * pipeline(1.0, bw_modifiers)

func _update_bandwidth() -> void:
	# Check node disable modifiers
	var disable_mods := GameState.get_modifiers_for_effect("nodes_disabled")
	if GameState.ModifierPipeline.apply_bool_or(disable_mods):
		GameState.set_resource("bandwidth", 0.0)
		GameState.set_per_second("bandwidth", 0.0)
		return

	var raw_bw: float = GameState.get_node_total_bw()

	# Apply BW multiplier modifiers (upgrades additive + events multiplicative)
	var bw_mods := GameState.get_modifiers_for_effect("bw_multiplier")
	var total_bw: float = GameState.ModifierPipeline.apply(raw_bw, bw_mods)
	total_bw = maxf(total_bw, 0.0)

	if is_nan(total_bw) or is_inf(total_bw):
		push_error("[Resources] BW produced NaN/Inf — clamping to 0")
		total_bw = 0.0

	GameState.set_resource("bandwidth", total_bw)
	GameState.set_per_second("bandwidth", total_bw)

# === INFLUENCE ===
# Influence/sec = BW * pipeline(base_efficiency, efficiency_modifiers)

func _update_influence(delta: float) -> void:
	var cfg := GameConfig.get_tier_config(GameState.tier)
	var base_eff: float = cfg.get("base_efficiency", 0.05)
	var bw: float = GameState.get_resource("bandwidth")

	# Apply efficiency modifiers through pipeline
	var eff_mods := GameState.get_modifiers_for_effect("efficiency")
	var total_eff: float = GameState.ModifierPipeline.apply(base_eff, eff_mods)

	var inf_per_sec: float = bw * total_eff
	inf_per_sec = maxf(inf_per_sec, 0.0)

	if is_nan(inf_per_sec) or is_inf(inf_per_sec):
		push_error("[Resources] Influence rate produced NaN/Inf — clamping to 0")
		inf_per_sec = 0.0

	GameState.set_per_second("influence", inf_per_sec)
	GameState.add_resource("influence", inf_per_sec * delta)

	# Safety cap
	if GameState.get_resource("influence") > INFLUENCE_CAP:
		GameState.set_resource("influence", INFLUENCE_CAP)

# === DETECTION RISK ===
# Nonlinear: dr_gain = pow(nodes, exponent) * gain_per_node * (1 - dr_reduction)
# Decay: passive_decay + dr_decay_bonus
# Clamped 0-100

func _update_detection_risk(delta: float) -> void:
	var cfg := GameConfig.get_tier_config(GameState.tier)
	var node_count: int = GameState.get_node_count()
	var gain_per_node: float = cfg.get("dr_gain_per_node", 0.02)
	var passive_decay: float = cfg.get("dr_passive_decay", 0.01)
	var dr_exponent: float = cfg.get("dr_scale_exponent", 1.12)

	# Nonlinear node scaling
	var base_dr_gain: float = pow(float(node_count), dr_exponent) * gain_per_node

	# Apply DR reduction modifiers
	var dr_red_mods := GameState.get_modifiers_for_effect("dr_reduction")
	var total_reduction: float = GameState.ModifierPipeline.apply(0.0, dr_red_mods)
	var reduction_factor: float = maxf(0.0, 1.0 - total_reduction)

	var dr_gain: float = base_dr_gain * reduction_factor
	dr_gain = maxf(dr_gain, 0.0)

	# Apply DR decay modifiers
	var decay_mods := GameState.get_modifiers_for_effect("dr_decay")
	var dr_decay: float = GameState.ModifierPipeline.apply(passive_decay, decay_mods)
	dr_decay = maxf(dr_decay, 0.0)

	var current_dr: float = GameState.get_resource("detection_risk")
	var new_dr: float = current_dr + (dr_gain - dr_decay) * delta
	new_dr = clampf(new_dr, 0.0, 100.0)
	GameState.set_resource("detection_risk", new_dr)

	var net_rate: float = dr_gain - dr_decay
	GameState.set_per_second("detection_risk", net_rate)

# === ENERGY (Tier 1+ hidden resource) ===

func _update_energy(delta: float) -> void:
	var node_count: int = GameState.get_node_count()
	var energy_per_node: float = 0.1  # Placeholder rate
	var energy_rate: float = float(node_count) * energy_per_node

	GameState.set_per_second("energy", energy_rate)
	GameState.add_resource("energy", energy_rate * delta)

# === THRESHOLD CHECKS ===

func _check_dr_thresholds() -> void:
	var cfg := GameConfig.get_tier_config(GameState.tier)
	var dr: float = GameState.get_resource("detection_risk")
	var danger: float = cfg.get("dr_danger_threshold", 85.0)
	var reset_at: float = cfg.get("dr_soft_reset_threshold", 100.0)

	if dr >= reset_at:
		soft_reset_triggered.emit()
		GameState.soft_reset_current_tier()
		return

	if dr >= 50.0:
		risk_warning.emit(dr)

func _check_unlock_conditions() -> void:
	if GameState.check_unlock_condition():
		var cfg := GameConfig.get_tier_config(GameState.tier)
		var reward: String = cfg.get("unlock_reward", "")
		if reward != "" and not GameState.has_unlock(reward):
			GameState.achieve_unlock(reward)

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
