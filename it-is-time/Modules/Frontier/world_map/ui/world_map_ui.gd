class_name WorldMapUI
extends CanvasLayer

signal save_requested
signal load_requested
signal focus_requested
signal hex_debug_changed(enabled: bool)
signal nav_debug_changed(enabled: bool)
var status: Label
var feedback: Label
var tooltip: PanelContainer
var tooltip_text: Label
var modal: Control
var interaction_host: CenterContainer
var save_button: Button
var load_button: Button

func _ready() -> void:
	layer = 20
	var theme := Theme.new()
	theme.default_font_size = 16
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("142530")
	panel_style.border_color = Color("526e70")
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	theme.set_stylebox("panel", "PanelContainer", panel_style)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme
	add_child(root)
	var header := PanelContainer.new()
	header.position = Vector2(22, 20)
	header.custom_minimum_size = Vector2(350, 112)
	root.add_child(header)
	var header_box := VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 8)
	var padding := _padding(header, 16)
	padding.add_child(header_box)
	var title := Label.new()
	title.text = "THE FRONTIER / WORLD MAP"
	title.add_theme_color_override("font_color", Color("e4c68d"))
	title.add_theme_font_size_override("font_size", 22)
	header_box.add_child(title)
	status = Label.new()
	header_box.add_child(status)
	var help := Label.new()
	help.text = "LMB  Travel    RMB  Pan    Wheel  Zoom"
	help.add_theme_font_size_override("font_size", 13)
	help.add_theme_color_override("font_color", Color("9db8b8"))
	header_box.add_child(help)
	var toolbar := PanelContainer.new()
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	toolbar.position = Vector2(-250, 20)
	toolbar.custom_minimum_size = Vector2(228, 170)
	root.add_child(toolbar)
	var tools := VBoxContainer.new()
	_padding(toolbar, 12).add_child(tools)
	var row := HBoxContainer.new()
	tools.add_child(row)
	save_button = _button(row, "Save", func() -> void: save_requested.emit())
	load_button = _button(row, "Load", func() -> void: load_requested.emit())
	_button(tools, "Focus on traveler", func() -> void: focus_requested.emit())
	var hex_toggle := CheckButton.new()
	hex_toggle.text = "Hex debug"
	hex_toggle.toggled.connect(func(value: bool) -> void: hex_debug_changed.emit(value))
	tools.add_child(hex_toggle)
	var nav_toggle := CheckButton.new()
	nav_toggle.text = "Location / nav debug"
	nav_toggle.toggled.connect(func(value: bool) -> void: nav_debug_changed.emit(value))
	tools.add_child(nav_toggle)
	feedback = Label.new()
	feedback.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	feedback.position = Vector2(24, -54)
	feedback.add_theme_color_override("font_color", Color("edca81"))
	root.add_child(feedback)
	tooltip = PanelContainer.new()
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tooltip)
	tooltip_text = Label.new()
	tooltip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_padding(tooltip, 12).add_child(tooltip_text)
	tooltip.hide()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.06, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(shade)
	interaction_host = CenterContainer.new()
	interaction_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(interaction_host)
	modal.hide()

func show_tooltip(location: WorldMapLocation, point: Vector2) -> void:
	if location == null or modal.visible:
		tooltip.hide()
		return
	tooltip_text.text = "%s  ·  %s\n%s\n%s" % [location.definition.display_name, location.definition.type_id, location.definition.short_description, LocationRuntimeState.Lifecycle.keys()[location.state.lifecycle]]
	tooltip.reset_size()
	tooltip.position = (point + Vector2(18, 20)).clamp(Vector2(8, 8), get_viewport().get_visible_rect().size - tooltip.size - Vector2(8, 8))
	tooltip.show()

func open_interaction(panel: Control) -> void:
	tooltip.hide()
	modal.show()
	interaction_host.add_child(panel)
	save_button.disabled = true
	load_button.disabled = true

func close_interaction() -> void:
	for child in interaction_host.get_children():
		interaction_host.remove_child(child)
		child.queue_free()
	modal.hide()
	save_button.disabled = false
	load_button.disabled = false

func notify(message: String) -> void:
	feedback.text = message

func _padding(parent: Control, amount: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, amount)
	parent.add_child(margin)
	return margin

func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 34
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	parent.add_child(button)
	return button
