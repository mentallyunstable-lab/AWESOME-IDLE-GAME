extends Node
## system_memory.gd — Long-Term System Memory (Phase 1 #4)
##
## Not event memory. System-level meta-trends.
## Persists across prestige — tracks doctrine preferences, collapse patterns,
## per-tier performance, and generates meta-trend reports.
##
## Used later for AI narrative and adaptive balancing.

signal meta_trend_updated(report: Dictionary)

# === PER-TIER DR AVERAGES ===
# { tier: Array[float] } — rolling sample of DR values, kept to max 3600 entries
var tier_dr_averages: Dictionary = {}

# === COLLAPSE HISTORY ===
# { tier: { collapse_type: count } }
var tier_collapse_history: Dictionary = {}

# === TIER PERFORMANCE TRENDS ===
# { tier: { sessions: int, avg_inf_rate: float, avg_survival_time: float } }
var tier_performance_trends: Dictionary = {}

# === DOCTRINE TIME TRACKING ===
# { doctrine_id: total_seconds_active }
var doctrine_time_tracking: Dictionary = {}

# Derived
var doctrine_preference: String = ""   # Most-used doctrine across all sessions

# Internal session state
var _session_start_time: float = 0.0
var _sample_accumulator: float = 0.0
const SAMPLE_INTERVAL: float = 1.0
const MAX_DR_SAMPLES_PER_TIER: int = 3600

func _ready() -> void:
	TickEngine.game_tick.connect(_on_tick)
	GameState.collapse_triggered.connect(_on_collapse)
	GameState.doctrine_changed.connect(_on_doctrine_changed)
	_session_start_time = GameState.get_game_clock()

func _on_tick(delta: float) -> void:
	_sample_accumulator += delta
	if _sample_accumulator >= SAMPLE_INTERVAL:
		_sample_accumulator -= SAMPLE_INTERVAL
		_sample_current_state(delta)

func _sample_current_state(delta: float) -> void:
	var tier: int = GameState.tier

	# Sample DR
	if not tier_dr_averages.has(tier):
		tier_dr_averages[tier] = []
	tier_dr_averages[tier].append(GameState.get_resource("detection_risk"))
	if tier_dr_averages[tier].size() > MAX_DR_SAMPLES_PER_TIER:
		tier_dr_averages[tier].pop_front()

	# Track doctrine time
	var doctrine: String = GameState.active_doctrine
	if not doctrine_time_tracking.has(doctrine):
		doctrine_time_tracking[doctrine] = 0.0
	doctrine_time_tracking[doctrine] += delta

	# Track tier performance
	if not tier_performance_trends.has(tier):
		tier_performance_trends[tier] = {"sessions": 0, "total_inf": 0.0, "total_time": 0.0}
	tier_performance_trends[tier]["total_inf"] += GameState.get_per_second("influence") * delta
	tier_performance_trends[tier]["total_time"] += delta

func _on_collapse(collapse_type: String, _scope: String) -> void:
	var tier: int = GameState.tier
	if not tier_collapse_history.has(tier):
		tier_collapse_history[tier] = {}
	if not tier_collapse_history[tier].has(collapse_type):
		tier_collapse_history[tier][collapse_type] = 0
	tier_collapse_history[tier][collapse_type] += 1

func _on_doctrine_changed(_doctrine_id: String) -> void:
	pass  # Tracking handled per-tick

# =========================================================
# META-TREND REPORT
# =========================================================

func get_meta_trend_report() -> Dictionary:
	# Find preferred doctrine
	var max_time: float = 0.0
	doctrine_preference = ""
	for d: String in doctrine_time_tracking.keys():
		if doctrine_time_tracking[d] > max_time:
			max_time = doctrine_time_tracking[d]
			doctrine_preference = d

	# Per-tier DR averages
	var avg_dr_by_tier: Dictionary = {}
	for t: int in tier_dr_averages.keys():
		var samples: Array = tier_dr_averages[t]
		if not samples.is_empty():
			var total: float = 0.0
			for v: float in samples:
				total += v
			avg_dr_by_tier[t] = total / float(samples.size())

	# Per-tier avg influence rate
	var avg_inf_by_tier: Dictionary = {}
	for t: int in tier_performance_trends.keys():
		var perf: Dictionary = tier_performance_trends[t]
		if perf["total_time"] > 0.0:
			avg_inf_by_tier[t] = perf["total_inf"] / perf["total_time"]

	var report: Dictionary = {
		"doctrine_preference":     doctrine_preference,
		"doctrine_time_tracking":  doctrine_time_tracking.duplicate(),
		"avg_dr_by_tier":          avg_dr_by_tier,
		"avg_inf_rate_by_tier":    avg_inf_by_tier,
		"collapse_history":        tier_collapse_history.duplicate(true),
		"session_duration":        GameState.get_game_clock() - _session_start_time,
	}

	meta_trend_updated.emit(report)
	return report

## Returns the doctrine the player has used longest.
func get_preferred_doctrine() -> String:
	return doctrine_preference

## Returns the most frequent collapse type for a given tier.
func get_most_frequent_collapse(tier: int) -> String:
	var history: Dictionary = tier_collapse_history.get(tier, {})
	var max_count: int = 0
	var most_common: String = ""
	for ct: String in history.keys():
		if history[ct] > max_count:
			max_count = history[ct]
			most_common = ct
	return most_common

## Returns total time spent in a given doctrine.
func get_doctrine_time(doctrine_id: String) -> float:
	return doctrine_time_tracking.get(doctrine_id, 0.0)

## Returns average DR for a given tier across all recorded samples.
func get_avg_dr_for_tier(tier: int) -> float:
	var samples: Array = tier_dr_averages.get(tier, [])
	if samples.is_empty():
		return -1.0
	var total: float = 0.0
	for v: float in samples:
		total += v
	return total / float(samples.size())

# =========================================================
# SAVE / LOAD (persists across prestige)
# =========================================================

func get_save_data() -> Dictionary:
	return {
		"tier_dr_averages":       tier_dr_averages.duplicate(true),
		"tier_collapse_history":  tier_collapse_history.duplicate(true),
		"tier_performance_trends": tier_performance_trends.duplicate(true),
		"doctrine_time_tracking": doctrine_time_tracking.duplicate(),
		"doctrine_preference":    doctrine_preference,
	}

func load_save_data(data: Dictionary) -> void:
	tier_dr_averages          = data.get("tier_dr_averages", {})
	tier_collapse_history     = data.get("tier_collapse_history", {})
	tier_performance_trends   = data.get("tier_performance_trends", {})
	doctrine_time_tracking    = data.get("doctrine_time_tracking", {})
	doctrine_preference       = data.get("doctrine_preference", "")

func debug_print() -> void:
	var report := get_meta_trend_report()
	print("[SystemMemory] === META-TREND REPORT ===")
	print("  Preferred doctrine: %s" % report["doctrine_preference"])
	print("  Session duration: %.0fs" % report["session_duration"])
	for t: int in report["avg_dr_by_tier"].keys():
		print("  Tier %d avg DR: %.1f" % [t, report["avg_dr_by_tier"][t]])
	for t: int in report["collapse_history"].keys():
		print("  Tier %d collapses: %s" % [t, str(report["collapse_history"][t])])
