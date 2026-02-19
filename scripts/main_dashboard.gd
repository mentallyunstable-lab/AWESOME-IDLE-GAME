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

# === DEBUG PANEL STATE ===
var _debug_visible: bool = false
var _debug_panel: PanelContainer
var _debug_labels: Dictionary = {}
var _inf_samples: Array = []
var _sample_accumulator: float = 0.0
var _event_uptime_total: float = 0.0
var _game_time_total: float = 0.0

# === SILENT MODE UI ===
var _silent_mode_button: Button

# === DOCTRINE UI ===
var _doctrine_container: HBoxContainer

# === PRESSURE BAR REFERENCES (Phase 2 TASK 12) ===
var _dr_pressure_bar: Dictionary = {}
var _energy_pressure_bar: Dictionary = {}
var _dr_bar_flash_timer: float = 0.0
var _dr_bar_flash_active: bool = false

# === SPEED CYCLE ===
const SPEED_STEPS: Array = [1.0, 2.0, 5.0, 10.0]
var _speed_index: int = 0

# === TAB COLORS ===
const TAB_COLORS := {
	"router": Color(0.0, 1.0, 0.835, 1),
	"encryption": Color(1.0, 0.4, 0.4, 1),
	"hardware": Color(0.7, 0.4, 1.0, 1),
}

func _ready() -> void:
	deploy_button.pressed.connect(_on_deploy_pressed)
	remove_button.pressed.connect(_on_remove_pressed)
	upgrade_node_button.pressed.connect(_on_upgrade_node_pressed)

	Resources.resources_updated.connect(_update_display)
	Resources.risk_warning.connect(_on_risk_warning)
	Resources.soft_reset_triggered.connect(_on_soft_reset)

	EventSystem.event_started.connect(_on_event_started)
	EventSystem.event_ended.connect(_on_event_ended)
	EventSystem.event_requires_repair.connect(_on_event_requires_repair)

	Upgrades.upgrade_purchased.connect(_on_upgrade_purchased)

	GameState.unlock_achieved.connect(_on_unlock_achieved)
	GameState.node_degraded.connect(_on_node_degraded)

	risk_pulse_timer.timeout.connect(_on_risk_pulse)

	router_tab.pressed.connect(_on_tab_pressed.bind("router"))
	encryption_tab.pressed.connect(_on_tab_pressed.bind("encryption"))
	hardware_tab.pressed.connect(_on_tab_pressed.bind("hardware"))

	tier_label.text = "TIER %d // %s" % [GameState.tier, GameConfig.get_tier_name(GameState.tier).to_upper()]
	_on_tab_pressed("router")

	# Build dynamic UI BEFORE first display update
	_build_debug_panel()
	_build_silent_mode_button()
	_build_doctrine_ui()

	_update_display()

# === SILENT MODE BUTTON (TASK 6) ===

func _build_silent_mode_button() -> void:
	_silent_mode_button = Button.new()
	_silent_mode_button.text = "[ SILENT MODE: OFF ]"
	_silent_mode_button.custom_minimum_size = Vector2(160, 32)
	_silent_mode_button.pressed.connect(_on_silent_mode_pressed)

	var center_vbox: VBoxContainer = $VBoxLayout/ContentHBox/CenterPanel/CenterVBox
	center_vbox.add_child(_silent_mode_button)
	center_vbox.move_child(_silent_mode_button, center_vbox.get_child_count() - 2)

func _on_silent_mode_pressed() -> void:
	GameState.toggle_silent_mode()
	_update_silent_mode_display()

func _update_silent_mode_display() -> void:
	if GameState.silent_mode:
		_silent_mode_button.text = "[ SILENT MODE: ON ]"
		_silent_mode_button.add_theme_color_override("font_color", GameConfig.COLOR_GOLD)
	else:
		_silent_mode_button.text = "[ SILENT MODE: OFF ]"
		_silent_mode_button.remove_theme_color_override("font_color")

# === DOCTRINE UI (TASK 11) ===

