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
		"base_efficiency": 0.06,
		"node_bw_cost": 2.0,
		"node_upgrade_cost_mult": 1.5,
		"events_enabled": true,
		"event_interval_min": 30.0,
		"event_interval_max": 90.0,
		"dr_gain_per_node": 0.02,
		"dr_scale_exponent": 1.12,
		"dr_passive_decay": 0.01,
		"dr_danger_threshold": 85.0,
		"dr_soft_reset_threshold": 100.0,
		"unlock_objectives": [
			{"type": "influence_min", "value": 500.0, "label": "Reach %.0f Influence"},
			{"type": "detection_risk_below", "value": 70.0, "label": "Detection Risk < %.0f%%"},
		],
		"unlock_reward": "distributed_hub_framework",
	},
	1: {
		"name": "City Network",
		"description": "Distributed infrastructure across the city.",
		"resources": ["bandwidth", "influence", "detection_risk", "energy"],
		"max_nodes": 50,
		"node_base_bw": 1.5,
		"base_efficiency": 0.08,
		"node_bw_cost": 5.0,
		"node_upgrade_cost_mult": 1.6,
		"events_enabled": true,
		"event_interval_min": 25.0,
		"event_interval_max": 75.0,
		"dr_gain_per_node": 0.025,
		"dr_scale_exponent": 1.15,
		"dr_passive_decay": 0.012,
		"dr_danger_threshold": 85.0,
		"dr_soft_reset_threshold": 100.0,
		# Energy system
		"energy_base_gen": 5.0,
		"energy_per_node_drain": 0.3,
		"energy_overload_efficiency_mult": 0.5,
		"energy_overload_dr_mult": 1.5,
		"energy_dr_factor": 0.005,
		# Districts
		"districts": {
			"downtown": {"cap": 20, "risk_mod": 1.2, "energy_mod": 0.8, "display_name": "Downtown"},
			"industrial": {"cap": 15, "risk_mod": 0.8, "energy_mod": 1.3, "display_name": "Industrial"},
			"residential": {"cap": 15, "risk_mod": 1.0, "energy_mod": 1.0, "display_name": "Residential"},
		},
		# Objectives
		"unlock_objectives": [
			{"type": "influence_min", "value": 5000.0, "label": "Reach %.0f Influence"},
			{"type": "stability_duration", "value": 60.0, "label": "Energy stable for %.0fs"},
			{"type": "detection_risk_below", "value": 75.0, "label": "Detection Risk < %.0f%%"},
		],
		"unlock_reward": "regional_mesh_protocol",
	},
}

# === RESOURCE DEFAULTS ===
# Initial values for resource registry entries.

const RESOURCE_DEFAULTS: Dictionary = {
	"bandwidth": {"value": 0.0, "per_second": 0.0, "display_name": "Bandwidth", "format": "%.1f"},
	"influence": {"value": 0.0, "per_second": 0.0, "display_name": "Influence", "format": "%.1f"},
	"detection_risk": {"value": 0.0, "per_second": 0.0, "display_name": "Detection Risk", "format": "%.1f%%"},
	"energy": {"value": 0.0, "per_second": 0.0, "display_name": "Energy", "format": "%.1f"},
}

# === NODE UPGRADE LEVELS ===
# Each node can be upgraded to increase its output.
# Cost scales exponentially per level.

const NODE_UPGRADE_MAX_LEVEL: int = 5
const NODE_UPGRADE_BW_BONUS: float = 0.3  # +30% BW per upgrade level
const NODE_UPGRADE_BASE_COST: float = 15.0  # Influence cost for first upgrade
const NODE_UPGRADE_COST_SCALING: float = 1.5

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
	"infrastructure": {
		"display_name": "Infrastructure",
		"color": [1.0, 0.85, 0.3, 1.0],
	},
}

# === UPGRADE DEFINITIONS ===
# Indexed by tier. Each upgrade: id, name, category, base_cost, cost_scaling,
# multiplier, max_level, description, effect_type, unlock_influence.
# Core logic uses get_upgrades_for_tier() — never references TIER0 directly.

