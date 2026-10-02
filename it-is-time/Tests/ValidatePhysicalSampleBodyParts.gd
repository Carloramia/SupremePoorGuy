extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var part: RigidBody3D = load("res://Scenes/Creatures/Bodyparts/_PhysicalSampleBodyParts.tscn").instantiate()
	part.left_distance = 1.0
	part.right_distance = 3.0
	part.top_distance = 4.0
	part.bottom_distance = 2.0
	part.collision_thickness = 0.5
	part.tags.append(part.BodyPartTag.Torso)
	part.tags.append(part.BodyPartTag.Arm)
	root.add_child(part)
	await process_frame
	var sprite := part.get_node("Sprite3D") as Sprite3D
	var collision := part.get_node("CollisionShape3D") as CollisionShape3D
	var shape := collision.shape as BoxShape3D
	assert(part.get_outline_edge_distances().is_equal_approx(Vector4(1.0, 3.0, 4.0, 2.0)))
	assert(part.tags.size() == 2)
	assert(part.tags[0] == part.BodyPartTag.Torso)
	assert(part.tags[1] == part.BodyPartTag.Arm)
	assert(shape.size.is_equal_approx(Vector3(4.0, 6.0, 0.5)))
	assert(collision.position.is_equal_approx(Vector3(1.0, 1.0, 0.0)))
	assert(sprite.material_override is ShaderMaterial)
	var material := sprite.material_override as ShaderMaterial
	assert(material.get_shader_parameter(&"edge_distances").is_equal_approx(Vector4(1.0, 3.0, 4.0, 2.0)))
	print("PHYSICAL_SAMPLE_BODY_PARTS_VALIDATION_PASSED")
	part.queue_free()
	quit()
