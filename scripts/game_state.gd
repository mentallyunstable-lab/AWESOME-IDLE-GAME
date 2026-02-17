extends Node
## game_state.gd — Centralized game state.
## All game data flows through here. Systems read/write via this singleton.
## Future tiers inject their resources and state here.

signal state_changed
signal resource_changed(resource_id: String)
signal tier_changed(new_tier: int)
signal unlock_achieved(unlock_id: String)

# === CORE STATE ===
var tier: int = 0

# === UNIVERSAL RESOURCE REGISTRY ===
# { "bandwidth": { "value": 0.0, "per_second": 0.0 }, ... }
var resources: Dictionary = {}

# === NODE STATE ===
var nodes: Array = []  # Array of node dictionaries: { "level": 1 }
var max_nodes_bonus: int = 0  # From upgrades

# === UPGRADE STATE ===
# { "upgrade_id": level (int) }
var upgrade_levels: Dictionary = {}

# === COMPUTED MODIFIERS (recalculated from upgrades) ===
var bw_multiplier: float = 0.0
var node_base_bonus: float = 0.0
var efficiency_bonus: float = 0.0
var dr_reduction: float = 0.0
var dr_decay_bonus: float = 0.0

# === EVENT MODIFIERS (applied by event system) ===
var event_bw_multiplier: float = 1.0
var event_nodes_disabled: bool = false

# === CONSTRAINTS ===
var constraints: Dictionary = {}

# === AUTOMATION (stub) ===
var automation: Dictionary = {}

# === PRESTIGE (stub) ===
var prestige: Dictionary = {
	"tier0": {
		"points": 0,
		"bonuses": [],
	},
}

# === PROGRESSION ===
var progression: Dictionary = {
	"unlocks": {},  # { "unlock_id": true }
	"tier1_preview_shown": false,
}

# === ACTIVE EVENTS ===
var active_events: Array = []

func _ready() -> void:
	_init_tier(tier)

func _init_tier(t: int) -> void:
	var cfg := GameConfig.get_tier_config(t)
	if cfg.is_empty():
		return

	# Register resources for this tier
	var tier_resources: Array = cfg.get("resources", [])
	for res_id: String in tier_resources:
		if not resources.has(res_id):
			var defaults: Dictionary = GameConfig.RESOURCE_DEFAULTS.get(res_id, {})
			resources[res_id] = {
				"value": defaults.get("value", 0.0),
				"per_second": defaults.get("per_second", 0.0),
			}

	# Init upgrade levels
	for upgrade_def: Dictionary in GameConfig.TIER0_UPGRADES:
		var uid: String = upgrade_def["id"]
		if not upgrade_levels.has(uid):
			upgrade_levels[uid] = 0

# === RESOURCE ACCESS ===

func get_resource(id: String) -> float:
	if resources.has(id):
		return resources[id]["value"]
	return 0.0

func set_resource(id: String, value: float) -> void:
	if resources.has(id):
		resources[id]["value"] = value
		resource_changed.emit(id)

func add_resource(id: String, amount: float) -> void:
	if resources.has(id):
		resources[id]["value"] += amount

func get_per_second(id: String) -> float:
	if resources.has(id):
		return resources[id].get("per_second", 0.0)
	return 0.0

func set_per_second(id: String, rate: float) -> void:
	if resources.has(id):
		resources[id]["per_second"] = rate

# === NODE ACCESS ===

func get_node_count() -> int:
	return nodes.size()

func get_max_nodes() -> int:
	var cfg := GameConfig.get_tier_config(tier)
	return cfg.get("max_nodes", 20) + max_nodes_bonus

func can_deploy_node() -> bool:
	return get_node_count() < get_max_nodes() and not event_nodes_disabled

func deploy_node() -> bool:
	if not can_deploy_node():
		return false
	nodes.append({"level": 1})
	state_changed.emit()
	return true

func remove_node(index: int) -> bool:
	if index < 0 or index >= nodes.size():
		return false
	nodes.remove_at(index)
	state_changed.emit()
	return true

