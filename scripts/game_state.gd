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
##   pipeline_apply(base, modifiers) — universal calculation system
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
signal node_degraded(index: int)
signal doctrine_changed(doctrine_id: String)
signal collapse_triggered(collapse_type: String, scope: String)
signal equilibrium_reached
signal equilibrium_lost

# === MODIFIER PIPELINE ===

func pipeline_apply(base: float, modifiers: Array) -> float:
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

func pipeline_apply_bool_or(modifiers: Array) -> bool:
	for mod: Dictionary in modifiers:
		if mod.get("value", false):
			return true
	return false

# === GLOBAL VALUE CLAMP UTILITY (Phase 2 TASK 4) ===

func safe_value(value: float, min_val: float = 0.0, max_val: float = 1000000.0) -> float:
	if is_nan(value) or is_inf(value):
		push_error("[SafeValue] NaN/Inf detected — clamping to 0. Stack: %s" % get_stack())
		return clampf(0.0, min_val, max_val)
	return clampf(value, min_val, max_val)

# === CORE STATE ===
var tier: int = 0
var save_version: int = GameConfig.SAVE_VERSION

# === UNIVERSAL RESOURCE REGISTRY ===
var resources: Dictionary = {}

# === NODE STATE ===
var nodes: Array = []  # Array of { "level": int, "district": String, "degraded": bool, "degradation_timer": float }
var max_nodes_bonus: int = 0

# === UPGRADE STATE ===
var upgrade_levels: Dictionary = {}

# === COMPUTED MODIFIERS (recalculated from upgrades) ===
var bw_multiplier: float = 0.0
var node_base_bonus: float = 0.0
var efficiency_bonus: float = 0.0
var dr_reduction: float = 0.0
var dr_decay_bonus: float = 0.0

# === EVENT RESISTANCE MODIFIERS (TASK 10) ===
var event_duration_reduction: float = 0.0
var event_severity_reduction: float = 0.0

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

# === SILENT MODE (TASK 6) ===
var silent_mode: bool = false

# === DR MOMENTUM (TASK 7) ===
var dr_momentum_history: Array = []  # Array of { "time": float, "dr": float }
var dr_momentum_bonus: float = 0.0

# === DOCTRINE (TASK 11) ===
var active_doctrine: String = "stability"

# === DISTRICT SPECIALIZATIONS (TASK 12) ===
var district_specializations: Dictionary = {}  # { "district_id": "spec_id" }

# === DISTRICT LOAD (TASK 2) ===
var district_load_ratios: Dictionary = {}  # { "district_id": float }

# === CONSTRAINT REGISTRY (Phase 2 TASK 1 — fully abstract) ===
# Each constraint: { id, active, priority, value, max_value, rate, update_func, collapse_type }
var constraint_registry: Array = []
var constraints: Dictionary = {}

# === AUTOMATION REGISTRY (Phase 2 TASK 15) ===
var automation: Dictionary = {"systems": [], "active": false}

# === REGIONAL STRUCTURE (Phase 2 TASK 16) ===
var regions: Array = []

# === TIER LOCK FLAG (Phase 2 TASK 17) ===
var tier_locked: Dictionary = {0: true, 1: false, 2: false, 3: false, 4: false, 5: false, 6: false, 7: false}

# === EQUILIBRIUM TRACKING (Phase 2 TASK 11) ===
var _equilibrium_timer: float = 0.0
var _equilibrium_dr_baseline: float = -1.0
var _equilibrium_inf_rate_baseline: float = -1.0
var _equilibrium_active: bool = false

# === STABILITY LOG (Phase 2 TASK 10) ===
var _stability_log: Array = []
var _stability_log_timer: float = 0.0

# === BALANCE SNAPSHOT (Phase 2 TASK 18) ===
var _last_balance_snapshot: Dictionary = {}

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
	"unlocks": {},
	"tier1_preview_shown": false,
}

# === ACTIVE EVENTS ===
var active_events: Array = []

# === EVENT HISTORY (TASK 9) ===
var event_history: Array = []  # Array of { "id": String, "timestamp": float }
var _game_clock: float = 0.0

func _ready() -> void:
	inject_tier_features(tier)
	_init_constraint_registry()

func _init_constraint_registry() -> void:
	constraint_registry = [
		{
			"id": "detection_risk",
			"active": true,
			"priority": GameConfig.CONSTRAINT_PRIORITIES.get("detection_risk", 10),
			"value": 0.0,
			"max_value": 100.0,
			"rate": 0.0,
			"collapse_type": "dr_overflow",
			"collapse_threshold": 100.0,
		},
		{
			"id": "energy",
			"active": true,
			"priority": GameConfig.CONSTRAINT_PRIORITIES.get("energy", 20),
			"value": 0.0,
			"max_value": 999.0,
			"rate": 0.0,
			"collapse_type": "energy_failure",
			"collapse_threshold": -1.0,  # Collapse handled by overload timer
		},
		{
			"id": "thermal_load",
			"active": false,
			"priority": GameConfig.CONSTRAINT_PRIORITIES.get("thermal_load", 30),
			"value": 0.0,
			"max_value": 100.0,
			"rate": 0.0,
			"collapse_type": "thermal_overload",
			"collapse_threshold": 100.0,
		},
		{
			"id": "cognitive_load",
			"active": false,
			"priority": GameConfig.CONSTRAINT_PRIORITIES.get("cognitive_load", 40),
			"value": 0.0,
			"max_value": 100.0,
			"rate": 0.0,
			"collapse_type": "",
			"collapse_threshold": -1.0,
		},
	]
	# Sort by priority (lower = higher priority)
	constraint_registry.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["priority"] < b["priority"]
	)

