extends PanelContainer

signal node_type_selected(type_id: String)
signal popup_closed

@onready var title_label: Label = $VBox/TitleLabel
@onready var type_list: VBoxContainer = $VBox/ScrollContainer/TypeList
@onready var close_button: Button = $VBox/CloseButton

var _context: String = ""  # "dashboard" or region_id

func _ready() -> void:
	close_button.pressed.connect(_on_close)
	visible = false

func open(context: String) -> void:
	_context = context
	visible = true
	if context == "dashboard":
		title_label.text = "SELECT NODE TYPE"
	else:
		var r: Region = MapController.get_region(context)
		title_label.text = "DEPLOY TO: %s" % (r.name if r else context)
	_rebuild_list()

func _on_close() -> void:
	visible = false
	popup_closed.emit()

func _rebuild_list() -> void:
	for child in type_list.get_children():
		child.queue_free()

	var unlocked := NodeTypes.get_unlocked_types()
	for nt: NodeType in unlocked:
		var row := _create_type_row(nt)
		type_list.add_child(row)

	# Show locked types greyed out
	for nt: NodeType in NodeTypes.all_types.values():
		if not nt.is_unlocked(Resources.influence):
			var row := _create_locked_row(nt)
			type_list.add_child(row)

func _create_type_row(nt: NodeType) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(nt.color.r, nt.color.g, nt.color.b, 0.08)
	style.border_color = Color(nt.color.r, nt.color.g, nt.color.b, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	# Color indicator
	var indicator := ColorRect.new()
	indicator.color = nt.color
	indicator.custom_minimum_size = Vector2(6, 0)
	hbox.add_child(indicator)

	# Info column
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = nt.name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", nt.color)
	info_vbox.add_child(name_label)

	var stats_label := Label.new()
	var stats_text := "BW: %.2f  |  DR: %.2f" % [nt.base_bw, nt.base_dr]
	if nt.influence_per_sec > 0.0:
		stats_text += "  |  Inf: +%.3f/s" % nt.influence_per_sec
	stats_label.text = stats_text
	stats_label.add_theme_font_size_override("font_size", 11)
	stats_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6, 1))
	info_vbox.add_child(stats_label)

	# Cost + Deploy button
	var right_vbox := VBoxContainer.new()
	right_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(right_vbox)

	var cost_label := Label.new()
	if nt.cost > 0.0:
		cost_label.text = "%d Inf" % int(nt.cost)
	else:
		cost_label.text = "Free"
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 11)
	cost_label.add_theme_color_override("font_color", Color(0.45, 0.5, 0.55, 1))
	right_vbox.add_child(cost_label)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(80, 28)
	var can_afford := Resources.influence >= nt.cost
	btn.text = "DEPLOY" if can_afford else "DEPLOY"
	btn.disabled = not can_afford
	btn.tooltip_text = nt.get_tooltip()
	btn.pressed.connect(_on_type_selected.bind(nt.id))
	right_vbox.add_child(btn)

	return panel

func _create_locked_row(nt: NodeType) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.15, 0.4)
	style.border_color = Color(0.2, 0.22, 0.25, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = nt.name + " [LOCKED]"
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(0.35, 0.38, 0.42, 0.6))
	info_vbox.add_child(name_label)

	var req_label := Label.new()
	req_label.text = "Requires %d Influence" % int(nt.unlock_influence)
	req_label.add_theme_font_size_override("font_size", 11)
	req_label.add_theme_color_override("font_color", Color(0.3, 0.33, 0.37, 0.5))
	info_vbox.add_child(req_label)

	return panel

func _on_type_selected(type_id: String) -> void:
	node_type_selected.emit(type_id)
	visible = false
