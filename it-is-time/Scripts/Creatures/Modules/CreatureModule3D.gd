@tool
class_name CreatureModule3D
extends Node3D
## Template root is never a character or a rigid body. Parts and Joints may be empty.
const JOINT_SETTINGS = preload("res://Scripts/Creatures/Modules/ModuleJointSettings.gd")
@export var root_part_path: NodePath
@export var mount_joint: JOINT_SETTINGS = JOINT_SETTINGS.new()
## Relative to the host character. Missing dependencies reject generation, not silently add abilities.
@export var required_components: Array[NodePath] = []
@export var disable_on_host_broken := true
@export_storage var captured_mount_joint_settings: Dictionary = {}
var _host_part: PhysicalBodyPart3D
var _host_character: Node3D
var _character_enabled := true
var _authored_visible := true

func _ready() -> void:
	if Engine.is_editor_hint(): return
	_authored_visible = visible
	_bind_host.call_deferred()

func _bind_host() -> void:
	_host_part = get_parent() as PhysicalBodyPart3D
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor.has_method("get_body_parts_revision"):
			_host_character = ancestor as Node3D
			break
		ancestor = ancestor.get_parent()
	if _host_part == null or _host_character == null:
		# Standalone templates are previews, not headless living characters.
		process_mode = Node.PROCESS_MODE_DISABLED
		for body: Node in find_children("*","RigidBody3D",true,false): body.freeze = true
		return
	if not _host_part.broken.is_connected(_on_host_broken): _host_part.broken.connect(_on_host_broken)
	for node: Node in find_children("*","",true,false):
		if node.has_method("on_module_mounted"): node.call("on_module_mounted",_host_character,_host_part)
	set_character_control_enabled(_character_enabled)

func get_host_character() -> Node3D: return _host_character if is_instance_valid(_host_character) else null
func get_host_part() -> PhysicalBodyPart3D: return _host_part if is_instance_valid(_host_part) else null

func get_module_part(local_name: StringName) -> PhysicalBodyPart3D:
	if not is_instance_valid(_host_character): return null
	var container := _host_character.get_node_or_null("GeneratedParts")
	if container == null: return null
	for body: Node in container.get_children():
		if body is PhysicalBodyPart3D and body.get_meta(&"generated_module_id","")==get_meta(&"generated_module_id","") and body.get_meta(&"module_part_name","")==str(local_name): return body
	return null

func _on_host_broken(_source: Node) -> void:
	set_character_control_enabled(_character_enabled)

func set_character_control_enabled(value: bool) -> void:
	_character_enabled = value
	var active := value and (not disable_on_host_broken or (is_instance_valid(_host_part) and not _host_part.is_broken))
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	visible = _authored_visible and active
	if not Engine.is_editor_hint():
		for node: Node in find_children("*","",true,false):
			if node.has_method("on_module_enabled_changed"): node.call("on_module_enabled_changed",active)