# === TIER INJECTION ===

func inject_tier_features(t: int) -> void:
	var cfg := GameConfig.get_tier_config(t)
	if cfg.is_empty():
		return

	var tier_resources: Array = cfg.get("resources", [])
	for res_id: String in tier_resources:
		if not resources.has(res_id):
			var defaults: Dictionary = GameConfig.RESOURCE_DEFAULTS.get(res_id, {})
			resources[res_id] = {
				"value": defaults.get("value", 0.0),
				"per_second": defaults.get("per_second", 0.0),
			}
			print("[TierInjection] Registered resource: %s" % res_id)

	for upgrade_def: Dictionary in GameConfig.get_upgrades_for_tier(t):
		var uid: String = upgrade_def["id"]
		if not upgrade_levels.has(uid):
			upgrade_levels[uid] = 0

	var tier_constraints: Dictionary = cfg.get("constraints", {})
	for key: String in tier_constraints.keys():
		constraints[key] = tier_constraints[key]

	# Init district specializations for Tier 1+
	var districts: Dictionary = cfg.get("districts", {})
	for dist_id: String in districts.keys():
		if not district_specializations.has(dist_id):
			district_specializations[dist_id] = "none"

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

	# Silent mode modifiers (TASK 6)
	if silent_mode:
		match effect_id:
			"efficiency":
				mods.append({"type": "mult", "value": GameConfig.SILENT_MODE_INFLUENCE_MULT, "source": "silent_mode"})
			"dr_gain":
				mods.append({"type": "mult", "value": GameConfig.SILENT_MODE_DR_GAIN_MULT, "source": "silent_mode"})
			"energy_consumption":
				mods.append({"type": "mult", "value": GameConfig.SILENT_MODE_ENERGY_MULT, "source": "silent_mode"})

	# Doctrine modifiers (TASK 11)
	if active_doctrine != "" and GameConfig.DOCTRINES.has(active_doctrine):
		var doctrine: Dictionary = GameConfig.DOCTRINES[active_doctrine]
		match effect_id:
			"efficiency":
				if doctrine.get("influence_multiplier", 1.0) != 1.0:
					mods.append({"type": "mult", "value": doctrine["influence_multiplier"], "source": "doctrine"})
			"dr_gain":
				if doctrine.get("dr_multiplier", 1.0) != 1.0:
					mods.append({"type": "mult", "value": doctrine["dr_multiplier"], "source": "doctrine"})
			"energy_consumption":
				if doctrine.get("energy_multiplier", 1.0) != 1.0:
					mods.append({"type": "mult", "value": doctrine["energy_multiplier"], "source": "doctrine"})

	# DR momentum modifier (TASK 7)
	if effect_id == "dr_gain" and dr_momentum_bonus != 0.0:
		mods.append({"type": "mult", "value": 1.0 + dr_momentum_bonus, "source": "dr_momentum"})

	# DR tiered state bonus (TASK 5)
	if effect_id == "efficiency":
		var dr: float = get_resource("detection_risk")
		if dr < GameConfig.DR_STEALTH_THRESHOLD:
			mods.append({"type": "add", "value": GameConfig.DR_STEALTH_EFFICIENCY_BONUS, "source": "dr_stealth"})

	return mods

func debug_print_modifiers(effect_id: String) -> void:
	var mods := get_modifiers_for_effect(effect_id)
	print("[ModifierDebug] %s: %d modifiers" % [effect_id, mods.size()])
	for mod: Dictionary in mods:
		print("  - %s: %s (from %s)" % [mod.get("type", "?"), str(mod.get("value", 0)), mod.get("source", "?")])

# === GLOBAL EFFICIENCY CURVE (TASK 1) ===

func calculate_global_efficiency() -> float:
	var n: float = float(get_node_count())
	var softcap: float = GameConfig.EFFICIENCY_SOFTCAP
	var exponent: float = GameConfig.EFFICIENCY_EXPONENT
	var eff: float = 1.0 / (1.0 + pow(n / softcap, exponent))
	# Efficiency floor cap (Phase 2 TASK 5)
	return maxf(eff, GameConfig.MIN_GLOBAL_EFFICIENCY)

# === DISTRICT LOAD (TASK 2) ===

func update_district_loads() -> void:
	var cfg := GameConfig.get_tier_config(tier)
	var districts: Dictionary = cfg.get("districts", {})
	for dist_id: String in districts.keys():
		var cap: int = districts[dist_id].get("cap", 1)
		var assigned: int = get_district_node_count(dist_id)
		district_load_ratios[dist_id] = float(assigned) / float(maxf(cap, 1))

