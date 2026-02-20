extends Node
## event_system.gd — Random event engine.
##
## === EVENT LIFECYCLE ===
## 1. Spawn: _spawn_random_event() picks from tier events, creates entry
## 2. Apply: _apply_combined_modifiers() sets GameState event modifiers
## 3. Tick: _update_active_events(delta) decrements remaining time
## 4. Expire: remaining <= 0 -> remove -> _apply_combined_modifiers() recalc
## 5. Manual repair: repair_event(id) -> immediate removal
##
## Modifier stacking:
##   BW multipliers: multiplicative (0.5 * 0.8 = 0.4)
##   Node disable: boolean OR (any event disabling = all disabled)
##   DR spikes: immediate one-time addition to DR resource
##
## Event escalation (TASK 9):
##   Tracks event history. Repeated events get stronger.
## Event resistance (TASK 10):
##   Duration/severity reduced by upgrade modifiers.
## DR band frequency (TASK 5):
##   Higher DR bands increase event spawn rate.
##
## Dynamic Event Chains (Phase 2 #5):
##   Events can trigger follow-up events conditionally.
##   Chains escalate risk with branching outcomes.

signal event_started(event_data: Dictionary)
signal event_ended(event_id: String)
signal event_requires_repair(event_id: String)
signal event_chain_started(chain_id: String, stage: Dictionary)
signal event_chain_advanced(chain_id: String, stage: Dictionary)
signal event_chain_completed(chain_id: String)

var _event_timer: float = 0.0
var _next_event_time: float = 0.0
var _active_events: Array = []  # Array of { "def": {}, "remaining": float, "escalated": bool }

# === EVENT CHAIN STATE (Phase 2 #5) ===
# { chain_id: { "stage_index": int, "active": bool, "trigger_count": int } }
var _active_chains: Dictionary = {}
# IDs of events that have been spawned as part of a chain this session
var _chain_spawned_event_ids: Array = []

func _ready() -> void:
	_roll_next_event_time()
	TickEngine.game_tick.connect(_on_game_tick)

func _roll_next_event_time() -> void:
	var cfg := GameConfig.get_tier_config(GameState.tier)
	var min_t: float = cfg.get("event_interval_min", 30.0)
	var max_t: float = cfg.get("event_interval_max", 90.0)
	_next_event_time = randf_range(min_t, max_t)
	_event_timer = 0.0

func _on_game_tick(delta: float) -> void:
	var cfg := GameConfig.get_tier_config(GameState.tier)
	if not cfg.get("events_enabled", false):
		return

	if GameState.get_node_count() <= 0:
		return

	_update_active_events(delta)

	_event_timer += delta

	# DR band frequency multiplier (TASK 5)
	var dr_freq_mult: float = GameState.get_dr_event_frequency_multiplier()

	# Adaptive difficulty event frequency (Phase 1 #1)
	var adapt_freq_mult: float = 1.0
	if has_node("/root/AdaptiveDifficulty"):
		adapt_freq_mult = get_node("/root/AdaptiveDifficulty").event_frequency_multiplier
	dr_freq_mult *= adapt_freq_mult

	# Higher DR = more frequent events above danger threshold
	var dr: float = GameState.get_resource("detection_risk")
	var danger: float = cfg.get("dr_danger_threshold", 85.0)
	var time_mult: float = 1.0 / dr_freq_mult
	if dr > danger:
		time_mult *= 0.5

	if _event_timer >= _next_event_time * time_mult:
		_spawn_random_event()
		_roll_next_event_time()

func _update_active_events(delta: float) -> void:
	var expired: Array = []

	for i in range(_active_events.size()):
		var entry: Dictionary = _active_events[i]
		var remaining: float = entry["remaining"]

		if remaining < 0.0:
			continue

		entry["remaining"] = remaining - delta
		if entry["remaining"] <= 0.0:
			expired.append(i)

	expired.reverse()
	for idx: int in expired:
		var entry: Dictionary = _active_events[idx]
		var expired_id: String = entry["def"]["id"]
		event_ended.emit(expired_id)
		_active_events.remove_at(idx)
		# Advance chain if this was a chain stage (Phase 2 #5)
		_advance_chain_if_needed(expired_id)

	_apply_combined_modifiers()

func _spawn_random_event() -> void:
	var available: Array = []
	var active_ids: Array = []
	for entry: Dictionary in _active_events:
		active_ids.append(entry["def"]["id"])

	for evt: Dictionary in GameConfig.get_events_for_tier(GameState.tier):
		if not active_ids.has(evt["id"]):
			available.append(evt)

	if available.is_empty():
		return

	var chosen: Dictionary = available[randi() % available.size()]
	_activate_event(chosen)

