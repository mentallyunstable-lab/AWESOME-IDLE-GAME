extends Node
## automation_system.gd — Automation AI System (Phase 2 #8)
##
## === DESIGN ===
## Automation agents monitor constraints, allocate influence, trigger repairs,
## and activate doctrines. Each agent:
##   - Has a priority weight
##   - Can conflict with player strategy
##   - Has a misallocation chance (makes mistakes)
##   - Costs influence/s overhead
##
## Automation efficiency penalty: more agents = diminishing returns.
## Risk of misallocation: doctrine optimizer can pick wrong doctrine.

signal automation_action(agent_id: String, action: String, data: Dictionary)
signal agent_activated(agent_id: String)
signal agent_deactivated(agent_id: String)
signal misallocation_occurred(agent_id: String, description: String)

var active_agents: Dictionary = {}   # { agent_id: { timer, config } }
var automation_enabled: bool = false
var total_efficiency_penalty: float = 0.0  # Fraction of influence lost to overhead

const MIN_INFLUENCE_TO_ACT: float = 20.0   # Don't act if influence is critically low

func _ready() -> void:
	TickEngine.game_tick.connect(_on_tick)

func _on_tick(delta: float) -> void:
	if not automation_enabled or active_agents.is_empty():
		return
	_update_efficiency_penalty()
	_tick_agents(delta)

# =========================================================
# AGENT MANAGEMENT
# =========================================================

func activate_agent(agent_id: String) -> bool:
	if not GameConfig.AUTOMATION_AGENTS.has(agent_id):
		push_warning("[Automation] Unknown agent: %s" % agent_id)
		return false
	if active_agents.has(agent_id):
		return false  # Already active

	var cfg: Dictionary = GameConfig.AUTOMATION_AGENTS[agent_id]
	active_agents[agent_id] = {
		"config": cfg,
		"timer":  0.0,
		"misallocation_cooldown": 0.0,
	}
	automation_enabled = true
	GameState.automation["active"] = true
	agent_activated.emit(agent_id)
	print("[Automation] Activated agent: %s" % cfg.get("name", agent_id))
	return true

func deactivate_agent(agent_id: String) -> void:
	if active_agents.has(agent_id):
		active_agents.erase(agent_id)
		agent_deactivated.emit(agent_id)
		print("[Automation] Deactivated: %s" % agent_id)
	if active_agents.is_empty():
		automation_enabled = false
		GameState.automation["active"] = false

func deactivate_all() -> void:
	var ids: Array = active_agents.keys()
	for id: String in ids:
		deactivate_agent(id)

# =========================================================
# EFFICIENCY
# =========================================================

func _update_efficiency_penalty() -> void:
	var total_cost: float = 0.0
	for id: String in active_agents.keys():
		var cfg: Dictionary = active_agents[id]["config"]
		total_cost += cfg.get("efficiency_cost", 0.05)
	# Diminishing returns: 3+ agents get extra overhead
	var count: int = active_agents.size()
	if count > 2:
		total_cost *= (1.0 + float(count - 2) * 0.15)
	total_efficiency_penalty = clampf(total_cost, 0.0, 0.50)

func get_automation_overhead() -> float:
	return total_efficiency_penalty

# =========================================================
# AGENT TICK
# =========================================================

func _tick_agents(delta: float) -> void:
	for id: String in active_agents.keys():
		var entry: Dictionary = active_agents[id]
		entry["timer"] += delta

		# Drain influence for overhead
		var cost: float = entry["config"].get("efficiency_cost", 0.05) * delta
		GameState.add_resource("influence", -cost)

		# Tick misallocation cooldown
		if entry["misallocation_cooldown"] > 0.0:
			entry["misallocation_cooldown"] -= delta

		# Agent-specific action intervals
		_tick_agent_action(id, entry, delta)

func _tick_agent_action(agent_id: String, entry: Dictionary, _delta: float) -> void:
	var cfg: Dictionary = entry["config"]
	var timer: float = entry["timer"]

	match agent_id:
		"constraint_monitor":
			if timer >= 5.0:
				entry["timer"] = 0.0
				_act_constraint_monitor(entry)

		"repair_agent":
			var interval: float = cfg.get("repair_interval", 15.0)
			if timer >= interval:
				entry["timer"] = 0.0
				_act_repair_agent(entry)

		"influence_allocator":
			var interval: float = cfg.get("rebalance_interval", 30.0)
			if timer >= interval:
				entry["timer"] = 0.0
				_act_influence_allocator(entry)

		"doctrine_optimizer":
			var interval: float = cfg.get("evaluation_interval", 45.0)
			if timer >= interval:
				entry["timer"] = 0.0
				_act_doctrine_optimizer(entry)

# =========================================================
# AGENT BEHAVIORS
# =========================================================