func get_district_load_ratio(district_id: String) -> float:
	return district_load_ratios.get(district_id, 0.0)

func is_district_overloaded(district_id: String) -> bool:
	return get_district_load_ratio(district_id) > GameConfig.DISTRICT_OVERLOAD_THRESHOLD

func get_district_dr_multiplier(district_id: String) -> float:
	if is_district_overloaded(district_id):
		return GameConfig.DISTRICT_DR_MULTIPLIER
	return 1.0

func get_district_energy_multiplier(district_id: String) -> float:
	if is_district_overloaded(district_id):
		return GameConfig.DISTRICT_ENERGY_MULTIPLIER
	return 1.0

# === DISTRICT SPECIALIZATION (TASK 12) ===

func get_district_specialization(district_id: String) -> String:
	return district_specializations.get(district_id, "none")

func set_district_specialization(district_id: String, spec_id: String) -> void:
	if GameConfig.DISTRICT_SPECIALIZATIONS.has(spec_id):
		district_specializations[district_id] = spec_id
		state_changed.emit()

func get_district_spec_modifier(district_id: String, modifier_key: String) -> float:
	var spec_id: String = get_district_specialization(district_id)
	var spec: Dictionary = GameConfig.DISTRICT_SPECIALIZATIONS.get(spec_id, {})
	return spec.get(modifier_key, 1.0)

# === MAINTENANCE DRAIN (TASK 3) ===

func calculate_maintenance_drain() -> float:
	return float(get_node_count()) * GameConfig.MAINTENANCE_PER_NODE

# === NODE DEGRADATION (TASK 4) ===

func tick_degradation(delta: float) -> void:
	var chance_per_sec: float = GameConfig.DEGRADATION_CHANCE_PER_MINUTE / 60.0
	for i in range(nodes.size()):
		var node_data: Dictionary = nodes[i]
		if node_data.get("degraded", false):
			continue
		if randf() < chance_per_sec * delta:
			node_data["degraded"] = true
			node_data["degradation_timer"] = 0.0
			node_degraded.emit(i)

func repair_node(index: int) -> bool:
	if index < 0 or index >= nodes.size():
		return false
	var node_data: Dictionary = nodes[index]
	if not node_data.get("degraded", false):
		return false
	var cost: float = GameConfig.DEGRADATION_REPAIR_COST
	if get_resource("influence") < cost:
		return false
	add_resource("influence", -cost)
	node_data["degraded"] = false
	node_data["degradation_timer"] = 0.0
	state_changed.emit()
	return true

func get_degraded_node_count() -> int:
	var count: int = 0
	for node_data: Dictionary in nodes:
		if node_data.get("degraded", false):
			count += 1
	return count

func is_node_degraded(index: int) -> bool:
	if index < 0 or index >= nodes.size():
		return false
	return nodes[index].get("degraded", false)

# === DR TIERED STATE (TASK 5) ===

func get_dr_band() -> String:
	var dr: float = get_resource("detection_risk")
	if dr >= GameConfig.DR_CRISIS_THRESHOLD:
		return "crisis"
	elif dr >= GameConfig.DR_VOLATILE_THRESHOLD:
		return "volatile"
	elif dr >= GameConfig.DR_STEALTH_THRESHOLD:
		return "normal"
	else:
		return "stealth"

func get_dr_event_frequency_multiplier() -> float:
	var band: String = get_dr_band()
	if band == "volatile" or band == "crisis":
		return GameConfig.DR_VOLATILE_EVENT_FREQ_MULT
	return 1.0

func get_dr_scan_chance_multiplier() -> float:
	if get_dr_band() == "crisis":
		return GameConfig.DR_CRISIS_SCAN_CHANCE_MULT
	return 1.0

# === SILENT MODE (TASK 6) ===

func toggle_silent_mode() -> void:
	silent_mode = not silent_mode
	state_changed.emit()

# === DR MOMENTUM (TASK 7) ===

func update_dr_momentum(current_time: float) -> void:
	var current_dr: float = get_resource("detection_risk")
	dr_momentum_history.append({"time": current_time, "dr": current_dr})

	# Prune entries older than window
	var cutoff: float = current_time - GameConfig.DR_MOMENTUM_WINDOW
	while dr_momentum_history.size() > 0 and dr_momentum_history[0]["time"] < cutoff:
		dr_momentum_history.pop_front()

	if dr_momentum_history.size() < 2:
		dr_momentum_bonus = 0.0
		return

	var oldest: Dictionary = dr_momentum_history[0]
	var newest: Dictionary = dr_momentum_history[dr_momentum_history.size() - 1]
	var dr_change: float = newest["dr"] - oldest["dr"]
	var time_span: float = newest["time"] - oldest["time"]

	if time_span <= 0.0:
		dr_momentum_bonus = 0.0
		return

	var rate: float = dr_change / time_span

	if rate > 0.1:  # DR rising consistently
		dr_momentum_bonus = minf((GameConfig.DR_MOMENTUM_RISE_MULT - 1.0) * (rate / 1.0), GameConfig.DR_MOMENTUM_MAX_BONUS - 1.0)
	elif rate < -0.05:  # DR falling
		dr_momentum_bonus = -GameConfig.DR_MOMENTUM_FALL_DECAY_BONUS
	else:
		dr_momentum_bonus = 0.0

	# Momentum cap (Phase 2 TASK 6)
	dr_momentum_bonus = clampf(dr_momentum_bonus, -(GameConfig.MAX_MOMENTUM_MULTIPLIER - 1.0), GameConfig.MAX_MOMENTUM_MULTIPLIER - 1.0)