const UPGRADES_BY_TIER: Dictionary = {
0: [
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
		"unlock_influence": 80.0,
	},
	{
		"id": "stealth_protocol",
		"name": "Stealth Protocol",
		"category": "encryption",
		"base_cost": 500.0,
		"cost_scaling": 1.7,
		"multiplier": 0.008,
		"max_level": 3,
		"description": "Increases passive DR decay rate.\n+0.008 decay/s per level.",
		"effect_type": "dr_decay_bonus",
		"unlock_influence": 200.0,
	},
	# --- Event Resistance Upgrades (TASK 10) ---
	{
		"id": "event_dampener",
		"name": "Event Dampener",
		"category": "encryption",
		"base_cost": 150.0,
		"cost_scaling": 1.5,
		"multiplier": 0.10,
		"max_level": 3,
		"description": "Reduces event duration.\n-10% event duration per level.",
		"effect_type": "event_duration_reduction",
		"unlock_influence": 100.0,
	},
	{
		"id": "event_shield",
		"name": "Event Shield",
		"category": "encryption",
		"base_cost": 300.0,
		"cost_scaling": 1.6,
		"multiplier": 0.08,
		"max_level": 3,
		"description": "Reduces event severity.\n-8% event severity per level.",
		"effect_type": "event_severity_reduction",
		"unlock_influence": 150.0,
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
		"unlock_influence": 100.0,
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
		"unlock_influence": 200.0,
	},
],
1: [
	# --- Infrastructure Upgrades (new Tier 1 category) ---
	{
		"id": "energy_gen_boost",
		"name": "Energy Gen Boost",
		"category": "infrastructure",
		"base_cost": 100.0,
		"cost_scaling": 1.5,
		"multiplier": 1.5,
		"max_level": 5,
		"description": "Increases base energy generation.\n+1.5 energy/s per level.",
		"effect_type": "energy_gen_bonus",
		"unlock_influence": 0.0,
	},
	{
		"id": "grid_stabilizer",
		"name": "Grid Stabilizer",
		"category": "infrastructure",
		"base_cost": 200.0,
		"cost_scaling": 1.5,
		"multiplier": 0.05,
		"max_level": 4,
		"description": "Reduces per-node energy drain.\n-5% drain per level.",
		"effect_type": "energy_drain_reduction",
		"unlock_influence": 500.0,
	},
	{
		"id": "power_routing",
		"name": "Power Routing",
		"category": "infrastructure",
		"base_cost": 400.0,
		"cost_scaling": 1.6,
		"multiplier": 0.15,
		"max_level": 3,
		"description": "Multiplicative energy generation boost.\n+15% energy gen per level.",
		"effect_type": "energy_gen_multiplier",
		"unlock_influence": 1000.0,
	},
	{
		"id": "surge_protector",
		"name": "Surge Protector",
		"category": "infrastructure",
		"base_cost": 600.0,
		"cost_scaling": 1.7,
		"multiplier": 0.10,
		"max_level": 3,
		"description": "Reduces overload penalties.\n-10% overload severity per level.",
		"effect_type": "overload_reduction",
		"unlock_influence": 2000.0,
	},
	# --- Router Upgrades (Tier 1) ---
	{
		"id": "city_router_boost",
		"name": "City Router Boost",
		"category": "router",
		"base_cost": 150.0,
		"cost_scaling": 1.5,
		"multiplier": 0.20,
		"max_level": 5,
		"description": "City-scale bandwidth boost.\n+20% BW multiplier per level.",
		"effect_type": "bw_multiplier",
		"unlock_influence": 0.0,
	},
	{
		"id": "district_amplifier",
		"name": "District Amplifier",
		"category": "router",
		"base_cost": 500.0,
		"cost_scaling": 1.6,
		"multiplier": 0.5,
		"max_level": 3,
		"description": "Boosts base node output for all districts.\n+0.5 base BW per level.",
		"effect_type": "node_base_bonus",
		"unlock_influence": 500.0,
	},
	# --- Encryption Upgrades (Tier 1) ---
	{
		"id": "city_encryption",
		"name": "City-Wide Encryption",
		"category": "encryption",
		"base_cost": 200.0,
		"cost_scaling": 1.5,
		"multiplier": 0.12,
		"max_level": 5,
		"description": "City-scale DR reduction.\n-12% DR gain per level.",
		"effect_type": "dr_reduction",
		"unlock_influence": 0.0,
	},
	{
		"id": "district_firewall",
		"name": "District Firewall",
		"category": "encryption",
		"base_cost": 600.0,
		"cost_scaling": 1.6,
		"multiplier": 0.010,
		"max_level": 3,
		"description": "Enhanced passive DR decay.\n+0.010 decay/s per level.",
		"effect_type": "dr_decay_bonus",
		"unlock_influence": 1000.0,
	},
	# --- Hardware Upgrades (Tier 1) ---
	{
		"id": "city_cpu",
		"name": "City Processing Hub",
		"category": "hardware",
		"base_cost": 180.0,
		"cost_scaling": 1.5,
		"multiplier": 0.03,
		"max_level": 5,
		"description": "City-scale efficiency.\n+0.03 efficiency per level.",
		"effect_type": "efficiency_bonus",
		"unlock_influence": 0.0,
	},
	{
		"id": "network_optimizer",
		"name": "Network Optimizer",
		"category": "hardware",
		"base_cost": 700.0,
		"cost_scaling": 1.7,
		"multiplier": 3.0,
		"max_level": 3,
		"description": "Expands maximum node capacity.\n+3 max nodes per level.",
		"effect_type": "max_nodes_bonus",
		"unlock_influence": 1500.0,
	},
],
}

# === EVENT DEFINITIONS ===
# Indexed by tier. Core logic uses get_events_for_tier().

