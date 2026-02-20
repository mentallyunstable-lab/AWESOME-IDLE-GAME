extends Node
## adaptive_difficulty.gd — Dynamic self-balancing tuning core.
##
## === DESIGN PHILOSOPHY ===
## The system subtly rebalances itself based on player performance.
## Changes are never abrupt — always smoothed over time.
## Clamped to safe bounds — can never overcorrect into unwinnable states.
##
## === SYSTEMS INSIDE ===
## 1. Adaptive Difficulty Engine (Phase 1 #1)
## 2. System Noise Injection (Phase 3 #11)
## 3. DR Phase Transitions (Phase 3 #10)

# === ADAPTIVE DIFFICULTY STATE ===
var player_skill_score: float = 0.5       # 0.0 = struggling, 1.0 = dominating
var adaptation_level: float = 1.0         # Difficulty multiplier (smoothed)
var performance_window: Array = []        # Recent { time, inf_rate, dr_rate, dr } samples

# Computed averages
var _avg_influence_rate: float = 0.0
var _avg_dr_rate: float = 0.0
var _collapse_count: int = 0
var _session_elapsed: float = 0.0

# Dynamic output scalars (applied by resources.gd and other systems)
var dr_gain_multiplier: float = 1.0
var event_frequency_multiplier: float = 1.0
var maintenance_cost_scalar: float = 1.0
var constraint_regen_rate: float = 1.0

# === NOISE STATE (Phase 3 #11) ===
var _noise_phase: float = 0.0

# === EQUILIBRIUM DEEP MODEL STATE (Phase 3 #9) ===
var equilibrium_state: String = "unknown"   # stable | meta-stable | chaotic | collapse_trajectory
var _eq_dr_history: Array = []              # { time, dr } for derivative calc
var _eq_deriv_1: float = 0.0               # First derivative of DR
var _eq_deriv_2: float = 0.0               # Second derivative (acceleration)

func _ready() -> void:
	TickEngine.game_tick.connect(_on_tick)
	if GameState.has_signal("collapse_triggered"):
		GameState.collapse_triggered.connect(_on_collapse)

func _on_tick(delta: float) -> void:
	_session_elapsed += delta
	_record_performance_sample(delta)
	update_adaptive_difficulty(delta)
	_advance_noise(delta)
	_update_equilibrium_deep_model(delta)

func _on_collapse(_collapse_type: String, _scope: String) -> void:
	_collapse_count += 1

# =========================================================
# ADAPTIVE DIFFICULTY ENGINE (Phase 1 #1)
# =========================================================

func _record_performance_sample(_delta: float) -> void:
	performance_window.append({
		"time": _session_elapsed,
		"inf_rate": GameState.get_per_second("influence"),
		"dr_rate": GameState.get_per_second("detection_risk"),
		"dr": GameState.get_resource("detection_risk"),
	})
	var cutoff: float = _session_elapsed - GameConfig.ADAPTIVE_WINDOW
	while performance_window.size() > 0 and performance_window[0]["time"] < cutoff:
		performance_window.pop_front()

