class_name NodeType
extends RefCounted

var id: String
var name: String
var base_bw: float
var base_dr: float
var influence_per_sec: float
var unlock_influence: float
var cost: float
var color: Color

func is_unlocked(current_influence: float) -> bool:
	return current_influence >= unlock_influence

func get_tooltip() -> String:
	var lines := PackedStringArray()
	lines.append(name)
	lines.append("BW: %.2f  |  DR: %.2f" % [base_bw, base_dr])
	if influence_per_sec > 0.0:
		lines.append("Inf/sec bonus: +%.2f" % influence_per_sec)
	lines.append("Cost: %d Influence" % int(cost))
	if unlock_influence > 0.0:
		lines.append("Unlock: %d Influence" % int(unlock_influence))
	return "\n".join(lines)