const EVENTS_BY_TIER: Dictionary = {
0: [
	{
		"id": "isp_throttle",
		"name": "ISP Throttle",
		"description": "Your ISP detected unusual traffic. Bandwidth reduced.",
		"category": "network",
		"duration": 20.0,
		"modifier_type": "bw_multiplier",
		"modifier_value": 0.5,
		"dr_spike": 0.0,
		"icon": "throttle",
		"severity": "warning",
	},
	{
		"id": "power_flicker",
		"name": "Power Flicker",
		"description": "Power fluctuation! Nodes temporarily disabled.",
		"category": "power",
		"duration": 10.0,
		"modifier_type": "nodes_disabled",
		"modifier_value": 1.0,
		"dr_spike": 0.0,
		"icon": "power",
		"severity": "danger",
	},
	{
		"id": "router_crash",
		"name": "Router Crash",
		"description": "Router firmware crash. Manual repair required.",
		"category": "hardware",
		"duration": -1.0,
		"modifier_type": "bw_multiplier",
		"modifier_value": 0.0,
		"dr_spike": 0.0,
		"icon": "crash",
		"severity": "critical",
	},
	{
		"id": "suspicious_traffic",
		"name": "Suspicious Traffic Warning",
		"description": "Network probe detected. Detection risk spiking.",
		"category": "security",
		"duration": 15.0,
		"modifier_type": "dr_spike",
		"modifier_value": 0.0,
		"dr_spike": 15.0,
		"icon": "warning",
		"severity": "warning",
	},
],
1: [
	{
		"id": "grid_overload",
		"name": "Grid Overload",
		"description": "Power grid instability! Energy generation halved.",
		"category": "power",
		"duration": 25.0,
		"modifier_type": "energy_gen_multiplier",
		"modifier_value": 0.5,
		"dr_spike": 0.0,
		"icon": "power",
		"severity": "warning",
	},
	{
		"id": "city_inspection",
		"name": "City Inspection",
		"description": "Authorities scanning the network...",
		"category": "security",
		"duration": 30.0,
		"modifier_type": "city_inspection",
		"modifier_value": 1.0,
		"dr_spike": 10.0,
		"icon": "warning",
		"severity": "danger",
		"dr_scan_threshold": 60.0,
		"dr_shutdown_threshold": 80.0,
	},
	{
		"id": "power_surge",
		"name": "Power Surge",
		"description": "Electrical surge! Nodes temporarily offline.",
		"category": "power",
		"duration": 12.0,
		"modifier_type": "nodes_disabled",
		"modifier_value": 1.0,
		"dr_spike": 5.0,
		"icon": "power",
		"severity": "critical",
	},
	{
		"id": "traffic_analysis",
		"name": "Traffic Analysis Alert",
		"description": "Deep packet inspection detected. DR climbing.",
		"category": "security",
		"duration": 20.0,
		"modifier_type": "dr_spike",
		"modifier_value": 0.0,
		"dr_spike": 20.0,
		"icon": "warning",
		"severity": "warning",
	},
	{
		"id": "district_shutdown",
		"name": "District Lockdown",
		"description": "A district is locked down by authorities.",
		"category": "security",
		"duration": -1.0,
		"modifier_type": "district_shutdown",
		"modifier_value": 1.0,
		"dr_spike": 5.0,
		"icon": "crash",
		"severity": "critical",
		"target_district": "",
	},
],
}

# === UNLOCK DEFINITIONS ===

const UNLOCKS: Dictionary = {
	"distributed_hub_framework": {
		"name": "Distributed Hub Framework",
		"description": "A blueprint for expanding beyond your home network.\nTier 1: City Network awaits...",
		"tier_preview": 1,
	},
	"regional_mesh_protocol": {
		"name": "Regional Mesh Protocol",
		"description": "Foundation for regional expansion.\nTier 2 awaits...",
		"tier_preview": 2,
	},
}

# === GLOBAL EFFICIENCY CURVE (TASK 1) ===
const EFFICIENCY_SOFTCAP: float = 12.0
const EFFICIENCY_EXPONENT: float = 1.25

# === DISTRICT LOAD (TASK 2) ===
const DISTRICT_OVERLOAD_THRESHOLD: float = 0.8
const DISTRICT_DR_MULTIPLIER: float = 1.15
const DISTRICT_ENERGY_MULTIPLIER: float = 1.20

# === MAINTENANCE DRAIN (TASK 3) ===
const MAINTENANCE_PER_NODE: float = 0.02
const MAINTENANCE_DR_SPIKE_RATE: float = 0.5

# === NODE DEGRADATION (TASK 4) ===
const DEGRADATION_CHANCE_PER_MINUTE: float = 0.002
const DEGRADATION_OUTPUT_PENALTY: float = 0.5
const DEGRADATION_DR_MODIFIER: float = 0.005
const DEGRADATION_REPAIR_COST: float = 10.0

# === DR TIERED STATE (TASK 5) ===
const DR_STEALTH_THRESHOLD: float = 30.0
const DR_VOLATILE_THRESHOLD: float = 60.0
const DR_CRISIS_THRESHOLD: float = 80.0
const DR_STEALTH_EFFICIENCY_BONUS: float = 0.1
const DR_VOLATILE_EVENT_FREQ_MULT: float = 1.5
const DR_CRISIS_SCAN_CHANCE_MULT: float = 2.0

# === SILENT MODE (TASK 6) ===
const SILENT_MODE_INFLUENCE_MULT: float = 0.5
const SILENT_MODE_DR_GAIN_MULT: float = 0.4
const SILENT_MODE_ENERGY_MULT: float = 0.8