func _activate_event(evt: Dictionary) -> void:
	var duration: float = evt.get("duration", 10.0)
	var modifier_value: float = evt.get("modifier_value", 1.0)
	var dr_spike: float = evt.get("dr_spike", 0.0)
	var escalated: bool = false

	# Event escalation with cap (Phase 2 TASK 7)
	var escalation_level: int = GameState.get_event_escalation_level(evt["id"])
	if escalation_level > 0:
		for _i in range(escalation_level):
			duration *= GameConfig.EVENT_ESCALATION_DURATION_MULT
			if modifier_value > 0.0 and modifier_value < 1.0:
				modifier_value *= GameConfig.EVENT_ESCALATION_SEVERITY_MULT
				modifier_value = maxf(modifier_value, 0.0)
			dr_spike *= GameConfig.EVENT_ESCALATION_SEVERITY_MULT
		escalated = true

	# Event resistance from upgrades (TASK 10)
	if GameState.event_duration_reduction > 0.0 and duration > 0.0:
		duration *= maxf(0.1, 1.0 - GameState.event_duration_reduction)
	if GameState.event_severity_reduction > 0.0:
		if modifier_value > 0.0 and modifier_value < 1.0:
			# Bring modifier closer to 1.0 (less severe)
			modifier_value = lerpf(modifier_value, 1.0, GameState.event_severity_reduction)
		dr_spike *= maxf(0.1, 1.0 - GameState.event_severity_reduction)

	var entry: Dictionary = {
		"def": evt.duplicate(),
		"remaining": duration,
		"escalated": escalated,
	}
	# Override values with modified versions
	entry["def"]["modifier_value"] = modifier_value

	# Apply immediate DR spike
	if dr_spike > 0.0:
		GameState.add_resource("detection_risk", dr_spike)

	# Record in event history (TASK 9)
	GameState.record_event(evt["id"])

	_active_events.append(entry)
	GameState.active_events = _active_events

	if evt.get("duration", 0.0) < 0.0:
		event_requires_repair.emit(evt["id"])
	event_started.emit(evt)

	_apply_combined_modifiers()

	# Check if this event triggers a chain (Phase 2 #5)
	_check_chain_triggers(evt["id"])

func _apply_combined_modifiers() -> void:
	var combined_bw_mult: float = 1.0
	var nodes_off: bool = false
	var combined_energy_mult: float = 1.0

	for entry: Dictionary in _active_events:
		var def: Dictionary = entry["def"]
		var mod_type: String = def.get("modifier_type", "")
		var mod_value: float = def.get("modifier_value", 1.0)

		match mod_type:
			"bw_multiplier":
				combined_bw_mult *= mod_value
			"nodes_disabled":
				nodes_off = true
			"energy_gen_multiplier":
				combined_energy_mult *= mod_value

	GameState.event_bw_multiplier = combined_bw_mult
	GameState.event_nodes_disabled = nodes_off
	GameState.event_energy_gen_multiplier = combined_energy_mult

func repair_event(event_id: String) -> void:
	for i in range(_active_events.size()):
		var entry: Dictionary = _active_events[i]
		if entry["def"]["id"] == event_id:
			event_ended.emit(event_id)
			_active_events.remove_at(i)
			_apply_combined_modifiers()
			GameState.active_events = _active_events
			return

func get_active_events() -> Array:
	return _active_events

func has_active_event(event_id: String) -> bool:
	for entry: Dictionary in _active_events:
		if entry["def"]["id"] == event_id:
			return true
	return false

func clear_all_events() -> void:
	_active_events.clear()
	GameState.event_bw_multiplier = 1.0
	GameState.event_nodes_disabled = false
	GameState.event_energy_gen_multiplier = 1.0
	GameState.active_events = _active_events
	_active_chains.clear()
	_chain_spawned_event_ids.clear()

# =========================================================
# DYNAMIC EVENT CHAINS (Phase 2 #5)
# =========================================================

func _check_chain_triggers(event_id: String) -> void:
	for chain_id: String in GameConfig.EVENT_CHAINS.keys():
		if _active_chains.has(chain_id):
			continue  # Already running this chain
		var chain_def: Dictionary = GameConfig.EVENT_CHAINS[chain_id]
		var trigger_events: Array = chain_def.get("trigger_events", [])
		if not trigger_events.has(event_id):
			continue
		# Check conditions
		if _chain_conditions_met(chain_def.get("trigger_conditions", {})):
			_start_chain(chain_id, chain_def)

func _chain_conditions_met(conditions: Dictionary) -> bool:
	for cond_key: String in conditions.keys():
		var cond_val = conditions[cond_key]
		match cond_key:
			"dr_above":
				if GameState.get_resource("detection_risk") < float(cond_val):
					return false
			"thermal_above":
				if GameState.get_thermal_load() < float(cond_val):
					return false
			"nodes_above":
				if GameState.get_node_count() < int(cond_val):
					return false
	return true

func _start_chain(chain_id: String, chain_def: Dictionary) -> void:
	var stages: Array = chain_def.get("stages", [])
	if stages.is_empty():
		return
	_active_chains[chain_id] = {
		"stage_index": 0,
		"active": true,
		"trigger_count": 0,
	}
	_activate_chain_stage(chain_id, chain_def, 0)
	print("[EventChain] Chain started: %s" % chain_def.get("name", chain_id))
	event_chain_started.emit(chain_id, stages[0])

