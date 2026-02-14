extends Node

signal upgrade_purchased(upgrade_id: String)

var infra_upgrades: Dictionary = {}
var security_upgrades: Dictionary = {}
var intel_upgrades: Dictionary = {}

func _ready() -> void:
	_init_infra()
	_init_security()
	_init_intel()

func _init_infra() -> void:
	var u := Upgrade.new()
	u.id = "node_efficiency"
	u.name = "Node Efficiency"
	u.base_cost = 50.0
	u.multiplier = 0.1
	u.max_level = 5
	u.description = "Boosts infrastructure multiplier.\n+0.10 BW multiplier per level."
	u.category = "infra"
	infra_upgrades[u.id] = u

	var u2 := Upgrade.new()
	u2.id = "bandwidth_compress"
	u2.name = "BW Compression"
	u2.base_cost = 120.0
	u2.multiplier = 0.25
	u2.max_level = 3
	u2.description = "Increases base node output.\n+0.25 node base per level."
	u2.category = "infra"
	infra_upgrades[u2.id] = u2

	var u3 := Upgrade.new()
	u3.id = "parallel_threads"
	u3.name = "Parallel Threads"
	u3.base_cost = 300.0
	u3.multiplier = 0.15
	u3.max_level = 4
	u3.description = "Further infra multiplier scaling.\n+0.15 BW multiplier per level."
	u3.category = "infra"
	infra_upgrades[u3.id] = u3

	# === Mid-Game Infra ===
	var u4 := Upgrade.new()
	u4.id = "overclocking"
	u4.name = "Overclocking"
	u4.base_cost = 800.0
	u4.cost_scaling = 1.6
	u4.multiplier = 0.20
	u4.max_level = 5
	u4.description = "Aggressive BW multiplier boost.\n+0.20 BW multiplier per level."
	u4.category = "infra"
	u4.unlock_influence = 500.0
	infra_upgrades[u4.id] = u4

	var u5 := Upgrade.new()
	u5.id = "multi_core"
	u5.name = "Multi-Core Expansion"
	u5.base_cost = 1500.0
	u5.cost_scaling = 1.8
	u5.multiplier = 0.5
	u5.max_level = 3
	u5.description = "Major base node output increase.\n+0.50 node base per level."
	u5.category = "infra"
	u5.unlock_influence = 1000.0
	infra_upgrades[u5.id] = u5

func _init_security() -> void:
	var u := Upgrade.new()
	u.id = "encryption"
	u.name = "Encryption"
	u.base_cost = 50.0
	u.multiplier = 0.05
	u.max_level = 5
	u.description = "Reduces detection risk.\n-5% DR multiplier per level."
	u.category = "security"
	security_upgrades[u.id] = u

	var u2 := Upgrade.new()
	u2.id = "firewall"
	u2.name = "Firewall"
	u2.base_cost = 150.0
	u2.multiplier = 0.08
	u2.max_level = 3
	u2.description = "Additional DR reduction.\n-8% DR multiplier per level."
	u2.category = "security"
	security_upgrades[u2.id] = u2

	var u3 := Upgrade.new()
	u3.id = "obfuscation"
	u3.name = "Obfuscation"
	u3.base_cost = 400.0
	u3.multiplier = 0.10
	u3.max_level = 3
	u3.description = "Heavy DR reduction.\n-10% DR multiplier per level."
	u3.category = "security"
	security_upgrades[u3.id] = u3

	# === Mid-Game Security ===
	var u4 := Upgrade.new()
	u4.id = "adv_encryption"
	u4.name = "Advanced Encryption"
	u4.base_cost = 900.0
	u4.cost_scaling = 1.7
	u4.multiplier = 0.07
	u4.max_level = 5
	u4.description = "Strong DR reduction.\n-7% DR multiplier per level."
	u4.category = "security"
	u4.unlock_influence = 500.0
	security_upgrades[u4.id] = u4

	var u5 := Upgrade.new()
	u5.id = "ai_firewall"
	u5.name = "AI Firewall"
	u5.base_cost = 2000.0
	u5.cost_scaling = 2.0
	u5.multiplier = 0.12
	u5.max_level = 3
	u5.description = "AI-powered DR mitigation.\n-12% DR multiplier per level."
	u5.category = "security"
	u5.unlock_influence = 1200.0
	security_upgrades[u5.id] = u5

