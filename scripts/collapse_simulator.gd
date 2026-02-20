extends Node
## collapse_simulator.gd — Predictive Collapse Simulator (Phase 1 #2)
##
## Simulates 30-120 seconds into the future without affecting real state.
## Clones a lightweight snapshot and fast-forwards at a fixed timestep.
## Returns projected collapse probability %.
##
## Exposed in debug panel via get_collapse_risk_score() and get_last_simulation().

signal simulation_complete(result: Dictionary)

var _last_simulation: Dictionary = {}
var _sim_run_interval: float = 6.0   # Simulate every 6 real seconds
var _sim_timer: float = 0.0
var _default_window: float = 60.0    # Seconds to simulate ahead

func _ready() -> void:
	TickEngine.game_tick.connect(_on_tick)

func _on_tick(delta: float) -> void:
	_sim_timer += delta
	if _sim_timer >= _sim_run_interval:
		_sim_timer = 0.0
		_last_simulation = _run_simulation(_default_window)
		simulation_complete.emit(_last_simulation)

## Public API: simulate ahead by `seconds`. Does not modify real state.
func simulate_future(seconds: float = 60.0) -> Dictionary:
	seconds = clampf(seconds, 10.0, 120.0)
	return _run_simulation(seconds)

## Returns probability of collapse within the default window (0.0 - 1.0).
func get_collapse_risk_score() -> float:
	return _last_simulation.get("collapse_probability", 0.0)

func get_last_simulation() -> Dictionary:
	return _last_simulation

func get_risk_level() -> String:
	var risk: float = get_collapse_risk_score()
	if risk < 0.20:   return "low"
	elif risk < 0.45: return "moderate"
	elif risk < 0.72: return "high"
	else:             return "critical"

# =========================================================
# INTERNAL SIMULATION
# =========================================================

func _run_simulation(seconds: float) -> Dictionary:
	var snap := _take_snapshot()
	var dt: float = 0.5                      # Simulation timestep (seconds)
	var steps: int = int(seconds / dt)
	var collapse_time: float = -1.0
	var collapse_type: String = ""

	for i in range(steps):
		var t_sim: float = float(i) * dt

		# --- Detection Risk ---
		var base_gain: float = pow(float(snap["nodes"]), snap["dr_exponent"]) * snap["dr_gain_per_node"]
		base_gain *= snap["dr_mult"]
		base_gain *= snap["adapt_mult"]
		var net_dr: float = (base_gain - snap["dr_decay"]) * dt
		snap["dr"] = clampf(snap["dr"] + net_dr, 0.0, 100.0)

		# --- Thermal ---
		var thermal_gen: float = float(snap["nodes"]) * GameConfig.THERMAL_PER_NODE_RATE
		var thermal_dissip: float = GameConfig.THERMAL_DISSIPATION_BASE
		snap["thermal"] = clampf(snap["thermal"] + (thermal_gen - thermal_dissip) * dt, 0.0, 100.0)

		# --- Energy (if applicable) ---
		snap["energy"] = maxf(0.0, snap["energy"] + snap["energy_rate"] * dt)

		# --- Collapse checks ---
		if snap["dr"] >= 100.0:
			collapse_time = t_sim
			collapse_type = "dr_overflow"
			break
		if snap["thermal"] >= GameConfig.THERMAL_MELTDOWN_THRESHOLD:
			collapse_time = t_sim
			collapse_type = "thermal_meltdown"
			break

	# Compute probability
	var collapse_prob: float = 0.0
	if collapse_time > 0.0:
		# Earlier collapse = higher probability score
		collapse_prob = clampf(1.0 - (collapse_time / seconds), 0.0, 1.0)
		# Boost slightly for certainty
		collapse_prob = minf(collapse_prob + 0.10, 1.0)
	else:
		# No simulated collapse — estimate from trajectory
		var dr_margin: float = 100.0 - snap["dr"]
		var dr_rate: float = GameState.get_per_second("detection_risk")
		if dr_rate > 0.0:
			var ttc: float = dr_margin / dr_rate
			collapse_prob = clampf(1.0 - (ttc / seconds), 0.0, 0.90)

		var thermal_margin: float = GameConfig.THERMAL_MELTDOWN_THRESHOLD - snap["thermal"]
		var thermal_rate: float = float(snap["nodes"]) * GameConfig.THERMAL_PER_NODE_RATE - GameConfig.THERMAL_DISSIPATION_BASE
		if thermal_rate > 0.0:
			var ttc_th: float = thermal_margin / thermal_rate
			var thermal_prob: float = clampf(1.0 - (ttc_th / seconds), 0.0, 0.90)
			collapse_prob = maxf(collapse_prob, thermal_prob)

	var result: Dictionary = {
		"collapse_probability": collapse_prob,
		"projected_collapse_time": collapse_time,
		"projected_collapse_type": collapse_type,
		"final_dr": snap["dr"],
		"final_thermal": snap["thermal"],
		"final_energy": snap["energy"],
		"simulated_seconds": seconds,
		"risk_level": "",
		"timestamp": GameState.get_game_clock(),
	}
	result["risk_level"] = _classify_risk(collapse_prob)
	return result

func _take_snapshot() -> Dictionary:
	var cfg := GameConfig.get_tier_config(GameState.tier)
	var adapt_mult: float = 1.0
	if has_node("/root/AdaptiveDifficulty"):
		adapt_mult = get_node("/root/AdaptiveDifficulty").dr_gain_multiplier

	return {
		"tier":           GameState.tier,
		"dr":             GameState.get_resource("detection_risk"),
		"thermal":        GameState.get_thermal_load(),
		"energy":         GameState.get_resource("energy") if GameState.resources.has("energy") else 0.0,
		"nodes":          GameState.get_node_count(),
		"energy_rate":    GameState.get_per_second("energy") if GameState.resources.has("energy") else 0.0,
		"dr_gain_per_node": cfg.get("dr_gain_per_node", 0.02),
		"dr_exponent":    cfg.get("dr_scale_exponent", 1.12),
		"dr_decay":       cfg.get("dr_passive_decay", 0.01),
		"dr_mult":        maxf(0.0, 1.0 - GameState.dr_reduction),
		"adapt_mult":     adapt_mult,
	}

func _classify_risk(prob: float) -> String:
	if prob < 0.20:   return "low"
	elif prob < 0.45: return "moderate"
	elif prob < 0.72: return "high"
	else:             return "critical"

func debug_print() -> void:
	var sim: Dictionary = _last_simulation
	if sim.is_empty():
		print("[CollapseSimulator] No simulation data yet.")
		return
	print("[CollapseSimulator] === COLLAPSE RISK REPORT ===")
	print("  Risk: %.1f%% (%s)" % [sim.get("collapse_probability", 0.0) * 100.0, sim.get("risk_level", "unknown")])
	print("  Final DR: %.1f | Final Thermal: %.1f" % [sim.get("final_dr", 0.0), sim.get("final_thermal", 0.0)])
	if sim.get("projected_collapse_time", -1.0) > 0.0:
		print("  Projected collapse in %.0fs via: %s" % [sim["projected_collapse_time"], sim["projected_collapse_type"]])
	else:
		print("  No collapse projected in %.0fs window" % sim.get("simulated_seconds", 0.0))
