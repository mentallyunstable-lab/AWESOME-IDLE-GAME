extends MarginContainer
## main_dashboard.gd — Main UI controller.
## 3-panel layout: Left (resources/constraints/objectives),
##                 Center (node management/events),
##                 Right (upgrades).

# === LEFT PANEL ===
@onready var tier_label: Label = %TierLabel
@onready var bandwidth_value: Label = %BandwidthValue
@onready var influence_value: Label = %InfluenceValue
@onready var influence_rate: Label = %InfluenceRate
@onready var detection_value: Label = %DetectionValue
@onready var detection_rate: Label = %DetectionRate
@onready var dr_bar: ProgressBar = %DrBar
@onready var objective_influence: Label = %ObjectiveInfluence
@onready var objective_dr: Label = %ObjectiveDR
@onready var unlock_status: Label = %UnlockStatus

# === CENTER PANEL ===
@onready var node_count_label: Label = %NodeCount
@onready var node_capacity: Label = %NodeCapacity
@onready var node_subtitle: Label = %NodeSubtitle
@onready var deploy_button: Button = %DeployButton
@onready var remove_button: Button = %RemoveButton
@onready var upgrade_node_button: Button = %UpgradeNodeButton
@onready var node_grid: GridContainer = %NodeGrid
@onready var risk_warning: Label = %RiskWarning
@onready var events_container: VBoxContainer = %EventsContainer

# === RIGHT PANEL ===
@onready var router_tab: Button = %RouterTab
@onready var encryption_tab: Button = %EncryptionTab
@onready var hardware_tab: Button = %HardwareTab
@onready var upgrade_panel = $VBoxLayout/ContentHBox/RightPanel/RightVBox/TabContent/UpgradePanel

# === TIMERS ===
@onready var risk_pulse_timer: Timer = %RiskPulseTimer

# === STATE ===
var active_tab: String = "router"
var risk_pulse_on: bool = false
var risk_is_critical: bool = false
var _last_node_count: int = 0

# === TAB COLORS ===
const TAB_COLORS := {
	"router": Color(0.0, 1.0, 0.835, 1),
	"encryption": Color(1.0, 0.4, 0.4, 1),
	"hardware": Color(0.7, 0.4, 1.0, 1),
}

func _ready() -> void:
	# Node action buttons
	deploy_button.pressed.connect(_on_deploy_pressed)
	remove_button.pressed.connect(_on_remove_pressed)
	upgrade_node_button.pressed.connect(_on_upgrade_node_pressed)

	# Resource updates
	Resources.resources_updated.connect(_update_display)
	Resources.risk_warning.connect(_on_risk_warning)
	Resources.soft_reset_triggered.connect(_on_soft_reset)

	# Event system
	EventSystem.event_started.connect(_on_event_started)
	EventSystem.event_ended.connect(_on_event_ended)
	EventSystem.event_requires_repair.connect(_on_event_requires_repair)

	# Upgrades
	Upgrades.upgrade_purchased.connect(_on_upgrade_purchased)

	# Unlock
	GameState.unlock_achieved.connect(_on_unlock_achieved)

	# Risk pulse timer
	risk_pulse_timer.timeout.connect(_on_risk_pulse)

	# Tab buttons
	router_tab.pressed.connect(_on_tab_pressed.bind("router"))
	encryption_tab.pressed.connect(_on_tab_pressed.bind("encryption"))
	hardware_tab.pressed.connect(_on_tab_pressed.bind("hardware"))

	# Init
	tier_label.text = "TIER %d // %s" % [GameState.tier, GameConfig.get_tier_name(GameState.tier).to_upper()]
	_on_tab_pressed("router")
	_update_display()

# === NODE ACTIONS ===

func _on_deploy_pressed() -> void:
	if GameState.deploy_node():
		_rebuild_node_grid()
		_flash_label(node_count_label)

func _on_remove_pressed() -> void:
	var count := GameState.get_node_count()
	if count > 0:
		GameState.remove_node(count - 1)
		_rebuild_node_grid()

func _on_upgrade_node_pressed() -> void:
	# Upgrade the lowest-level node
	var best_idx: int = -1
	var best_level: int = GameConfig.NODE_UPGRADE_MAX_LEVEL + 1
	for i in range(GameState.nodes.size()):
		var lvl: int = GameState.nodes[i].get("level", 1)
		if lvl < best_level:
			best_level = lvl
			best_idx = i
	if best_idx >= 0:
		if GameState.upgrade_node(best_idx):
			_rebuild_node_grid()
			_flash_label(node_count_label)

# === TAB SWITCHING ===

func _on_tab_pressed(category: String) -> void:
	active_tab = category
	upgrade_panel.show_category(category)
	_update_tab_visuals()

