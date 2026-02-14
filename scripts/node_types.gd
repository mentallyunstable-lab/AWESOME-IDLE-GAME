extends Node

signal node_types_updated

var all_types: Dictionary = {}

func _ready() -> void:
	_init_types()

func _init_types() -> void:
	# === Early Game (Week 1-2 baseline) ===
	_add_type("standard", "Standard Node", 1.5, 3.0, 0.0, 0.0, 0.0,
		Color(0.0, 1.0, 0.835, 0.8))

	# === Mid Game (Week 4) ===
	_add_type("corporate", "Corporate Backbone", 1.875, 3.15, 0.0, 200.0, 25.0,
		Color(0.3, 0.7, 1.0, 0.8))

	_add_type("satellite", "Satellite Uplink", 1.725, 3.0, 0.015, 400.0, 60.0,
		Color(0.9, 0.8, 0.2, 0.8))

	_add_type("quantum", "Quantum Relay", 2.1, 3.6, 0.0, 800.0, 150.0,
		Color(0.8, 0.3, 1.0, 0.8))

func _add_type(id: String, type_name: String, bw: float, dr: float,
		inf_sec: float, unlock_inf: float, cost: float, color: Color) -> void:
	var nt := NodeType.new()
	nt.id = id
	nt.name = type_name
	nt.base_bw = bw
	nt.base_dr = dr
	nt.influence_per_sec = inf_sec
	nt.unlock_influence = unlock_inf
	nt.cost = cost
	nt.color = color
	all_types[id] = nt

func get_unlocked_types() -> Array[NodeType]:
	var result: Array[NodeType] = []
	for nt: NodeType in all_types.values():
		if nt.is_unlocked(Resources.influence):
			result.append(nt)
	return result

func get_type(type_id: String) -> NodeType:
	return all_types.get(type_id)
