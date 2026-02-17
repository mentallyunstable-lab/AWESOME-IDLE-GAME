extends Node
## game_state.gd — Centralized game state.
##
## === STATE ARCHITECTURE ===
## All game data flows through this singleton. No other script stores state.
##
## Resource registry:
##   resources["id"] = {value, per_second}
##   Populated by inject_tier_features(tier) from GameConfig.TIER_DEFS
##
## Modifier pipeline:
##   ModifierPipeline.apply(base, modifiers) — universal calculation system
##   Modifiers: {type: "mult"/"add", value: float, source: String}
##   get_modifiers_for_effect(id) collects all active modifiers for an effect
##
## Tier injection:
##   inject_tier_features(tier) registers resources, upgrades, constraints
##
## Objective system:
##   check_unlock_objectives() evaluates all objectives from tier config

signal state_changed
signal resource_changed(resource_id: String)
signal tier_changed(new_tier: int)
signal unlock_achieved(unlock_id: String)

# === MODIFIER PIPELINE ===

class ModifierPipeline:
	## Apply a stack of modifiers to a base value.
	## Additive modifiers are summed first, then multiplicative modifiers are applied.
	## modifiers: Array of {type: "mult"/"add", value: float}
	static func apply(base: float, modifiers: Array) -> float:
		var add_total: float = 0.0
		var mult_total: float = 1.0

		for mod: Dictionary in modifiers:
			var mod_type: String = mod.get("type", "add")
			var mod_value: float = mod.get("value", 0.0)

			match mod_type:
				"mult":
					mult_total *= mod_value
				"add":
					add_total += mod_value

		return (base + add_total) * mult_total

	## Boolean OR for disable flags.
	static func apply_bool_or(modifiers: Array) -> bool:
		for mod: Dictionary in modifiers:
			if mod.get("value", false):
				return true
		return false

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

# === ENERGY MODIFIERS (Tier 1+) ===
var energy_gen_bonus: float = 0.0
var energy_drain_reduction: float = 0.0
var energy_gen_multiplier_bonus: float = 0.0
var overload_reduction: float = 0.0

# === ENERGY OVERLOAD STATE ===
var energy_overload: bool = false

# === STABILITY TRACKING ===
var stability_timer: float = 0.0

# === EVENT MODIFIERS (applied by event system) ===
var event_bw_multiplier: float = 1.0
var event_nodes_disabled: bool = false
var event_energy_gen_multiplier: float = 1.0
var event_district_shutdown: String = ""

# === CONSTRAINTS ===
var constraints: Dictionary = {}

# === AUTOMATION (stub) ===
var automation: Dictionary = {}

# === PRESTIGE (tier-indexed) ===
var prestige: Dictionary = {
	0: {"points": 0, "bonuses": []},
	1: {"points": 0, "bonuses": []},
	2: {"points": 0, "bonuses": []},
	3: {"points": 0, "bonuses": []},
	4: {"points": 0, "bonuses": []},
	5: {"points": 0, "bonuses": []},
	6: {"points": 0, "bonuses": []},
	7: {"points": 0, "bonuses": []},
}

# === PROGRESSION ===
var progression: Dictionary = {
	"unlocks": {},  # { "unlock_id": true }
	"tier1_preview_shown": false,
}

# === ACTIVE EVENTS ===
var active_events: Array = []

func _ready() -> void:
	inject_tier_features(tier)

# === TIER INJECTION ===

func inject_tier_features(t: int) -> void:
	var cfg := GameConfig.get_tier_config(t)
	if cfg.is_empty():
		return

	# 1. Register resources for this tier
	var tier_resources: Array = cfg.get("resources", [])
	for res_id: String in tier_resources:
		if not resources.has(res_id):
			var defaults: Dictionary = GameConfig.RESOURCE_DEFAULTS.get(res_id, {})
			resources[res_id] = {
				"value": defaults.get("value", 0.0),
				"per_second": defaults.get("per_second", 0.0),
			}
			print("[TierInjection] Registered resource: %s" % res_id)

	# 2. Initialize upgrade levels for tier
	for upgrade_def: Dictionary in GameConfig.get_upgrades_for_tier(t):
		var uid: String = upgrade_def["id"]
		if not upgrade_levels.has(uid):
			upgrade_levels[uid] = 0

	# 3. Apply tier constraints
	var tier_constraints: Dictionary = cfg.get("constraints", {})
	for key: String in tier_constraints.keys():
		constraints[key] = tier_constraints[key]

	# 4. Log injection summary
	print("[TierInjection] Tier %d '%s' loaded: %d resources, %d upgrades, %d events" % [
		t, cfg.get("name", "Unknown"),
		tier_resources.size(),
		GameConfig.get_upgrades_for_tier(t).size(),
		GameConfig.get_events_for_tier(t).size(),
	])