func _init_intel() -> void:
	var u := Upgrade.new()
	u.id = "predictive_scaling"
	u.name = "Predictive Scaling"
	u.base_cost = 50.0
	u.multiplier = 0.02
	u.max_level = 5
	u.description = "Boosts Influence generation.\n+0.02 efficiency multiplier per level."
	u.category = "intel"
	intel_upgrades[u.id] = u

	var u2 := Upgrade.new()
	u2.id = "data_mining"
	u2.name = "Data Mining"
	u2.base_cost = 200.0
	u2.multiplier = 0.04
	u2.max_level = 4
	u2.description = "Further Influence boost.\n+0.04 efficiency multiplier per level."
	u2.category = "intel"
	intel_upgrades[u2.id] = u2

	var u3 := Upgrade.new()
	u3.id = "neural_cache"
	u3.name = "Neural Cache"
	u3.base_cost = 500.0
	u3.multiplier = 0.06
	u3.max_level = 3
	u3.description = "Major Influence scaling.\n+0.06 efficiency multiplier per level."
	u3.category = "intel"
	intel_upgrades[u3.id] = u3

	# === Mid-Game Intel ===
	var u4 := Upgrade.new()
	u4.id = "predictive_ai"
	u4.name = "Predictive AI"
	u4.base_cost = 1000.0
	u4.cost_scaling = 1.6
	u4.multiplier = 0.05
	u4.max_level = 5
	u4.description = "AI-driven efficiency boost.\n+0.05 efficiency multiplier per level."
	u4.category = "intel"
	u4.unlock_influence = 600.0
	intel_upgrades[u4.id] = u4

	var u5 := Upgrade.new()
	u5.id = "deep_data_mining"
	u5.name = "Deep Data Mining"
	u5.base_cost = 2500.0
	u5.cost_scaling = 2.0
	u5.multiplier = 0.08
	u5.max_level = 3
	u5.description = "Deep analysis for massive Influence.\n+0.08 efficiency multiplier per level."
	u5.category = "intel"
	u5.unlock_influence = 1500.0
	intel_upgrades[u5.id] = u5

func try_purchase(upgrade_id: String) -> bool:
	var u := _find_upgrade(upgrade_id)
	if u == null:
		return false
	if not u.can_afford(Resources.influence):
		return false

	Resources.influence -= u.get_cost()
	u.purchase()
	_apply_all_upgrades()
	upgrade_purchased.emit(upgrade_id)
	return true

func _apply_all_upgrades() -> void:
	# Infra → BW multiplier + node base
	var total_infra_mult: float = 0.0
	var total_base_bonus: float = 0.0
	for u: Upgrade in infra_upgrades.values():
		if u.id == "bandwidth_compress" or u.id == "multi_core":
			total_base_bonus += u.get_current_effect()
		else:
			total_infra_mult += u.get_current_effect()
	Resources.infra_multiplier = total_infra_mult
	Resources.node_base_output = 1.5 + total_base_bonus

	# Security → encryption level visual + DR handled in resources.gd
	var total_enc_level: float = 1.0
	for u: Upgrade in security_upgrades.values():
		total_enc_level += u.level
	Resources.encryption_level = total_enc_level

	# Intel → efficiency multiplier
	var total_efficiency: float = 0.1
	for u: Upgrade in intel_upgrades.values():
		total_efficiency += u.get_current_effect()
	Resources.efficiency_multiplier = total_efficiency

	Resources.recalculate()

func get_dr_reduction() -> float:
	var dr_reduction: float = 0.0
	for u: Upgrade in security_upgrades.values():
		dr_reduction += u.get_current_effect()
	return dr_reduction

func get_upgrades_for_category(category: String) -> Dictionary:
	match category:
		"infra":
			return infra_upgrades
		"security":
			return security_upgrades
		"intel":
			return intel_upgrades
	return {}

func _find_upgrade(upgrade_id: String) -> Upgrade:
	for dict in [infra_upgrades, security_upgrades, intel_upgrades]:
		if dict.has(upgrade_id):
			return dict[upgrade_id]
	return null