# === DR MOMENTUM (TASK 7) ===
const DR_MOMENTUM_WINDOW: float = 20.0
const DR_MOMENTUM_RISE_MULT: float = 1.3
const DR_MOMENTUM_FALL_DECAY_BONUS: float = 0.005
const DR_MOMENTUM_MAX_BONUS: float = 2.0

# === EVENT ESCALATION (TASK 9) ===
const EVENT_ESCALATION_COUNT: int = 3
const EVENT_ESCALATION_WINDOW: float = 300.0  # 5 minutes
const EVENT_ESCALATION_DURATION_MULT: float = 1.5
const EVENT_ESCALATION_SEVERITY_MULT: float = 1.3

# === DOCTRINES (TASK 11) ===
const DOCTRINES: Dictionary = {
	"stealth": {
		"name": "Stealth Doctrine",
		"description": "Minimize detection. Reduced output.",
		"influence_multiplier": 0.75,
		"dr_multiplier": 0.6,
		"energy_multiplier": 0.9,
		"switch_cost": 100.0,
	},
	"throughput": {
		"name": "Throughput Doctrine",
		"description": "Maximum output. Higher risk.",
		"influence_multiplier": 1.3,
		"dr_multiplier": 1.4,
		"energy_multiplier": 1.2,
		"switch_cost": 100.0,
	},
	"stability": {
		"name": "Stability Doctrine",
		"description": "Balanced approach. Steady growth.",
		"influence_multiplier": 1.0,
		"dr_multiplier": 1.0,
		"energy_multiplier": 1.0,
		"switch_cost": 50.0,
	},
}

# === DISTRICT SPECIALIZATIONS (TASK 12) ===
const DISTRICT_SPECIALIZATIONS: Dictionary = {
	"none": {
		"name": "None",
		"description": "No specialization.",
		"output_modifier": 1.0,
		"dr_modifier": 1.0,
		"energy_modifier": 1.0,
	},
	"mining": {
		"name": "Data Mining",
		"description": "Higher output, higher risk.",
		"output_modifier": 1.3,
		"dr_modifier": 1.2,
		"energy_modifier": 1.1,
	},
	"stealth": {
		"name": "Stealth Ops",
		"description": "Lower risk, lower output.",
		"output_modifier": 0.8,
		"dr_modifier": 0.7,
		"energy_modifier": 0.9,
	},
	"relay": {
		"name": "Relay Hub",
		"description": "Energy efficient, moderate output.",
		"output_modifier": 1.1,
		"dr_modifier": 1.0,
		"energy_modifier": 0.75,
	},
}

# === EFFICIENCY FLOOR CAP (Phase 2 TASK 5) ===
const MIN_GLOBAL_EFFICIENCY: float = 0.15

# === MOMENTUM CAP (Phase 2 TASK 6) ===
const MAX_MOMENTUM_MULTIPLIER: float = 1.35

# === EVENT ESCALATION CAP (Phase 2 TASK 7) ===
const MAX_EVENT_ESCALATION_LEVEL: int = 3

# === CONSTRAINT PRIORITIES (Phase 2 TASK 2) ===
# Lower number = higher priority = updated first
const CONSTRAINT_PRIORITIES: Dictionary = {
	"detection_risk": 10,
	"energy": 20,
	"thermal_load": 30,
	"cognitive_load": 40,
}

# === COLLAPSE TYPES (Phase 2 TASK 3) ===
const COLLAPSE_TYPES: Dictionary = {
	"dr_overflow": {
		"description": "Detection risk exceeded maximum threshold.",
		"influence_penalty": 0.5,
		"clear_nodes": true,
		"clear_events": true,
	},
	"energy_failure": {
		"description": "Total energy failure — grid collapse.",
		"influence_penalty": 0.25,
		"clear_nodes": false,
		"clear_events": true,
	},
	"thermal_overload": {
		"description": "Thermal runaway — emergency shutdown.",
		"influence_penalty": 0.5,
		"clear_nodes": true,
		"clear_events": true,
	},
}

# === EQUILIBRIUM DETECTION (Phase 2 TASK 11) ===
const EQUILIBRIUM_WINDOW: float = 120.0  # seconds of stable values
const EQUILIBRIUM_DR_TOLERANCE: float = 2.0  # DR fluctuation tolerance
const EQUILIBRIUM_INF_RATE_TOLERANCE: float = 0.5  # inf/s fluctuation tolerance

# === STABILITY LOGGER (Phase 2 TASK 10) ===
const STABILITY_LOG_INTERVAL: float = 300.0  # 5 simulated minutes

# === BALANCE SNAPSHOT (Phase 2 TASK 18) ===
# Hotkey: F12 — saves current state snapshot for regression testing

# === SAVE VERSION (Phase 2 TASK 8) ===
const SAVE_VERSION: int = 3

# === SAVE SCHEMA (Phase 2 TASK 8) ===
# Required top-level keys and their expected types for save validation
const SAVE_SCHEMA: Dictionary = {
	"save_version": TYPE_INT,
	"tier": TYPE_INT,
	"resources": TYPE_DICTIONARY,
	"nodes": TYPE_ARRAY,
	"upgrade_levels": TYPE_DICTIONARY,
	"prestige": TYPE_DICTIONARY,
	"progression": TYPE_DICTIONARY,
	"active_doctrine": TYPE_STRING,
	"district_specializations": TYPE_DICTIONARY,
	"silent_mode": TYPE_BOOL,
	"event_history": TYPE_ARRAY,
	"game_clock": TYPE_FLOAT,
	"regions": TYPE_ARRAY,
	"automation": TYPE_DICTIONARY,
	"tier_locked": TYPE_DICTIONARY,
}

