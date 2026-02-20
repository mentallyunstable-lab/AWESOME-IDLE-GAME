extends Node
## system_advisor.gd — System Advisor AI + Strategic Personality Profiles (Phase 7 #22, #23)
##
## === DESIGN ===
## Advisory-only AI. Does NOT take actions — only suggests.
## Uses internal simulation (CollapseSimulator) for predictions.
## Occasionally wrong — confidence is randomized to simulate uncertainty.
## Personality profiles shape what advice is prioritized.
##
## === PERSONALITIES (Phase 7 #23) ===
## See GameConfig.PERSONALITY_PROFILES:
##   conservative_stabilizer | growth_maximizer | risk_gambler
##   thermal_minimalist | chaos_harnessing

signal advice_generated(advice: Dictionary)
signal personality_changed(profile_id: String)

var _active_personality: String = "conservative_stabilizer"
var _advice_history: Array = []
var _advice_timer: float = 0.0

const ADVICE_INTERVAL: float = 28.0     # How often to generate new advice
const MAX_ADVICE_HISTORY: int = 30
const CONFIDENCE_VARIANCE: float = 0.22 # How much confidence can swing

func _ready() -> void:
	TickEngine.game_tick.connect(_on_tick)

func _on_tick(delta: float) -> void:
	_advice_timer += delta
	if _advice_timer >= ADVICE_INTERVAL:
		_advice_timer = 0.0
		_generate_all_advice()

# =========================================================
# PERSONALITY
# =========================================================

func set_personality(profile_id: String) -> void:
	if not GameConfig.PERSONALITY_PROFILES.has(profile_id):
		push_warning("[SystemAdvisor] Unknown personality: %s" % profile_id)
		return
	_active_personality = profile_id
	print("[SystemAdvisor] Personality -> %s" % GameConfig.PERSONALITY_PROFILES[profile_id].get("name", profile_id))
	personality_changed.emit(profile_id)

func get_personality() -> String:
	return _active_personality

func get_personality_def() -> Dictionary:
	return GameConfig.PERSONALITY_PROFILES.get(_active_personality, {})

func get_personality_summary() -> Dictionary:
	var p: Dictionary = get_personality_def()
	return {
		"id":                _active_personality,
		"name":              p.get("name", "Unknown"),
		"description":       p.get("description", ""),
		"risk_tolerance":    p.get("risk_tolerance", 0.5),
		"preferred_doctrine": p.get("preferred_doctrine", "stability"),
		"dr_threshold":      p.get("dr_threshold", 60.0),
	}

# =========================================================
# ADVICE GENERATION
# =========================================================

func _generate_all_advice() -> void:
	var personality: Dictionary = get_personality_def()
	var dr: float = GameState.get_resource("detection_risk")
	var dr_rate: float = GameState.get_per_second("detection_risk")
	var inf_rate: float = GameState.get_per_second("influence")
	var thermal: float = GameState.get_thermal_load()
	var risk_tolerance: float = personality.get("risk_tolerance", 0.5)
	var dr_threshold: float = personality.get("dr_threshold", 60.0)
	var preferred_doctrine: String = personality.get("preferred_doctrine", "stability")
	var collapse_risk: float = 0.0

	if has_node("/root/CollapseSimulator"):
		collapse_risk = get_node("/root/CollapseSimulator").get_collapse_risk_score()

	# --- Doctrine suggestion ---
	if dr > dr_threshold * 0.9 and GameState.active_doctrine != preferred_doctrine:
		_emit_advice({
			"type":             "doctrine_switch",
			"message":          "DR at %.0f%% — %s recommends switching to %s doctrine." % [
				dr, get_personality_def().get("name", "Advisor"), preferred_doctrine
			],
			"suggested_action": "switch_doctrine:%s" % preferred_doctrine,
			"confidence":       _vary_confidence(0.80),
		})

	# --- Collapse warning (uses simulator) ---
	if collapse_risk > 0.45:
		var urgency: String = "critical" if collapse_risk > 0.72 else "high"
		_emit_advice({
			"type":             "collapse_warning",
			"message":          "Collapse probability at %.0f%% — take defensive action now." % (collapse_risk * 100.0),
			"suggested_action": "reduce_dr",
			"confidence":       _vary_confidence(0.88),
			"urgency":          urgency,
		})
	elif dr_rate > 0.4:
		var ttc: float = (100.0 - dr) / dr_rate if dr_rate > 0.0 else 999.0
		if ttc < 90.0:
			_emit_advice({
				"type":             "ttc_warning",
				"message":          "DR trajectory: collapse in ~%.0fs at current rate." % ttc,
				"suggested_action": "reduce_node_count",
				"confidence":       _vary_confidence(0.82),
				"urgency":          "high" if ttc < 45.0 else "medium",
			})

	# --- Thermal advice ---
	if thermal > 55.0:
		var thermal_weight: float = personality.get("thermal_weight", 1.0)
		if thermal_weight > 1.2 or thermal > 75.0:
			_emit_advice({
				"type":             "thermal_warning",
				"message":          "Thermal load at %.0f%% — hardware stress accumulating." % thermal,
				"suggested_action": "reduce_thermal",
				"confidence":       _vary_confidence(0.78),
			})

	# --- Growth opportunity (personality-dependent) ---
	if risk_tolerance > 0.6 and inf_rate > 5.0 and dr < dr_threshold * 0.7:
		_emit_advice({
			"type":             "growth_opportunity",
			"message":          "System stable and producing %.1f inf/s — safe to expand." % inf_rate,
			"suggested_action": "deploy_nodes",
			"confidence":       _vary_confidence(0.70),
		})

	# --- Equilibrium analysis ---
	if not GameState.is_in_equilibrium() and GameState.get_game_clock() > 60.0:
		var eq_timer: float = GameState.get_equilibrium_timer()
		if eq_timer > 45.0:
			_emit_advice({
				"type":             "equilibrium_unstable",
				"message":          "System drifting — equilibrium not achieved after %.0fs." % eq_timer,
				"suggested_action": "stabilize",
				"confidence":       _vary_confidence(0.72),
			})

	# --- Region specialization hint ---
	if GameState.tier >= 1 and not GameState.regions.is_empty():
		_emit_advice({
			"type":             "region_hint",
			"message":          "Region specialization could optimize constraint distribution.",
			"suggested_action": "optimize_regions",
			"confidence":       _vary_confidence(0.60),
		})

	# --- Doctrine evolution hint ---
	if has_node("/root/SystemMemory"):
		var sm := get_node("/root/SystemMemory")
		for mutation_id: String in GameConfig.DOCTRINE_MUTATIONS.keys():
			var mutation: Dictionary = GameConfig.DOCTRINE_MUTATIONS[mutation_id]
			var parent: String = mutation.get("parent_doctrine", "")
			if parent == GameState.active_doctrine:
				var conds: Dictionary = mutation.get("unlock_conditions", {})
				var stealth_time: float = sm.get_doctrine_time("stealth")
				var parent_time: float = sm.get_doctrine_time(parent)
				var req_time: float = conds.get(parent + "_doctrine_time", 999999.0)
				if parent_time >= req_time * 0.8:
					_emit_advice({
						"type":             "doctrine_evolution",
						"message":          "Approaching unlock for '%s' doctrine mutation." % mutation.get("name", mutation_id),
						"suggested_action": "check_doctrine_tree",
						"confidence":       _vary_confidence(0.65),
					})
					break

