class_name Region
extends RefCounted
## Region — Regional unit for the simulation layer (Phase 2 #6).
##
## Each region has:
##   - efficiency:   Output multiplier relative to global base
##   - load:         Current utilization ratio (nodes/max_nodes)
##   - instability:  Risk coefficient; drives local stress and collapses
##   - doctrine_bias: Preferred doctrine — shifts output/DR modifiers
##
## Global constraints aggregate from region outputs via RegionManager.

# === IDENTITY ===
var id: String
var name: String
var position: Vector2

# === UNLOCK ===
var unlock_threshold: float = 500.0
var unlocked: bool = false

# === NODES ===
var node_count: int = 0
var max_nodes: int = 10

# === SIMULATION STATE (Phase 2 #6) ===
var efficiency: float = GameConfig.REGION_BASE_EFFICIENCY
var load: float = 0.0           # 0.0 -> 1.0 utilization
var instability: float = 0.0    # 0.0 -> 1.0 instability rating
var doctrine_bias: String = "none"  # stealth | throughput | stability | none

# Local collapse state
var local_collapse_active: bool = false
var local_collapse_timer: float = 0.0
const LOCAL_COLLAPSE_DURATION: float = 30.0

# === LEGACY MULTIPLIERS (kept for UI compat) ===
var bw_multiplier: float = 0.0
var dr_multiplier: float = 0.0
var influence_multiplier: float = 0.0

# Visual state
var dr_event_active: bool = false
var dr_event_type: String = ""

# =========================================================
# SIMULATION TICK
# =========================================================

func tick(delta: float) -> void:
	if not unlocked:
		return

	# Update load from node count
	load = float(node_count) / float(maxi(max_nodes, 1))

	# Instability growth when overloaded
	if load > GameConfig.REGION_INSTABILITY_THRESHOLD:
		var overload_factor: float = (load - GameConfig.REGION_INSTABILITY_THRESHOLD) / \
			(1.0 - GameConfig.REGION_INSTABILITY_THRESHOLD)
		instability = clampf(instability + GameConfig.REGION_INSTABILITY_GROWTH_RATE * overload_factor * delta, 0.0, 1.0)
	else:
		# Natural stability recovery
		instability = clampf(instability - GameConfig.REGION_LOAD_DISSIPATION * delta, 0.0, 1.0)

	# Local collapse check
	if instability >= GameConfig.REGION_LOCAL_COLLAPSE_THRESHOLD and not local_collapse_active:
		_trigger_local_collapse()

	# Recover from local collapse
	if local_collapse_active:
		local_collapse_timer -= delta
		if local_collapse_timer <= 0.0:
			local_collapse_active = false
			instability *= 0.3   # Partial instability reset after recovery

	# Compute output multipliers from simulation state
	_recompute_multipliers()

func _trigger_local_collapse() -> void:
	local_collapse_active = true
	local_collapse_timer = LOCAL_COLLAPSE_DURATION
	# Partial reset of this region's nodes
	var nodes_removed: int = node_count / 2
	node_count = maxi(0, node_count - nodes_removed)
	load = float(node_count) / float(maxi(max_nodes, 1))
	print("[Region:%s] Local collapse — removed %d nodes. Instability: %.2f" % [
		id, nodes_removed, instability
	])

func _recompute_multipliers() -> void:
	# Efficiency penalty from instability
	var instability_penalty: float = instability * 0.4
	var effective_efficiency: float = maxf(0.2, efficiency - instability_penalty)

	# Local collapse halves output
	if local_collapse_active:
		effective_efficiency *= 0.3

	influence_multiplier = effective_efficiency - 1.0  # Relative to base 1.0

	# DR multiplier: higher load + instability = more DR
	dr_multiplier = instability * 0.3 + (maxf(0.0, load - 0.7) * 0.2)

	# BW multiplier: base from efficiency, penalty from local collapse
	bw_multiplier = effective_efficiency - 1.0

# =========================================================
# DOCTRINE BIAS (Phase 2 #6)
# =========================================================

## Returns the output modifier influenced by doctrine bias.
## If the player's doctrine aligns with region bias -> bonus. Misaligned -> penalty.
func get_doctrine_alignment_modifier(active_doctrine: String) -> float:
	if doctrine_bias == "none" or doctrine_bias == "":
		return 1.0

	if active_doctrine == doctrine_bias:
		return 1.0 + GameConfig.REGION_DOCTRINE_BIAS_STRENGTH
	elif active_doctrine == "stability":
		return 1.0  # Neutral
	else:
		return 1.0 - GameConfig.REGION_DOCTRINE_BIAS_STRENGTH * 0.5

## Returns per-region DR contribution to global DR.
func get_regional_dr_contribution() -> float:
	if not unlocked or local_collapse_active:
		return 0.0
	return float(node_count) * (1.0 + dr_multiplier) * (1.0 + instability * 0.2)

## Returns per-region influence contribution.
func get_regional_influence_contribution() -> float:
	if not unlocked:
		return 0.0
	return float(node_count) * (1.0 + influence_multiplier)

## Returns per-region bandwidth contribution.
func get_regional_bw_contribution(base_node_bw: float) -> float:
	if not unlocked or local_collapse_active:
		return 0.0
	return float(node_count) * base_node_bw * (1.0 + bw_multiplier)

# =========================================================
# STATE QUERIES
# =========================================================

func is_full() -> bool:
	return node_count >= max_nodes

func is_overloaded() -> bool:
	return load > GameConfig.REGION_INSTABILITY_THRESHOLD

func is_stable() -> bool:
	return instability < 0.2 and not local_collapse_active

func can_unlock(current_influence: float) -> bool:
	return not unlocked and current_influence >= unlock_threshold

func get_status_string() -> String:
	if not unlocked:
		return "LOCKED"
	if local_collapse_active:
		return "LOCAL COLLAPSE (%.0fs)" % local_collapse_timer
	if instability > GameConfig.REGION_INSTABILITY_THRESHOLD:
		return "UNSTABLE"
	if is_overloaded():
		return "OVERLOADED"
	return "ONLINE"

func get_tooltip() -> String:
	var lines := PackedStringArray()
	lines.append("[%s] %s" % [name, get_status_string()])
	if not unlocked:
		lines.append("Requires %.0f Influence to unlock." % unlock_threshold)
		return "\n".join(lines)
	lines.append("Nodes: %d / %d (Load: %.0f%%)" % [node_count, max_nodes, load * 100.0])
	lines.append("Efficiency: %.2f | Instability: %.0f%%" % [efficiency, instability * 100.0])
	lines.append("Doctrine Bias: %s" % doctrine_bias.capitalize())
	if bw_multiplier != 0.0:
		lines.append("BW: %+.0f%%" % (bw_multiplier * 100.0))
	if influence_multiplier != 0.0:
		lines.append("Influence: %+.0f%%" % (influence_multiplier * 100.0))
	if dr_multiplier != 0.0:
		lines.append("DR: %+.0f%%" % (dr_multiplier * 100.0))
	return "\n".join(lines)