# === UI COLORS ===

const COLOR_CYAN := Color(0.0, 1.0, 0.835, 1.0)
const COLOR_RED := Color(1.0, 0.4, 0.4, 1.0)
const COLOR_ORANGE := Color(1.0, 0.6, 0.2, 1.0)
const COLOR_PURPLE := Color(0.7, 0.4, 1.0, 1.0)
const COLOR_GOLD := Color(1.0, 0.85, 0.3, 1.0)
const COLOR_MUTED := Color(0.45, 0.5, 0.55, 1.0)
const COLOR_DIM := Color(0.3, 0.35, 0.4, 1.0)
const COLOR_BG_DARK := Color(0.055, 0.067, 0.086, 1.0)

# === HELPER FUNCTIONS ===

func get_tier_config(tier: int) -> Dictionary:
	if TIER_DEFS.has(tier):
		return TIER_DEFS[tier]
	return {}

func get_tier_name(tier: int) -> String:
	var cfg := get_tier_config(tier)
	return cfg.get("name", "Unknown")

func get_upgrades_for_tier(tier: int) -> Array:
	return UPGRADES_BY_TIER.get(tier, [])

func get_events_for_tier(tier: int) -> Array:
	return EVENTS_BY_TIER.get(tier, [])

func get_upgrade_cost(base_cost: float, cost_scaling: float, level: int) -> float:
	return base_cost * pow(cost_scaling, level)

func get_node_upgrade_cost(level: int) -> float:
	return NODE_UPGRADE_BASE_COST * pow(NODE_UPGRADE_COST_SCALING, level)

# === CONSTRAINT INTERACTION MATRIX (Phase 1 #3) ===
# Cross-modifiers applied during constraint dispatch, before final calculation.
# Key: source constraint. Value: { target_effect: modifier_strength }
const CONSTRAINT_INTERACTIONS: Dictionary = {
	"thermal_load": {
		"bandwidth":  0.15,   # High thermal degrades BW output
		"dr_gain":    0.10,   # High thermal increases DR gain rate
	},
	"detection_risk": {
		"thermal_load": 0.08, # High DR stresses hardware, raises thermal
	},
	"energy": {
		"dr_gain": 0.12,      # Energy deficit increases DR gain (desperate ops)
	},
}

# === THERMAL LOAD CONFIG (Phase 2 #7) ===
const THERMAL_PER_NODE_RATE: float       = 0.08   # thermal/s generated per node
const THERMAL_MAINTENANCE_FACTOR: float  = 0.40   # extra thermal from maintenance events
const THERMAL_DEGRADED_FACTOR: float     = 2.50   # degraded nodes generate extra heat
const THERMAL_DISSIPATION_BASE: float    = 0.60   # natural cooling rate (%/s)
const THERMAL_EFFICIENCY_PENALTY: float  = 0.35   # max efficiency penalty at 100% thermal
const THERMAL_DR_GAIN_BONUS: float       = 0.25   # DR gain multiplier at 100% thermal
const THERMAL_EVENT_SEVERITY_BONUS: float = 0.20  # event severity multiplier per 50% thermal
const THERMAL_MELTDOWN_THRESHOLD: float  = 95.0   # triggers thermal_meltdown collapse

# === SYSTEM NOISE INJECTION (Phase 3 #11) ===
const NOISE_BASE_AMPLITUDE: float      = 0.018   # Base micro-fluctuation amplitude
const NOISE_DR_SCALE_FACTOR: float     = 0.006   # Noise scales linearly with DR/100
const NOISE_CONSTRAINT_DRIFT: float    = 0.008   # Constraint regen variance (subtle)
const NOISE_MAX_AMPLITUDE: float       = 0.12    # Hard cap — never causes pure-random collapse
const NOISE_SPEED: float               = 1.0     # Phase advance rate

# === DR PHASE TRANSITION BANDS (Phase 3 #10) ===
# Nonlinear behavior shifts at band boundaries.
# Each band applies a distinct function rather than an if-statement scalar.
const DR_PHASE_BANDS: Dictionary = {
	"predictable":  {"min":  0.0, "max": 25.0},
	"noisy":        {"min": 25.0, "max": 50.0},
	"coupled":      {"min": 50.0, "max": 75.0},
	"exponential":  {"min": 75.0, "max": 100.0},
}

# === ADAPTIVE DIFFICULTY (Phase 1 #1) ===
const ADAPTIVE_DR_GAIN_RANGE: Array        = [0.55, 1.80]
const ADAPTIVE_EVENT_FREQ_RANGE: Array     = [0.60, 1.70]
const ADAPTIVE_MAINTENANCE_RANGE: Array    = [0.60, 1.60]
const ADAPTIVE_CONSTRAINT_REGEN_RANGE: Array = [0.65, 1.35]
const ADAPTIVE_SMOOTHING: float            = 0.04   # Low = smooth, imperceptible changes
const ADAPTIVE_WINDOW: float               = 240.0  # 4-minute performance window