# === DOCTRINE (TASK 11) ===

func switch_doctrine(doctrine_id: String) -> bool:
	if not GameConfig.DOCTRINES.has(doctrine_id):
		return false
	if doctrine_id == active_doctrine:
		return false
	var cost: float = GameConfig.DOCTRINES[doctrine_id].get("switch_cost", 100.0)
	if get_resource("influence") < cost:
		return false
	add_resource("influence", -cost)
	active_doctrine = doctrine_id
	doctrine_changed.emit(doctrine_id)
	state_changed.emit()
	return true

# === EVENT HISTORY (TASK 9) ===

func record_event(event_id: String) -> void:
	event_history.append({"id": event_id, "timestamp": _game_clock})
	# Keep only last 10 entries
	while event_history.size() > 10:
		event_history.pop_front()

func get_recent_event_count(event_id: String) -> int:
	var cutoff: float = _game_clock - GameConfig.EVENT_ESCALATION_WINDOW
	var count: int = 0
	for entry: Dictionary in event_history:
		if entry["id"] == event_id and entry["timestamp"] >= cutoff:
			count += 1
	return count

func should_escalate_event(event_id: String) -> bool:
	return get_recent_event_count(event_id) >= GameConfig.EVENT_ESCALATION_COUNT

func get_event_escalation_level(event_id: String) -> int:
	# Returns capped escalation level (Phase 2 TASK 7)
	var count: int = get_recent_event_count(event_id)
	if count < GameConfig.EVENT_ESCALATION_COUNT:
		return 0
	var level: int = count - GameConfig.EVENT_ESCALATION_COUNT + 1
	return mini(level, GameConfig.MAX_EVENT_ESCALATION_LEVEL)

func advance_game_clock(delta: float) -> void:
	_game_clock += delta

func get_game_clock() -> float:
	return _game_clock

# === CONSTRAINT REGISTRY (Phase 2 TASK 1 — abstract dispatch) ===

func update_constraints(delta: float) -> void:
	# Dispatch loop: iterate constraints by priority order
	for entry: Dictionary in constraint_registry:
		if not entry.get("active", false):
			continue
		# Resources.gd calls the actual update functions via dispatch_constraint_update
		# This sync step pushes current resource values into constraint entries
		_sync_constraint_value(entry)

func _sync_constraint_value(entry: Dictionary) -> void:
	var cid: String = entry["id"]
	match cid:
		"detection_risk":
			entry["value"] = get_resource("detection_risk")
			entry["rate"] = get_per_second("detection_risk")
		"energy":
			entry["value"] = get_resource("energy")
			entry["rate"] = get_per_second("energy")
		"thermal_load":
			# Stub — no real value yet (Phase 2 TASK 14)
			entry["value"] = 0.0
			entry["rate"] = 0.0
		"cognitive_load":
			entry["value"] = 0.0
			entry["rate"] = 0.0

func get_constraint(constraint_id: String) -> Dictionary:
	for entry: Dictionary in constraint_registry:
		if entry["id"] == constraint_id:
			return entry
	return {}

func get_active_constraints() -> Array:
	var result: Array = []
	for entry: Dictionary in constraint_registry:
		if entry.get("active", false):
			result.append(entry)
	return result

func get_all_constraints() -> Array:
	return constraint_registry

func is_constraint_active(constraint_id: String) -> bool:
	var entry: Dictionary = get_constraint(constraint_id)
	return entry.get("active", false)

func set_constraint_active(constraint_id: String, active: bool) -> void:
	for entry: Dictionary in constraint_registry:
		if entry["id"] == constraint_id:
			entry["active"] = active
			return

func debug_print_constraints() -> void:
	print("[ConstraintDebug] === ACTIVE CONSTRAINTS ===")
	for entry: Dictionary in constraint_registry:
		var status: String = "ACTIVE" if entry.get("active", false) else "INACTIVE"
		print("  [P%d] %s: %.2f / %.2f (rate: %+.3f) [%s]" % [
			entry.get("priority", 99),
			entry["id"],
			entry.get("value", 0.0),
			entry.get("max_value", 0.0),
			entry.get("rate", 0.0),
			status,
		])

# === COLLAPSE GENERALIZATION (Phase 2 TASK 3) ===

