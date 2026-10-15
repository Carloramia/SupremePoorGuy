@tool
extends EditorInspectorPlugin

const EDIT = preload("res://addons/creature_part_editor/part_edit.gd")
const PANEL = preload("res://addons/creature_part_editor/panel.gd")
var plugin: EditorPlugin

func _can_handle(object: Object) -> bool:
	return object is PhysicalBodyPart3D and not EDIT.context(object).is_empty()

func _parse_begin(object: Object) -> void:
	var panel := PANEL.new()
	panel.setup(object, plugin)
	add_custom_control(panel)