func _activate_chain_stage(chain_id: String, chain_def: Dictionary, stage_index: int) -> void:
	var stages: Array = chain_def.get("stages", [])
	if stage_index >= stages.size():
		_complete_chain(chain_id)
		return

	var stage: Dictionary = stages[stage_index]
	_chain_spawned_event_ids.append(stage.get("id", ""))

	# Build a pseudo-event dict from the stage definition
	var pseudo_event: Dictionary = {
		"id":             stage.get("id", "chain_stage_%d" % stage_index),
		"name":           stage.get("name", "Chain Stage"),
		"description":    stage.get("description", ""),
		"category":       "chain",
		"duration":       stage.get("duration", 30.0),
		"modifier_type":  stage.get("modifier_type", "bw_multiplier"),
		"modifier_value": stage.get("modifier_value", 1.0),
		"dr_spike":       stage.get("dr_spike", 0.0),
		"severity":       stage.get("severity", "warning"),
		"icon":           "chain",
		"_chain_id":      chain_id,
		"_stage_index":   stage_index,
		"_next_stage_id": stage.get("next_stage_id", ""),
		"_next_chance":   stage.get("next_stage_chance", 0.0),
		"_collapse_type": stage.get("triggers_collapse", ""),
		"_collapse_chance": stage.get("collapse_chance", 0.0),
	}
	_activate_event(pseudo_event)
	event_chain_advanced.emit(chain_id, stage)

func _advance_chain_if_needed(expired_event_id: String) -> void:
	for chain_id: String in _active_chains.keys():
		var chain_state: Dictionary = _active_chains[chain_id]
		if not chain_state.get("active", false):
			continue
		var chain_def: Dictionary = GameConfig.EVENT_CHAINS.get(chain_id, {})
		var stages: Array = chain_def.get("stages", [])
		var stage_idx: int = chain_state["stage_index"]
		if stage_idx >= stages.size():
			continue
		var current_stage: Dictionary = stages[stage_idx]
		if current_stage.get("id", "") != expired_event_id and \
		   ("chain_stage_%d" % stage_idx) != expired_event_id:
			# Also match generated stage IDs
			if not expired_event_id.begins_with("chain_") or \
			   not _chain_spawned_event_ids.has(expired_event_id):
				continue

		# Stage expired — check if next stage triggers
		var next_id: String = current_stage.get("next_stage_id", "")
		var next_chance: float = current_stage.get("next_stage_chance", 0.0)

		# Optional: collapse chance
		var collapse_type: String = current_stage.get("triggers_collapse", "")
		var collapse_chance: float = current_stage.get("collapse_chance", 0.0)
		if collapse_type != "" and randf() < collapse_chance:
			GameState.trigger_meta_collapse(collapse_type)

		# Advance or complete chain
		if next_id != "" and randf() < next_chance:
			chain_state["stage_index"] = stage_idx + 1
			_activate_chain_stage(chain_id, chain_def, stage_idx + 1)
		else:
			_complete_chain(chain_id)

func _complete_chain(chain_id: String) -> void:
	if _active_chains.has(chain_id):
		_active_chains.erase(chain_id)
		event_chain_completed.emit(chain_id)
		print("[EventChain] Chain completed: %s" % chain_id)

func get_active_chain_ids() -> Array:
	return _active_chains.keys()

func is_chain_active(chain_id: String) -> bool:
	return _active_chains.has(chain_id)

# === DEBUG ===

func force_trigger_event(event_id: String) -> void:
	for evt: Dictionary in GameConfig.get_events_for_tier(GameState.tier):
		if evt["id"] == event_id:
			_activate_event(evt)
			print("[EventDebug] Force triggered: %s" % event_id)
			return
	print("[EventDebug] Event not found: %s" % event_id)

func force_trigger_all_events() -> void:
	print("[EventDebug] === FORCING ALL EVENTS ===")
	for evt: Dictionary in GameConfig.get_events_for_tier(GameState.tier):
		if not has_active_event(evt["id"]):
			_activate_event(evt)
	print("[EventDebug] Active events: %d" % _active_events.size())
	print_active_modifiers()

func print_active_modifiers() -> void:
	print("[EventDebug] === ACTIVE MODIFIERS ===")
	print("  event_bw_multiplier: %.3f" % GameState.event_bw_multiplier)
	print("  event_nodes_disabled: %s" % str(GameState.event_nodes_disabled))
	print("  event_energy_gen_multiplier: %.3f" % GameState.event_energy_gen_multiplier)
	for entry: Dictionary in _active_events:
		var def: Dictionary = entry["def"]
		var esc_tag: String = " [ESCALATED]" if entry.get("escalated", false) else ""
		print("  [%s] %s = %s (%.1fs)%s" % [
			def.get("id", "?"),
			def.get("modifier_type", "?"),
			str(def.get("modifier_value", 0)),
			entry["remaining"],
			esc_tag,
		])
