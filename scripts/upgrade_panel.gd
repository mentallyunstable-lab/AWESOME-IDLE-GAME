extends VBoxContainer

const CATEGORY_COLORS := {
	"infra": Color(0.0, 1.0, 0.835, 1),
	"security": Color(1.0, 0.4, 0.4, 1),
	"intel": Color(0.7, 0.4, 1.0, 1),
}

@onready var upgrade_list: VBoxContainer = %UpgradeList

var current_category: String = "infra"
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

	var dict := Upgrades.get_upgrades_for_category(current_category)
	var accent: Color = CATEGORY_COLORS.get(current_category, Color.WHITE)

	for upgrade_id: String in dict.keys():
		var u: Upgrade = dict[upgrade_id]
		if u.is_locked(Resources.influence):
			var row := _create_locked_upgrade_row(u)
			upgrade_list.add_child(row)
			_upgrade_rows[u.id] = row
			_locked_ids.append(u.id)
		else:
			var row := _create_upgrade_row(u, accent)
			upgrade_list.add_child(row)
			_upgrade_rows[u.id] = row

func _create_upgrade_row(u: Upgrade, accent: Color) -> PanelContainer:
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
	label_name.text = u.name
	label_name.add_theme_font_size_override("font_size", 15)
	label_name.add_theme_color_override("font_color", accent)
	name_vbox.add_child(label_name)

	var label_desc := Label.new()
	label_desc.text = u.description.split("\n")[0]
	label_desc.add_theme_font_size_override("font_size", 11)
	label_desc.add_theme_color_override("font_color", Color(0.45, 0.5, 0.55, 1))
	name_vbox.add_child(label_desc)

	# Level column
	var label_level := Label.new()
	label_level.name = "LevelLabel"
	label_level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_level.add_theme_font_size_override("font_size", 14)
	label_level.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1))
	_update_level_text(label_level, u)
	hbox.add_child(label_level)

	# Cost column
	var label_cost := Label.new()
	label_cost.name = "CostLabel"
	label_cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_cost.add_theme_font_size_override("font_size", 13)
	label_cost.add_theme_color_override("font_color", Color(0.45, 0.5, 0.55, 1))
	_update_cost_text(label_cost, u)
	hbox.add_child(label_cost)

	# Buy button
	var btn := Button.new()
	btn.name = "BuyButton"
	btn.custom_minimum_size = Vector2(70, 32)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_update_button_state(btn, u)
	btn.pressed.connect(_on_buy_pressed.bind(u.id))
	btn.tooltip_text = u.get_tooltip()
	hbox.add_child(btn)

	return panel

func _create_locked_upgrade_row(u: Upgrade) -> PanelContainer:
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
	label_name.text = u.name + " [LOCKED]"
	label_name.add_theme_font_size_override("font_size", 14)
	label_name.add_theme_color_override("font_color", Color(0.35, 0.38, 0.42, 0.6))
	name_vbox.add_child(label_name)

	var req_label := Label.new()
	req_label.text = "Requires %d Influence" % int(u.unlock_influence)
	req_label.add_theme_font_size_override("font_size", 11)
	req_label.add_theme_color_override("font_color", Color(0.3, 0.33, 0.37, 0.5))
	name_vbox.add_child(req_label)

	return panel

func _update_level_text(label: Label, u: Upgrade) -> void:
	if u.is_maxed():
		label.text = "MAX"
		label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1))
	else:
		label.text = "Lv. %d/%d" % [u.level, u.max_level]

func _update_cost_text(label: Label, u: Upgrade) -> void:
	if u.is_maxed():
		label.text = "—"
	else:
		label.text = "%d Inf" % int(u.get_cost())

func _update_button_state(btn: Button, u: Upgrade) -> void:
	if u.is_maxed():
		btn.text = "MAXED"
		btn.disabled = true
	elif u.can_afford(Resources.influence):
		btn.text = "BUY"
		btn.disabled = false
	else:
		btn.text = "BUY"
		btn.disabled = true

func _on_buy_pressed(upgrade_id: String) -> void:
	if Upgrades.try_purchase(upgrade_id):
		_flash_row(upgrade_id)

func _on_upgrade_purchased(_upgrade_id: String) -> void:
	# Rebuild entirely to handle newly unlocked upgrades
	_rebuild_list()

func _refresh_button_states() -> void:
	# Check if any locked upgrades should now be unlocked
	if _locked_ids.size() > 0:
		var dict := Upgrades.get_upgrades_for_category(current_category)
		for lid: String in _locked_ids:
			if dict.has(lid):
				var u: Upgrade = dict[lid]
				if not u.is_locked(Resources.influence):
					_rebuild_list()
					return

	var dict := Upgrades.get_upgrades_for_category(current_category)
	for upgrade_id: String in _upgrade_rows.keys():
		if _locked_ids.has(upgrade_id):
			continue
		if not dict.has(upgrade_id):
			continue
		var u: Upgrade = dict[upgrade_id]
		var row: PanelContainer = _upgrade_rows[upgrade_id]
		var hbox: HBoxContainer = row.get_child(0)

		var btn: Button = hbox.get_node_or_null("BuyButton")
		if btn:
			_update_button_state(btn, u)
			btn.tooltip_text = u.get_tooltip()

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
