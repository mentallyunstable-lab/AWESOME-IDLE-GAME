extends Node
## upgrades.gd — Upgrade system facade.
## Reads definitions from GameConfig, state from GameState.
## Provides query methods for the UI.

signal upgrade_purchased(upgrade_id: String)

func try_purchase(upgrade_id: String) -> bool:
	if GameState.try_purchase_upgrade(upgrade_id):
		upgrade_purchased.emit(upgrade_id)
		return true
	return false

func get_upgrade_level(upgrade_id: String) -> int:
	return GameState.get_upgrade_level(upgrade_id)

func get_upgrades_for_category(category: String) -> Array:
	var result: Array = []
	for def: Dictionary in GameConfig.TIER0_UPGRADES:
		if def.get("category", "") == category:
			result.append(def)
	return result

func get_upgrade_def(upgrade_id: String) -> Dictionary:
	for def: Dictionary in GameConfig.TIER0_UPGRADES:
		if def["id"] == upgrade_id:
			return def
	return {}

func get_cost(upgrade_id: String) -> float:
	var def := get_upgrade_def(upgrade_id)
	if def.is_empty():
		return 0.0
	var level: int = get_upgrade_level(upgrade_id)
	return GameConfig.get_upgrade_cost(
		def.get("base_cost", 100.0),
		def.get("cost_scaling", 1.4),
		level
	)

func is_maxed(upgrade_id: String) -> bool:
	var def := get_upgrade_def(upgrade_id)
	if def.is_empty():
		return true
	return get_upgrade_level(upgrade_id) >= def.get("max_level", 5)

func is_locked(upgrade_id: String) -> bool:
	var def := get_upgrade_def(upgrade_id)
	if def.is_empty():
		return true
	var unlock_inf: float = def.get("unlock_influence", 0.0)
	return unlock_inf > 0.0 and GameState.get_resource("influence") < unlock_inf

func can_afford(upgrade_id: String) -> bool:
	if is_maxed(upgrade_id) or is_locked(upgrade_id):
		return false
	return GameState.get_resource("influence") >= get_cost(upgrade_id)

func get_current_effect(upgrade_id: String) -> float:
	var def := get_upgrade_def(upgrade_id)
	var level: int = get_upgrade_level(upgrade_id)
	return level * def.get("multiplier", 0.0)

func get_next_effect(upgrade_id: String) -> float:
	var def := get_upgrade_def(upgrade_id)
	var level: int = get_upgrade_level(upgrade_id)
	return (level + 1) * def.get("multiplier", 0.0)

func get_tooltip(upgrade_id: String) -> String:
	var def := get_upgrade_def(upgrade_id)
	if def.is_empty():
		return ""
	var level: int = get_upgrade_level(upgrade_id)
	var max_level: int = def.get("max_level", 5)
	var desc: String = def.get("description", "")

	if level >= max_level:
		return "%s\nMAX LEVEL\nEffect: %.2f" % [desc, get_current_effect(upgrade_id)]

	var lines := "%s\nCurrent: %.2f\nNext: %.2f\nCost: %d Influence" % [
		desc, get_current_effect(upgrade_id), get_next_effect(upgrade_id), int(get_cost(upgrade_id))
	]
	var unlock_inf: float = def.get("unlock_influence", 0.0)
	if unlock_inf > 0.0:
		lines += "\nUnlock: %d Influence" % int(unlock_inf)
	return lines