# === EQUILIBRIUM DEEP MODEL (Phase 3 #9) ===
# True dynamic equilibrium via derivative stability analysis.
const EQUILIBRIUM_DERIV_WINDOW: float         = 10.0   # Window for derivative calc
const EQUILIBRIUM_STABLE_DERIV_MAX: float     = 0.08   # Max |dDR/dt| for "stable"
const EQUILIBRIUM_META_STABLE_DERIV_MAX: float = 0.25  # Max |dDR/dt| for "meta-stable"
const EQUILIBRIUM_CHAOTIC_THRESHOLD: float    = 0.50   # 2nd derivative threshold for chaos

# === META-COLLAPSE TYPES (Phase 3 #12) ===
# Extends COLLAPSE_TYPES with multi-layer collapses.
const META_COLLAPSE_TYPES: Dictionary = {
	"infrastructure_collapse": {
		"description": "Critical infrastructure failure — hardware destroyed.",
		"influence_penalty": 0.40,
		"clear_nodes": true,
		"clear_events": true,
		"resets_thermal": true,
		"affects_memory": true,
		"adaptive_difficulty_shift": -0.08,
	},
	"social_collapse": {
		"description": "Network exposure — influence network compromised.",
		"influence_penalty": 0.65,
		"clear_nodes": false,
		"clear_events": false,
		"resets_doctrine": true,
		"affects_memory": true,
		"adaptive_difficulty_shift": -0.05,
	},
	"economic_collapse": {
		"description": "Economic resources drained by counter-operations.",
		"influence_penalty": 0.88,
		"clear_nodes": false,
		"clear_events": true,
		"affects_memory": true,
	},
	"thermal_meltdown": {
		"description": "Thermal runaway destroyed hardware — emergency shutdown.",
		"influence_penalty": 0.38,
		"clear_nodes": true,
		"clear_events": true,
		"resets_thermal": true,
		"affects_memory": true,
	},
	"systemic_cascade": {
		"description": "All constraints exceeded simultaneously — total systemic failure.",
		"influence_penalty": 0.85,
		"clear_nodes": true,
		"clear_events": true,
		"affects_memory": true,
		"resets_all_constraints": true,
		"adaptive_difficulty_shift": -0.15,
	},
}

# === EVENT CHAINS (Phase 2 #5) ===
# Events can trigger follow-up events conditionally.
# chain_conditions: list of conditions that must be met for chain to trigger.
const EVENT_CHAINS: Dictionary = {
	"infrastructure_crisis": {
		"name": "Infrastructure Crisis",
		"trigger_events": ["power_surge", "grid_overload"],
		"trigger_conditions": {"dr_above": 60.0, "thermal_above": 40.0},
		"stages": [
			{
				"id": "chain_infra_1",
				"name": "Infrastructure Strain",
				"description": "Cascading failures spreading through infrastructure.",
				"duration": 35.0,
				"modifier_type": "bw_multiplier",
				"modifier_value": 0.55,
				"dr_spike": 8.0,
				"severity": "danger",
				"next_stage_id": "chain_infra_2",
				"next_stage_chance": 0.65,
			},
			{
				"id": "chain_infra_2",
				"name": "Grid Cascade Failure",
				"description": "Full grid cascade — emergency shutdown protocols activated.",
				"duration": 55.0,
				"modifier_type": "nodes_disabled",
				"modifier_value": 1.0,
				"dr_spike": 18.0,
				"severity": "critical",
				"next_stage_id": "",
				"next_stage_chance": 0.0,
				"triggers_collapse": "infrastructure_collapse",
				"collapse_chance": 0.25,
			},
		],
	},
	"security_escalation": {
		"name": "Security Escalation",
		"trigger_events": ["suspicious_traffic", "city_inspection"],
		"trigger_conditions": {"dr_above": 70.0},
		"stages": [
			{
				"id": "chain_sec_1",
				"name": "Active Surveillance",
				"description": "Authorities have escalated to active surveillance mode.",
				"duration": 45.0,
				"modifier_type": "bw_multiplier",
				"modifier_value": 0.7,
				"dr_spike": 12.0,
				"severity": "danger",
				"next_stage_id": "chain_sec_2",
				"next_stage_chance": 0.55,
			},
			{
				"id": "chain_sec_2",
				"name": "Lockdown Protocol",
				"description": "Full lockdown — network integrity at risk.",
				"duration": -1.0,
				"modifier_type": "nodes_disabled",
				"modifier_value": 1.0,
				"dr_spike": 25.0,
				"severity": "critical",
				"next_stage_id": "",
				"next_stage_chance": 0.0,
			},
		],
	},
}