func trigger_collapse(collapse_type: String, scope: String = "current_tier") -> void:
	var collapse_def: Dictionary = GameConfig.COLLAPSE_TYPES.get(collapse_type, {})
	if collapse_def.is_empty():
		push_error("[Collapse] Unknown collapse type: %s" % collapse_type)
		return

	print("[Collapse] === %s === scope: %s" % [collapse_type.to_upper(), scope])
	print("  %s" % collapse_def.get("description", ""))

	var inf_penalty: float = collapse_def.get("influence_penalty", 0.5)
	set_resource("influence", get_resource("influence") * inf_penalty)

	if collapse_def.get("clear_nodes", false):
		nodes.clear()

	if collapse_def.get("clear_events", false):
		active_events.clear()
		event_bw_multiplier = 1.0
		event_nodes_disabled = false
		event_energy_gen_multiplier = 1.0
		event_district_shutdown = ""

	# Reset constraint-specific state
	match collapse_type:
		"dr_overflow":
			set_resource("detection_risk", 0.0)
			dr_momentum_history.clear()
			dr_momentum_bonus = 0.0
		"energy_failure":
			set_resource("energy", 0.0)
			energy_overload = false
		"thermal_overload":
			# Future: reset thermal_load to 0
			pass

	stability_timer = 0.0
	collapse_triggered.emit(collapse_type, scope)
	state_changed.emit()

# === EQUILIBRIUM DETECTION (Phase 2 TASK 11) ===

func update_equilibrium(delta: float) -> void:
	var current_dr: float = get_resource("detection_risk")
	var current_inf_rate: float = get_per_second("influence")

	if _equilibrium_dr_baseline < 0.0:
		# First sample
		_equilibrium_dr_baseline = current_dr
		_equilibrium_inf_rate_baseline = current_inf_rate
		_equilibrium_timer = 0.0
		return

	var dr_delta: float = absf(current_dr - _equilibrium_dr_baseline)
	var inf_rate_delta: float = absf(current_inf_rate - _equilibrium_inf_rate_baseline)

	if dr_delta > GameConfig.EQUILIBRIUM_DR_TOLERANCE or inf_rate_delta > GameConfig.EQUILIBRIUM_INF_RATE_TOLERANCE:
		# Reset — values drifted outside tolerance
		_equilibrium_dr_baseline = current_dr
		_equilibrium_inf_rate_baseline = current_inf_rate
		_equilibrium_timer = 0.0
		if _equilibrium_active:
			_equilibrium_active = false
			equilibrium_lost.emit()
		return

	_equilibrium_timer += delta
	if _equilibrium_timer >= GameConfig.EQUILIBRIUM_WINDOW and not _equilibrium_active:
		_equilibrium_active = true
		equilibrium_reached.emit()
		print("[Equilibrium] Stable state detected at DR=%.1f, Inf/s=%.2f" % [current_dr, current_inf_rate])

func is_in_equilibrium() -> bool:
	return _equilibrium_active

func get_equilibrium_timer() -> float:
	return _equilibrium_timer

# === STABILITY LOGGER (Phase 2 TASK 10) ===

func log_stability_snapshot() -> void:
	var snapshot: Dictionary = {
		"time": _game_clock,
		"dr": get_resource("detection_risk"),
		"dr_rate": get_per_second("detection_risk"),
		"influence": get_resource("influence"),
		"inf_rate": get_per_second("influence"),
		"nodes": get_node_count(),
		"degraded": get_degraded_node_count(),
		"energy": get_resource("energy") if resources.has("energy") else 0.0,
		"energy_rate": get_per_second("energy") if resources.has("energy") else 0.0,
		"dr_band": get_dr_band(),
		"equilibrium": _equilibrium_active,
	}
	_stability_log.append(snapshot)
	print("[StabilityLog] t=%.0f | DR=%.1f(%+.3f/s) | Inf=%.0f(%+.2f/s) | Nodes=%d(%d degraded) | Band=%s | Eq=%s" % [
		snapshot["time"], snapshot["dr"], snapshot["dr_rate"],
		snapshot["influence"], snapshot["inf_rate"],
		snapshot["nodes"], snapshot["degraded"],
		snapshot["dr_band"], "YES" if snapshot["equilibrium"] else "NO",
	])

func update_stability_logger(delta: float) -> void:
	_stability_log_timer += delta
	if _stability_log_timer >= GameConfig.STABILITY_LOG_INTERVAL:
		_stability_log_timer -= GameConfig.STABILITY_LOG_INTERVAL
		log_stability_snapshot()

func get_stability_log() -> Array:
	return _stability_log

func clear_stability_log() -> void:
	_stability_log.clear()
	_stability_log_timer = 0.0

# === THERMAL LOAD STUB (Phase 2 TASK 14) ===

func update_thermal_load(_delta: float) -> void:
	# Stub: thermal_load constraint exists but update is a no-op
	# Safe to activate — will read 0.0 / write 0.0
	pass

func get_thermal_load() -> float:
	var entry: Dictionary = get_constraint("thermal_load")
	return entry.get("value", 0.0)

# === BALANCE SNAPSHOT (Phase 2 TASK 18) ===

