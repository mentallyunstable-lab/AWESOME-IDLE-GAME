extends MarginContainer

# === UI References (unique names) ===
@onready var bandwidth_value: Label = %BandwidthValue
@onready var influence_value: Label = %InfluenceValue
@onready var influence_rate: Label = %InfluenceRate
@onready var detection_value: Label = %DetectionValue
@onready var encryption_value: Label = %EncryptionValue
@onready var node_count: Label = %NodeCount
@onready var node_subtitle: Label = %NodeSubtitle
@onready var buy_node_button: Button = %BuyNodeButton
@onready var risk_warning: Label = %RiskWarning
@onready var dr_event_label: Label = %DrEventLabel
@onready var status_label: Label = %StatusLabel
@onready var risk_pulse_timer: Timer = %RiskPulseTimer

# Tab buttons
@onready var infra_tab: Button = %InfraTab
@onready var security_tab: Button = %SecurityTab
@onready var intel_tab: Button = %IntelTab

# View toggle
@onready var dashboard_view_btn: Button = %DashboardViewBtn
@onready var map_view_btn: Button = %MapViewBtn
@onready var dashboard_view: VBoxContainer = %DashboardView
@onready var map_view: Control = %MapView

# Upgrade panel (instanced scene)
@onready var upgrade_panel = $VBoxLayout/ContentHBox/RightPanel/RightVBox/TabContent/UpgradePanel

# === Tab Colors ===
const TAB_COLORS := {
	"infra": Color(0.0, 1.0, 0.835, 1),
	"security": Color(1.0, 0.4, 0.4, 1),
	"intel": Color(0.7, 0.4, 1.0, 1),
}

# === State ===
var risk_pulse_on: bool = false
var risk_is_critical: bool = false
var active_tab: String = "infra"
var current_view: String = "dashboard"

func _ready() -> void:
	buy_node_button.pressed.connect(_on_buy_node_pressed)
	Resources.resources_updated.connect(_update_display)
	Resources.risk_warning.connect(_on_risk_warning)
	Resources.dr_event_triggered.connect(_on_dr_event)
	Resources.dr_event_cleared.connect(_on_dr_event_cleared)
	Upgrades.upgrade_purchased.connect(_on_upgrade_purchased)
	risk_pulse_timer.timeout.connect(_on_risk_pulse)

	# Tab buttons
	infra_tab.pressed.connect(_on_tab_pressed.bind("infra"))
	security_tab.pressed.connect(_on_tab_pressed.bind("security"))
	intel_tab.pressed.connect(_on_tab_pressed.bind("intel"))

	# View toggle
	dashboard_view_btn.pressed.connect(_switch_view.bind("dashboard"))
	map_view_btn.pressed.connect(_switch_view.bind("map"))

	# Default state
	_on_tab_pressed("infra")
	_switch_view("dashboard")
	_update_display()

func _on_buy_node_pressed() -> void:
	Resources.add_node()

# === View Switching ===

func _switch_view(view_name: String) -> void:
	current_view = view_name
	dashboard_view.visible = (view_name == "dashboard")
	map_view.visible = (view_name == "map")

	# Highlight active view button
	if view_name == "dashboard":
		dashboard_view_btn.add_theme_color_override("font_color", Color(0.0, 1.0, 0.835, 1))
		map_view_btn.add_theme_color_override("font_color", Color(0.45, 0.5, 0.55, 1))
	else:
		dashboard_view_btn.add_theme_color_override("font_color", Color(0.45, 0.5, 0.55, 1))
		map_view_btn.add_theme_color_override("font_color", Color(0.0, 1.0, 0.835, 1))

# === Tab Switching ===

func _on_tab_pressed(category: String) -> void:
	active_tab = category
	upgrade_panel.show_category(category)
	_update_tab_visuals()

func _update_tab_visuals() -> void:
	var tabs := {"infra": infra_tab, "security": security_tab, "intel": intel_tab}
	for cat: String in tabs.keys():
		var btn: Button = tabs[cat]
		var color: Color = TAB_COLORS.get(cat, Color.WHITE)
		if cat == active_tab:
			btn.add_theme_color_override("font_color", color)
			btn.add_theme_color_override("font_hover_color", color)
		else:
			btn.add_theme_color_override("font_color", Color(0.45, 0.5, 0.55, 1))
			btn.add_theme_color_override("font_hover_color", Color(0.6, 0.65, 0.7, 1))

# === Live Display ===

func _update_display() -> void:
	bandwidth_value.text = Resources.get_bandwidth_display()
	influence_value.text = Resources.get_influence_display()
	influence_rate.text = "(+%.1f/s)" % Resources.get_influence_rate()
	detection_value.text = Resources.get_detection_risk_display()
	encryption_value.text = Resources.get_encryption_display()
	node_count.text = str(Resources.node_count)
	node_subtitle.text = "generating %s bandwidth" % Resources.get_bandwidth_display()

	# Update detection risk color based on level
	if Resources.detection_risk >= 75.0:
		detection_value.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1))
	elif Resources.detection_risk >= 50.0:
		detection_value.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2, 1))
	else:
		detection_value.add_theme_color_override("font_color", Color(0.0, 1.0, 0.835, 1))

# === Upgrade Purchase Feedback ===

func _on_upgrade_purchased(_upgrade_id: String) -> void:
	_pulse_stat("bandwidth")
	_pulse_stat("influence")

func _pulse_stat(stat_name: String) -> void:
	var label: Label
	match stat_name:
		"bandwidth":
			label = bandwidth_value
		"influence":
			label = influence_value
		_:
			return

	var original_color: Color = Color(0.0, 1.0, 0.835, 1)
	var flash_color: Color = Color(1.0, 1.0, 1.0, 1)

	var tween := create_tween()
	tween.tween_property(label, "theme_override_colors/font_color", flash_color, 0.08)
	tween.tween_property(label, "theme_override_colors/font_color", original_color, 0.35)

# === Risk Warning System ===

func _on_risk_warning(level: float) -> void:
	if not risk_is_critical:
		risk_is_critical = true
		risk_pulse_timer.start()

	if level >= 75.0:
		risk_warning.text = "!! CRITICAL EXPOSURE — DETECTION IMMINENT !!"
	else:
		risk_warning.text = "! WARNING — Detection Risk Elevated !"

func _on_risk_pulse() -> void:
	if not risk_is_critical:
		risk_pulse_timer.stop()
		risk_warning.text = ""
		return

	risk_pulse_on = not risk_pulse_on
	if risk_pulse_on:
		risk_warning.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1))
	else:
		risk_warning.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 0.3))

	# Check if risk dropped below threshold
	if Resources.detection_risk < Resources.dr_warning_threshold:
		risk_is_critical = false
		risk_pulse_timer.stop()
		risk_warning.text = ""

# === DR Events ===

func _on_dr_event(event_type: String) -> void:
	match event_type:
		"slowdown":
			dr_event_label.text = "// NODE SLOWDOWN — BW reduced 10% for 5s"
			dr_event_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2, 1))
			_pulse_stat("bandwidth")
		"alert":
			dr_event_label.text = "!! SCAN DETECTED — Reduce exposure immediately !!"
			dr_event_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1))

func _on_dr_event_cleared(event_type: String) -> void:
	match event_type:
		"slowdown":
			dr_event_label.text = ""
			# Clear alert flag too if DR dropped
			if Resources.detection_risk <= 80.0:
				Resources.clear_dr_alert()
		"alert":
			if not Resources.bw_penalty_active:
				dr_event_label.text = ""
