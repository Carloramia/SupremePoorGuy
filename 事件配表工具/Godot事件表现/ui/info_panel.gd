extends CanvasLayer
## Non-mutating explanation layer. Hover hint and modal glossary share one renderer.
const UI := preload("res://ui/layout_theme.gd")
var _root: Control
var _dim: ColorRect
var _panel: PanelContainer
var _heading: Label
var _entries: VBoxContainer
var _close: Button
var _mode := "closed"
var _owner := 0
var _previous_focus: WeakRef

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UI.create()
	add_child(_root)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_dim)
	_panel = UI.panel(UI.PANEL, 20)
	_root.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	_panel.add_child(column)
	_heading = UI.label("", 26)
	_heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_heading)
	column.add_child(HSeparator.new())
	_entries = VBoxContainer.new()
	_entries.add_theme_constant_override("separation", 8)
	column.add_child(_entries)
	_close = UI.button("关闭说明", true)
	column.add_child(_close)
	_close.pressed.connect(close)
	_root.hide()

func bind_hint(control: Control, title: String, entries: Array) -> void:
	control.mouse_entered.connect(func():
		if _mode != "modal":
			show_hint(control.get_global_rect(), title, entries, control.get_instance_id()))
	control.mouse_exited.connect(func():
		if _mode == "hint" and _owner == control.get_instance_id():
			close())
	control.tree_exiting.connect(func():
		if _mode == "hint" and _owner == control.get_instance_id():
			close())

func is_modal_open() -> bool:
	return _mode == "modal"

func open_details(title: String, entries: Array) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focused) if focused else null
	_mode = "modal"
	_fill(title, entries)
	_dim.show()
	_close.show()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.show()
	_place.call_deferred(Vector2(700, 0), Vector2.ZERO, true)
	_close.grab_focus()

func show_hint(anchor: Rect2, title: String, entries: Array, owner := 0) -> void:
	if is_modal_open():
		return
	_mode = "hint"
	_owner = owner
	_fill(title, entries)
	_dim.hide()
	_close.hide()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.show()
	_place.call_deferred(Vector2(400, 0), anchor.end + Vector2(8, 6), false)

func close() -> void:
	var was_modal := is_modal_open()
	_mode = "closed"
	_root.hide()
	if was_modal and _previous_focus:
		var previous = _previous_focus.get_ref()
		if is_instance_valid(previous) and previous.is_visible_in_tree():
			previous.grab_focus()
	_previous_focus = null

func _fill(title: String, entries: Array) -> void:
	_heading.text = title
	for child in _entries.get_children():
		_entries.remove_child(child)
		child.queue_free()
	for entry in entries:
		var well := UI.panel(UI.WELL, 10)
		var column := VBoxContainer.new()
		well.add_child(column)
		column.add_child(UI.label(str(entry.get("title", "")), 19))
		column.add_child(UI.label(str(entry.get("text", "")), 17, UI.MUTED))
		_entries.add_child(well)

func _place(minimum: Vector2, at: Vector2, centered: bool) -> void:
	if _mode == "closed":
		return
	_panel.custom_minimum_size = minimum
	_panel.size.x = minimum.x
	await get_tree().process_frame
	await get_tree().process_frame
	_panel.reset_size()
	await get_tree().process_frame
	var viewport_size := get_viewport().get_visible_rect().size
	var target := (viewport_size - _panel.size) / 2 if centered else at
	_panel.position = Vector2(clampf(target.x, 12, maxf(12, viewport_size.x - _panel.size.x - 12)), clampf(target.y, 12, maxf(12, viewport_size.y - _panel.size.y - 12)))

func _unhandled_key_input(event: InputEvent) -> void:
	if is_modal_open() and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
