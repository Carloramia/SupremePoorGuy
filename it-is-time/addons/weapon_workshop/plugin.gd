@tool
extends EditorPlugin

const PANEL = preload("res://addons/weapon_workshop/workshop_panel.gd")
var panel: Control

func _enter_tree() -> void:
	panel = PANEL.new()
	panel.custom_minimum_size = Vector2(0,400)
	panel.editor_plugin = self
	add_control_to_bottom_panel(panel,"武器工坊")

func _exit_tree() -> void:
	if not is_instance_valid(panel): return
	remove_control_from_bottom_panel(panel)
	panel.queue_free()

func refresh_files() -> void:
	get_editor_interface().get_resource_filesystem().scan()
