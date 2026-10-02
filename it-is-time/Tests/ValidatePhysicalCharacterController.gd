extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character: Node3D = load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate()
	root.add_child(character)
	await physics_frame
	var torso := character.get_node("Torso") as RigidBody3D
	var leg_r := character.get_node("Leg_R") as RigidBody3D
	var leg_l := character.get_node("Leg_L") as RigidBody3D
	assert(leg_r in leg_l.get_collision_exceptions())
	assert(leg_l in leg_r.get_collision_exceptions())
	assert(torso in leg_l.get_collision_exceptions())
	assert(torso in leg_r.get_collision_exceptions())
	assert(leg_l in torso.get_collision_exceptions())
	assert(leg_r in torso.get_collision_exceptions())
	assert(character.body_parts_ignore_each_other)
	print("PHYSICAL_CHARACTER_CONTROLLER_VALIDATION_PASSED")
	character.queue_free()
	quit()