# === MODIFIER COLLECTION ===

func get_modifiers_for_effect(effect_id: String) -> Array:
	var mods: Array = []

	# Upgrade modifiers (additive bonuses)
	match effect_id:
		"bw_multiplier":
			if bw_multiplier != 0.0:
				mods.append({"type": "add", "value": bw_multiplier, "source": "upgrades"})
		"node_base":
			if node_base_bonus != 0.0:
				mods.append({"type": "add", "value": node_base_bonus, "source": "upgrades"})
		"efficiency":
			if efficiency_bonus != 0.0:
				mods.append({"type": "add", "value": efficiency_bonus, "source": "upgrades"})
		"dr_reduction":
			if dr_reduction != 0.0:
				mods.append({"type": "add", "value": dr_reduction, "source": "upgrades"})
		"dr_decay":
			if dr_decay_bonus != 0.0:
				mods.append({"type": "add", "value": dr_decay_bonus, "source": "upgrades"})

	# Energy modifiers (Tier 1+)
	match effect_id:
		"energy_gen":
			if energy_gen_bonus != 0.0:
				mods.append({"type": "add", "value": energy_gen_bonus, "source": "upgrades"})
			if event_energy_gen_multiplier != 1.0:
				mods.append({"type": "mult", "value": event_energy_gen_multiplier, "source": "events"})
		"energy_drain":
			if energy_drain_reduction != 0.0:
				mods.append({"type": "add", "value": energy_drain_reduction, "source": "upgrades"})
		"overload":
			if overload_reduction != 0.0:
				mods.append({"type": "add", "value": overload_reduction, "source": "upgrades"})

	# Event modifiers (multiplicative)
	if effect_id == "bw_multiplier" and event_bw_multiplier != 1.0:
		mods.append({"type": "mult", "value": event_bw_multiplier, "source": "events"})

	# Node disable flag
	if effect_id == "nodes_disabled":
		mods.append({"type": "bool", "value": event_nodes_disabled, "source": "events"})

	return mods

func debug_print_modifiers(effect_id: String) -> void:
	var mods := get_modifiers_for_effect(effect_id)
	print("[ModifierDebug] %s: %d modifiers" % [effect_id, mods.size()])
	for mod: Dictionary in mods:
		print("  - %s: %s (from %s)" % [mod.get("type", "?"), str(mod.get("value", 0)), mod.get("source", "?")])

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

func can_deploy_node(district_id: String = "") -> bool:
	if event_nodes_disabled:
		return false
	if get_node_count() >= get_max_nodes():
		return false
	# District cap check (Tier 1+)
	if district_id != "":
		var cfg := GameConfig.get_tier_config(tier)
		var districts: Dictionary = cfg.get("districts", {})
		if districts.has(district_id):
			var district_cap: int = districts[district_id].get("cap", 0)
			if get_district_node_count(district_id) >= district_cap:
				return false
		# Check if district is shutdown by event
		if event_district_shutdown == district_id:
			return false
	return true

func deploy_node(district_id: String = "") -> bool:
	if not can_deploy_node(district_id):
		return false
	var node_data: Dictionary = {"level": 1}
	if district_id != "":
		node_data["district"] = district_id
	nodes.append(node_data)
	state_changed.emit()
	return true

func remove_node(index: int) -> bool:
	if index < 0 or index >= nodes.size():
		return false
	nodes.remove_at(index)
	state_changed.emit()
	return true

# === DISTRICT ACCESS ===