# === AUTOMATION AGENTS (Phase 2 #8) ===
const AUTOMATION_AGENTS: Dictionary = {
	"constraint_monitor": {
		"name": "Constraint Monitor",
		"description": "Watches constraint levels and warns before thresholds.",
		"priority": 1.0,
		"efficiency_cost": 0.04,    # Influence/s overhead
		"misallocation_chance": 0.06,
		"dr_threshold_warn": 65.0,
		"thermal_threshold_warn": 55.0,
	},
	"repair_agent": {
		"name": "Repair Agent",
		"description": "Auto-repairs degraded nodes when influence is available.",
		"priority": 0.90,
		"efficiency_cost": 0.06,
		"misallocation_chance": 0.05,
		"repair_interval": 15.0,    # Seconds between repair attempts
	},
	"influence_allocator": {
		"name": "Influence Allocator",
		"description": "Dynamically distributes influence across budget categories.",
		"priority": 0.80,
		"efficiency_cost": 0.08,
		"misallocation_chance": 0.12,
		"rebalance_interval": 30.0,
	},
	"doctrine_optimizer": {
		"name": "Doctrine Optimizer",
		"description": "Switches doctrines based on real-time system state.",
		"priority": 0.65,
		"efficiency_cost": 0.10,
		"misallocation_chance": 0.22,  # Can conflict with player strategy
		"evaluation_interval": 45.0,
	},
}

# === INFLUENCE ALLOCATION MODEL (Phase 5 #18) ===
const INFLUENCE_BUDGET_CATEGORIES: Dictionary = {
	"maintenance": {
		"name": "Maintenance Fund",
		"description": "Reduces degradation rate and repair costs.",
		"min_weight": 0.05,
		"max_weight": 0.60,
		"dr_effect": "degradation_reduction",
		"diminishing_returns": 0.55,  # Past this fraction, returns drop sharply
	},
	"research": {
		"name": "Research Budget",
		"description": "Boosts upgrade effectiveness and discovery speed.",
		"min_weight": 0.05,
		"max_weight": 0.50,
		"dr_effect": "upgrade_amplifier",
		"diminishing_returns": 0.45,
	},
	"automation_fund": {
		"name": "Automation Systems",
		"description": "Funds automation agent efficiency.",
		"min_weight": 0.0,
		"max_weight": 0.50,
		"dr_effect": "automation_efficiency",
		"diminishing_returns": 0.40,
	},
	"stabilization": {
		"name": "Stabilization Reserve",
		"description": "Reduces DR gain and event frequency.",
		"min_weight": 0.05,
		"max_weight": 0.60,
		"dr_effect": "stability_boost",
		"diminishing_returns": 0.50,
	},
}

# === DOCTRINE EVOLUTION TREE (Phase 5 #16) ===
# Mutations are unlockable branches off base doctrines.
const DOCTRINE_MUTATIONS: Dictionary = {
	"ghost_protocol": {
		"name": "Ghost Protocol",
		"parent_doctrine": "stealth",
		"description": "Extreme stealth — nearly undetectable but minimal output.",
		"unlock_conditions": {"stealth_doctrine_time": 300.0, "dr_max_during": 25.0},
		"influence_multiplier": 0.50,
		"dr_multiplier": 0.30,
		"energy_multiplier": 0.85,
		"switch_cost": 280.0,
		"instability_side_effect": 0.04,
		"dr_spike_immunity": 0.40,
	},
	"distributed_shadow": {
		"name": "Distributed Shadow",
		"parent_doctrine": "stealth",
		"description": "Shadow operations across regions — stealth at scale.",
		"unlock_conditions": {"stealth_doctrine_time": 200.0},
		"influence_multiplier": 0.65,
		"dr_multiplier": 0.42,
		"energy_multiplier": 0.88,
		"switch_cost": 220.0,
		"instability_side_effect": 0.03,
	},
	"overclocked_grid": {
		"name": "Overclocked Grid",
		"parent_doctrine": "throughput",
		"description": "Maximum output — thermal runaway is a real risk.",
		"unlock_conditions": {"throughput_doctrine_time": 300.0, "thermal_reached": 40.0},
		"influence_multiplier": 1.80,
		"dr_multiplier": 1.65,
		"energy_multiplier": 1.50,
		"thermal_multiplier": 1.40,
		"switch_cost": 320.0,
		"instability_side_effect": 0.16,
	},
	"surge_protocol": {
		"name": "Surge Protocol",
		"parent_doctrine": "throughput",
		"description": "Burst output with high collapse risk — high variance.",
		"unlock_conditions": {"throughput_doctrine_time": 180.0, "collapses_survived": 3},
		"influence_multiplier": 1.55,
		"dr_multiplier": 1.38,
		"energy_multiplier": 1.28,
		"switch_cost": 210.0,
		"instability_side_effect": 0.11,
	},
	"iron_equilibrium": {
		"name": "Iron Equilibrium",
		"parent_doctrine": "stability",
		"description": "Perfect balance — reduced DR spikes, locked-in efficiency.",
		"unlock_conditions": {"stability_doctrine_time": 400.0, "equilibrium_time_reached": 180.0},
		"influence_multiplier": 1.12,
		"dr_multiplier": 0.82,
		"energy_multiplier": 0.94,
		"switch_cost": 380.0,
		"instability_side_effect": 0.01,
		"dr_spike_immunity": 0.55,
	},
	"hybrid_adaptive": {
		"name": "Hybrid Adaptive",
		"parent_doctrine": "",   # No parent — requires both stealth and throughput time
		"description": "Dynamically shifts between stealth and throughput based on DR.",
		"unlock_conditions": {"stealth_doctrine_time": 180.0, "throughput_doctrine_time": 180.0},
		"dynamic": true,
		"switch_cost": 500.0,
		"instability_side_effect": 0.08,
	},
}