func _act_constraint_monitor(entry: Dictionary) -> void:
	var cfg: Dictionary = entry["config"]
	var dr: float = GameState.get_resource("detection_risk")
	var thermal: float = GameState.get_thermal_load()

	# Warn at DR threshold
	if dr > cfg.get("dr_threshold_warn", 65.0):
		var action_data := {"dr": dr, "warning": "DR approaching critical"}
		automation_action.emit("constraint_monitor", "warn_dr", action_data)

	# Warn at thermal threshold
	if thermal > cfg.get("thermal_threshold_warn", 55.0):
		var action_data := {"thermal": thermal, "warning": "Thermal elevated"}
		automation_action.emit("constraint_monitor", "warn_thermal", action_data)

func _act_repair_agent(entry: Dictionary) -> void:
	if GameState.get_resource("influence") < MIN_INFLUENCE_TO_ACT:
		return

	# Check for misallocation
	if _check_misallocation(entry):
		return

	# Repair degraded nodes
	var repaired: int = 0
	for i in range(GameState.nodes.size()):
		if GameState.nodes[i].get("degraded", false):
			if GameState.repair_node(i):
				repaired += 1
				automation_action.emit("repair_agent", "repair_node", {"index": i})
				break  # Repair one per tick to avoid draining influence

func _act_influence_allocator(entry: Dictionary) -> void:
	if GameState.get_resource("influence") < MIN_INFLUENCE_TO_ACT * 2.0:
		return

	# Check for misallocation
	if _check_misallocation(entry):
		misallocation_occurred.emit("influence_allocator", "Budget misallocated — funds diverted to wrong category.")
		return

	# Simple rebalancing: if DR high, shift influence toward stabilization upgrades
	var dr: float = GameState.get_resource("detection_risk")
	if dr > 65.0:
		automation_action.emit("influence_allocator", "rebalance_toward_stability", {"dr": dr})
	else:
		automation_action.emit("influence_allocator", "rebalance_toward_growth", {"inf": GameState.get_resource("influence")})

func _act_doctrine_optimizer(entry: Dictionary) -> void:
	if GameState.get_resource("influence") < MIN_INFLUENCE_TO_ACT:
		return

	# Check for misallocation (highest chance — doctrine optimizer makes mistakes)
	if _check_misallocation(entry):
		# Misallocation: pick a random doctrine instead of optimal
		var all_doctrines: Array = GameConfig.DOCTRINES.keys()
		var random_doctrine: String = all_doctrines[randi() % all_doctrines.size()]
		misallocation_occurred.emit("doctrine_optimizer",
			"Optimizer confused — suggested '%s' doctrine (suboptimal)." % random_doctrine)
		automation_action.emit("doctrine_optimizer", "doctrine_mistake", {"doctrine": random_doctrine})
		return

	# Optimal doctrine selection based on system state
	var dr: float = GameState.get_resource("detection_risk")
	var inf_rate: float = GameState.get_per_second("influence")
	var target_doctrine: String = ""

	if dr > 70.0:
		target_doctrine = "stealth"
	elif inf_rate < 2.0 and dr < 50.0:
		target_doctrine = "throughput"
	else:
		target_doctrine = "stability"

	if target_doctrine != "" and target_doctrine != GameState.active_doctrine:
		if GameState.switch_doctrine(target_doctrine):
			automation_action.emit("doctrine_optimizer", "switch_doctrine", {"doctrine": target_doctrine})

func _check_misallocation(entry: Dictionary) -> bool:
	if entry["misallocation_cooldown"] > 0.0:
		return false
	var chance: float = entry["config"].get("misallocation_chance", 0.1)
	if randf() < chance:
		entry["misallocation_cooldown"] = 60.0  # 1 minute cooldown
		return true
	return false

# =========================================================
# STRATEGY EVALUATION (Phase 2 #8)
# =========================================================

func evaluate_automation_strategy() -> Dictionary:
	var report: Dictionary = {
		"active_agents":       active_agents.keys(),
		"overhead_penalty":    total_efficiency_penalty,
		"net_efficiency":      1.0 - total_efficiency_penalty,
		"recommendations":     [],
		"conflicts_detected":  [],
	}

	# Detect conflicts with player doctrine strategy
	if active_agents.has("doctrine_optimizer") and GameState.active_doctrine == "stealth":
		report["conflicts_detected"].append(
			"Doctrine optimizer may override your stealth doctrine selection."
		)

	if active_agents.has("influence_allocator") and GameState.get_resource("influence") < 100.0:
		report["conflicts_detected"].append(
			"Influence allocator is active but influence reserve is very low."
		)

	if active_agents.size() >= 4:
		report["recommendations"].append(
			"Running all agents simultaneously — overhead penalty is %.0f%%." % (total_efficiency_penalty * 100.0)
		)

	return report

func get_agent_status() -> Dictionary:
	var status: Dictionary = {}
	for id: String in active_agents.keys():
		var entry: Dictionary = active_agents[id]
		status[id] = {
			"name":          entry["config"].get("name", id),
			"timer":         entry["timer"],
			"on_cooldown":   entry["misallocation_cooldown"] > 0.0,
			"cost_per_sec":  entry["config"].get("efficiency_cost", 0.0),
		}
	return status