func get_district_node_count(district_id: String) -> int:
	var count: int = 0
	for node_data: Dictionary in nodes:
		if node_data.get("district", "") == district_id:
			count += 1
	return count

func get_district_nodes(district_id: String) -> Array:
	var result: Array = []
	for i in range(nodes.size()):
		if nodes[i].get("district", "") == district_id:
			result.append(i)
	return result

func get_districts() -> Dictionary:
	var cfg := GameConfig.get_tier_config(tier)
	return cfg.get("districts", {})

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
	var base_bw: float = cfg.get("node_base_bw", 1.0)

	# Apply node base modifiers through pipeline
	var base_mods := get_modifiers_for_effect("node_base")
	var modified_base: float = ModifierPipeline.apply(base_bw, base_mods)

	var total: float = 0.0
	for node_data: Dictionary in nodes:
		var level: int = node_data.get("level", 1)
		var level_mult: float = 1.0 + (level - 1) * GameConfig.NODE_UPGRADE_BW_BONUS
		total += modified_base * level_mult
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
	energy_gen_bonus = 0.0
	energy_drain_reduction = 0.0
	energy_gen_multiplier_bonus = 0.0
	overload_reduction = 0.0

	for upgrade_def: Dictionary in GameConfig.get_upgrades_for_tier(tier):
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
			"energy_gen_bonus":
				energy_gen_bonus += effect
			"energy_drain_reduction":
				energy_drain_reduction += effect
			"energy_gen_multiplier":
				energy_gen_multiplier_bonus += effect
			"overload_reduction":
				overload_reduction += effect

func _find_upgrade_def(upgrade_id: String) -> Dictionary:
	for upgrade_def: Dictionary in GameConfig.get_upgrades_for_tier(tier):
		if upgrade_def["id"] == upgrade_id:
			return upgrade_def
	return {}

# === STABILITY TRACKING ===

func update_stability(delta: float, energy_rate: float) -> void:
	if energy_rate >= 0.0:
		stability_timer += delta
	else:
		stability_timer = 0.0

# === OBJECTIVE SYSTEM ===

func check_unlock_condition() -> bool:
	return check_unlock_objectives()

func check_unlock_objectives() -> bool:
	var cfg := GameConfig.get_tier_config(tier)
	var objectives: Array = cfg.get("unlock_objectives", [])
	if objectives.is_empty():
		return false

	for obj: Dictionary in objectives:
		if not _evaluate_objective(obj):
			return false
	return true

func _evaluate_objective(obj: Dictionary) -> bool:
	var obj_type: String = obj.get("type", "")
	var obj_value: float = obj.get("value", 0.0)

	match obj_type:
		"influence_min":
			return get_resource("influence") >= obj_value
		"detection_risk_below":
			return get_resource("detection_risk") < obj_value
		"energy_surplus":
			return get_per_second("energy") >= 0.0
		"multi_region":
			return false  # stub
		"stability_duration":
			return stability_timer >= obj_value
		_:
			push_error("[Objectives] Unknown objective type: %s" % obj_type)
			return false

func get_objective_progress(obj: Dictionary) -> Dictionary:
	var obj_type: String = obj.get("type", "")
	var obj_value: float = obj.get("value", 0.0)
	var met: bool = _evaluate_objective(obj)
	var label: String = obj.get("label", "Objective")

	match obj_type:
		"influence_min":
			var current: float = get_resource("influence")
			return {"met": met, "label": label % obj_value, "progress": "%.0f / %.0f" % [current, obj_value]}
		"detection_risk_below":
			var current: float = get_resource("detection_risk")
			return {"met": met, "label": label % obj_value, "progress": "%.1f%%" % current}
		"energy_surplus":
			var rate: float = get_per_second("energy")
			var status: String = "%.1f/s" % rate if rate >= 0.0 else "DEFICIT"
			return {"met": met, "label": label % obj_value, "progress": status}
		"stability_duration":
			return {"met": met, "label": label % obj_value, "progress": "%.0f / %.0fs" % [stability_timer, obj_value]}
		_:
			return {"met": met, "label": label % obj_value, "progress": ""}

