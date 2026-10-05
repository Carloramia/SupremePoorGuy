class_name CharacterDamageController3D
extends Node

const TORSO_TAG: int = 0
const HEAD_TAG: int = 3

@export var team_id: int = 0
@export var damage_logging_enabled: bool = false

var _parts: Array[PhysicalBodyPart3D] = []
var _character_disabled: bool = false

func _ready() -> void:
	add_to_group(&"damage_components")
	_discover_parts()
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	if console != null and console.has_method("is_damage_tracking_enabled"):
		set_damage_logging_enabled(bool(console.call("is_damage_tracking_enabled")))

func _discover_parts() -> void:
	_parts.clear()
	for node: Node in get_parent().find_children("*", "PhysicalBodyPart3D", true, false):
		var part := node as PhysicalBodyPart3D
		if part == null:
			continue
		_parts.append(part)
		part.broken.connect(_on_part_broken.bind(part))

func _on_part_broken(source: Node, part: PhysicalBodyPart3D) -> void:
	call_deferred("_handle_part_broken", part, source)

func _handle_part_broken(part: PhysicalBodyPart3D, source: Node) -> void:
	if not is_instance_valid(part):
		return
	var inventory := get_parent().get_node_or_null("InventoryController3D")
	if inventory != null and inventory.has_method("handle_part_broken"):
		inventory.call("handle_part_broken", part)
	# Capture connections before the joints are queued for removal.
	var connected_parts := _get_connected_parts(part)
	var removed_joints := _remove_connected_joints(part)
	if TORSO_TAG in part.tags:
		for other_part: PhysicalBodyPart3D in connected_parts:
			if not other_part.is_broken and TORSO_TAG not in other_part.tags:
				other_part.break_part(source)
	if not _character_disabled and _all_heads_broken():
		_disable_character_controllers()
		for other_part: PhysicalBodyPart3D in _parts:
			if is_instance_valid(other_part) and not other_part.is_broken:
				other_part.break_part(source)
	if damage_logging_enabled:
		print(
			("[character_damage] character=%s broken_part=%s removed_joints=%s "
			+ "all_heads_broken=%s")
			% [get_parent().name, part.name, removed_joints, _character_disabled]
		)

func _remove_connected_joints(part: PhysicalBodyPart3D) -> Array[StringName]:
	var removed: Array[StringName] = []
	for node: Node in get_parent().find_children("*", "Joint3D", true, false):
		var joint := node as Joint3D
		if joint == null or joint.is_queued_for_deletion():
			continue
		var body_a := joint.get_node_or_null(joint.node_a)
		var body_b := joint.get_node_or_null(joint.node_b)
		if body_a != part and body_b != part:
			continue
		removed.append(joint.name)
		joint.queue_free()
	return removed

func _get_connected_parts(part: PhysicalBodyPart3D) -> Array[PhysicalBodyPart3D]:
	var connected: Array[PhysicalBodyPart3D] = []
	for node: Node in get_parent().find_children("*", "Joint3D", true, false):
		var joint := node as Joint3D
		if joint == null or joint.is_queued_for_deletion() or joint.has_meta(&"planar_depth_guide"):
			continue
		var body_a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
		var body_b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
		var other: PhysicalBodyPart3D
		if body_a == part:
			other = body_b
		elif body_b == part:
			other = body_a
		if other != null and other not in connected:
			connected.append(other)
	return connected

## A character without Head parts does not trigger the whole-body cascade.
func _all_heads_broken() -> bool:
	var found_head := false
	for part: PhysicalBodyPart3D in _parts:
		if not is_instance_valid(part) or HEAD_TAG not in part.tags:
			continue
		found_head = true
		if not part.is_broken:
			return false
	return found_head

func _disable_character_controllers() -> void:
	if _character_disabled:
		return
	_character_disabled = true
	for child: Node in get_parent().find_children("*", "", true, false):
		if child is PhysicalBodyPart3D or child is Joint3D or child == self:
			continue
		if child.has_method("set_character_control_enabled"):
			child.call("set_character_control_enabled", false)
		elif child.name.to_lower().contains("controller") or child.name.to_lower().contains("state_machine"):
			child.set_process(false)
			child.set_physics_process(false)
			child.set_process_input(false)
			child.set_process_unhandled_input(false)

func is_character_disabled() -> bool:
	return _character_disabled

func get_parts() -> Array[PhysicalBodyPart3D]:
	return _parts.duplicate()

func set_damage_logging_enabled(enabled: bool) -> void:
	damage_logging_enabled = enabled
	for part: PhysicalBodyPart3D in _parts:
		if is_instance_valid(part):
			part.set_damage_logging_enabled(enabled)