func _update_tab_visuals() -> void:
	var tabs := {"router": router_tab, "encryption": encryption_tab, "hardware": hardware_tab}
	for cat: String in tabs.keys():
		var btn: Button = tabs[cat]
		var color: Color = TAB_COLORS.get(cat, Color.WHITE)
		if cat == active_tab:
			btn.add_theme_color_override("font_color", color)
			btn.add_theme_color_override("font_hover_color", color)
		else:
			btn.add_theme_color_override("font_color", GameConfig.COLOR_MUTED)
			btn.add_theme_color_override("font_hover_color", Color(0.6, 0.65, 0.7, 1))

# === LIVE DISPLAY ===

func _update_display() -> void:
	# Resources
	bandwidth_value.text = Resources.get_bandwidth_display()
	influence_value.text = Resources.get_influence_display()
	influence_rate.text = "(+%.2f/s)" % Resources.get_influence_rate()

	# Detection Risk
	var dr: float = GameState.get_resource("detection_risk")
	detection_value.text = Resources.get_detection_risk_display()
	detection_rate.text = Resources.get_dr_rate_display()
	dr_bar.value = dr

	# DR color coding
	if dr >= 85.0:
		detection_value.add_theme_color_override("font_color", GameConfig.COLOR_RED)
		detection_rate.add_theme_color_override("font_color", GameConfig.COLOR_RED)
	elif dr >= 50.0:
		detection_value.add_theme_color_override("font_color", GameConfig.COLOR_ORANGE)
		detection_rate.add_theme_color_override("font_color", GameConfig.COLOR_ORANGE)
	else:
		detection_value.add_theme_color_override("font_color", GameConfig.COLOR_CYAN)
		detection_rate.add_theme_color_override("font_color", GameConfig.COLOR_MUTED)

	# Nodes
	var nc: int = GameState.get_node_count()
	node_count_label.text = str(nc)
	node_capacity.text = "/ %d nodes" % GameState.get_max_nodes()
	node_subtitle.text = "generating %s bandwidth" % Resources.get_bandwidth_display()

	# Button states
	deploy_button.disabled = not GameState.can_deploy_node()
	remove_button.disabled = nc <= 0
	upgrade_node_button.disabled = not _can_upgrade_any_node()

	# Upgrade node button cost display
	var cheapest_cost := _get_cheapest_node_upgrade_cost()
	if cheapest_cost > 0.0:
		upgrade_node_button.text = "[ UPGRADE NODE — %d Inf ]" % int(cheapest_cost)
	else:
		upgrade_node_button.text = "[ UPGRADE NODE ]"

	# Rebuild grid only when node count changes
	if nc != _last_node_count:
		_last_node_count = nc
		_rebuild_node_grid()

	# Objectives
	_update_objectives()

# === NODE GRID VISUAL ===

func _rebuild_node_grid() -> void:
	for child in node_grid.get_children():
		child.queue_free()

	for i in range(GameState.nodes.size()):
		var node_data: Dictionary = GameState.nodes[i]
		var level: int = node_data.get("level", 1)
		var rect := ColorRect.new()
		rect.custom_minimum_size = Vector2(16, 16)
		rect.size = Vector2(16, 16)

		# Color intensity by level
		var alpha: float = 0.4 + (level - 1) * 0.15
		rect.color = Color(0.0, 1.0, 0.835, clampf(alpha, 0.4, 1.0))

		rect.tooltip_text = "Node %d — Lv.%d" % [i + 1, level]
		node_grid.add_child(rect)

# === OBJECTIVES ===

func _update_objectives() -> void:
	var inf: float = GameState.get_resource("influence")
	var dr: float = GameState.get_resource("detection_risk")

	var inf_met: bool = inf >= 500.0
	var dr_met: bool = dr < 70.0

	if inf_met:
		objective_influence.text = "[x] Reach 500 Influence"
		objective_influence.add_theme_color_override("font_color", GameConfig.COLOR_CYAN)
	else:
		objective_influence.text = "[ ] Reach 500 Influence (%.0f / 500)" % inf
		objective_influence.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65, 1))

	if dr_met:
		objective_dr.text = "[x] Detection Risk < 70%%"
		objective_dr.add_theme_color_override("font_color", GameConfig.COLOR_CYAN)
	else:
		objective_dr.text = "[ ] Detection Risk < 70%% (%.1f%%)" % dr
		objective_dr.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65, 1))

# === EVENT DISPLAY ===

func _on_event_started(_event_data: Dictionary) -> void:
	_rebuild_events_display()

func _on_event_ended(_event_id: String) -> void:
	_rebuild_events_display()

func _on_event_requires_repair(_event_id: String) -> void:
	_rebuild_events_display()

