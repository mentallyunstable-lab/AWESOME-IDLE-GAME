extends Node
## balance_analyzer.gd — Balance Analyzer Tool + Monte Carlo Simulation (Phase 4 #14, #15)
##
## === BALANCE ANALYZER ===
## Auto-detects during stress test:
##   - Infinite DR loops / unrecoverable collapse patterns
##   - Dominant strategy builds
##   - Dead mechanics (unused systems)
## Generates generate_balance_report() dictionary.
##
## === MONTE CARLO ===
## Runs 100 randomized seeds with:
##   - Randomized doctrines, initial states, node counts
## Measures: avg survival time, collapse distribution, stability variance.

signal balance_report_ready(report: Dictionary)
signal monte_carlo_complete(results: Dictionary)
signal monte_carlo_progress(pct: float)

const MC_SEED_COUNT: int = 100
const MC_SIM_DURATION: float = 600.0   # 10 simulated minutes per seed
const MC_SIM_DT: float = 1.0           # Timestep for MC fast-forward

var _last_report: Dictionary = {}
var _last_mc_results: Dictionary = {}

# =========================================================
# BALANCE REPORT (Phase 4 #14)
# =========================================================

func generate_balance_report() -> Dictionary:
	var report: Dictionary = {
		"timestamp":             GameState.get_game_clock(),
		"tier":                  GameState.tier,
		"issues":                [],
		"dominant_strategies":   [],
		"dead_mechanics":        [],
		"recommendations":       [],
	}

	var dr: float = GameState.get_resource("detection_risk")
	var dr_rate: float = GameState.get_per_second("detection_risk")
	var inf_rate: float = GameState.get_per_second("influence")
	var inf: float = GameState.get_resource("influence")
	var thermal: float = GameState.get_thermal_load()
	var node_count: int = GameState.get_node_count()

	# --- ISSUE DETECTION ---

	# Runaway DR
	if dr_rate > 4.0 and dr > 75.0:
		report["issues"].append({
			"type": "runaway_dr",
			"severity": "critical",
			"description": "DR rising at %.2f/s at %.0f%% — collapse within %.0fs" % [
				dr_rate, dr, (100.0 - dr) / dr_rate if dr_rate > 0.0 else 999.0
			],
		})
	elif dr_rate > 2.0 and dr > 60.0:
		report["issues"].append({
			"type": "elevated_dr_gain",
			"severity": "warning",
			"description": "DR gaining rapidly: %.2f/s at %.0f%% DR." % [dr_rate, dr],
		})

	# Influence drain loop
	if inf_rate < -5.0:
		report["issues"].append({
			"type": "influence_drain",
			"severity": "warning",
			"description": "Influence draining at %.2f/s — maintenance exceeds production." % inf_rate,
		})

	# Thermal critical
	if thermal > 85.0:
		report["issues"].append({
			"type": "thermal_critical",
			"severity": "critical",
			"description": "Thermal load at %.1f%% — thermal meltdown imminent." % thermal,
		})
	elif thermal > 55.0:
		report["issues"].append({
			"type": "thermal_elevated",
			"severity": "warning",
			"description": "Thermal load elevated at %.1f%%." % thermal,
		})

	# Node overcrowding
	var max_nodes: int = GameState.get_max_nodes()
	if max_nodes > 0 and float(node_count) / float(max_nodes) > 0.95:
		report["issues"].append({
			"type": "node_cap_near",
			"severity": "info",
			"description": "Node capacity near maximum (%d/%d). Growth ceiling reached." % [node_count, max_nodes],
		})

	# Energy deficit
	if GameState.resources.has("energy") and GameState.get_per_second("energy") < -0.5:
		report["issues"].append({
			"type": "energy_deficit",
			"severity": "warning",
			"description": "Energy deficit: %.2f/s." % GameState.get_per_second("energy"),
		})

	# --- DEAD MECHANICS ---
	var upgrades: Array = GameConfig.get_upgrades_for_tier(GameState.tier)
	var unused: Array = []
	for upg: Dictionary in upgrades:
		if GameState.get_upgrade_level(upg["id"]) == 0:
			unused.append(upg["id"])

	var unused_ratio: float = float(unused.size()) / float(maxi(upgrades.size(), 1))
	if unused_ratio > 0.55:
		report["dead_mechanics"].append({
			"type": "upgrades_unused",
			"description": "%d/%d upgrades never purchased." % [unused.size(), upgrades.size()],
			"items": unused,
		})

	if GameState.regions.is_empty() and GameState.tier >= 1:
		report["dead_mechanics"].append({
			"type": "regions_unused",
			"description": "Regions array empty — regional simulation layer inactive.",
		})

	if not GameState.automation.get("active", false):
		report["dead_mechanics"].append({
			"type": "automation_inactive",
			"description": "Automation system never activated.",
		})

	if GameState.active_doctrine == "stability" and inf > 500.0:
		report["dead_mechanics"].append({
			"type": "doctrine_default",
			"description": "Stability doctrine still active — player has not experimented with alternatives.",
		})

	# --- DOMINANT STRATEGIES ---
	if GameState.active_doctrine == "throughput" and inf_rate > 30.0:
		report["dominant_strategies"].append({
			"type": "throughput_dominant",
			"description": "Throughput doctrine generating %.1f inf/s — may overshadow all other strategies." % inf_rate,
		})

	if GameState.get_degraded_node_count() == 0 and node_count > 10:
		report["dominant_strategies"].append({
			"type": "perfect_maintenance",
			"description": "No degraded nodes with %d deployed — maintenance mechanics may be trivially managed." % node_count,
		})

	# --- RECOMMENDATIONS ---
	if dr > 60.0 and GameState.active_doctrine != "stealth":
		report["recommendations"].append("DR at %.0f%% — switch to Stealth doctrine to reduce pressure." % dr)
	if thermal > 50.0:
		report["recommendations"].append("Thermal elevated — reduce node count or enable cooling upgrades.")
	if inf_rate < 0.5 and node_count > 3:
		report["recommendations"].append("Low influence rate — check maintenance drain vs production.")
	if unused_ratio > 0.7:
		report["recommendations"].append("Many upgrades unused — explore upgrade tree more aggressively.")

	# Summary
	report["summary"] = {
		"issue_count":            report["issues"].size(),
		"dead_mechanic_count":    report["dead_mechanics"].size(),
		"dominant_strategy_count": report["dominant_strategies"].size(),
		"health_score":           _compute_health_score(report),
		"recommendation_count":   report["recommendations"].size(),
	}

	_last_report = report
	balance_report_ready.emit(report)

	print("[BalanceAnalyzer] === BALANCE REPORT ===")
	print("  Issues: %d | Dead mechanics: %d | Dominant: %d | Health: %.2f" % [
		report["issues"].size(),
		report["dead_mechanics"].size(),
		report["dominant_strategies"].size(),
		report["summary"]["health_score"],
	])
	return report

