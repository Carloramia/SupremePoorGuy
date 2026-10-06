extends SceneTree

var last_plan: Dictionary = {}

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character: Node3D = load("res://Scenes/Creatures/Characters/Generate_Beast.tscn").instantiate()
	character.generate_on_ready = false
	root.add_child(character)
	var generator := character.get_node("CreatureGenerator")
	generator.rear_leg_count = maxi((4) - 2, 0)
	generator.foreleg_count = mini((4), 2)
	generator.unsymmetrie = 0.0
	generator.neck_number = 1


	generator.framework_generated.connect(func(plan: Dictionary) -> void: last_plan = plan)
	var reference: Dictionary = {}
	for multiplier: float in [1.0, 2.0, 0.5, 1.0]:
		generator.overall_scale = multiplier
		generator._random.seed = 42
		assert(character.generate_creature())
		assert(last_plan.overall_scale == multiplier)
		assert(generator.scale.is_equal_approx(Vector3.ONE))
		var blueprint: Dictionary = character._build_blueprint(last_plan, generator.torso_connection_distance)
		if reference.is_empty(): reference = blueprint.duplicate(true)
		assert(blueprint.parts.size() == reference.parts.size())
		assert(blueprint.connections.size() == reference.connections.size())
		var container := character.get_node("GeneratedParts")
		for index: int in range(blueprint.parts.size()):
			var layout: Dictionary = blueprint.parts[index]
			var original: Dictionary = reference.parts[index]
			assert(layout.size.is_equal_approx(original.size * multiplier))
			assert(layout.transform.origin.is_equal_approx(original.transform.origin * multiplier))
			assert(layout.transform.basis.is_equal_approx(original.transform.basis))
			var body := container.get_node(NodePath(layout.name)) as RigidBody3D
			assert(body.scale.is_equal_approx(Vector3.ONE))
			assert(body.get_node("CollisionShape3D").shape.size.is_equal_approx(layout.size))
			assert(is_equal_approx(body.mass, clampf(layout.size.x * layout.size.y * layout.size.z * character.mass_density, character.minimum_part_mass, character.maximum_part_mass)))
		for index: int in range(blueprint.connections.size()):
			assert(blueprint.connections[index].anchor.is_equal_approx(reference.connections[index].anchor * multiplier))
		var joints := container.get_node("Joints")
		for index: int in range(blueprint.connections.size()):
			var connection: Dictionary = blueprint.connections[index]
			if connection.kind == "Segment":
				assert(joints.has_node("SegmentSpring_%03d" % [index + 1]))
				continue
			var joint := joints.get_node("Joint_%03d_%s" % [index + 1, connection.kind]) as Node3D
			assert(joint.position.is_equal_approx(connection.anchor))
			assert(joint.scale.is_equal_approx(Vector3.ONE))
		# The preview and physical box must coincide after scaling, including the Head.
		for preview_name: String in ["SubTorso", "Torso", "Torso_2", "NeckLine/Head"]:
			var preview: MeshInstance3D = generator.get_node(preview_name if preview_name.contains("/") else preview_name + "/Wireframe")
			var body_name := "Head_1" if preview_name.contains("/") else preview_name
			var collision: CollisionShape3D = container.get_node(body_name + "/CollisionShape3D")
			var preview_bounds := preview.mesh.get_aabb()
			var physical_bounds := AABB(-collision.shape.size * 0.5, collision.shape.size)
			for corner: int in range(8):
				assert((preview.global_transform * preview_bounds.get_endpoint(corner)).is_equal_approx(collision.global_transform * physical_bounds.get_endpoint(corner)))
		var frame_scale: Vector3 = generator.get_node("Feets").scale
		assert(frame_scale.is_equal_approx(Vector3.ONE * multiplier), "Regeneration must not accumulate scale")
		for foot: Node3D in generator.get_node("Feets").get_children():
			if foot.has_meta(&"limb_points"):
				var wireframe := foot.get_node("Wireframe") as MeshInstance3D
				assert(is_zero_approx((wireframe.global_transform * wireframe.mesh.get_aabb().position).y))
	generator.overall_scale = 0.0
	assert(not character.generate_creature(), "Invalid scale must preserve the existing character")
	assert(character.get_node("GeneratedParts").get_child_count() > 0)
	character.queue_free()
	await process_frame
	print("CREATURE_OVERALL_SCALE_VALIDATION_PASSED")
	quit()
