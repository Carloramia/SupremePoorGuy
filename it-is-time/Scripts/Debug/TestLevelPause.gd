extends CanvasLayer
const L10N = preload("res://Scripts/Localization/GameText.gd")
## Standalone test scenes do not have GameRoot's battle pause handler.
var _paused_by_space := false
var _hint: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hint = Label.new()
	_hint.name = "PauseHint"
	L10N.bind(_hint,&"text","console.3b6e827f7aea")
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_font_size_override("font_size",26)
	_hint.add_theme_color_override("font_color",Color.WHITE)
	_hint.add_theme_color_override("font_outline_color",Color("29231d"))
	_hint.add_theme_constant_override("outline_size",8)
	add_child(_hint)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hint.offset_top = 18
	_hint.offset_bottom = 60
	_hint.hide()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(&"Space"): return
	if get_tree().get_first_node_in_group(&"application_host")!=null: return
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	if console!=null and console.is_console_open(): return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	for interface: Node in get_tree().get_nodes_in_group(&"ui_interface_2d"):
		if interface is CanvasLayer and interface.visible and not interface.is_queued_for_deletion(): return
	# Do not release a pause owned by another interface or system.
	if get_tree().paused and not _paused_by_space: return
	_paused_by_space = not _paused_by_space
	get_tree().paused = _paused_by_space
	_hint.visible = _paused_by_space
	get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if _paused_by_space: get_tree().paused = false
