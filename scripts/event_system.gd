extends Node
## event_system.gd — Random event engine.
## Fires events at random intervals, applies modifiers, expires them cleanly.

signal event_started(event_data: Dictionary)
signal event_ended(event_id: String)
signal event_requires_repair(event_id: String)

var _event_timer: float = 0.0
var _next_event_time: float = 0.0
var _active_events: Array = []  # Array of { "def": {}, "remaining": float }

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

	# Tick down active events
	_update_active_events(delta)

	# Event spawn timer
	_event_timer += delta

	# Higher DR = more frequent events above danger threshold
	var dr: float = GameState.get_resource("detection_risk")
	var danger: float = cfg.get("dr_danger_threshold", 85.0)
	var time_mult: float = 1.0
	if dr > danger:
		time_mult = 0.5  # Events come twice as fast

	if _event_timer >= _next_event_time * time_mult:
		_spawn_random_event()
		_roll_next_event_time()

func _update_active_events(delta: float) -> void:
	var expired: Array = []

	for i in range(_active_events.size()):
		var entry: Dictionary = _active_events[i]
		var def: Dictionary = entry["def"]
		var remaining: float = entry["remaining"]

		# Manual repair events don't tick down
		if remaining < 0.0:
			continue

		entry["remaining"] = remaining - delta
		if entry["remaining"] <= 0.0:
			expired.append(i)

	# Remove expired (reverse order to preserve indices)
	expired.reverse()
	for idx: int in expired:
		var entry: Dictionary = _active_events[idx]
		_remove_event_modifiers(entry["def"])
		event_ended.emit(entry["def"]["id"])
		_active_events.remove_at(idx)

	_apply_combined_modifiers()

func _spawn_random_event() -> void:
	# Don't stack the same event
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
	var entry: Dictionary = {
		"def": chosen,
		"remaining": chosen.get("duration", 10.0),
	}

	# Apply immediate DR spike if any
	var dr_spike: float = chosen.get("dr_spike", 0.0)
	if dr_spike > 0.0:
		GameState.add_resource("detection_risk", dr_spike)

	_active_events.append(entry)
	GameState.active_events = _active_events

	if chosen.get("duration", 0.0) < 0.0:
		event_requires_repair.emit(chosen["id"])
	event_started.emit(chosen)

func _apply_combined_modifiers() -> void:
	# Reset event modifiers
	var combined_bw_mult: float = 1.0
	var nodes_off: bool = false

	for entry: Dictionary in _active_events:
		var def: Dictionary = entry["def"]
		var mod_type: String = def.get("modifier_type", "")
		var mod_value: float = def.get("modifier_value", 1.0)

		match mod_type:
			"bw_multiplier":
				combined_bw_mult *= mod_value
			"nodes_disabled":
				nodes_off = true

	GameState.event_bw_multiplier = combined_bw_mult
	GameState.event_nodes_disabled = nodes_off

func _remove_event_modifiers(_def: Dictionary) -> void:
	# Modifiers are recalculated combinatorially, no individual removal needed
	pass

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
	GameState.active_events = _active_events