func upgrade_node(index: int) -> bool:
	if index < 0 or index >= nodes.size():
		return false
	var node_data: Dictionary = nodes[index]
	var level: int = node_data.get("level", 1)
	if level >= GameConfig.NODE_UPGRADE_MAX_LEVEL:
		return false
	var cost := GameConfig.get_node_upgrade_cost(level)
	if get_resource("influence") < cost:
		return false
	add_resource("influence", -cost)
	node_data["level"] = level + 1
	state_changed.emit()
	return true

func get_node_total_bw() -> float:
	var cfg := GameConfig.get_tier_config(tier)
	var base_bw: float = cfg.get("node_base_bw", 1.0) + node_base_bonus
	var total: float = 0.0
	for node_data: Dictionary in nodes:
		var level: int = node_data.get("level", 1)
		var level_mult: float = 1.0 + (level - 1) * GameConfig.NODE_UPGRADE_BW_BONUS
		total += base_bw * level_mult
	return total

# === UPGRADE ACCESS ===

func get_upgrade_level(upgrade_id: String) -> int:
	return upgrade_levels.get(upgrade_id, 0)

func try_purchase_upgrade(upgrade_id: String) -> bool:
	var upgrade_def := _find_upgrade_def(upgrade_id)
	if upgrade_def.is_empty():
		return false

	var level: int = get_upgrade_level(upgrade_id)
	var max_level: int = upgrade_def.get("max_level", 5)
	if level >= max_level:
		return false

	var unlock_inf: float = upgrade_def.get("unlock_influence", 0.0)
	if unlock_inf > 0.0 and get_resource("influence") < unlock_inf:
		return false

	var cost := GameConfig.get_upgrade_cost(
		upgrade_def.get("base_cost", 100.0),
		upgrade_def.get("cost_scaling", 1.4),
		level
	)
	if get_resource("influence") < cost:
		return false

	add_resource("influence", -cost)
	upgrade_levels[upgrade_id] = level + 1
	_recalculate_modifiers()
	state_changed.emit()
	return true

func _recalculate_modifiers() -> void:
	bw_multiplier = 0.0
	node_base_bonus = 0.0
	efficiency_bonus = 0.0
	dr_reduction = 0.0
	dr_decay_bonus = 0.0
	max_nodes_bonus = 0

	for upgrade_def: Dictionary in GameConfig.TIER0_UPGRADES:
		var uid: String = upgrade_def["id"]
		var level: int = get_upgrade_level(uid)
		if level <= 0:
			continue
		var effect: float = level * upgrade_def.get("multiplier", 0.0)
		var effect_type: String = upgrade_def.get("effect_type", "")

		match effect_type:
			"bw_multiplier":
				bw_multiplier += effect
			"node_base_bonus":
				node_base_bonus += effect
			"efficiency_bonus":
				efficiency_bonus += effect
			"dr_reduction":
				dr_reduction += effect
			"dr_decay_bonus":
				dr_decay_bonus += effect
			"max_nodes_bonus":
				max_nodes_bonus += int(effect)

func _find_upgrade_def(upgrade_id: String) -> Dictionary:
	for upgrade_def: Dictionary in GameConfig.TIER0_UPGRADES:
		if upgrade_def["id"] == upgrade_id:
			return upgrade_def
	return {}

# === UNLOCK CHECKS ===

func check_unlock_condition() -> bool:
	var cfg := GameConfig.get_tier_config(tier)
	var condition: Dictionary = cfg.get("unlock_condition", {})
	if condition.is_empty():
		return false

	var inf_min: float = condition.get("influence_min", 0.0)
	var dr_below: float = condition.get("detection_risk_below", 100.0)

	return get_resource("influence") >= inf_min and get_resource("detection_risk") < dr_below

func achieve_unlock(unlock_id: String) -> void:
	if not progression["unlocks"].has(unlock_id):
		progression["unlocks"][unlock_id] = true
		unlock_achieved.emit(unlock_id)

func has_unlock(unlock_id: String) -> bool:
	return progression["unlocks"].has(unlock_id)

# === SOFT RESET (Tier 0 DR = 100) ===

func soft_reset_tier0() -> void:
	# Reset resources but keep upgrades and unlocks
	set_resource("bandwidth", 0.0)
	set_resource("influence", get_resource("influence") * 0.5)  # Lose half influence
	set_resource("detection_risk", 0.0)
	nodes.clear()
	event_bw_multiplier = 1.0
	event_nodes_disabled = false
	active_events.clear()
	state_changed.emit()
