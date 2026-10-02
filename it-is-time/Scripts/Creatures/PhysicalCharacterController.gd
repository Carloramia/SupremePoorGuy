extends Node3D

@export_group("Collision")
## Adds pairwise collision exceptions between every physical BodyPart in this character.
## Collision with terrain, other characters, and external physics bodies is unchanged.
@export var body_parts_ignore_each_other: bool = true

func _ready() -> void:
	_configure_body_part_collision_exceptions()

func _configure_body_part_collision_exceptions() -> void:
	if not body_parts_ignore_each_other:
		return
	var body_parts := _get_physical_body_parts()
	for first_index: int in range(body_parts.size()):
		for second_index: int in range(first_index + 1, body_parts.size()):
			var first_part := body_parts[first_index]
			var second_part := body_parts[second_index]
			first_part.add_collision_exception_with(second_part)
			second_part.add_collision_exception_with(first_part)

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
