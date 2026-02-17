extends Node
## game_config.gd — Central configuration for all game constants.
## All balance numbers, tier definitions, and formulas live here.
## Nothing is hardcoded in game logic — everything references this file.

# === TIER DEFINITIONS ===
# Each tier config defines resources, limits, events, and unlock conditions.
# Future tiers add entries here — core logic stays untouched.

const TIER_DEFS: Dictionary = {
	0: {
		"name": "House",
		"description": "A single residential node operating from home.",
		"resources": ["bandwidth", "influence", "detection_risk"],
		"max_nodes": 20,
		"node_base_bw": 1.0,
		"base_efficiency": 0.05,
		"node_bw_cost": 2.0,
		"node_upgrade_cost_mult": 1.5,
		"events_enabled": true,
		"event_interval_min": 30.0,
		"event_interval_max": 90.0,
		"dr_gain_per_node": 0.02,
		"dr_passive_decay": 0.01,
		"dr_danger_threshold": 85.0,
		"dr_soft_reset_threshold": 100.0,
		"unlock_condition": {
			"influence_min": 500.0,
			"detection_risk_below": 70.0,
		},
		"unlock_reward": "distributed_hub_framework",
	},
	# Tier 1-7 stubs — added when those tiers are implemented
}

# === RESOURCE DEFAULTS ===
# Initial values for resource registry entries.

const RESOURCE_DEFAULTS: Dictionary = {
	"bandwidth": {"value": 0.0, "per_second": 0.0, "display_name": "Bandwidth", "format": "%.1f"},
	"influence": {"value": 0.0, "per_second": 0.0, "display_name": "Influence", "format": "%.1f"},
	"detection_risk": {"value": 0.0, "per_second": 0.0, "display_name": "Detection Risk", "format": "%.1f%%"},
}

# === NODE UPGRADE LEVELS ===
# Each node can be upgraded to increase its output.
# Cost scales exponentially per level.

const NODE_UPGRADE_MAX_LEVEL: int = 5
const NODE_UPGRADE_BW_BONUS: float = 0.3  # +30% BW per upgrade level
const NODE_UPGRADE_BASE_COST: float = 15.0  # Influence cost for first upgrade
const NODE_UPGRADE_COST_SCALING: float = 1.8

# === UPGRADE CATEGORIES (TIER 0) ===
# Router = bandwidth generation + max node soft cap
# Encryption = detection risk reduction
# Hardware = influence per node boost

const UPGRADE_CATEGORIES: Dictionary = {
	"router": {
		"display_name": "Router",
		"color": [0.0, 1.0, 0.835, 1.0],
	},
	"encryption": {
		"display_name": "Encryption",
		"color": [1.0, 0.4, 0.4, 1.0],
	},
	"hardware": {
		"display_name": "Hardware",
		"color": [0.7, 0.4, 1.0, 1.0],
	},
}

# === UPGRADE DEFINITIONS (TIER 0) ===
# Each upgrade: id, name, category, base_cost, cost_scaling, multiplier,
#               max_level, description, effect_type, unlock_influence

const TIER0_UPGRADES: Array = [
	# --- Router Upgrades ---
	{
		"id": "router_boost",
		"name": "Router Boost",
		"category": "router",
		"base_cost": 30.0,
		"cost_scaling": 1.4,
		"multiplier": 0.15,
		"max_level": 5,
		"description": "Increases bandwidth generation.\n+15% BW multiplier per level.",
		"effect_type": "bw_multiplier",
		"unlock_influence": 0.0,
	},
	{
		"id": "signal_amplifier",
		"name": "Signal Amplifier",
		"category": "router",
		"base_cost": 80.0,
		"cost_scaling": 1.5,
		"multiplier": 0.25,
		"max_level": 3,
		"description": "Boosts base node output.\n+0.25 base BW per level.",
		"effect_type": "node_base_bonus",
		"unlock_influence": 0.0,
	},
	{
		"id": "dual_band",
		"name": "Dual-Band Router",
		"category": "router",
		"base_cost": 200.0,
		"cost_scaling": 1.6,
		"multiplier": 0.20,
		"max_level": 4,
		"description": "Further bandwidth scaling.\n+20% BW multiplier per level.",
		"effect_type": "bw_multiplier",
		"unlock_influence": 100.0,
	},
	{
		"id": "mesh_network",
		"name": "Mesh Network",
		"category": "router",
		"base_cost": 500.0,
		"cost_scaling": 1.7,
		"multiplier": 2.0,
		"max_level": 3,
		"description": "Expands maximum node capacity.\n+2 max nodes per level.",
		"effect_type": "max_nodes_bonus",
		"unlock_influence": 200.0,
	},
	# --- Encryption Upgrades ---
	{
		"id": "basic_encryption",
		"name": "Basic Encryption",
		"category": "encryption",
		"base_cost": 25.0,
		"cost_scaling": 1.4,
		"multiplier": 0.15,
		"max_level": 5,
		"description": "Reduces detection risk gain.\n-15% DR gain per level.",
		"effect_type": "dr_reduction",
		"unlock_influence": 0.0,
	},
	{
		"id": "firewall",
		"name": "Firewall",
		"category": "encryption",
		"base_cost": 100.0,
		"cost_scaling": 1.5,
		"multiplier": 0.10,
		"max_level": 3,
		"description": "Additional DR reduction.\n-10% DR gain per level.",
		"effect_type": "dr_reduction",
		"unlock_influence": 0.0,
	},
	{
		"id": "vpn_tunneling",
		"name": "VPN Tunneling",
		"category": "encryption",
		"base_cost": 250.0,
		"cost_scaling": 1.6,
		"multiplier": 0.08,
		"max_level": 4,
		"description": "Advanced traffic obfuscation.\n-8% DR gain per level.",
		"effect_type": "dr_reduction",
		"unlock_influence": 120.0,
	},
	{
		"id": "stealth_protocol",
		"name": "Stealth Protocol",
		"category": "encryption",
		"base_cost": 600.0,
		"cost_scaling": 1.8,
		"multiplier": 0.05,
		"max_level": 3,
		"description": "Increases passive DR decay rate.\n+0.005 decay/s per level.",
		"effect_type": "dr_decay_bonus",
		"unlock_influence": 250.0,
	},
	# --- Hardware Upgrades ---
	{
		"id": "cpu_overclock",
		"name": "CPU Overclock",
		"category": "hardware",
		"base_cost": 35.0,
		"cost_scaling": 1.4,
		"multiplier": 0.02,
		"max_level": 5,
		"description": "Boosts influence generation efficiency.\n+0.02 efficiency per level.",
		"effect_type": "efficiency_bonus",
		"unlock_influence": 0.0,
	},
	{
		"id": "ram_expansion",
		"name": "RAM Expansion",
		"category": "hardware",
		"base_cost": 120.0,
		"cost_scaling": 1.5,
		"multiplier": 0.03,
		"max_level": 4,
		"description": "Further influence efficiency.\n+0.03 efficiency per level.",
		"effect_type": "efficiency_bonus",
		"unlock_influence": 0.0,
	},
	{
		"id": "ssd_cache",
		"name": "SSD Cache",
		"category": "hardware",
		"base_cost": 300.0,
		"cost_scaling": 1.6,
		"multiplier": 0.04,
		"max_level": 3,
		"description": "High-speed data processing.\n+0.04 efficiency per level.",
		"effect_type": "efficiency_bonus",
		"unlock_influence": 150.0,
	},
	{
		"id": "gpu_compute",
		"name": "GPU Compute",
		"category": "hardware",
		"base_cost": 700.0,
		"cost_scaling": 1.8,
		"multiplier": 0.05,
		"max_level": 3,
		"description": "Massive influence processing power.\n+0.05 efficiency per level.",
		"effect_type": "efficiency_bonus",
		"unlock_influence": 300.0,
	},
]

