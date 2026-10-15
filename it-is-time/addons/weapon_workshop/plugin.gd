@tool
extends EditorPlugin

const PANEL = preload("res://addons/weapon_workshop/workshop_panel.gd")
const GRIP_INSPECTOR = preload("res://addons/weapon_workshop/grip_inspector.gd")
const GRIP_EDIT = preload("res://addons/weapon_workshop/grip_edit.gd")
var panel: Control
var grip_inspector: EditorInspectorPlugin

func _enter_tree() -> void:
	panel = PANEL.new()
	panel.custom_minimum_size = Vector2(0,400)
	panel.editor_plugin = self
	add_control_to_bottom_panel(panel,"武器工坊")
	grip_inspector = GRIP_INSPECTOR.new()
	grip_inspector.plugin = self
	add_inspector_plugin(grip_inspector)

func _exit_tree() -> void:
	if grip_inspector != null:
		remove_inspector_plugin(grip_inspector)
		grip_inspector = null
	if not is_instance_valid(panel): return
	remove_control_from_bottom_panel(panel)
	panel.queue_free()

func refresh_files() -> void:
	get_editor_interface().get_resource_filesystem().scan()

func edit_weapon_grips(weapon: Node3D, operation: StringName, value: int = -1, arm_path: NodePath = NodePath()) -> String:
	if not is_instance_valid(weapon) or not weapon.is_inside_tree(): return "物品已不在当前场景中。"
	var transaction := GRIP_EDIT.prepare(weapon,operation,value,arm_path)
	if transaction.has("error"): return transaction.error
	var history := get_undo_redo()
	history.create_action("调整物品持握点 " + str(weapon.name),UndoRedo.MERGE_DISABLE,weapon)
	history.add_do_method(self,&"_apply_weapon_grips",weapon,transaction.after)
	history.add_undo_method(self,&"_apply_weapon_grips",weapon,transaction.before)
	history.commit_action()
	if int(weapon.get("grip_point_count")) == 0: return "已恢复使用原 Attachment 参数，请保存场景。"
	return "持握数据已更新，请保存场景。主持握点：%d / %d" % [int(weapon.get("active_grip_point"))+1,int(weapon.get("grip_point_count"))]

func _apply_weapon_grips(weapon: Node3D, state: Dictionary) -> void:
	if not is_instance_valid(weapon): return
	GRIP_EDIT.apply(weapon,state,get_editor_interface().get_edited_scene_root())
	weapon.call_deferred("notify_property_list_changed")
	EditorInterface.mark_scene_as_unsaved()