func take_balance_snapshot() -> Dictionary:
	var snapshot: Dictionary = {
		"timestamp": _game_clock,
		"tier": tier,
		"node_count": get_node_count(),
		"degraded_nodes": get_degraded_node_count(),
		"resources": {},
		"rates": {},
		"upgrade_levels": upgrade_levels.duplicate(true),
		"active_doctrine": active_doctrine,
		"district_specializations": district_specializations.duplicate(true),
		"dr_band": get_dr_band(),
		"global_efficiency": calculate_global_efficiency(),
		"maintenance_drain": calculate_maintenance_drain(),
		"silent_mode": silent_mode,
		"equilibrium": _equilibrium_active,
		"constraint_states": [],
	}

	for res_id: String in resources.keys():
		snapshot["resources"][res_id] = get_resource(res_id)
		snapshot["rates"][res_id] = get_per_second(res_id)

	for entry: Dictionary in constraint_registry:
		snapshot["constraint_states"].append({
			"id": entry["id"],
			"active": entry.get("active", false),
			"value": entry.get("value", 0.0),
			"rate": entry.get("rate", 0.0),
		})

	_last_balance_snapshot = snapshot
	print("[BalanceSnapshot] === SNAPSHOT TAKEN ===")
	print("  Tier: %d | Nodes: %d | DR: %.1f | Inf: %.0f" % [
		snapshot["tier"], snapshot["node_count"],
		snapshot["resources"].get("detection_risk", 0.0),
		snapshot["resources"].get("influence", 0.0),
	])
	print("  Rates: DR=%+.3f/s Inf=%+.2f/s" % [
		snapshot["rates"].get("detection_risk", 0.0),
		snapshot["rates"].get("influence", 0.0),
	])
	print("  Doctrine: %s | Silent: %s | Equilibrium: %s" % [
		snapshot["active_doctrine"],
		"ON" if snapshot["silent_mode"] else "OFF",
		"YES" if snapshot["equilibrium"] else "NO",
	])
	for upg_id: String in snapshot["upgrade_levels"].keys():
		var lvl: int = snapshot["upgrade_levels"][upg_id]
		if lvl > 0:
			print("  Upgrade: %s Lv.%d" % [upg_id, lvl])

	return snapshot

func get_last_balance_snapshot() -> Dictionary:
	return _last_balance_snapshot

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

func get_active_node_count() -> int:
	var count: int = 0
	for node_data: Dictionary in nodes:
		if not node_data.get("degraded", false):
			count += 1
	return count

func get_max_nodes() -> int:
	var cfg := GameConfig.get_tier_config(tier)
	return cfg.get("max_nodes", 20) + max_nodes_bonus

func can_deploy_node(district_id: String = "") -> bool:
	if event_nodes_disabled:
		return false
	if get_node_count() >= get_max_nodes():
		return false
	if district_id != "":
		var cfg := GameConfig.get_tier_config(tier)
		var districts: Dictionary = cfg.get("districts", {})
		if districts.has(district_id):
			var district_cap: int = districts[district_id].get("cap", 0)
			if get_district_node_count(district_id) >= district_cap:
				return false
		if event_district_shutdown == district_id:
			return false
	return true

func deploy_node(district_id: String = "") -> bool:
	if not can_deploy_node(district_id):
		return false
	var node_data: Dictionary = {
		"level": 1,
		"degraded": false,
		"degradation_timer": 0.0,
	}
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

	var base_mods := get_modifiers_for_effect("node_base")
	var modified_base: float = pipeline_apply(base_bw, base_mods)

	var total: float = 0.0
	for node_data: Dictionary in nodes:
		var level: int = node_data.get("level", 1)
		var level_mult: float = 1.0 + (level - 1) * GameConfig.NODE_UPGRADE_BW_BONUS

		# Degradation penalty (TASK 4)
		var degradation_mult: float = 1.0
		if node_data.get("degraded", false):
			degradation_mult = GameConfig.DEGRADATION_OUTPUT_PENALTY

		total += modified_base * level_mult * degradation_mult
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
	event_duration_reduction = 0.0
	event_severity_reduction = 0.0

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
			"event_duration_reduction":
				event_duration_reduction += effect
			"event_severity_reduction":
				event_severity_reduction += effect

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
			return false
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
		# Mark current tier as locked (objectives met) (Phase 2 TASK 17)
		tier_locked[tier] = true
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
	# Route through unified collapse system (Phase 2 TASK 3)
	trigger_collapse("dr_overflow", "current_tier")
	# Also reset bandwidth and energy
	set_resource("bandwidth", 0.0)
	if resources.has("energy"):
		set_resource("energy", 0.0)
	energy_overload = false

func advance_tier() -> void:
	var next_tier: int = tier + 1

	# Tier lock check (Phase 2 TASK 17)
	if not tier_locked.get(tier, false):
		push_warning("[TierAdvance] Current tier %d is not locked (objectives not met)" % tier)

	var next_cfg := GameConfig.get_tier_config(next_tier)
	if next_cfg.is_empty():
		push_warning("[TierAdvance] No config for tier %d" % next_tier)
		return

	print("[TierAdvance] === ADVANCING FROM TIER %d TO TIER %d ===" % [tier, next_tier])

	var influence_carry: float = get_resource("influence") * 0.25

	for res_id: String in resources.keys():
		resources[res_id]["value"] = 0.0
		resources[res_id]["per_second"] = 0.0

	nodes.clear()

	event_bw_multiplier = 1.0
	event_nodes_disabled = false
	event_energy_gen_multiplier = 1.0
	event_district_shutdown = ""
	active_events.clear()
	stability_timer = 0.0
	energy_overload = false
	dr_momentum_history.clear()
	dr_momentum_bonus = 0.0
	silent_mode = false
	active_doctrine = "stability"
	district_specializations.clear()
	district_load_ratios.clear()
	event_history.clear()

	# Reset equilibrium tracking
	_equilibrium_timer = 0.0
	_equilibrium_dr_baseline = -1.0
	_equilibrium_inf_rate_baseline = -1.0
	_equilibrium_active = false

	tier = next_tier

	inject_tier_features(tier)

	set_resource("influence", influence_carry)

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

