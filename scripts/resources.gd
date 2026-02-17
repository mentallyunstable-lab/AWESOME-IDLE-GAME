extends Node
## resources.gd — Resource calculation engine.
## Connects to TickEngine, reads/writes GameState.
## Handles bandwidth generation, influence accumulation, and DR pressure.

signal resources_updated
signal risk_warning(level: float)
signal soft_reset_triggered

func _ready() -> void:
	TickEngine.game_tick.connect(_on_tick)
	TickEngine.slow_tick.connect(_on_slow_tick)

func _on_tick(delta: float) -> void:
	if GameState.get_node_count() <= 0:
		return

	_update_bandwidth()
	_update_influence(delta)
	_update_detection_risk(delta)
	resources_updated.emit()

func _on_slow_tick() -> void:
	_check_unlock_conditions()
	_check_dr_thresholds()

# === BANDWIDTH ===
# BW = sum(node BW) * (1 + bw_multiplier) * event_multiplier

func _update_bandwidth() -> void:
	if GameState.event_nodes_disabled:
		GameState.set_resource("bandwidth", 0.0)
		GameState.set_per_second("bandwidth", 0.0)
		return

	var raw_bw: float = GameState.get_node_total_bw()
	var total_bw: float = raw_bw * (1.0 + GameState.bw_multiplier) * GameState.event_bw_multiplier
	GameState.set_resource("bandwidth", total_bw)
	GameState.set_per_second("bandwidth", total_bw)

# === INFLUENCE ===
# Influence/sec = BW * (base_efficiency + efficiency_bonus)

func _update_influence(delta: float) -> void:
	var cfg := GameConfig.get_tier_config(GameState.tier)
	var base_eff: float = cfg.get("base_efficiency", 0.05)
	var bw: float = GameState.get_resource("bandwidth")
	var inf_per_sec: float = bw * (base_eff + GameState.efficiency_bonus)
	GameState.set_per_second("influence", inf_per_sec)
	GameState.add_resource("influence", inf_per_sec * delta)

# === DETECTION RISK ===
# DR += nodes * dr_gain_per_node * (1 - dr_reduction) per second
# DR -= (dr_passive_decay + dr_decay_bonus) per second
# Clamp 0-100

func _update_detection_risk(delta: float) -> void:
	var cfg := GameConfig.get_tier_config(GameState.tier)
	var node_count: int = GameState.get_node_count()
	var gain_per_node: float = cfg.get("dr_gain_per_node", 0.02)
	var passive_decay: float = cfg.get("dr_passive_decay", 0.01)

	# DR gain reduced by encryption upgrades
	var reduction_factor: float = maxf(0.0, 1.0 - GameState.dr_reduction)
	var dr_gain: float = node_count * gain_per_node * reduction_factor

	# DR decay boosted by stealth upgrades
	var dr_decay: float = passive_decay + GameState.dr_decay_bonus

	var current_dr: float = GameState.get_resource("detection_risk")
	var new_dr: float = current_dr + (dr_gain - dr_decay) * delta
	new_dr = clampf(new_dr, 0.0, 100.0)
	GameState.set_resource("detection_risk", new_dr)

	# Per-second rate for display
	var net_rate: float = dr_gain - dr_decay
	GameState.set_per_second("detection_risk", net_rate)

# === THRESHOLD CHECKS ===

func _check_dr_thresholds() -> void:
	var cfg := GameConfig.get_tier_config(GameState.tier)
	var dr: float = GameState.get_resource("detection_risk")
	var danger: float = cfg.get("dr_danger_threshold", 85.0)
	var reset_at: float = cfg.get("dr_soft_reset_threshold", 100.0)

	if dr >= reset_at:
		soft_reset_triggered.emit()
		GameState.soft_reset_tier0()
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
