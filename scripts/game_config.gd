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