func _emit_advice(advice: Dictionary) -> void:
	advice["personality"] = _active_personality
	advice["timestamp"]   = GameState.get_game_clock()
	if not advice.has("urgency"):
		advice["urgency"] = "low"

	_advice_history.append(advice)
	while _advice_history.size() > MAX_ADVICE_HISTORY:
		_advice_history.pop_front()

	advice_generated.emit(advice)
	print("[SystemAdvisor|%s] [%.0f%%] (%s) %s" % [
		_active_personality,
		advice.get("confidence", 0.0) * 100.0,
		advice.get("urgency", "low").to_upper(),
		advice.get("message", ""),
	])

func _vary_confidence(base: float) -> float:
	var variance: float = randf_range(-CONFIDENCE_VARIANCE, CONFIDENCE_VARIANCE * 0.6)
	return clampf(base + variance, 0.08, 1.0)

# =========================================================
# TREND ANALYSIS
# =========================================================

func analyze_trends() -> Dictionary:
	if not has_node("/root/Telemetry"):
		return {"error": "Telemetry system not available."}

	var tel := get_node("/root/Telemetry")
	var samples: Array = tel.get_recent_samples(120.0)

	if samples.size() < 5:
		return {"error": "Insufficient telemetry data (need >=5 samples)."}

	var first: Dictionary = samples[0]
	var last: Dictionary = samples[samples.size() - 1]
	var dt: float = last["t"] - first["t"]
	if dt <= 0.0:
		return {"error": "Zero time span in telemetry."}

	return {
		"dr_trend":       (last["dr"] - first["dr"]) / dt,
		"inf_trend":      (last["inf"] - first["inf"]) / dt,
		"thermal_trend":  (last.get("thermal", 0.0) - first.get("thermal", 0.0)) / dt,
		"sample_count":   samples.size(),
		"window_seconds": dt,
		"collapse_risk":  tel.get_average("collapse_risk", 60.0),
		"avg_dr":         tel.get_average("dr", 60.0),
		"avg_inf_rate":   tel.get_average("inf_rate", 60.0),
		"eq_state":       last.get("eq_state", "unknown"),
		"dr_phase":       last.get("dr_phase", "predictable"),
	}

# =========================================================
# QUERY API
# =========================================================

func get_recent_advice(count: int = 5) -> Array:
	var result: Array = []
	var start: int = maxi(0, _advice_history.size() - count)
	for i in range(start, _advice_history.size()):
		result.append(_advice_history[i])
	return result

func get_advice_by_type(advice_type: String) -> Array:
	var result: Array = []
	for a: Dictionary in _advice_history:
		if a.get("type", "") == advice_type:
			result.append(a)
	return result

func force_generate_advice() -> void:
	_advice_timer = ADVICE_INTERVAL