func _compute_health_score(report: Dictionary) -> float:
	var score: float = 1.0
	for issue: Dictionary in report["issues"]:
		match issue.get("severity", "info"):
			"critical": score -= 0.30
			"warning":  score -= 0.10
			"info":     score -= 0.03
	score -= float(report["dead_mechanics"].size()) * 0.04
	return clampf(score, 0.0, 1.0)

func get_last_report() -> Dictionary:
	return _last_report

# =========================================================
# MONTE CARLO SIMULATION (Phase 4 #15)
# =========================================================

func run_monte_carlo(seed_count: int = MC_SEED_COUNT) -> void:
	print("[MonteCarlo] Starting %d-seed simulation (%.0f min each)..." % [
		seed_count, MC_SIM_DURATION / 60.0
	])
	var results: Array = []
	for i in range(seed_count):
		var seed: int = (i + 1) * 7919 + GameState.tier * 1337  # Varied prime offsets
		results.append(_simulate_seed(seed))
		if i % 10 == 9:
			monte_carlo_progress.emit(float(i + 1) / float(seed_count))

	var summary: Dictionary = _summarize_monte_carlo(results)
	_last_mc_results = summary
	monte_carlo_complete.emit(summary)
	_print_monte_carlo_summary(summary)

func _simulate_seed(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	# Randomize initial state
	var dr: float = rng.randf_range(0.0, 35.0)
	var nodes: int = rng.randi_range(1, 12)
	var thermal: float = rng.randf_range(0.0, 15.0)

	# Random doctrine
	var all_doctrines: Array = GameConfig.DOCTRINES.keys()
	var doctrine: String = all_doctrines[rng.randi() % all_doctrines.size()]
	var doctrine_def: Dictionary = GameConfig.DOCTRINES.get(doctrine, {})
	var dr_mult: float = doctrine_def.get("dr_multiplier", 1.0)

	# Tier config
	var cfg := GameConfig.get_tier_config(GameState.tier)
	var gain_per_node: float = cfg.get("dr_gain_per_node", 0.02)
	var dr_exponent: float   = cfg.get("dr_scale_exponent", 1.12)
	var dr_decay: float      = cfg.get("dr_passive_decay", 0.01)

	var survival_time: float = 0.0
	var collapsed: bool = false
	var collapse_type: String = ""
	var max_dr_seen: float = dr
	var total_inf: float = 0.0

	# Fast-forward
	while survival_time < MC_SIM_DURATION:
		# DR update
		var base_gain: float = pow(float(nodes), dr_exponent) * gain_per_node * dr_mult
		var net_dr: float = (base_gain - dr_decay) * MC_SIM_DT
		dr = clampf(dr + net_dr, 0.0, 100.0)
		max_dr_seen = maxf(max_dr_seen, dr)

		# Thermal update (simplified)
		var t_gen: float = float(nodes) * GameConfig.THERMAL_PER_NODE_RATE
		thermal = clampf(thermal + (t_gen - GameConfig.THERMAL_DISSIPATION_BASE) * MC_SIM_DT, 0.0, 100.0)

		# Random node deployment
		if rng.randf() < 0.005 and nodes < cfg.get("max_nodes", 20):
			nodes += 1

		# Random events (simplified: occasional DR spikes)
		if rng.randf() < 0.01:
			dr = clampf(dr + rng.randf_range(3.0, 15.0), 0.0, 100.0)

		# Simplified influence
		var base_eff: float = cfg.get("base_efficiency", 0.06)
		var bw: float = float(nodes) * cfg.get("node_base_bw", 1.0)
		total_inf += bw * base_eff * MC_SIM_DT

		# Collapse checks
		if dr >= 100.0:
			collapsed = true
			collapse_type = "dr_overflow"
			break
		if thermal >= GameConfig.THERMAL_MELTDOWN_THRESHOLD:
			collapsed = true
			collapse_type = "thermal_meltdown"
			break

		survival_time += MC_SIM_DT

	return {
		"seed":          seed,
		"survived":      not collapsed,
		"survival_time": survival_time,
		"collapse_type": collapse_type,
		"final_dr":      dr,
		"final_thermal": thermal,
		"final_nodes":   nodes,
		"max_dr":        max_dr_seen,
		"total_inf":     total_inf,
		"doctrine":      doctrine,
	}

func _summarize_monte_carlo(results: Array) -> Dictionary:
	if results.is_empty():
		return {}

	var survived: int = 0
	var total_survival: float = 0.0
	var collapse_types: Dictionary = {}
	var dr_samples: Array = []
	var inf_samples: Array = []
	var doctrine_survival: Dictionary = {}

	for r: Dictionary in results:
		if r["survived"]:
			survived += 1
		total_survival += r["survival_time"]
		var ct: String = r.get("collapse_type", "survived")
		collapse_types[ct] = collapse_types.get(ct, 0) + 1
		dr_samples.append(r["final_dr"])
		inf_samples.append(r["total_inf"])

		var doc: String = r["doctrine"]
		if not doctrine_survival.has(doc):
			doctrine_survival[doc] = {"survived": 0, "total": 0}
		doctrine_survival[doc]["total"] += 1
		if r["survived"]:
			doctrine_survival[doc]["survived"] += 1

	var n: int = results.size()
	var avg_survival: float = total_survival / float(n)

	# Variance and std dev for DR
	var mean_dr: float = 0.0
	for v: float in dr_samples:
		mean_dr += v
	mean_dr /= float(dr_samples.size())
	var variance: float = 0.0
	for v: float in dr_samples:
		var d: float = v - mean_dr
		variance += d * d
	variance /= float(dr_samples.size())

	# Best doctrine by survival rate
	var best_doctrine: String = ""
	var best_rate: float = -1.0
	for doc: String in doctrine_survival.keys():
		var rate: float = float(doctrine_survival[doc]["survived"]) / float(doctrine_survival[doc]["total"])
		if rate > best_rate:
			best_rate = rate
			best_doctrine = doc

	return {
		"total_seeds":           n,
		"survived_count":        survived,
		"survival_rate":         float(survived) / float(n),
		"avg_survival_time":     avg_survival,
		"collapse_distribution": collapse_types,
		"mean_final_dr":         mean_dr,
		"dr_variance":           variance,
		"dr_std_dev":            sqrt(variance),
		"doctrine_survival":     doctrine_survival,
		"best_doctrine":         best_doctrine,
		"best_doctrine_rate":    best_rate,
	}

func _print_monte_carlo_summary(summary: Dictionary) -> void:
	print("[MonteCarlo] === RESULTS (%d seeds) ===" % summary.get("total_seeds", 0))
	print("  Survival rate: %.1f%% (%d/%d)" % [
		summary.get("survival_rate", 0.0) * 100.0,
		summary.get("survived_count", 0),
		summary.get("total_seeds", 0),
	])
	print("  Avg survival time: %.0fs" % summary.get("avg_survival_time", 0.0))
	print("  Mean final DR: %.1f | Variance: %.2f | StdDev: %.2f" % [
		summary.get("mean_final_dr", 0.0),
		summary.get("dr_variance", 0.0),
		summary.get("dr_std_dev", 0.0),
	])
	print("  Best doctrine: %s (%.1f%% survival)" % [
		summary.get("best_doctrine", "none"),
		summary.get("best_doctrine_rate", 0.0) * 100.0,
	])
	print("  Collapse distribution:")
	for ct: String in summary.get("collapse_distribution", {}).keys():
		print("    %s: %d" % [ct, summary["collapse_distribution"][ct]])

func get_last_mc_results() -> Dictionary:
	return _last_mc_results
