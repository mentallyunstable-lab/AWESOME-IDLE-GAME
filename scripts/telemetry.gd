extends Node
## telemetry.gd — Deep Telemetry Recorder (Phase 4 #13)
##
## Per-second sampling of all key game metrics.
## Maintains a rolling 5-minute buffer.
## Supports JSON export and statistical queries.
##
## Used by: BalanceAnalyzer, SystemAdvisor, CollapseSimulator, debug UI.

const BUFFER_DURATION: float = GameConfig.TELEMETRY_BUFFER_SECONDS
const SAMPLE_INTERVAL: float = GameConfig.TELEMETRY_SAMPLE_RATE

var _buffer: Array = []
var _sample_timer: float = 0.0
var _total_samples_recorded: int = 0

func _ready() -> void:
	TickEngine.game_tick.connect(_on_tick)

func _on_tick(delta: float) -> void:
	_sample_timer += delta
	if _sample_timer >= SAMPLE_INTERVAL:
		_sample_timer -= SAMPLE_INTERVAL
		_record_sample()

func _record_sample() -> void:
	var has_energy: bool = GameState.resources.has("energy")
	var adapt_level: float = 1.0
	var noise_val: float = 0.0
	var eq_state: String = "unknown"
	var collapse_risk: float = 0.0
	var dr_phase: String = "predictable"

	if has_node("/root/AdaptiveDifficulty"):
		var ad := get_node("/root/AdaptiveDifficulty")
		adapt_level = ad.adaptation_level
		noise_val = ad.get_noise_value(0)
		eq_state = ad.equilibrium_state
		dr_phase = ad.get_dr_phase()

	if has_node("/root/CollapseSimulator"):
		collapse_risk = get_node("/root/CollapseSimulator").get_collapse_risk_score()

	var sample: Dictionary = {
		"t":            GameState.get_game_clock(),
		"tier":         GameState.tier,
		# Resources
		"inf":          GameState.get_resource("influence"),
		"inf_rate":     GameState.get_per_second("influence"),
		"dr":           GameState.get_resource("detection_risk"),
		"dr_rate":      GameState.get_per_second("detection_risk"),
		"bw":           GameState.get_resource("bandwidth"),
		"energy":       GameState.get_resource("energy") if has_energy else 0.0,
		"energy_rate":  GameState.get_per_second("energy") if has_energy else 0.0,
		# Nodes
		"nodes":        GameState.get_node_count(),
		"degraded":     GameState.get_degraded_node_count(),
		# Constraints
		"thermal":      GameState.get_thermal_load(),
		# System state
		"efficiency":   GameState.calculate_global_efficiency(),
		"events":       GameState.active_events.size(),
		"dr_band":      GameState.get_dr_band(),
		"dr_phase":     dr_phase,
		"doctrine":     GameState.active_doctrine,
		"equilibrium":  GameState.is_in_equilibrium(),
		"eq_state":     eq_state,
		# AI Layer
		"adapt_level":  adapt_level,
		"noise":        noise_val,
		"collapse_risk": collapse_risk,
	}

	_buffer.append(sample)
	_total_samples_recorded += 1

	# Prune old samples outside buffer window
	var cutoff: float = sample["t"] - BUFFER_DURATION
	while _buffer.size() > 0 and _buffer[0]["t"] < cutoff:
		_buffer.pop_front()

# =========================================================
# QUERY API
# =========================================================

func get_buffer() -> Array:
	return _buffer

func get_recent_samples(seconds: float) -> Array:
	var cutoff: float = GameState.get_game_clock() - seconds
	var result: Array = []
	for s: Dictionary in _buffer:
		if s["t"] >= cutoff:
			result.append(s)
	return result

func get_latest() -> Dictionary:
	if _buffer.is_empty():
		return {}
	return _buffer[_buffer.size() - 1]

## Returns the running average of a metric over the given window.
func get_average(key: String, window_seconds: float = 60.0) -> float:
	var samples: Array = get_recent_samples(window_seconds)
	if samples.is_empty():
		return 0.0
	var total: float = 0.0
	for s: Dictionary in samples:
		total += float(s.get(key, 0.0))
	return total / float(samples.size())

## Returns [min, max] of a metric over the given window.
func get_min_max(key: String, window_seconds: float = 60.0) -> Array:
	var samples: Array = get_recent_samples(window_seconds)
	if samples.is_empty():
		return [0.0, 0.0]
	var min_val: float = INF
	var max_val: float = -INF
	for s: Dictionary in samples:
		var v: float = float(s.get(key, 0.0))
		min_val = minf(min_val, v)
		max_val = maxf(max_val, v)
	return [min_val, max_val]

## Returns variance of a metric over the given window.
func get_variance(key: String, window_seconds: float = 60.0) -> float:
	var samples: Array = get_recent_samples(window_seconds)
	if samples.size() < 2:
		return 0.0
	var mean: float = get_average(key, window_seconds)
	var variance: float = 0.0
	for s: Dictionary in samples:
		var diff: float = float(s.get(key, 0.0)) - mean
		variance += diff * diff
	return variance / float(samples.size())

## Returns the trend (slope) of a metric over the given window.
func get_trend(key: String, window_seconds: float = 60.0) -> float:
	var samples: Array = get_recent_samples(window_seconds)
	if samples.size() < 2:
		return 0.0
	var first: Dictionary = samples[0]
	var last: Dictionary = samples[samples.size() - 1]
	var dt: float = last["t"] - first["t"]
	if dt <= 0.0:
		return 0.0
	return (float(last.get(key, 0.0)) - float(first.get(key, 0.0))) / dt

# =========================================================
# EXPORT
# =========================================================

func export_json() -> String:
	var export_data: Dictionary = {
		"export_time":       GameState.get_game_clock(),
		"tier":              GameState.tier,
		"buffer_duration":   BUFFER_DURATION,
		"sample_count":      _buffer.size(),
		"total_recorded":    _total_samples_recorded,
		"samples":           _buffer,
	}
	return JSON.stringify(export_data, "\t")

func get_summary() -> Dictionary:
	var window: float = 60.0
	return {
		"buffer_size":       _buffer.size(),
		"total_recorded":    _total_samples_recorded,
		"avg_inf_rate":      get_average("inf_rate", window),
		"avg_dr":            get_average("dr", window),
		"avg_dr_rate":       get_average("dr_rate", window),
		"avg_thermal":       get_average("thermal", window),
		"avg_efficiency":    get_average("efficiency", window),
		"dr_variance":       get_variance("dr", window),
		"inf_trend":         get_trend("inf", window),
		"collapse_risk":     get_average("collapse_risk", window),
	}

func clear() -> void:
	_buffer.clear()
	_sample_timer = 0.0