func achieve_unlock(unlock_id: String) -> void:
	if not progression["unlocks"].has(unlock_id):
		progression["unlocks"][unlock_id] = true
		unlock_achieved.emit(unlock_id)

func has_unlock(unlock_id: String) -> bool:
	return progression["unlocks"].has(unlock_id)

# === PRESTIGE ===

func get_prestige_for_tier(t: int) -> Dictionary:
	return prestige.get(t, {"points": 0, "bonuses": []})

func add_prestige_points(t: int, points: int) -> void:
	if not prestige.has(t):
		prestige[t] = {"points": 0, "bonuses": []}
	prestige[t]["points"] += points
	print("[Prestige] Tier %d: +%d points (total: %d)" % [t, points, prestige[t]["points"]])

# === SOFT RESET ===

func soft_reset_current_tier() -> void:
	set_resource("bandwidth", 0.0)
	set_resource("influence", get_resource("influence") * 0.5)
	set_resource("detection_risk", 0.0)
	nodes.clear()
	event_bw_multiplier = 1.0
	event_nodes_disabled = false
	event_energy_gen_multiplier = 1.0
	event_district_shutdown = ""
	energy_overload = false
	stability_timer = 0.0
	if resources.has("energy"):
		set_resource("energy", 0.0)
	active_events.clear()
	state_changed.emit()

func advance_tier() -> void:
	var next_tier: int = tier + 1
	var next_cfg := GameConfig.get_tier_config(next_tier)
	if next_cfg.is_empty():
		push_warning("[TierAdvance] No config for tier %d" % next_tier)
		return

	print("[TierAdvance] === ADVANCING FROM TIER %d TO TIER %d ===" % [tier, next_tier])

	# Preserve influence (partial carryover)
	var influence_carry: float = get_resource("influence") * 0.25

	# Reset resources
	for res_id: String in resources.keys():
		resources[res_id]["value"] = 0.0
		resources[res_id]["per_second"] = 0.0

	# Reset nodes
	nodes.clear()

	# Reset events
	event_bw_multiplier = 1.0
	event_nodes_disabled = false
	event_energy_gen_multiplier = 1.0
	event_district_shutdown = ""
	active_events.clear()
	stability_timer = 0.0
	energy_overload = false

	# Set new tier
	tier = next_tier

	# Inject new tier features
	inject_tier_features(tier)

	# Restore partial influence
	set_resource("influence", influence_carry)

	# Recalculate modifiers for new tier upgrades
	_recalculate_modifiers()

	tier_changed.emit(tier)
	state_changed.emit()

func soft_reset(reset_tier: int) -> void:
	print("[SoftReset] === SOFT RESET TIER %d ===" % reset_tier)
	print("  Influence: %.0f" % get_resource("influence"))
	print("  DR: %.1f" % get_resource("detection_risk"))
	print("  Nodes: %d" % get_node_count())
	print("  Prestige points: %d" % get_prestige_for_tier(reset_tier)["points"])
	print("[SoftReset] Hook called — no action taken yet.")

# === DEBUG ===

func debug_stress_test() -> void:
	print("[StressTest] === EXTREME VALUE TEST ===")

	var saved_nodes := nodes.duplicate(true)
	var saved_inf := get_resource("influence")
	var saved_dr := get_resource("detection_risk")

	# Test: 0 nodes
	nodes.clear()
	print("  0 nodes -> node_count: %d" % get_node_count())

	# Test: 20 maxed nodes
	nodes.clear()
	for i in range(20):
		nodes.append({"level": GameConfig.NODE_UPGRADE_MAX_LEVEL})
	print("  20 maxed nodes -> total_bw: %.2f" % get_node_total_bw())

	# Test: DR at 99.9%
	set_resource("detection_risk", 99.9)
	print("  DR set to 99.9 -> value: %.2f" % get_resource("detection_risk"))

	# Test: Influence at 1M
	set_resource("influence", 1000000.0)
	print("  Influence set to 1M -> value: %.0f" % get_resource("influence"))

	# Restore state
	nodes = saved_nodes
	set_resource("influence", saved_inf)
	set_resource("detection_risk", saved_dr)
	print("[StressTest] === COMPLETE (state restored) ===")
