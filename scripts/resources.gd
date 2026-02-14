extends Node

# === Core Resources ===
var bandwidth: float = 0.0
var influence: float = 0.0
var detection_risk: float = 0.0
var encryption_level: float = 1.0
var node_count: int = 0

# === Node Stats ===
var node_base_output: float = 1.5
var risk_per_node: float = 3.0

# === Multipliers ===
var infra_multiplier: float = 0.0
var efficiency_multiplier: float = 0.1

# === Map Bonuses (set by MapController) ===
var map_bw_bonus: float = 0.0
var map_dr_bonus: float = 0.0
var map_inf_bonus: float = 0.0

# === Thresholds ===
var dr_warning_threshold: float = 50.0

# === DR Event State ===
var bw_penalty_active: bool = false
var bw_penalty_multiplier: float = 1.0
var dr_alert_active: bool = false

# === Signals ===
signal resources_updated
signal risk_warning(level: float)
signal node_purchased(total: int)
signal dr_event_triggered(event_type: String)
signal dr_event_cleared(event_type: String)
signal stat_changed(stat_name: String)

func _ready() -> void:
	recalculate()

func add_node() -> void:
	node_count += 1
	recalculate()
	node_purchased.emit(node_count)

func recalculate() -> void:
	# Bandwidth = TotalNodes × NodeBase × (1 + InfraMultiplier + MapBwBonus) × PenaltyMultiplier
	bandwidth = node_count * node_base_output * (1.0 + infra_multiplier + map_bw_bonus) * bw_penalty_multiplier

	# Detection Risk = Nodes × RiskPerNode × (1 - SecurityReduction + MapDrBonus)
	var dr_reduction: float = 0.0
	if is_instance_valid(Upgrades):
		dr_reduction = Upgrades.get_dr_reduction()
	var dr_factor: float = maxf(0.0, 1.0 - dr_reduction + map_dr_bonus)
	detection_risk = node_count * risk_per_node * dr_factor

	# Clamp DR to 0-100 range
	detection_risk = clampf(detection_risk, 0.0, 100.0)

	# DR events
	_check_dr_events()

	resources_updated.emit()

	if detection_risk >= dr_warning_threshold:
		risk_warning.emit(detection_risk)

func _check_dr_events() -> void:
	# DR > 60 → Node slowdown (-10% BW for 5s)
	if detection_risk > 60.0 and not bw_penalty_active:
		bw_penalty_active = true
		bw_penalty_multiplier = 0.9
		dr_event_triggered.emit("slowdown")
		# Recalc BW with penalty (avoid recursion via flag check above)
		bandwidth = node_count * node_base_output * (1.0 + infra_multiplier + map_bw_bonus) * bw_penalty_multiplier

		var timer := get_tree().create_timer(5.0)
		timer.timeout.connect(_clear_bw_penalty)

	# DR > 80 → Alert popup
	if detection_risk > 80.0 and not dr_alert_active:
		dr_alert_active = true
		dr_event_triggered.emit("alert")

func _clear_bw_penalty() -> void:
	bw_penalty_active = false
	bw_penalty_multiplier = 1.0
	dr_event_cleared.emit("slowdown")
	recalculate()

func _process(delta: float) -> void:
	if node_count <= 0:
		return

	# Influence/sec = Bandwidth × (EfficiencyMultiplier + MapInfBonus)
	var influence_per_sec: float = bandwidth * (efficiency_multiplier + map_inf_bonus)
	influence += influence_per_sec * delta

	resources_updated.emit()

# Clear alert state when DR drops
func clear_dr_alert() -> void:
	dr_alert_active = false
	dr_event_cleared.emit("alert")

func get_bandwidth_display() -> String:
	return "%.1f" % bandwidth

func get_influence_display() -> String:
	return "%.1f" % influence

func get_detection_risk_display() -> String:
	return "%.1f%%" % detection_risk

func get_encryption_display() -> String:
	return "Lv. %d" % int(encryption_level)

func get_influence_rate() -> float:
	return bandwidth * (efficiency_multiplier + map_inf_bonus)