func _build_doctrine_ui() -> void:
	_doctrine_container = HBoxContainer.new()
	_doctrine_container.add_theme_constant_override("separation", 4)
	_doctrine_container.alignment = BoxContainer.ALIGNMENT_CENTER

	for doctrine_id: String in GameConfig.DOCTRINES.keys():
		var doctrine: Dictionary = GameConfig.DOCTRINES[doctrine_id]
		var btn := Button.new()
		btn.name = "Doctrine_%s" % doctrine_id
		btn.text = doctrine.get("name", doctrine_id)
		btn.custom_minimum_size = Vector2(110, 28)
		btn.tooltip_text = doctrine.get("description", "")
		btn.pressed.connect(_on_doctrine_pressed.bind(doctrine_id))
		_doctrine_container.add_child(btn)

	var center_vbox: VBoxContainer = $VBoxLayout/ContentHBox/CenterPanel/CenterVBox
	center_vbox.add_child(_doctrine_container)
	center_vbox.move_child(_doctrine_container, center_vbox.get_child_count() - 2)
	_update_doctrine_display()

func _on_doctrine_pressed(doctrine_id: String) -> void:
	GameState.switch_doctrine(doctrine_id)
	_update_doctrine_display()

func _update_doctrine_display() -> void:
	for doctrine_id: String in GameConfig.DOCTRINES.keys():
		var btn: Button = _doctrine_container.get_node_or_null("Doctrine_%s" % doctrine_id)
		if btn:
			if doctrine_id == GameState.active_doctrine:
				btn.add_theme_color_override("font_color", GameConfig.COLOR_CYAN)
			else:
				btn.add_theme_color_override("font_color", GameConfig.COLOR_MUTED)

# === DEBUG PANEL (programmatic) ===

