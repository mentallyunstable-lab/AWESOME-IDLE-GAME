class_name Upgrade
extends RefCounted

var id: String
var name: String
var level: int = 0
var max_level: int = 5
var base_cost: float
var cost_scaling: float = 1.4
var multiplier: float
var description: String
var category: String

func get_cost() -> float:
	return base_cost * pow(cost_scaling, level)

func get_current_effect() -> float:
	return level * multiplier

func get_next_effect() -> float:
	return (level + 1) * multiplier

func is_maxed() -> bool:
	return level >= max_level

func can_afford(currency: float) -> bool:
	return not is_maxed() and currency >= get_cost()

func purchase() -> bool:
	if is_maxed():
		return false
	level += 1
	return true

func get_tooltip() -> String:
	if is_maxed():
		return "%s\nMAX LEVEL\nEffect: %.2f" % [description, get_current_effect()]
	return "%s\nCurrent: %.2f\nNext: %.2f\nCost: %d Influence" % [
		description, get_current_effect(), get_next_effect(), int(get_cost())
	]
