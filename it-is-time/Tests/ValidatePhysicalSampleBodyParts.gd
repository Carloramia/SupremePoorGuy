extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var part: RigidBody3D = load("res://Scenes/Creatures/Bodyparts/_PhysicalSampleBodyParts.tscn").instantiate()
	part.freeze = true
	part.sprite_visible = true
	part.left_distance = 1.0
	part.right_distance = 3.0
	part.top_distance = 4.0
	part.bottom_distance = 2.0
	part.collision_thickness = 0.5
	part.tags.append(part.BodyPartTag.Torso)
	part.tags.append(part.BodyPartTag.Arm)
	var swing_binding := ArmSwingBinding.new()
	swing_binding.control_group_name = &"PrimaryArm"
	swing_binding.swing_preset = load("res://Resources/Combat/PrimaryArmSwing.tres")
	part.arm_swing_bindings.append(swing_binding)
	root.add_child(part)
	await process_frame
	var sprite := part.get_node("Sprite3D") as Sprite3D
	var collision := part.get_node("CollisionShape3D") as CollisionShape3D
	var shape := collision.shape as BoxShape3D
	assert(part.get_outline_edge_distances().is_equal_approx(Vector4(1.0, 3.0, 4.0, 2.0)))
	assert(part.tags.size() == 2)
	assert(part.tags[0] == part.BodyPartTag.Torso)
	assert(part.tags[1] == part.BodyPartTag.Arm)
	assert(part.arm_swing_bindings.size() == 1)
	assert(part.arm_swing_bindings[0].swing_preset is LimbSwingPresetBase)
	assert(shape.size.is_equal_approx(Vector3(4.0, 6.0, 0.5)))
	assert(collision.position.is_equal_approx(Vector3(1.0, 1.0, 0.0)))
	assert(sprite.material_override is ShaderMaterial)
	var material := sprite.material_override as ShaderMaterial
	assert(material.get_shader_parameter(&"edge_distances").is_equal_approx(Vector4(1.0, 3.0, 4.0, 2.0)))
	var mesh_node := part.get_node("MeshInstance3D") as Node3D
	assert(not part.has_node("Cube2"))
	assert(sprite.visible and mesh_node.visible)
	_assert_mesh_node_matches_collision(part, collision)
	part.sprite_visible = false
	assert(not sprite.visible and mesh_node.visible)
	part.mesh_visible = false
	assert(not sprite.visible and not mesh_node.visible)
	part.sprite_visible = true
	assert(sprite.visible and not mesh_node.visible)
	part.mesh_visible = true
	for axis: int in [Vector3.AXIS_X, Vector3.AXIS_Y, Vector3.AXIS_Z]:
		sprite.axis = axis
		part.collision_thickness = 0.75
		await process_frame
		await process_frame
		_assert_mesh_node_matches_collision(part, collision)
	var replacement := BoxMesh.new()
	replacement.size = Vector3(2.0, 3.0, 4.0)
	(mesh_node as MeshInstance3D).mesh = replacement
	await process_frame
	await process_frame
	_assert_mesh_node_matches_collision(part, collision)
	var second: PhysicalBodyPart3D = load("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Arm.tscn").instantiate()
	second.freeze = true
	second.left_distance = 0.5
	second.right_distance = 0.5
	second.top_distance = 0.5
	second.bottom_distance = 0.5
	second.mesh_visible = false
	root.add_child(second)
	await process_frame
	_assert_mesh_node_matches_collision(second, second.get_node("CollisionShape3D"))
	_assert_mesh_node_matches_collision(part, collision)
	assert(mesh_node.visible and not second.get_node("MeshInstance3D").visible)
	second.queue_free()
	print("PHYSICAL_SAMPLE_BODY_PARTS_VALIDATION_PASSED")
	part.queue_free()
	quit()

func _assert_mesh_node_matches_collision(part: Node3D, collision: CollisionShape3D) -> void:
	var mesh_node := part.get_node("MeshInstance3D") as Node3D
	var meshes := mesh_node.find_children("*", "MeshInstance3D", true, false)
	if mesh_node is MeshInstance3D:
		meshes.append(mesh_node)
	var found_mesh := false
	var actual: AABB
	for node: Node in meshes:
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var bounds: AABB = (part.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		actual = actual.merge(bounds) if found_mesh else bounds
		found_mesh = true
	assert(found_mesh, "MeshInstance3D must contain a mesh")
	var box := collision.shape as BoxShape3D
	var expected: AABB = collision.transform * AABB(-box.size * 0.5, box.size)
	assert(actual.size.is_equal_approx(expected.size), "Mesh dimensions must match collision")
	assert(actual.get_center().is_equal_approx(expected.get_center()), "Mesh center must match collision")
