@tool
class_name CreatureModuleAttachment
extends Resource
## One installation. Stable IDs distinguish multiple instances of the same template.
@export var enabled := true
@export var instance_id: StringName = &"module_1"
@export var module_scene: PackedScene:
	set(value):
		if module_scene != value: captured_scene = null
		module_scene = value
@export var host_part_key := "Torso"
## Relative to the host PhysicalPart; empty uses its origin.
@export var host_socket: NodePath
## Position is in base creature units; rotation is relative to the socket.
@export var mount_offset := Transform3D.IDENTITY
@export_range(0.01, 10.0, 0.01, "or_greater") var size_multiplier := 1.0
@export_storage var captured_scene: PackedScene
@export_tool_button("重新使用原始模组模板", "Reload") var reset_capture_button: Callable:
	get: return Callable(self,&"reset_capture")

func _init() -> void: resource_local_to_scene = true

func reset_capture() -> void:
	captured_scene = null
	emit_changed()

func get_template() -> PackedScene:
	return captured_scene if captured_scene != null else module_scene