func update_adaptive_difficulty(delta: float) -> void:
	if performance_window.size() < 8:
		return

	var total_inf: float = 0.0
	var total_dr_rate: float = 0.0
	for s: Dictionary in performance_window:
		total_inf += s["inf_rate"]
		total_dr_rate += s["dr_rate"]

	_avg_influence_rate = total_inf / float(performance_window.size())
	_avg_dr_rate = total_dr_rate / float(performance_window.size())

	# Skill score: high sustained influence + low DR = skilled
	var inf_score: float = clampf(_avg_influence_rate / 15.0, 0.0, 1.0)
	var dr: float = GameState.get_resource("detection_risk")
	var dr_score: float = 1.0 - clampf(dr / 100.0, 0.0, 1.0)
	var collapse_penalty: float = clampf(float(_collapse_count) / 8.0, 0.0, 0.5)

	var target_skill: float = (inf_score * 0.45 + dr_score * 0.45) - collapse_penalty * 0.1
	target_skill = clampf(target_skill, 0.0, 1.0)

	# Smooth transition — never feels artificial
	player_skill_score = lerpf(player_skill_score, target_skill, GameConfig.ADAPTIVE_SMOOTHING * delta)

	# High skill -> harder game (adaptation_level > 1.0)
	# Low skill  -> easier game (adaptation_level < 1.0)
	var raw_adapt: float = 1.0 + (player_skill_score - 0.5) * 0.8
	adaptation_level = lerpf(adaptation_level, raw_adapt, GameConfig.ADAPTIVE_SMOOTHING * delta)
	adaptation_level = clampf(adaptation_level,
		GameConfig.ADAPTIVE_DR_GAIN_RANGE[0],
		GameConfig.ADAPTIVE_DR_GAIN_RANGE[1])

	# Derive scalars from adaptation level
	var t: float = (adaptation_level - 1.0)  # -0.45 to +0.80
	dr_gain_multiplier      = clampf(1.0 + t * 0.60, GameConfig.ADAPTIVE_DR_GAIN_RANGE[0], GameConfig.ADAPTIVE_DR_GAIN_RANGE[1])
	event_frequency_multiplier = clampf(1.0 + t * 0.45, GameConfig.ADAPTIVE_EVENT_FREQ_RANGE[0], GameConfig.ADAPTIVE_EVENT_FREQ_RANGE[1])
	maintenance_cost_scalar = clampf(1.0 + t * 0.30, GameConfig.ADAPTIVE_MAINTENANCE_RANGE[0], GameConfig.ADAPTIVE_MAINTENANCE_RANGE[1])
	constraint_regen_rate   = clampf(1.0 - t * 0.18, GameConfig.ADAPTIVE_CONSTRAINT_REGEN_RANGE[0], GameConfig.ADAPTIVE_CONSTRAINT_REGEN_RANGE[1])

func get_adaptation_report() -> Dictionary:
	return {
		"skill_score":           player_skill_score,
		"adaptation_level":      adaptation_level,
		"dr_gain_mult":          dr_gain_multiplier,
		"event_freq_mult":       event_frequency_multiplier,
		"maintenance_scalar":    maintenance_cost_scalar,
		"constraint_regen":      constraint_regen_rate,
		"avg_influence_rate":    _avg_influence_rate,
		"avg_dr_rate":           _avg_dr_rate,
		"collapse_count":        _collapse_count,
		"equilibrium_state":     equilibrium_state,
	}

# =========================================================
# SYSTEM NOISE INJECTION (Phase 3 #11)
# =========================================================

func _advance_noise(delta: float) -> void:
	_noise_phase += delta * GameConfig.NOISE_SPEED

## Returns a bounded noise value for a given channel.
## Subtle multi-frequency sine composition — never pure random.
func get_noise_value(channel: int = 0) -> float:
	var dr: float = GameState.get_resource("detection_risk")
	var base_amp: float = GameConfig.NOISE_BASE_AMPLITUDE
	var dr_scale: float = (dr / 100.0) * GameConfig.NOISE_DR_SCALE_FACTOR * 12.0
	var amplitude: float = minf(base_amp + dr_scale, GameConfig.NOISE_MAX_AMPLITUDE)

	# Three-frequency composition for organic feel
	var p: float = _noise_phase
	var c: float = float(channel)
	var n: float  = sin(p * 7.31 + c * 2.17) * 0.50
	n += sin(p * 13.73 + c * 5.31) * 0.30
	n += sin(p * 31.13 + c * 9.71) * 0.20

	return n * amplitude

## Returns subtle constraint regeneration drift.
func get_constraint_drift(constraint_id: String) -> float:
	var hash_offset: float = float(constraint_id.hash() % 100) / 100.0
	var dr: float = GameState.get_resource("detection_risk")
	var scale: float = GameConfig.NOISE_CONSTRAINT_DRIFT * (1.0 + dr / 100.0)
	return sin(_noise_phase * 3.71 + hash_offset * 6.28) * scale

# =========================================================
# DR PHASE TRANSITIONS (Phase 3 #10)
# =========================================================

## Returns the current DR phase as a string enum.
func get_dr_phase() -> String:
	var dr: float = GameState.get_resource("detection_risk")
	if dr < 25.0:
		return "predictable"
	elif dr < 50.0:
		return "noisy"
	elif dr < 75.0:
		return "coupled"
	else:
		return "exponential"

