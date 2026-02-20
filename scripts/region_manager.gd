extends Node
## region_manager.gd — Regional Simulation Layer (Phase 2 #6)
##
## Manages all Region instances, ticks them each frame,
## and aggregates regional outputs into global system state.
##
## Provides:
##   update_regions(delta)          — Tick all active regions
##   calculate_global_from_regions() — Aggregate into GameState
##   unlock_region(region_id)       — Activate a region
##   add_node_to_region(id)         — Route a node to a region
##   remove_node_from_region(id)    — Remove from a region
##
## Global effects:
##   - Regional DR contributes to detection_risk gain
##   - Regional instability affects event frequency
##   - Local collapses trigger partial resets
##   - Doctrine alignment gives efficiency bonuses

signal region_unlocked(region_id: String)
signal local_collapse_triggered(region_id: String)
signal global_aggregated(aggregate: Dictionary)

# Internal region registry
var _regions: Dictionary = {}   # { region_id: Region }
var _aggregate_cache: Dictionary = {}

func _ready() -> void:
	TickEngine.game_tick.connect(_on_tick)
	_initialize_default_regions()

func _on_tick(delta: float) -> void:
	update_regions(delta)
	calculate_global_from_regions()

# =========================================================
# INITIALIZATION
# =========================================================

func _initialize_default_regions() -> void:
	# Sync with GameState.regions if populated from a saved game or scenario
	if not GameState.regions.is_empty():
		for region: Region in GameState.regions:
			_regions[region.id] = region
		return

	# Default: create placeholder regions for Tier 1+
	if GameState.tier >= 1:
		var r1: Region = _create_region("downtown", "Downtown District", 0, 20, 0.9)
		var r2: Region = _create_region("industrial", "Industrial Zone", 15, 15, 1.1, "throughput")
		var r3: Region = _create_region("residential", "Residential Grid", 15, 15, 0.8, "stealth")
		_register_region(r1)
		_register_region(r2)
		_register_region(r3)

func _create_region(
	region_id: String,
	display_name: String,
	unlock_threshold: float,
	max_nodes: int,
	efficiency: float,
	doctrine_bias: String = "none",
) -> Region:
	var r := Region.new()
	r.id = region_id
	r.name = display_name
	r.unlock_threshold = unlock_threshold
	r.max_nodes = max_nodes
	r.efficiency = efficiency
	r.doctrine_bias = doctrine_bias
	r.unlocked = unlock_threshold <= 0.0
	return r

func _register_region(region: Region) -> void:
	_regions[region.id] = region
	GameState.regions.append(region)

# =========================================================
# SIMULATION TICK
# =========================================================

func update_regions(delta: float) -> void:
	var prev_local_collapses: Dictionary = {}
	for region_id: String in _regions.keys():
		prev_local_collapses[region_id] = _regions[region_id].local_collapse_active

	for region_id: String in _regions.keys():
		var region: Region = _regions[region_id]
		region.tick(delta)
		# Detect newly triggered local collapses
		if region.local_collapse_active and not prev_local_collapses.get(region_id, false):
			local_collapse_triggered.emit(region_id)
			print("[RegionManager] Local collapse: %s" % region_id)

## Aggregate all region outputs into global constraint modifiers.
func calculate_global_from_regions() -> void:
	if _regions.is_empty():
		return

	var total_dr_contrib: float = 0.0
	var total_instability: float = 0.0
	var active_count: int = 0
	var avg_efficiency: float = 0.0
	var any_local_collapse: bool = false

	for region_id: String in _regions.keys():
		var region: Region = _regions[region_id]
		if not region.unlocked:
			continue
		active_count += 1
		total_dr_contrib += region.get_regional_dr_contribution()
		total_instability += region.instability
		avg_efficiency += region.efficiency
		if region.local_collapse_active:
			any_local_collapse = true

	if active_count == 0:
		return

	avg_efficiency /= float(active_count)
	var avg_instability: float = total_instability / float(active_count)

	# Aggregate values available for other systems to query
	_aggregate_cache = {
		"total_dr_contribution":  total_dr_contrib,
		"avg_instability":        avg_instability,
		"avg_efficiency":         avg_efficiency,
		"active_region_count":    active_count,
		"any_local_collapse":     any_local_collapse,
	}

	global_aggregated.emit(_aggregate_cache)

