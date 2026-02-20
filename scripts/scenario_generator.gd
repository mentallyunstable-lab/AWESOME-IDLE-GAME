extends Node
## scenario_generator.gd — Autonomous Scenario Generator (Phase 7 #24)
##
## Procedurally generates starting conditions from a seed:
##   - Initial DR, nodes, influence
##   - Regional layout (efficiency, load, instability, doctrine bias)
##   - Available doctrine pool
##   - Event pool bias (dominant category + frequency/severity multipliers)
##
## Deterministic: same seed -> identical scenario.

## Generates a full scenario dictionary from a seed. Does not modify state.
func generate_scenario(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var initial_dr: float         = rng.randf_range(0.0, 38.0)
	var initial_nodes: int        = rng.randi_range(1, 9)
	var initial_influence: float  = rng.randf_range(60.0, 450.0)
	var region_count: int         = rng.randi_range(1, 4)

	var regions: Array            = _generate_regions(rng, region_count)
	var available_doctrines: Array = _generate_doctrine_pool(rng)
	var event_bias: Dictionary    = _generate_event_bias(rng)

	return {
		"seed":                seed,
		"starting_tier":       0,
		"initial_dr":          initial_dr,
		"initial_nodes":       initial_nodes,
		"initial_influence":   initial_influence,
		"regions":             regions,
		"available_doctrines": available_doctrines,
		"event_bias":          event_bias,
		"name":                _generate_name(rng, seed),
		"description":         _generate_description(rng),
	}

## Applies a generated scenario to the current GameState.
func apply_scenario(scenario: Dictionary) -> void:
	# Reset resources
	GameState.set_resource("detection_risk", scenario.get("initial_dr", 0.0))
	GameState.set_resource("influence", scenario.get("initial_influence", 100.0))
	GameState.set_resource("bandwidth", 0.0)

	# Deploy initial nodes
	var count: int = scenario.get("initial_nodes", 1)
	for _i in range(count):
		GameState.deploy_node("")

	# Apply regional data if regions exist
	var region_data: Array = scenario.get("regions", [])
	if not region_data.is_empty() and has_node("/root/RegionManager"):
		get_node("/root/RegionManager").load_scenario_regions(region_data)

	print("[ScenarioGenerator] Applied scenario: '%s' (seed %d)" % [
		scenario.get("name", "Unknown"), scenario.get("seed", 0)
	])
	print("  DR: %.1f | Nodes: %d | Inf: %.0f | Regions: %d" % [
		scenario.get("initial_dr", 0.0),
		scenario.get("initial_nodes", 0),
		scenario.get("initial_influence", 0.0),
		region_data.size(),
	])

## Convenience: generate and immediately apply.
func generate_and_apply(seed: int) -> Dictionary:
	var scenario: Dictionary = generate_scenario(seed)
	apply_scenario(scenario)
	return scenario

## Generate using the default deterministic seed.
func generate_default() -> Dictionary:
	return generate_scenario(GameConfig.DEFAULT_SIMULATION_SEED)

# =========================================================
# GENERATION HELPERS
# =========================================================

func _generate_regions(rng: RandomNumberGenerator, count: int) -> Array:
	var names: Array    = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon", "Zeta"]
	var doc_biases: Array = ["stealth", "throughput", "stability", "none", "none"]
	var result: Array   = []

	for i in range(count):
		result.append({
			"id":            "region_%s" % names[i % names.size()].to_lower(),
			"name":          "Region %s" % names[i % names.size()],
			"efficiency":    rng.randf_range(0.65, 1.20),
			"load":          rng.randf_range(0.05, 0.50),
			"instability":   rng.randf_range(0.00, 0.28),
			"doctrine_bias": doc_biases[rng.randi() % doc_biases.size()],
			"max_nodes":     rng.randi_range(8, 20),
			"node_count":    0,
		})
	return result

func _generate_doctrine_pool(rng: RandomNumberGenerator) -> Array:
	var all: Array = GameConfig.DOCTRINES.keys()
	# Shuffle
	for i in range(all.size() - 1, 0, -1):
		var j: int = rng.randi() % (i + 1)
		var tmp = all[i]; all[i] = all[j]; all[j] = tmp
	# Always at least 2 available
	var count: int = rng.randi_range(2, all.size())
	return all.slice(0, count)

func _generate_event_bias(rng: RandomNumberGenerator) -> Dictionary:
	var categories: Array = ["network", "power", "security", "hardware"]
	return {
		"dominant_category":   categories[rng.randi() % categories.size()],
		"frequency_multiplier": rng.randf_range(0.65, 1.55),
		"severity_multiplier":  rng.randf_range(0.75, 1.35),
	}

func _generate_name(rng: RandomNumberGenerator, seed: int) -> String:
	var adj: Array  = ["Volatile", "Dormant", "Critical", "Resilient", "Fractured", "Adaptive", "Latent"]
	var noun: Array = ["Grid", "Network", "Matrix", "Nexus", "Cluster", "Array", "Lattice"]
	return "%s %s #%04d" % [
		adj[rng.randi() % adj.size()],
		noun[rng.randi() % noun.size()],
		seed % 10000,
	]

func _generate_description(rng: RandomNumberGenerator) -> String:
	var intros: Array = [
		"System initialized under hostile conditions.",
		"Remnants of a previous network detected.",
		"Clean slate — unknown territory ahead.",
		"Compromised infrastructure — proceed carefully.",
		"Legacy system partially intact.",
		"High-density deployment zone — resource competition expected.",
	]
	return intros[rng.randi() % intros.size()]