## Applies nonlinear phase-based behavior to base DR gain.
## Each band applies a distinct function, not an if-statement scalar.
func apply_dr_phase_behavior(base_dr_gain: float) -> float:
	var phase: String = get_dr_phase()
	var dr: float = GameState.get_resource("detection_risk")

	match phase:
		"predictable":
			# Band 0-25: Clean linear behavior, no distortion.
			return base_dr_gain

		"noisy":
			# Band 25-50: Micro-fluctuations injected via noise channel 0.
			var band_progress: float = (dr - 25.0) / 25.0
			var noise_strength: float = band_progress * 0.6
			return base_dr_gain * (1.0 + get_noise_value(0) * noise_strength)

		"coupled":
			# Band 50-75: Constraint cross-coupling active.
			var thermal_norm: float = GameState.get_thermal_load() / 100.0
			var coupling: float = thermal_norm * GameConfig.CONSTRAINT_INTERACTIONS.get("thermal_load", {}).get("dr_gain", 0.0)
			var band_noise: float = get_noise_value(1) * 0.35
			return base_dr_gain * (1.0 + coupling + band_noise)

		"exponential":
			# Band 75-100: Exponential instability — every point feels heavier.
			var excess: float = (dr - 75.0) / 25.0  # 0.0 -> 1.0
			var exp_mult: float = 1.0 + (excess * excess) * 2.2  # Quadratic escalation
			return base_dr_gain * exp_mult * (1.0 + get_noise_value(2) * 0.40)

	return base_dr_gain

# =========================================================
# EQUILIBRIUM DEEP MODEL (Phase 3 #9)
# =========================================================

func _update_equilibrium_deep_model(delta: float) -> void:
	var dr: float = GameState.get_resource("detection_risk")
	var t: float = _session_elapsed

	_eq_dr_history.append({"time": t, "dr": dr})
	var cutoff: float = t - GameConfig.EQUILIBRIUM_DERIV_WINDOW
	while _eq_dr_history.size() > 0 and _eq_dr_history[0]["time"] < cutoff:
		_eq_dr_history.pop_front()

	if _eq_dr_history.size() < 3:
		return

	# First derivative (velocity of DR change)
	var oldest: Dictionary = _eq_dr_history[0]
	var newest: Dictionary = _eq_dr_history[_eq_dr_history.size() - 1]
	var time_span: float = newest["time"] - oldest["time"]
	if time_span <= 0.0:
		return

	_eq_deriv_1 = (newest["dr"] - oldest["dr"]) / time_span

	# Second derivative (acceleration of DR change) from middle samples
	if _eq_dr_history.size() >= 5:
		var mid: int = _eq_dr_history.size() / 2
		var mid_entry: Dictionary = _eq_dr_history[mid]
		var half_span1: float = mid_entry["time"] - oldest["time"]
		var half_span2: float = newest["time"] - mid_entry["time"]
		if half_span1 > 0.0 and half_span2 > 0.0:
			var d1: float = (mid_entry["dr"] - oldest["dr"]) / half_span1
			var d2: float = (newest["dr"] - mid_entry["dr"]) / half_span2
			_eq_deriv_2 = (d2 - d1) / ((half_span1 + half_span2) * 0.5)

	# Classify equilibrium state
	var abs_d1: float = absf(_eq_deriv_1)
	var abs_d2: float = absf(_eq_deriv_2)

	if _eq_deriv_1 > 0.5 and abs_d2 > GameConfig.EQUILIBRIUM_CHAOTIC_THRESHOLD:
		equilibrium_state = "collapse_trajectory"
	elif abs_d2 > GameConfig.EQUILIBRIUM_CHAOTIC_THRESHOLD:
		equilibrium_state = "chaotic"
	elif abs_d1 < GameConfig.EQUILIBRIUM_STABLE_DERIV_MAX:
		equilibrium_state = "stable"
	elif abs_d1 < GameConfig.EQUILIBRIUM_META_STABLE_DERIV_MAX:
		equilibrium_state = "meta-stable"
	else:
		equilibrium_state = "chaotic"

func get_equilibrium_state() -> String:
	return equilibrium_state

func get_dr_derivatives() -> Dictionary:
	return {
		"first_derivative":  _eq_deriv_1,
		"second_derivative": _eq_deriv_2,
		"state":             equilibrium_state,
	}
