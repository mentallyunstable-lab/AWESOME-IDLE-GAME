class_name Region
extends RefCounted

var id: String
var name: String
var position: Vector2
var unlock_threshold: float
var unlocked: bool = false
var node_count: int = 0
var max_nodes: int = 10

# Region multipliers
var bw_multiplier: float = 0.0
var dr_multiplier: float = 0.0
var influence_multiplier: float = 0.0

# Visual state
var dr_event_active: bool = false
var dr_event_type: String = ""

func is_full() -> bool:
	return node_count >= max_nodes

func can_unlock(current_influence: float) -> bool:
	return not unlocked and current_influence >= unlock_threshold

func get_tooltip() -> String:
	var status := "LOCKED — Need %.0f Influence" % unlock_threshold if not unlocked else "ONLINE"
	var lines := PackedStringArray()
	lines.append("[%s] %s" % [name, status])
	if unlocked:
		lines.append("Nodes: %d / %d" % [node_count, max_nodes])
		if bw_multiplier != 0.0:
			lines.append("BW Bonus: %+.0f%%" % (bw_multiplier * 100))
		if influence_multiplier != 0.0:
			lines.append("Influence Bonus: %+.0f%%" % (influence_multiplier * 100))
		if dr_multiplier != 0.0:
			lines.append("DR Modifier: %+.0f%%" % (dr_multiplier * 100))
	return "\n".join(lines)