# === STRATEGIC PERSONALITY PROFILES (Phase 7 #23) ===
# Used by SystemAdvisor and Automation agents to shape decision-making.
const PERSONALITY_PROFILES: Dictionary = {
	"conservative_stabilizer": {
		"name": "Conservative Stabilizer",
		"description": "Minimize risk at all costs — stability above growth.",
		"dr_threshold": 38.0,
		"preferred_doctrine": "stealth",
		"automation_priority_agents": ["constraint_monitor", "repair_agent"],
		"adaptive_feedback": -0.14,
		"risk_tolerance": 0.18,
		"thermal_weight": 1.5,
	},
	"growth_maximizer": {
		"name": "Growth Maximizer",
		"description": "Maximum influence at any risk.",
		"dr_threshold": 72.0,
		"preferred_doctrine": "throughput",
		"automation_priority_agents": ["influence_allocator", "doctrine_optimizer"],
		"adaptive_feedback": 0.22,
		"risk_tolerance": 0.80,
	},
	"risk_gambler": {
		"name": "Risk Gambler",
		"description": "High variance — maximum reward or catastrophic failure.",
		"dr_threshold": 85.0,
		"preferred_doctrine": "throughput",
		"automation_priority_agents": ["doctrine_optimizer"],
		"adaptive_feedback": 0.32,
		"risk_tolerance": 0.94,
	},
	"thermal_minimalist": {
		"name": "Thermal Minimalist",
		"description": "Keep thermal load near zero — hardware longevity first.",
		"dr_threshold": 48.0,
		"preferred_doctrine": "stability",
		"automation_priority_agents": ["constraint_monitor", "repair_agent"],
		"adaptive_feedback": -0.06,
		"risk_tolerance": 0.32,
		"thermal_weight": 3.0,
	},
	"chaos_harnessing": {
		"name": "Chaos Harnessing",
		"description": "Operate at the edge of instability — extract value from disorder.",
		"dr_threshold": 78.0,
		"preferred_doctrine": "throughput",
		"automation_priority_agents": ["doctrine_optimizer", "influence_allocator"],
		"adaptive_feedback": 0.12,
		"risk_tolerance": 0.88,
		"chaos_bonus_mult": 0.28,
	},
}

# === REGIONAL SIMULATION CONFIG (Phase 2 #6) ===
const REGION_BASE_EFFICIENCY: float         = 0.85
const REGION_INSTABILITY_THRESHOLD: float   = 0.65   # Above this -> local stress
const REGION_LOCAL_COLLAPSE_THRESHOLD: float = 0.88  # Above this -> partial reset
const REGION_DOCTRINE_BIAS_STRENGTH: float  = 0.12   # How much regional bias affects output
const REGION_LOAD_DISSIPATION: float        = 0.05   # Load recovers per second
const REGION_INSTABILITY_GROWTH_RATE: float = 0.02   # Instability growth when overloaded

# === SYSTEM SINGULARITY PHASE (Phase 8 #25) ===
const SINGULARITY_TIER: int                    = 3
const SINGULARITY_DR_HARVEST_RATE: float       = 0.08   # DR -> influence conversion
const SINGULARITY_MERGE_THRESHOLD: float       = 0.80   # Constraint merge trigger
const SINGULARITY_INVERSION_BASE_CHANCE: float = 0.04   # Collapse inversion probability
const SINGULARITY_CONTROLLED_CHAOS_DR: float   = 65.0   # Target DR for "controlled chaos"

# === TELEMETRY CONFIG (Phase 4 #13) ===
const TELEMETRY_BUFFER_SECONDS: float = 300.0   # 5-minute rolling window
const TELEMETRY_SAMPLE_RATE: float    = 1.0     # Samples per second

# === HARD LIMIT SAFETY NET (Phase 6 #21) ===
const SAFETY_MAX_DR: float         = 100.0
const SAFETY_MAX_INFLUENCE: float  = 1000000.0
const SAFETY_MAX_THERMAL: float    = 100.0
const SAFETY_MAX_MOMENTUM: float   = 4.5
const SAFETY_MAX_ENERGY: float     = 99999.0
const SAFETY_MAX_NODE_BW: float    = 10000.0

# === DETERMINISTIC SIMULATION (Phase 6 #19) ===
const DEFAULT_SIMULATION_SEED: int = 42137

# === TIER LOCK ESCALATION (Phase 5 #17) ===
# Dynamic conditions that can temporarily lock/unlock tiers.
const TIER_LOCK_CONDITIONS: Dictionary = {
	"collapse_frequency_lock": {
		"description": "Too many collapses — tier locked until stability achieved.",
		"collapse_window": 300.0,    # Seconds
		"max_collapses": 3,
		"unlock_requirement": "equilibrium",
	},
	"equilibrium_required": {
		"description": "Must achieve equilibrium before advancing.",
		"equilibrium_duration": 60.0,
	},
}
