extends Control

# Region button references keyed by region_id
var region_buttons: Dictionary = {}
# Node icon containers per region
var node_containers: Dictionary = {}
# DR flash tweens
var _dr_tweens: Dictionary = {}

@onready var map_bg: ColorRect = $MapBackground
@onready var region_container: Control = $RegionContainer
@onready var node_icon_container: Control = $NodeIconContainer
@onready var tooltip_label: Label = $TooltipLabel
@onready var region_info_panel: PanelContainer = $RegionInfoPanel
@onready var info_name: Label = $RegionInfoPanel/InfoVBox/InfoName
@onready var info_stats: Label = $RegionInfoPanel/InfoVBox/InfoStats
@onready var deploy_button: Button = $RegionInfoPanel/InfoVBox/DeployButton

const LOCKED_COLOR := Color(0.25, 0.28, 0.32, 1)
const UNLOCKED_COLOR := Color(0.0, 1.0, 0.835, 0.8)
const SELECTED_COLOR := Color(0.0, 1.0, 0.835, 1.0)
const DR_SLOWDOWN_COLOR := Color(1.0, 0.6, 0.2, 1.0)
const DR_ALERT_COLOR := Color(1.0, 0.2, 0.2, 1.0)
const NODE_ICON_SIZE := Vector2(8, 8)

func _ready() -> void:
	tooltip_label.text = ""
	region_info_panel.visible = false

	MapController.region_unlocked.connect(_on_region_unlocked)
	MapController.node_deployed.connect(_on_node_deployed)
	MapController.region_dr_event.connect(_on_region_dr_event)
	MapController.region_dr_cleared.connect(_on_region_dr_cleared)
	MapController.selected_region_changed.connect(_on_selected_region_changed)

	_build_region_buttons()

func _build_region_buttons() -> void:
	for id: String in MapController.regions.keys():
		var r: Region = MapController.regions[id]

		# Region button
		var btn := Button.new()
		btn.name = "Region_" + id
		btn.custom_minimum_size = Vector2(120, 40)
		btn.position = r.position - Vector2(60, 20)
		btn.text = r.name
		btn.tooltip_text = r.get_tooltip()
		btn.mouse_entered.connect(_on_region_hover.bind(id))
		btn.mouse_exited.connect(_on_region_hover_exit)
		btn.pressed.connect(_on_region_clicked.bind(id))
		region_container.add_child(btn)
		region_buttons[id] = btn

		# Node icon sub-container for this region
		var icon_holder := Control.new()
		icon_holder.name = "Icons_" + id
		icon_holder.position = r.position - Vector2(40, 30)
		node_icon_container.add_child(icon_holder)
		node_containers[id] = icon_holder

		_update_button_visual(id)

func _update_button_visual(region_id: String) -> void:
	var r: Region = MapController.regions[region_id]
	var btn: Button = region_buttons[region_id]

	if not r.unlocked:
		btn.disabled = true
		btn.modulate = LOCKED_COLOR
	elif region_id == MapController.selected_region_id:
		btn.disabled = false
		btn.modulate = SELECTED_COLOR
	else:
		btn.disabled = false
		btn.modulate = UNLOCKED_COLOR

	btn.tooltip_text = r.get_tooltip()

func _update_all_buttons() -> void:
	for id: String in region_buttons.keys():
		_update_button_visual(id)

# === Region Interaction ===

func _on_region_hover(region_id: String) -> void:
	var r: Region = MapController.regions[region_id]
	tooltip_label.text = r.get_tooltip()

func _on_region_hover_exit() -> void:
	tooltip_label.text = ""

func _on_region_clicked(region_id: String) -> void:
	var r: Region = MapController.regions[region_id]
	if not r.unlocked:
		return
	MapController.select_region(region_id)

# === Selection & Info Panel ===

func _on_selected_region_changed(region_id: String) -> void:
	_update_all_buttons()
	_show_region_info(region_id)

func _show_region_info(region_id: String) -> void:
	var r: Region = MapController.get_region(region_id)
	if r == null:
		region_info_panel.visible = false
		return

	region_info_panel.visible = true
	info_name.text = r.name

	var lines := PackedStringArray()
	lines.append("Nodes: %d / %d" % [r.node_count, r.max_nodes])
	if r.bw_multiplier != 0.0:
		lines.append("BW Bonus: %+.0f%% per node" % (r.bw_multiplier * 100))
	if r.influence_multiplier != 0.0:
		lines.append("Influence Bonus: %+.0f%% per node" % (r.influence_multiplier * 100))
	if r.dr_multiplier != 0.0:
		var prefix := "DR Penalty" if r.dr_multiplier > 0 else "DR Reduction"
		lines.append("%s: %+.0f%% per node" % [prefix, r.dr_multiplier * 100])
	info_stats.text = "\n".join(lines)

	deploy_button.disabled = r.is_full()
	deploy_button.text = "FULL" if r.is_full() else "[ DEPLOY HERE ]"

	# Reconnect deploy button
	if deploy_button.pressed.is_connected(_on_deploy_pressed):
		deploy_button.pressed.disconnect(_on_deploy_pressed)
	deploy_button.pressed.connect(_on_deploy_pressed.bind(region_id))

func _on_deploy_pressed(region_id: String) -> void:
	MapController.deploy_node_to_region(region_id)

# === Node Deployed Visual ===

func _on_node_deployed(region_id: String, _total: int) -> void:
	_add_node_icon(region_id)
	_show_region_info(region_id)
	_update_button_visual(region_id)

func _add_node_icon(region_id: String) -> void:
	var holder: Control = node_containers[region_id]
	var icon := ColorRect.new()
	icon.color = Color(0.0, 1.0, 0.835, 0.8)
	icon.custom_minimum_size = NODE_ICON_SIZE
	icon.size = NODE_ICON_SIZE

	# Grid layout: 8 per row
	var count: int = holder.get_child_count()
	var col: int = count % 8
	var row: int = count / 8
	icon.position = Vector2(col * 12, row * 12)

	holder.add_child(icon)

# === Region Unlock Visual ===

func _on_region_unlocked(region_id: String) -> void:
	_update_button_visual(region_id)

	# Flash the button
	var btn: Button = region_buttons[region_id]
	var tween := create_tween()
	tween.tween_property(btn, "modulate", Color.WHITE, 0.1)
	tween.tween_property(btn, "modulate", UNLOCKED_COLOR, 0.4)

# === DR Events on Map ===

func _on_region_dr_event(region_id: String, event_type: String) -> void:
	if not region_buttons.has(region_id):
		return
	var btn: Button = region_buttons[region_id]
	var flash_color: Color

	match event_type:
		"slowdown":
			flash_color = DR_SLOWDOWN_COLOR
		"alert":
			flash_color = DR_ALERT_COLOR
		_:
			return

	# Pulsing tween
	if _dr_tweens.has(region_id) and _dr_tweens[region_id] != null:
		_dr_tweens[region_id].kill()

	var tween := create_tween().set_loops(0)
	tween.tween_property(btn, "modulate", flash_color, 0.3)
	tween.tween_property(btn, "modulate", Color(flash_color.r, flash_color.g, flash_color.b, 0.4), 0.3)
	_dr_tweens[region_id] = tween

func _on_region_dr_cleared(region_id: String) -> void:
	if _dr_tweens.has(region_id) and _dr_tweens[region_id] != null:
		_dr_tweens[region_id].kill()
		_dr_tweens.erase(region_id)

	if region_buttons.has(region_id):
		var btn: Button = region_buttons[region_id]
		var tween := create_tween()
		tween.tween_property(btn, "modulate", UNLOCKED_COLOR, 0.3)