# =========================================================
# REGION MANAGEMENT
# =========================================================

func unlock_region(region_id: String) -> bool:
	if not _regions.has(region_id):
		return false
	var region: Region = _regions[region_id]
	if region.unlocked:
		return false
	var inf: float = GameState.get_resource("influence")
	if inf < region.unlock_threshold:
		return false
	GameState.add_resource("influence", -region.unlock_threshold)
	region.unlocked = true
	region_unlocked.emit(region_id)
	print("[RegionManager] Unlocked region: %s" % region.name)
	return true

func add_node_to_region(region_id: String) -> bool:
	if not _regions.has(region_id):
		return false
	var region: Region = _regions[region_id]
	if not region.unlocked or region.is_full():
		return false
	region.node_count += 1
	return true

func remove_node_from_region(region_id: String) -> bool:
	if not _regions.has(region_id):
		return false
	var region: Region = _regions[region_id]
	if region.node_count <= 0:
		return false
	region.node_count -= 1
	return true

## Load regions from a scenario definition (ScenarioGenerator output).
func load_scenario_regions(scenario_regions: Array) -> void:
	_regions.clear()
	GameState.regions.clear()
	for rd: Dictionary in scenario_regions:
		var r: Region = Region.new()
		r.id            = rd.get("id", "region_unknown")
		r.name          = rd.get("name", "Region")
		r.efficiency    = rd.get("efficiency", GameConfig.REGION_BASE_EFFICIENCY)
		r.load          = rd.get("load", 0.0)
		r.instability   = rd.get("instability", 0.0)
		r.doctrine_bias = rd.get("doctrine_bias", "none")
		r.max_nodes     = rd.get("max_nodes", 10)
		r.unlock_threshold = 0.0   # Scenario regions start unlocked
		r.unlocked      = true
		_register_region(r)
	print("[RegionManager] Loaded %d regions from scenario." % _regions.size())

# =========================================================
# QUERY API
# =========================================================

func get_region(region_id: String) -> Region:
	return _regions.get(region_id, null)

func get_all_regions() -> Array:
	return _regions.values()

func get_unlocked_regions() -> Array:
	var result: Array = []
	for r: Region in _regions.values():
		if r.unlocked:
			result.append(r)
	return result

func get_aggregate() -> Dictionary:
	return _aggregate_cache

func get_total_region_dr_bonus() -> float:
	return _aggregate_cache.get("total_dr_contribution", 0.0)

func get_avg_instability() -> float:
	return _aggregate_cache.get("avg_instability", 0.0)

func get_doctrine_alignment_multiplier() -> float:
	# Weighted average doctrine alignment across all regions
	var total: float = 0.0
	var count: int = 0
	for r: Region in _regions.values():
		if r.unlocked:
			total += r.get_doctrine_alignment_modifier(GameState.active_doctrine)
			count += 1
	if count == 0:
		return 1.0
	return total / float(count)

func get_status_report() -> Dictionary:
	var report: Dictionary = {"regions": []}
	for r: Region in _regions.values():
		report["regions"].append({
			"id":            r.id,
			"name":          r.name,
			"unlocked":      r.unlocked,
			"nodes":         r.node_count,
			"max_nodes":     r.max_nodes,
			"load":          r.load,
			"instability":   r.instability,
			"efficiency":    r.efficiency,
			"doctrine_bias": r.doctrine_bias,
			"status":        r.get_status_string(),
			"local_collapse": r.local_collapse_active,
		})
	report["aggregate"] = _aggregate_cache
	return report

func debug_print() -> void:
	print("[RegionManager] === REGION STATUS ===")
	for r: Region in _regions.values():
		print("  [%s] %s | Load: %.0f%% | Instab: %.0f%% | Eff: %.2f | %s" % [
			r.id, r.name,
			r.load * 100.0, r.instability * 100.0,
			r.efficiency, r.get_status_string(),
		])
	print("  Aggregate DR bonus: %.2f" % get_total_region_dr_bonus())
	print("  Avg instability: %.0f%%" % (get_avg_instability() * 100.0))
	print("  Doctrine alignment mult: %.2f" % get_doctrine_alignment_multiplier())
