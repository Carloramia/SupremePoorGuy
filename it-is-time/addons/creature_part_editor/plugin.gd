@tool
extends EditorPlugin

const INSPECTOR = preload("res://addons/creature_part_editor/inspector.gd")
const EDIT = preload("res://addons/creature_part_editor/part_edit.gd")
var inspector: EditorInspectorPlugin

func _enter_tree() -> void:
	inspector = INSPECTOR.new()
	inspector.plugin = self
	add_inspector_plugin(inspector)

func _exit_tree() -> void:
	remove_inspector_plugin(inspector)
	inspector = null

func apply_part(body: PhysicalBodyPart3D, scene: PackedScene, multiplier: float) -> String:
	var transaction := EDIT.prepare(body, scene, multiplier)
	if transaction.has("error"): return transaction.error
	var actor: Node = transaction.actor
	var history := get_undo_redo()
	history.create_action("修改生成部件 " + str(body.name), UndoRedo.MERGE_DISABLE, actor)
	history.add_do_method(actor, &"restore_generated_part_edit", transaction.after)
	history.add_undo_method(actor, &"restore_generated_part_edit", transaction.before)
	history.add_do_reference(transaction.after.part)
	history.add_undo_reference(transaction.before.part)
	history.commit_action()
	return ""