# === EVENT DEFINITIONS (TIER 0) ===

const TIER0_EVENTS: Array = [
	{
		"id": "isp_throttle",
		"name": "ISP Throttle",
		"description": "Your ISP detected unusual traffic. Bandwidth reduced.",
		"duration": 20.0,
		"modifier_type": "bw_multiplier",
		"modifier_value": 0.5,  # 50% BW
		"dr_spike": 0.0,
		"icon": "throttle",
		"severity": "warning",
	},
	{
		"id": "power_flicker",
		"name": "Power Flicker",
		"description": "Power fluctuation! Nodes temporarily disabled.",
		"duration": 10.0,
		"modifier_type": "nodes_disabled",
		"modifier_value": 1.0,  # All nodes disabled
		"dr_spike": 0.0,
		"icon": "power",
		"severity": "danger",
	},
	{
		"id": "router_crash",
		"name": "Router Crash",
		"description": "Router firmware crash. Manual repair required.",
		"duration": -1.0,  # -1 = requires manual dismiss
		"modifier_type": "bw_multiplier",
		"modifier_value": 0.0,  # Zero BW
		"dr_spike": 0.0,
		"icon": "crash",
		"severity": "critical",
	},
	{
		"id": "suspicious_traffic",
		"name": "Suspicious Traffic Warning",
		"description": "Network probe detected. Detection risk spiking.",
		"duration": 15.0,
		"modifier_type": "dr_spike",
		"modifier_value": 0.0,
		"dr_spike": 15.0,  # Immediate DR increase
		"icon": "warning",
		"severity": "warning",
	},
]

# === UNLOCK DEFINITIONS ===

const UNLOCKS: Dictionary = {
	"distributed_hub_framework": {
		"name": "Distributed Hub Framework",
		"description": "A blueprint for expanding beyond your home network.\nTier 1: City Network awaits...",
		"tier_preview": 1,
	},
}

# === UI COLORS ===

const COLOR_CYAN := Color(0.0, 1.0, 0.835, 1.0)
const COLOR_RED := Color(1.0, 0.4, 0.4, 1.0)
const COLOR_ORANGE := Color(1.0, 0.6, 0.2, 1.0)
const COLOR_PURPLE := Color(0.7, 0.4, 1.0, 1.0)
const COLOR_MUTED := Color(0.45, 0.5, 0.55, 1.0)
const COLOR_DIM := Color(0.3, 0.35, 0.4, 1.0)
const COLOR_BG_DARK := Color(0.055, 0.067, 0.086, 1.0)

# === HELPER FUNCTIONS ===

static func get_tier_config(tier: int) -> Dictionary:
	if TIER_DEFS.has(tier):
		return TIER_DEFS[tier]
	return {}

static func get_tier_name(tier: int) -> String:
	var cfg := get_tier_config(tier)
	return cfg.get("name", "Unknown")

static func get_upgrade_cost(base_cost: float, cost_scaling: float, level: int) -> float:
	return base_cost * pow(cost_scaling, level)

static func get_node_upgrade_cost(level: int) -> float:
	return NODE_UPGRADE_BASE_COST * pow(NODE_UPGRADE_COST_SCALING, level)
