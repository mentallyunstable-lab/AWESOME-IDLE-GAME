extends Node
## replay_system.gd — Replay & Ghost System (Phase 6 #20)
##
## Records player decisions and state deltas each tick.
## Supports:
##   - Full replay of a prior run
##   - Ghost comparison (where did current run diverge?)
##   - Divergence point detection
##
## Recording is lightweight: stores compressed state deltas, not full snapshots.

signal replay_started
signal replay_stopped
signal ghost_diverged(delta: Dictionary)
signal recording_saved(run_id: String)

# === RECORDING STATE ===
var _is_recording: bool = false
var _current_recording: Array = []          # Array of frame records
var _saved_recordings: Dictionary = {}      # { run_id: Array[frame] }
var _record_interval: float = 1.0           # Record every 1 second
var _record_timer: float = 0.0
var _run_counter: int = 0

# === REPLAY STATE ===
var _is_replaying: bool = false
var _replay_frames: Array = []
var _replay_index: int = 0
var _replay_timer: float = 0.0

# === GHOST STATE ===
var _ghost_run_id: String = ""
var _ghost_frames: Array = []
var _ghost_pointer: int = 0
var _divergence_threshold: float = 5.0     # DR difference to flag divergence
var _diverged: bool = false

func _ready() -> void:
	TickEngine.game_tick.connect(_on_tick)
	GameState.collapse_triggered.connect(_on_collapse)

func _on_tick(delta: float) -> void:
	if _is_recording:
		_record_timer += delta
		if _record_timer >= _record_interval:
			_record_timer -= _record_interval
			_capture_frame()

	if _is_replaying:
		_replay_timer += delta
		if _replay_timer >= _record_interval:
			_replay_timer -= _record_interval
			_advance_replay()

	if not _ghost_run_id.is_empty():
		_compare_to_ghost()

func _on_collapse(collapse_type: String, _scope: String) -> void:
	if _is_recording:
		_capture_decision("collapse", {"type": collapse_type})

# =========================================================
# RECORDING
# =========================================================

func start_recording() -> void:
	_is_recording = true
	_current_recording = []
	_record_timer = 0.0
	print("[ReplaySystem] Recording started.")

func stop_and_save() -> String:
	if not _is_recording:
		return ""
	_is_recording = false
	_run_counter += 1
	var run_id: String = "run_%04d" % _run_counter
	_saved_recordings[run_id] = _current_recording.duplicate(true)
	_current_recording = []
	recording_saved.emit(run_id)
	print("[ReplaySystem] Saved recording '%s' (%d frames)" % [run_id, _saved_recordings[run_id].size()])
	return run_id

func record_decision(action: String, data: Dictionary = {}) -> void:
	if _is_recording:
		_capture_decision(action, data)

func _capture_frame() -> void:
	_current_recording.append({
		"t":        GameState.get_game_clock(),
		"type":     "state",
		"dr":       GameState.get_resource("detection_risk"),
		"inf":      GameState.get_resource("influence"),
		"nodes":    GameState.get_node_count(),
		"thermal":  GameState.get_thermal_load(),
		"doctrine": GameState.active_doctrine,
		"tier":     GameState.tier,
		"eq":       GameState.is_in_equilibrium(),
	})

func _capture_decision(action: String, data: Dictionary) -> void:
	var frame: Dictionary = {
		"t":      GameState.get_game_clock(),
		"type":   "decision",
		"action": action,
		"data":   data,
	}
	_current_recording.append(frame)

# =========================================================
# REPLAY
# =========================================================

func start_replay(run_id: String) -> bool:
	if not _saved_recordings.has(run_id):
		push_warning("[ReplaySystem] No recording with id: %s" % run_id)
		return false
	_replay_frames = _saved_recordings[run_id]
	_replay_index  = 0
	_replay_timer  = 0.0
	_is_replaying  = true
	replay_started.emit()
	print("[ReplaySystem] Replaying '%s' (%d frames)" % [run_id, _replay_frames.size()])
	return true

func stop_replay() -> void:
	_is_replaying = false
	_replay_index = 0
	replay_stopped.emit()
	print("[ReplaySystem] Replay stopped.")

func _advance_replay() -> void:
	if _replay_index >= _replay_frames.size():
		stop_replay()
		return

	var frame: Dictionary = _replay_frames[_replay_index]
	_replay_index += 1

	if frame.get("type", "") == "decision":
		print("[ReplaySystem] Decision at t=%.0f: %s" % [
			frame.get("t", 0.0), frame.get("action", "?")
		])

# =========================================================
# GHOST COMPARISON
# =========================================================

func set_ghost_run(run_id: String) -> bool:
	if not _saved_recordings.has(run_id):
		return false
	_ghost_run_id = run_id
	_ghost_frames = _saved_recordings[run_id]
	_ghost_pointer = 0
	_diverged = false
	print("[ReplaySystem] Ghost set to '%s'" % run_id)
	return true

func clear_ghost() -> void:
	_ghost_run_id = ""
	_ghost_frames = []
	_ghost_pointer = 0
	_diverged = false

func _compare_to_ghost() -> void:
	if _ghost_frames.is_empty() or _diverged:
		return

	# Find closest ghost frame by timestamp
	var current_t: float = GameState.get_game_clock()
	while _ghost_pointer < _ghost_frames.size() - 1:
		if _ghost_frames[_ghost_pointer + 1].get("t", 0.0) <= current_t:
			_ghost_pointer += 1
		else:
			break

	if _ghost_pointer >= _ghost_frames.size():
		return

	var ghost_frame: Dictionary = _ghost_frames[_ghost_pointer]
	if ghost_frame.get("type", "") != "state":
		return

	var ghost_dr: float = ghost_frame.get("dr", 0.0)
	var current_dr: float = GameState.get_resource("detection_risk")
	var dr_diff: float = absf(current_dr - ghost_dr)

	if dr_diff > _divergence_threshold:
		_diverged = true
		var divergence: Dictionary = {
			"timestamp":          current_t,
			"ghost_dr":           ghost_dr,
			"current_dr":         current_dr,
			"divergence":         dr_diff,
			"ghost_nodes":        ghost_frame.get("nodes", 0),
			"current_nodes":      GameState.get_node_count(),
			"ghost_doctrine":     ghost_frame.get("doctrine", ""),
			"current_doctrine":   GameState.active_doctrine,
		}
		ghost_diverged.emit(divergence)
		print("[ReplaySystem] DIVERGENCE at t=%.0f: DR delta=%.1f (current=%.1f vs ghost=%.1f)" % [
			current_t, dr_diff, current_dr, ghost_dr
		])

# =========================================================
# QUERY API
# =========================================================

func is_recording() -> bool:
	return _is_recording

func is_replaying() -> bool:
	return _is_replaying

func has_ghost() -> bool:
	return not _ghost_run_id.is_empty()

func get_saved_run_ids() -> Array:
	return _saved_recordings.keys()

func get_run_frame_count(run_id: String) -> int:
	return _saved_recordings.get(run_id, []).size()

func get_current_recording_frame_count() -> int:
	return _current_recording.size()

func get_ghost_run_id() -> String:
	return _ghost_run_id

func has_diverged() -> bool:
	return _diverged