func _build_debug_panel() -> void:
	_debug_panel = PanelContainer.new()
	_debug_panel.visible = false
	_debug_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug_panel.offset_left = -320
	_debug_panel.offset_right = 0
	_debug_panel.offset_top = 8
	_debug_panel.offset_bottom = 0
	_debug_panel.custom_minimum_size = Vector2(310, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.067, 0.086, 0.9)
	style.border_color = Color(0.0, 1.0, 0.835, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	_debug_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	_debug_panel.add_child(vbox)

	var title := Label.new()
	title.text = "// DEBUG STATS (F3)"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", GameConfig.COLOR_CYAN)
	vbox.add_child(title)

	var fields := [
		"avg_inf", "dr_rate", "node_eff", "event_uptime", "game_speed",
		"sep1",
		"global_eff", "maintenance", "dr_band", "dr_momentum",
		"ttc", "degraded_nodes", "silent_mode", "doctrine",
		"sep2",
		"inf_breakdown_title",
		"inf_base_output", "inf_global_penalty", "inf_efficiency",
		"inf_maintenance", "inf_net",
		"sep3",
		"constraint_title",
		"constraint_dr", "constraint_energy", "constraint_thermal",
		"equilibrium",
	]
	for field: String in fields:
		if field.begins_with("sep"):
			var sep := HSeparator.new()
			sep.add_theme_constant_override("separation", 2)
			vbox.add_child(sep)
			continue
		var label := Label.new()
		label.text = field
		label.add_theme_font_size_override("font_size", 10)
		if field == "inf_breakdown_title" or field == "constraint_title":
			label.add_theme_color_override("font_color", GameConfig.COLOR_CYAN)
		else:
			label.add_theme_color_override("font_color", GameConfig.COLOR_MUTED)
		vbox.add_child(label)
		_debug_labels[field] = label

	add_child(_debug_panel)

# === INPUT HANDLING ===

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return

	match event.keycode:
		KEY_F3:
			_debug_visible = not _debug_visible
			_debug_panel.visible = _debug_visible
		KEY_F4:
			_inf_samples.clear()
			_event_uptime_total = 0.0
			_game_time_total = 0.0
			print("[Debug] Stats reset")
		KEY_F5:
			_speed_index = (_speed_index + 1) % SPEED_STEPS.size()
			TickEngine.set_speed(SPEED_STEPS[_speed_index])
		KEY_F7:
			# Stress test (TASK 17)
			if not Resources.is_stress_testing():
				Resources.start_stress_test()
			else:
				print("[Debug] Stress test already running")
		KEY_F8:
			GameState.debug_stress_test()
		KEY_F9:
			EventSystem.force_trigger_all_events()
		KEY_F10:
			EventSystem.clear_all_events()
			print("[Debug] All events cleared")
		KEY_F11:
			GameState.soft_reset(GameState.tier)
		KEY_F12:
			# Balance snapshot (Phase 2 TASK 18)
			GameState.take_balance_snapshot()
			GameState.debug_print_constraints()

# === DEBUG UPDATE ===

func _process(delta: float) -> void:
	# DR bar flash animation (Phase 2 TASK 12)
	if _dr_bar_flash_active:
		_dr_bar_flash_timer += delta * 4.0
		var flash_alpha: float = 0.5 + 0.5 * sin(_dr_bar_flash_timer)
		var flash_style := dr_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if flash_style:
			flash_style.bg_color = Color(1.0, 0.2, 0.2, flash_alpha)
	else:
		_dr_bar_flash_timer = 0.0

	if not _debug_visible:
		return

	_sample_accumulator += delta
	if _sample_accumulator >= 1.0:
		_sample_accumulator -= 1.0
		_inf_samples.append(Resources.get_influence_rate())
		if _inf_samples.size() > 60:
			_inf_samples.pop_front()

	var avg_inf: float = 0.0
	if _inf_samples.size() > 0:
		var total: float = 0.0
		for sample: float in _inf_samples:
			total += sample
		avg_inf = total / float(_inf_samples.size())

	var dr_rate: float = GameState.get_per_second("detection_risk")

	var nc: int = GameState.get_node_count()
	var node_eff: float = avg_inf / maxf(1.0, float(nc))

	_game_time_total += delta
	if EventSystem.get_active_events().size() > 0:
		_event_uptime_total += delta
	var uptime_pct: float = 0.0
	if _game_time_total > 0.0:
		uptime_pct = (_event_uptime_total / _game_time_total) * 100.0

	# Basic stats
	_debug_labels["avg_inf"].text = "Avg Inf/s (60s): %.2f" % avg_inf
	_debug_labels["dr_rate"].text = "DR Rate: %+.3f/s" % dr_rate
	_debug_labels["node_eff"].text = "Node Eff: %.3f inf/s/node" % node_eff
	_debug_labels["event_uptime"].text = "Event Uptime: %.1f%%" % uptime_pct
	_debug_labels["game_speed"].text = "Speed: %.0fx" % TickEngine.get_speed()

	# New systems debug (TASKS 1,3,4,5,6,7,11,16)
	_debug_labels["global_eff"].text = "Global Eff: %.3f" % GameState.calculate_global_efficiency()
	_debug_labels["maintenance"].text = "Maintenance: %.3f inf/s" % GameState.calculate_maintenance_drain()
	_debug_labels["dr_band"].text = "DR Band: %s" % GameState.get_dr_band().to_upper()
	_debug_labels["dr_momentum"].text = "DR Momentum: %+.4f" % GameState.dr_momentum_bonus
	_debug_labels["degraded_nodes"].text = "Degraded: %d/%d nodes" % [GameState.get_degraded_node_count(), nc]
	_debug_labels["silent_mode"].text = "Silent Mode: %s" % ("ON" if GameState.silent_mode else "OFF")
	_debug_labels["doctrine"].text = "Doctrine: %s" % GameState.active_doctrine.to_upper()

	# Time to collapse (TASK 16)
	var ttc: float = Resources.get_time_to_collapse()
	if ttc < 0.0:
		_debug_labels["ttc"].text = "Time to Collapse: SAFE"
		_debug_labels["ttc"].add_theme_color_override("font_color", GameConfig.COLOR_CYAN)
	elif ttc < 30.0:
		_debug_labels["ttc"].text = "Time to Collapse: %.0fs !!" % ttc
		_debug_labels["ttc"].add_theme_color_override("font_color", GameConfig.COLOR_RED)
	else:
		_debug_labels["ttc"].text = "Time to Collapse: %.0fs" % ttc
		_debug_labels["ttc"].add_theme_color_override("font_color", GameConfig.COLOR_ORANGE)

	# Influence flow breakdown (TASK 15)
	var breakdown := GameState.get_influence_breakdown()
	_debug_labels["inf_breakdown_title"].text = "// INFLUENCE FLOW"
	_debug_labels["inf_base_output"].text = "  Base BW: %.2f" % breakdown["base_node_output"]
	_debug_labels["inf_global_penalty"].text = "  Global Eff: x%.3f" % breakdown["global_efficiency_penalty"]
	_debug_labels["inf_efficiency"].text = "  Efficiency: %.4f (base: %.4f)" % [breakdown["total_efficiency"], breakdown["base_efficiency"]]
	_debug_labels["inf_maintenance"].text = "  Maintenance: -%.3f" % breakdown["maintenance_drain"]

	var net_inf: float = breakdown["net_influence"]
	if net_inf >= 0.0:
		_debug_labels["inf_net"].text = "  NET: +%.3f inf/s" % net_inf
		_debug_labels["inf_net"].add_theme_color_override("font_color", GameConfig.COLOR_CYAN)
	else:
		_debug_labels["inf_net"].text = "  NET: %.3f inf/s" % net_inf
		_debug_labels["inf_net"].add_theme_color_override("font_color", GameConfig.COLOR_RED)

	# Constraint display (Phase 2 TASK 13)
	_debug_labels["constraint_title"].text = "// CONSTRAINTS"
	var dr_c: Dictionary = GameState.get_constraint("detection_risk")
	_debug_labels["constraint_dr"].text = "  DR: %.1f/%.0f (%+.3f/s) [%s]" % [
		dr_c.get("value", 0.0), dr_c.get("max_value", 100.0),
		dr_c.get("rate", 0.0),
		"ACTIVE" if dr_c.get("active", false) else "OFF",
	]
	var en_c: Dictionary = GameState.get_constraint("energy")
	_debug_labels["constraint_energy"].text = "  Energy: %.1f (%+.2f/s) [%s]" % [
		en_c.get("value", 0.0), en_c.get("rate", 0.0),
		"ACTIVE" if en_c.get("active", false) else "OFF",
	]
	var th_c: Dictionary = GameState.get_constraint("thermal_load")
	_debug_labels["constraint_thermal"].text = "  Thermal: %.1f/%.0f [%s]" % [
		th_c.get("value", 0.0), th_c.get("max_value", 100.0),
		"STUB" if not th_c.get("active", false) else "ACTIVE",
	]

	# Equilibrium display (Phase 2 TASK 11)
	if GameState.is_in_equilibrium():
		_debug_labels["equilibrium"].text = "Equilibrium: STABLE (%.0fs)" % GameState.get_equilibrium_timer()
		_debug_labels["equilibrium"].add_theme_color_override("font_color", GameConfig.COLOR_CYAN)
	else:
		var eq_timer: float = GameState.get_equilibrium_timer()
		_debug_labels["equilibrium"].text = "Equilibrium: TRACKING (%.0f/%.0fs)" % [eq_timer, GameConfig.EQUILIBRIUM_WINDOW]
		_debug_labels["equilibrium"].add_theme_color_override("font_color", GameConfig.COLOR_MUTED)

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

func _on_node_degraded(index: int) -> void:
	_rebuild_node_grid()

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
	bandwidth_value.text = Resources.get_bandwidth_display()
	influence_value.text = Resources.get_influence_display()
	influence_rate.text = "(+%.2f/s)" % Resources.get_influence_rate()

	# Detection Risk with pressure bar upgrade (Phase 2 TASK 12)
	var dr: float = GameState.get_resource("detection_risk")
	detection_value.text = Resources.get_detection_risk_display()
	detection_rate.text = Resources.get_dr_rate_display()
	dr_bar.value = dr

	# DR bar tooltip with rate breakdown (Phase 2 TASK 12)
	var dr_rate_val: float = GameState.get_per_second("detection_risk")
	var dr_band: String = GameState.get_dr_band()
	dr_bar.tooltip_text = "DR: %.1f%% | Rate: %+.3f/s | Band: %s\nThresholds: 30 / 60 / 80" % [dr, dr_rate_val, dr_band.to_upper()]

	# DR bar flash on approaching overflow (Phase 2 TASK 12)
	if dr >= GameConfig.DR_CRISIS_THRESHOLD and dr_rate_val > 0.0:
		if not _dr_bar_flash_active:
			_dr_bar_flash_active = true
	elif dr < GameConfig.DR_CRISIS_THRESHOLD:
		_dr_bar_flash_active = false

	# DR color coding using DR bands (TASK 5)
	match dr_band:
		"crisis":
			detection_value.add_theme_color_override("font_color", GameConfig.COLOR_RED)
			detection_rate.add_theme_color_override("font_color", GameConfig.COLOR_RED)
		"volatile":
			detection_value.add_theme_color_override("font_color", GameConfig.COLOR_ORANGE)
			detection_rate.add_theme_color_override("font_color", GameConfig.COLOR_ORANGE)
		"normal":
			detection_value.add_theme_color_override("font_color", Color(0.8, 0.8, 0.3, 1))
			detection_rate.add_theme_color_override("font_color", GameConfig.COLOR_MUTED)
		"stealth":
			detection_value.add_theme_color_override("font_color", GameConfig.COLOR_CYAN)
			detection_rate.add_theme_color_override("font_color", GameConfig.COLOR_MUTED)

	# Nodes
	var nc: int = GameState.get_node_count()
	var degraded: int = GameState.get_degraded_node_count()
	node_count_label.text = str(nc)
	node_capacity.text = "/ %d nodes" % GameState.get_max_nodes()
	var subtitle_text: String = "generating %s bandwidth" % Resources.get_bandwidth_display()
	if degraded > 0:
		subtitle_text += " (%d degraded)" % degraded
	node_subtitle.text = subtitle_text

	# Button states
	deploy_button.disabled = not GameState.can_deploy_node()
	remove_button.disabled = nc <= 0
	upgrade_node_button.disabled = not _can_upgrade_any_node()

	var cheapest_cost := _get_cheapest_node_upgrade_cost()
	if cheapest_cost > 0.0:
		upgrade_node_button.text = "[ UPGRADE NODE — %d Inf ]" % int(cheapest_cost)
	else:
		upgrade_node_button.text = "[ UPGRADE NODE ]"

	if nc != _last_node_count:
		_last_node_count = nc
		_rebuild_node_grid()

	_update_objectives()
	_update_silent_mode_display()
	_update_doctrine_display()

# === NODE GRID VISUAL ===

func _rebuild_node_grid() -> void:
	for child in node_grid.get_children():
		child.queue_free()

	for i in range(GameState.nodes.size()):
		var node_data: Dictionary = GameState.nodes[i]
		var level: int = node_data.get("level", 1)
		var degraded: bool = node_data.get("degraded", false)

		var rect := ColorRect.new()
		rect.custom_minimum_size = Vector2(16, 16)
		rect.size = Vector2(16, 16)

		if degraded:
			# Degraded nodes show red (TASK 4)
			rect.color = Color(1.0, 0.3, 0.3, 0.7)
			rect.tooltip_text = "Node %d — Lv.%d [DEGRADED] (Click to repair: %d Inf)" % [i + 1, level, int(GameConfig.DEGRADATION_REPAIR_COST)]
		else:
			var alpha: float = 0.4 + (level - 1) * 0.15
			rect.color = Color(0.0, 1.0, 0.835, clampf(alpha, 0.4, 1.0))
			rect.tooltip_text = "Node %d — Lv.%d" % [i + 1, level]

		# Make degraded nodes clickable for repair
		if degraded:
			rect.gui_input.connect(_on_node_rect_input.bind(i))

		node_grid.add_child(rect)

func _on_node_rect_input(event: InputEvent, node_index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if GameState.repair_node(node_index):
			_rebuild_node_grid()

# === OBJECTIVES ===

func _update_objectives() -> void:
	var cfg := GameConfig.get_tier_config(GameState.tier)
	var objectives: Array = cfg.get("unlock_objectives", [])

	if objectives.size() > 0:
		var progress := GameState.get_objective_progress(objectives[0])
		if progress["met"]:
			objective_influence.text = "[x] %s" % progress["label"]
			objective_influence.add_theme_color_override("font_color", GameConfig.COLOR_CYAN)
		else:
			objective_influence.text = "[ ] %s (%s)" % [progress["label"], progress["progress"]]
			objective_influence.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65, 1))

	if objectives.size() > 1:
		var progress := GameState.get_objective_progress(objectives[1])
		if progress["met"]:
			objective_dr.text = "[x] %s" % progress["label"]
			objective_dr.add_theme_color_override("font_color", GameConfig.COLOR_CYAN)
		else:
			objective_dr.text = "[ ] %s (%s)" % [progress["label"], progress["progress"]]
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
		var escalated: bool = entry.get("escalated", false)

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
		var event_name: String = def.get("name", "Event")
		if escalated:
			event_name += " [ESCALATED]"
		name_label.text = event_name
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

	var dr_band: String = GameState.get_dr_band()
	match dr_band:
		"crisis":
			risk_warning.text = "!! CRITICAL EXPOSURE — DETECTION IMMINENT !!"
		"volatile":
			risk_warning.text = "!! HIGH RISK — Reduce nodes or invest in Encryption !!"
		_:
			risk_warning.text = "! WARNING — Detection Risk Elevated !"

func _on_risk_pulse() -> void:
	var dr: float = GameState.get_resource("detection_risk")
	if dr < GameConfig.DR_STEALTH_THRESHOLD:
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
	_dr_bar_flash_active = false
	_dr_bar_flash_timer = 0.0
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