func _rebuild_events_display() -> void:
	for child in events_container.get_children():
		child.queue_free()

	var active := EventSystem.get_active_events()
	for entry: Dictionary in active:
		var def: Dictionary = entry["def"]
		var remaining: float = entry["remaining"]

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		events_container.add_child(hbox)

		var severity: String = def.get("severity", "warning")
		var color: Color
		match severity:
			"critical":
				color = GameConfig.COLOR_RED
			"danger":
				color = GameConfig.COLOR_ORANGE
			_:
				color = Color(1.0, 0.85, 0.3, 1)

		var indicator := ColorRect.new()
		indicator.color = color
		indicator.custom_minimum_size = Vector2(4, 0)
		hbox.add_child(indicator)

		var info_vbox := VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info_vbox)

		var name_label := Label.new()
		name_label.text = def.get("name", "Event")
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", color)
		info_vbox.add_child(name_label)

		var desc_label := Label.new()
		if remaining < 0.0:
			desc_label.text = def.get("description", "") + " [REPAIR REQUIRED]"
		else:
			desc_label.text = "%s (%.0fs)" % [def.get("description", ""), remaining]
		desc_label.add_theme_font_size_override("font_size", 10)
		desc_label.add_theme_color_override("font_color", GameConfig.COLOR_MUTED)
		info_vbox.add_child(desc_label)

		# Repair button for manual-dismiss events
		if remaining < 0.0:
			var repair_btn := Button.new()
			repair_btn.text = "REPAIR"
			repair_btn.custom_minimum_size = Vector2(60, 28)
			repair_btn.pressed.connect(_on_repair_pressed.bind(def["id"]))
			hbox.add_child(repair_btn)

func _on_repair_pressed(event_id: String) -> void:
	EventSystem.repair_event(event_id)

# === RISK WARNING SYSTEM ===

func _on_risk_warning(level: float) -> void:
	if not risk_is_critical:
		risk_is_critical = true
		risk_pulse_timer.start()

	if level >= 85.0:
		risk_warning.text = "!! CRITICAL EXPOSURE — DETECTION IMMINENT !!"
	elif level >= 70.0:
		risk_warning.text = "!! HIGH RISK — Reduce nodes or invest in Encryption !!"
	else:
		risk_warning.text = "! WARNING — Detection Risk Elevated !"

func _on_risk_pulse() -> void:
	var dr: float = GameState.get_resource("detection_risk")
	if dr < 50.0:
		risk_is_critical = false
		risk_pulse_timer.stop()
		risk_warning.text = ""
		return

	risk_pulse_on = not risk_pulse_on
	if risk_pulse_on:
		risk_warning.add_theme_color_override("font_color", GameConfig.COLOR_RED)
	else:
		risk_warning.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 0.3))

# === SOFT RESET ===

func _on_soft_reset() -> void:
	risk_warning.text = "// DETECTED — Network compromised. Rebuilding..."
	risk_is_critical = false
	risk_pulse_timer.stop()
	_last_node_count = 0
	_rebuild_node_grid()
	_rebuild_events_display()

	var tween := create_tween()
	tween.tween_property(risk_warning, "theme_override_colors/font_color", GameConfig.COLOR_RED, 0.1)
	tween.tween_interval(3.0)
	tween.tween_callback(func() -> void: risk_warning.text = "")

# === UNLOCK ===

func _on_unlock_achieved(unlock_id: String) -> void:
	var unlock_def: Dictionary = GameConfig.UNLOCKS.get(unlock_id, {})
	unlock_status.text = "UNLOCKED: %s" % unlock_def.get("name", unlock_id)
	unlock_status.add_theme_color_override("font_color", GameConfig.COLOR_CYAN)

	var tween := create_tween()
	tween.tween_property(unlock_status, "theme_override_colors/font_color", Color.WHITE, 0.1)
	tween.tween_property(unlock_status, "theme_override_colors/font_color", GameConfig.COLOR_CYAN, 0.5)

# === UPGRADE FEEDBACK ===

func _on_upgrade_purchased(_upgrade_id: String) -> void:
	_flash_label(bandwidth_value)

# === HELPERS ===

func _flash_label(label: Label) -> void:
	var original_color: Color = GameConfig.COLOR_CYAN
	var flash_color: Color = Color.WHITE

	var tween := create_tween()
	tween.tween_property(label, "theme_override_colors/font_color", flash_color, 0.08)
	tween.tween_property(label, "theme_override_colors/font_color", original_color, 0.35)

func _can_upgrade_any_node() -> bool:
	for node_data: Dictionary in GameState.nodes:
		var level: int = node_data.get("level", 1)
		if level < GameConfig.NODE_UPGRADE_MAX_LEVEL:
			var cost := GameConfig.get_node_upgrade_cost(level)
			if GameState.get_resource("influence") >= cost:
				return true
	return false

func _get_cheapest_node_upgrade_cost() -> float:
	var cheapest: float = -1.0
	for node_data: Dictionary in GameState.nodes:
		var level: int = node_data.get("level", 1)
		if level < GameConfig.NODE_UPGRADE_MAX_LEVEL:
			var cost := GameConfig.get_node_upgrade_cost(level)
			if cheapest < 0.0 or cost < cheapest:
				cheapest = cost
	return maxf(cheapest, 0.0)