# === SAVE / LOAD (Phase 2 TASK 8 — schema validation, v3) ===

func get_save_data() -> Dictionary:
	return {
		"save_version": GameConfig.SAVE_VERSION,
		"tier": tier,
		"resources": resources.duplicate(true),
		"nodes": nodes.duplicate(true),
		"upgrade_levels": upgrade_levels.duplicate(true),
		"prestige": prestige.duplicate(true),
		"progression": progression.duplicate(true),
		"active_doctrine": active_doctrine,
		"district_specializations": district_specializations.duplicate(true),
		"silent_mode": silent_mode,
		"event_history": event_history.duplicate(true),
		"game_clock": _game_clock,
		"regions": regions.duplicate(true),
		"automation": automation.duplicate(true),
		"tier_locked": tier_locked.duplicate(true),
	}

func load_save_data(data: Dictionary) -> void:
	# Schema validation (Phase 2 TASK 8)
	if not validate_save_schema(data):
		push_warning("[SaveLoad] Schema validation failed — attempting safe load")
		if not _safe_load(data):
			push_error("[SaveLoad] Safe load failed — starting fresh")
			return

	var version: int = data.get("save_version", 1)
	if version < 2:
		_migrate_v1_to_v2(data)
	if version < 3:
		_migrate_v2_to_v3(data)

	tier = data.get("tier", 0)
	resources = data.get("resources", {})
	nodes = data.get("nodes", [])
	upgrade_levels = data.get("upgrade_levels", {})
	prestige = data.get("prestige", prestige)
	progression = data.get("progression", progression)
	active_doctrine = data.get("active_doctrine", "stability")
	district_specializations = data.get("district_specializations", {})
	silent_mode = data.get("silent_mode", false)
	event_history = data.get("event_history", [])
	_game_clock = data.get("game_clock", 0.0)
	regions = data.get("regions", [])
	automation = data.get("automation", {"systems": [], "active": false})
	tier_locked = data.get("tier_locked", {0: true, 1: false})

	# Ensure new fields exist on old nodes
	for node_data: Dictionary in nodes:
		if not node_data.has("degraded"):
			node_data["degraded"] = false
		if not node_data.has("degradation_timer"):
			node_data["degradation_timer"] = 0.0

	inject_tier_features(tier)
	_recalculate_modifiers()
	state_changed.emit()

# === SAVE SCHEMA VALIDATOR (Phase 2 TASK 8) ===

func validate_save_schema(data: Dictionary) -> bool:
	if not data is Dictionary:
		push_error("[SaveValidator] Save data is not a Dictionary")
		return false

	var version: int = data.get("save_version", 0)
	if version < 1 or version > GameConfig.SAVE_VERSION:
		push_error("[SaveValidator] Invalid save version: %d (expected 1-%d)" % [version, GameConfig.SAVE_VERSION])
		return false

	# Validate essential keys exist (type-check relaxed for old versions)
	var essential_keys: Array = ["tier", "resources", "nodes", "upgrade_levels"]
	for key: String in essential_keys:
		if not data.has(key):
			push_error("[SaveValidator] Missing essential key: %s" % key)
			return false

	# Type checks on essential fields
	if not data["resources"] is Dictionary:
		push_error("[SaveValidator] 'resources' is not a Dictionary")
		return false
	if not data["nodes"] is Array:
		push_error("[SaveValidator] 'nodes' is not an Array")
		return false
	if not data["upgrade_levels"] is Dictionary:
		push_error("[SaveValidator] 'upgrade_levels' is not a Dictionary")
		return false

	# Validate node structures
	for i in range(data["nodes"].size()):
		var node_data = data["nodes"][i]
		if not node_data is Dictionary:
			push_error("[SaveValidator] nodes[%d] is not a Dictionary" % i)
			return false

	# Validate resource structures
	for res_id: String in data["resources"].keys():
		var res_data = data["resources"][res_id]
		if not res_data is Dictionary:
			push_error("[SaveValidator] resources['%s'] is not a Dictionary" % res_id)
			return false

	print("[SaveValidator] Schema validation passed (version %d)" % version)
	return true

# === SAFE LOAD MODE (Phase 2 TASK 9) ===

