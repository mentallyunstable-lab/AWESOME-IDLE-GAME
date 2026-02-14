extends Node

signal region_unlocked(region_id: String)
signal node_deployed(region_id: String, total: int)
signal region_dr_event(region_id: String, event_type: String)
signal region_dr_cleared(region_id: String)
signal selected_region_changed(region_id: String)

var regions: Dictionary = {}
var selected_region_id: String = ""

func _ready() -> void:
	_init_regions()
	Resources.dr_event_triggered.connect(_on_global_dr_event)
	Resources.dr_event_cleared.connect(_on_global_dr_cleared)

func _init_regions() -> void:
	_add_region("north_hub", "North Hub", Vector2(320, 140), 0.0, 8,
		0.0, 0.0, 0.0)
	_add_region("east_grid", "East Grid", Vector2(680, 200), 100.0, 10,
		0.15, 0.1, 0.0)
	_add_region("south_relay", "South Relay", Vector2(400, 380), 300.0, 12,
		0.0, -0.05, 0.20)
	_add_region("west_vault", "West Vault", Vector2(140, 300), 600.0, 8,
		0.10, -0.15, 0.10)
	_add_region("central_nexus", "Central Nexus", Vector2(420, 260), 1200.0, 15,
		0.25, 0.20, 0.15)

	# North Hub starts unlocked
	regions["north_hub"].unlocked = true

func _add_region(id: String, region_name: String, pos: Vector2,
		threshold: float, max_n: int,
		bw_mult: float, dr_mult: float, inf_mult: float) -> void:
	var r := Region.new()
	r.id = id
	r.name = region_name
	r.position = pos
	r.unlock_threshold = threshold
	r.max_nodes = max_n
	r.bw_multiplier = bw_mult
	r.dr_multiplier = dr_mult
	r.influence_multiplier = inf_mult
	regions[id] = r

func _process(_delta: float) -> void:
	_check_unlocks()

func _check_unlocks() -> void:
	for id: String in regions.keys():
		var r: Region = regions[id]
		if r.can_unlock(Resources.influence):
			r.unlocked = true
			region_unlocked.emit(id)

func select_region(region_id: String) -> void:
	selected_region_id = region_id
	selected_region_changed.emit(region_id)

func deploy_node_to_region(region_id: String) -> bool:
	if not regions.has(region_id):
		return false
	var r: Region = regions[region_id]
	if not r.unlocked or r.is_full():
		return false

	r.node_count += 1
	Resources.add_node()
	_apply_map_multipliers()
	node_deployed.emit(region_id, r.node_count)
	return true

func _apply_map_multipliers() -> void:
	var total_bw_bonus: float = 0.0
	var total_dr_bonus: float = 0.0
	var total_inf_bonus: float = 0.0
	var total_map_nodes: int = 0

	for r: Region in regions.values():
		if r.node_count <= 0:
			continue
		total_map_nodes += r.node_count
		total_bw_bonus += r.node_count * r.bw_multiplier
		total_dr_bonus += r.node_count * r.dr_multiplier
		total_inf_bonus += r.node_count * r.influence_multiplier

	# Apply as additive bonuses on top of existing upgrade multipliers
	# BW bonus: added into infra_multiplier contribution
	Resources.map_bw_bonus = total_bw_bonus
	Resources.map_dr_bonus = total_dr_bonus
	Resources.map_inf_bonus = total_inf_bonus
	Resources.recalculate()

func _on_global_dr_event(event_type: String) -> void:
	# Find region with highest node count to flash
	var worst_id: String = ""
	var worst_count: int = 0
	for id: String in regions.keys():
		var r: Region = regions[id]
		if r.node_count > worst_count:
			worst_count = r.node_count
			worst_id = id
	if worst_id != "":
		regions[worst_id].dr_event_active = true
		regions[worst_id].dr_event_type = event_type
		region_dr_event.emit(worst_id, event_type)

func _on_global_dr_cleared(_event_type: String) -> void:
	for id: String in regions.keys():
		var r: Region = regions[id]
		if r.dr_event_active:
			r.dr_event_active = false
			r.dr_event_type = ""
			region_dr_cleared.emit(id)

func get_region(region_id: String) -> Region:
	return regions.get(region_id)

func get_total_map_nodes() -> int:
	var total: int = 0
	for r: Region in regions.values():
		total += r.node_count
	return total
