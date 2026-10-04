extends Node3D

@export_group("Collision")
## Adds pairwise collision exceptions between every physical BodyPart in this character.
## Collision with terrain, other characters, and external physics bodies is unchanged.
@export var body_parts_ignore_each_other: bool = true

var _collision_refresh_pending: bool = false

func _ready() -> void:
	add_to_group(&"physical_characters_3d")
	_configure_body_part_collision_exceptions()

func _configure_body_part_collision_exceptions() -> void:
	if not body_parts_ignore_each_other:
		return
	# Joint teardown can clear an engine collision exception for its two bodies,
	# even if that pair was also excluded by the character. Restore after teardown.
	for node: Node in find_children("*", "Joint3D", true, false):
		if not node.tree_exited.is_connected(_on_internal_joint_removed):
			node.tree_exited.connect(_on_internal_joint_removed)
	var body_parts := _get_physical_body_parts()
	for first_index: int in range(body_parts.size()):
		for second_index: int in range(first_index + 1, body_parts.size()):
			var first_part := body_parts[first_index]
			var second_part := body_parts[second_index]
			first_part.add_collision_exception_with(second_part)
			second_part.add_collision_exception_with(first_part)

func _on_internal_joint_removed() -> void:
	if is_inside_tree() and not is_queued_for_deletion() and not _collision_refresh_pending:
		_collision_refresh_pending = true
		call_deferred("_restore_internal_collision_exceptions")

func _restore_internal_collision_exceptions() -> void:
	_collision_refresh_pending = false
	if is_inside_tree() and not is_queued_for_deletion():
		_configure_body_part_collision_exceptions()

func _get_physical_body_parts() -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	for node: Node in find_children("*", "RigidBody3D", true, false):
		var body := node as RigidBody3D
		if _has_tags_property(body):
			result.append(body)
	return result

func _has_tags_property(body: RigidBody3D) -> bool:
	for property: Dictionary in body.get_property_list():
		if property.name == &"tags":
			return true
	return false

## Read actual engine exceptions instead of reporting only the Inspector switch.
func get_internal_collision_diagnostics() -> Dictionary:
	var parts := _get_physical_body_parts()
	var exceptions: Dictionary = {}
	for part: RigidBody3D in parts:
		exceptions[part] = part.get_collision_exceptions()
	var missing: Array[String] = []
	var missing_count := 0
	for i: int in range(parts.size()):
		for j: int in range(i + 1, parts.size()):
			if parts[j] not in exceptions[parts[i]] or parts[i] not in exceptions[parts[j]]:
				missing_count += 1
				if missing.size() < 12: missing.append("%s <-> %s" % [parts[i].name, parts[j].name])
	return {"enabled": body_parts_ignore_each_other, "parts": parts.size(), "pairs": parts.size() * (parts.size() - 1) / 2, "missing_pairs": missing_count, "missing_examples": missing}