func _safe_load(data: Dictionary) -> bool:
	print("[SafeLoad] Attempting safe load with fallback defaults...")

	# Try to recover what we can
	tier = data.get("tier", 0) if data.has("tier") and data["tier"] is int else 0

	# Resources: rebuild from defaults if corrupt
	if data.has("resources") and data["resources"] is Dictionary:
		resources = data["resources"]
	else:
		resources = {}
		inject_tier_features(tier)

	# Nodes: use if valid array, else clear
	if data.has("nodes") and data["nodes"] is Array:
		nodes = data["nodes"]
		# Sanitize each node
		var valid_nodes: Array = []
		for node_data in nodes:
			if node_data is Dictionary:
				if not node_data.has("level"):
					node_data["level"] = 1
				if not node_data.has("degraded"):
					node_data["degraded"] = false
				if not node_data.has("degradation_timer"):
					node_data["degradation_timer"] = 0.0
				valid_nodes.append(node_data)
		nodes = valid_nodes
	else:
		nodes = []

	# Upgrade levels: use if valid, else empty
	if data.has("upgrade_levels") and data["upgrade_levels"] is Dictionary:
		upgrade_levels = data["upgrade_levels"]
	else:
		upgrade_levels = {}

	# Other fields with safe defaults
	active_doctrine = data.get("active_doctrine", "stability") if data.has("active_doctrine") else "stability"
	district_specializations = data.get("district_specializations", {}) if data.has("district_specializations") else {}
	silent_mode = data.get("silent_mode", false) if data.has("silent_mode") else false
	event_history = data.get("event_history", []) if data.has("event_history") else []
	_game_clock = data.get("game_clock", 0.0) if data.has("game_clock") else 0.0
	regions = data.get("regions", []) if data.has("regions") else []
	automation = data.get("automation", {"systems": [], "active": false}) if data.has("automation") else {"systems": [], "active": false}
	tier_locked = data.get("tier_locked", {0: true, 1: false}) if data.has("tier_locked") else {0: true, 1: false}

	inject_tier_features(tier)
	_recalculate_modifiers()
	state_changed.emit()

	print("[SafeLoad] Safe load complete — recovered what was possible")
	return true

# === SAVE MIGRATIONS ===

func _migrate_v1_to_v2(data: Dictionary) -> void:
	print("[SaveMigration] Migrating v1 -> v2")
	if not data.has("active_doctrine"):
		data["active_doctrine"] = "stability"
	if not data.has("district_specializations"):
		data["district_specializations"] = {}
	if not data.has("silent_mode"):
		data["silent_mode"] = false
	if not data.has("event_history"):
		data["event_history"] = []
	if not data.has("game_clock"):
		data["game_clock"] = 0.0
	data["save_version"] = 2

func _migrate_v2_to_v3(data: Dictionary) -> void:
	print("[SaveMigration] Migrating v2 -> v3")
	if not data.has("regions"):
		data["regions"] = []
	if not data.has("automation"):
		data["automation"] = {"systems": [], "active": false}
	if not data.has("tier_locked"):
		data["tier_locked"] = {0: true, 1: false}
	data["save_version"] = 3

# === INFLUENCE FLOW BREAKDOWN (TASK 15) ===

func get_influence_breakdown() -> Dictionary:
	var cfg := GameConfig.get_tier_config(tier)
	var base_bw: float = cfg.get("node_base_bw", 1.0)
	var base_eff: float = cfg.get("base_efficiency", 0.05)
	var raw_bw: float = get_node_total_bw()
	var global_eff: float = calculate_global_efficiency()
	var maintenance: float = calculate_maintenance_drain()

	var eff_mods := get_modifiers_for_effect("efficiency")
	var total_eff: float = pipeline_apply(base_eff, eff_mods)

	var gross_inf: float = raw_bw * total_eff * global_eff
	var net_inf: float = gross_inf - maintenance

	return {
		"base_node_output": raw_bw,
		"global_efficiency_penalty": global_eff,
		"base_efficiency": base_eff,
		"total_efficiency": total_eff,
		"maintenance_drain": maintenance,
		"gross_influence": gross_inf,
		"net_influence": net_inf,
		"dr_band": get_dr_band(),
		"silent_mode": silent_mode,
		"doctrine": active_doctrine,
	}

# === DEBUG ===

func debug_stress_test() -> void:
	print("[StressTest] === EXTREME VALUE TEST ===")

	var saved_nodes := nodes.duplicate(true)
	var saved_inf := get_resource("influence")
	var saved_dr := get_resource("detection_risk")

	nodes.clear()
	print("  0 nodes -> node_count: %d" % get_node_count())

	nodes.clear()
	for i in range(20):
		nodes.append({"level": GameConfig.NODE_UPGRADE_MAX_LEVEL, "degraded": false, "degradation_timer": 0.0})
	print("  20 maxed nodes -> total_bw: %.2f" % get_node_total_bw())
	print("  Global efficiency at 20 nodes: %.4f" % calculate_global_efficiency())

	set_resource("detection_risk", 99.9)
	print("  DR set to 99.9 -> value: %.2f, band: %s" % [get_resource("detection_risk"), get_dr_band()])

	set_resource("influence", 1000000.0)
	print("  Influence set to 1M -> value: %.0f" % get_resource("influence"))

	nodes = saved_nodes
	set_resource("influence", saved_inf)
	set_resource("detection_risk", saved_dr)
	print("[StressTest] === COMPLETE (state restored) ===")
