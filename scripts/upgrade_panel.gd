extends VBoxContainer
## upgrade_panel.gd — Dynamic upgrade list UI.
## Reads upgrade definitions from GameConfig, state from Upgrades facade.

const CATEGORY_COLORS := {
	"router": Color(0.0, 1.0, 0.835, 1),
	"encryption": Color(1.0, 0.4, 0.4, 1),
	"hardware": Color(0.7, 0.4, 1.0, 1),
}

@onready var upgrade_list: VBoxContainer = %UpgradeList

var current_category: String = "router"
var _upgrade_rows: Dictionary = {}
var _locked_ids: Array[String] = []

func _ready() -> void:
	Upgrades.upgrade_purchased.connect(_on_upgrade_purchased)
	Resources.resources_updated.connect(_refresh_button_states)

func show_category(category: String) -> void:
	current_category = category
	_rebuild_list()

func _rebuild_list() -> void:
	for child in upgrade_list.get_children():
		child.queue_free()
	_upgrade_rows.clear()
	_locked_ids.clear()

	var upgrades := Upgrades.get_upgrades_for_category(current_category)
	var accent: Color = CATEGORY_COLORS.get(current_category, Color.WHITE)

	for def: Dictionary in upgrades:
		var uid: String = def["id"]
		if Upgrades.is_locked(uid):
			var row := _create_locked_row(def)
			upgrade_list.add_child(row)
			_upgrade_rows[uid] = row
			_locked_ids.append(uid)
		else:
			var row := _create_upgrade_row(def, accent)
			upgrade_list.add_child(row)
			_upgrade_rows[uid] = row

func _create_upgrade_row(def: Dictionary, accent: Color) -> PanelContainer:
	var uid: String = def["id"]
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.r, accent.g, accent.b, 0.05)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	# Name column
	var name_vbox := VBoxContainer.new()
	name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_vbox.size_flags_stretch_ratio = 2.0
	hbox.add_child(name_vbox)

	var label_name := Label.new()
	label_name.text = def.get("name", "")
	label_name.add_theme_font_size_override("font_size", 15)
	label_name.add_theme_color_override("font_color", accent)
	name_vbox.add_child(label_name)

	var label_desc := Label.new()
	var desc: String = def.get("description", "")
	label_desc.text = desc.split("\n")[0] if desc != "" else ""
	label_desc.add_theme_font_size_override("font_size", 11)
	label_desc.add_theme_color_override("font_color", GameConfig.COLOR_MUTED)
	name_vbox.add_child(label_desc)

	# Level column
	var label_level := Label.new()
	label_level.name = "LevelLabel"
	label_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_level.add_theme_font_size_override("font_size", 14)
	label_level.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1))
	_update_level_text(label_level, uid)
	hbox.add_child(label_level)

	# Cost column
	var label_cost := Label.new()
	label_cost.name = "CostLabel"
	label_cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_cost.add_theme_font_size_override("font_size", 13)
	label_cost.add_theme_color_override("font_color", GameConfig.COLOR_MUTED)
	_update_cost_text(label_cost, uid)
	hbox.add_child(label_cost)

	# Buy button
	var btn := Button.new()
	btn.name = "BuyButton"
	btn.custom_minimum_size = Vector2(70, 32)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_update_button_state(btn, uid)
	btn.pressed.connect(_on_buy_pressed.bind(uid))
	btn.tooltip_text = Upgrades.get_tooltip(uid)
	hbox.add_child(btn)

	return panel

func _create_locked_row(def: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.15, 0.4)
	style.border_color = Color(0.2, 0.22, 0.25, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	var name_vbox := VBoxContainer.new()
	name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_vbox)

	var label_name := Label.new()
	label_name.text = def.get("name", "") + " [LOCKED]"
	label_name.add_theme_font_size_override("font_size", 14)
	label_name.add_theme_color_override("font_color", Color(0.35, 0.38, 0.42, 0.6))
	name_vbox.add_child(label_name)

	var req_label := Label.new()
	req_label.text = "Requires %d Influence" % int(def.get("unlock_influence", 0.0))
	req_label.add_theme_font_size_override("font_size", 11)
	req_label.add_theme_color_override("font_color", Color(0.3, 0.33, 0.37, 0.5))
	name_vbox.add_child(req_label)

	return panel

func _update_level_text(label: Label, uid: String) -> void:
	var def := Upgrades.get_upgrade_def(uid)
	var level: int = Upgrades.get_upgrade_level(uid)
	var max_level: int = def.get("max_level", 5)
	if level >= max_level:
		label.text = "MAX"
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1))
	else:
		label.text = "Lv. %d/%d" % [level, max_level]

func _update_cost_text(label: Label, uid: String) -> void:
	if Upgrades.is_maxed(uid):
		label.text = "\u2014"
	else:
		label.text = "%d Inf" % int(Upgrades.get_cost(uid))

func _update_button_state(btn: Button, uid: String) -> void:
	if Upgrades.is_maxed(uid):
		btn.text = "MAXED"
		btn.disabled = true
	elif Upgrades.can_afford(uid):
		btn.text = "BUY"
		btn.disabled = false
	else:
		btn.text = "BUY"
		btn.disabled = true

func _on_buy_pressed(upgrade_id: String) -> void:
	if Upgrades.try_purchase(upgrade_id):
		_flash_row(upgrade_id)

func _on_upgrade_purchased(_upgrade_id: String) -> void:
	_rebuild_list()

func _refresh_button_states() -> void:
	# Check if any locked upgrades should now be unlocked
	if _locked_ids.size() > 0:
		for lid: String in _locked_ids:
			if not Upgrades.is_locked(lid):
				_rebuild_list()
				return

	for uid: String in _upgrade_rows.keys():
		if _locked_ids.has(uid):
			continue
		var row: PanelContainer = _upgrade_rows[uid]
		var hbox: HBoxContainer = row.get_child(0)

		var level_label: Label = hbox.get_node_or_null("LevelLabel")
		if level_label:
			_update_level_text(level_label, uid)

		var cost_label: Label = hbox.get_node_or_null("CostLabel")
		if cost_label:
			_update_cost_text(cost_label, uid)

		var btn: Button = hbox.get_node_or_null("BuyButton")
		if btn:
			_update_button_state(btn, uid)
			btn.tooltip_text = Upgrades.get_tooltip(uid)

func _flash_row(upgrade_id: String) -> void:
	if not _upgrade_rows.has(upgrade_id):
		return
	var row: PanelContainer = _upgrade_rows[upgrade_id]
	var accent: Color = CATEGORY_COLORS.get(current_category, Color.WHITE)

	var tween := create_tween()
	var style: StyleBoxFlat = row.get_theme_stylebox("panel").duplicate()
	row.add_theme_stylebox_override("panel", style)
	tween.tween_property(style, "bg_color", Color(accent.r, accent.g, accent.b, 0.3), 0.1)
	tween.tween_property(style, "bg_color", Color(accent.r, accent.g, accent.b, 0.05), 0.4)
