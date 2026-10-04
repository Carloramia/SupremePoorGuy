extends SceneTree

var last_plan: Dictionary = {}

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character: Node3D = load("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn").instantiate()
	character.generate_on_ready = false
	root.add_child(character)
	var generator := character.get_node("CreatureGenerator")
	generator.feets = 4
	generator.unsymmetrie = 0.0
	generator.neck_number = 0
	generator.torso_core_extra_blocks = 0
	generator.max_limb_end_height_difference = 0.3
	generator.limb_minimum_size = Vector3(0.21, 0.52, 0.83)
	generator.limb_maximum_size = generator.limb_minimum_size
	generator.overall_scale = 2.0
	generator._random.seed = 42
	generator.framework_generated.connect(func(plan: Dictionary) -> void: last_plan = plan)
	assert(character.generate_creature())
	var counts := {"Leg": 0, "ForeLeg": 0}
	var container := character.get_node("GeneratedParts")
	for layout: Dictionary in last_plan.layouts:
		counts[layout.role] += 1
		var name := "%s_%d" % [layout.role, counts[layout.role]]
		assert(layout.limb_block_sizes.size() == layout.limb_points.size() - 1)
		for index: int in range(layout.limb_block_sizes.size()):
			assert(layout.limb_block_sizes[index].is_equal_approx(generator.limb_minimum_size))
			var preview: MeshInstance3D = generator.get_node("Feets/%s/Limb/Segment_%d" % [name, index + 1])
			var collision: CollisionShape3D = container.get_node("%s_Limb_%d/CollisionShape3D" % [name, index + 1])
			assert(collision.shape.size.is_equal_approx(generator.limb_minimum_size * 2.0))
			var bounds := preview.mesh.get_aabb()
			var collider_bounds := AABB(-collision.shape.size * 0.5, collision.shape.size)
			for corner: int in range(8):
				assert((preview.global_transform * bounds.get_endpoint(corner)).is_equal_approx(collision.global_transform * collider_bounds.get_endpoint(corner)))
	# Random intervals are independent on all axes, with paired samples at zero asymmetry.
	generator.limb_minimum_size = Vector3(0.2, 0.45, 0.7)
	generator.limb_maximum_size = Vector3(0.35, 0.65, 0.95)
	generator._random.seed = 42
	assert(character.generate_creature())
	for index: int in range(last_plan.layouts.size()):
		var layout: Dictionary = last_plan.layouts[index]
		for size: Vector3 in layout.limb_block_sizes:
			for axis: int in range(3):
				assert(size[axis] >= generator.limb_minimum_size[axis] and size[axis] <= generator.limb_maximum_size[axis])
		if index % 2 == 1 and last_plan.layouts[index - 1].role == layout.role:
			assert(layout.limb_block_sizes == last_plan.layouts[index - 1].limb_block_sizes)
	# Matching overrides only Y, with preview/collider endpoints coinciding with the line.
	generator.limb_y_matches_segment = true
	generator._random.seed = 42
	assert(character.generate_creature())
	counts = {"Leg": 0, "ForeLeg": 0}
	container = character.get_node("GeneratedParts")
	for layout: Dictionary in last_plan.layouts:
		counts[layout.role] += 1
		var name := "%s_%d" % [layout.role, counts[layout.role]]
		var foot: Node3D = generator.get_node("Feets/" + name)
		var points: PackedVector3Array = layout.limb_points
		for index: int in range(layout.limb_block_sizes.size()):
			var size: Vector3 = layout.limb_block_sizes[index]
			assert(is_equal_approx(size.y, points[index].distance_to(points[index + 1])))
			assert(size.x >= generator.limb_minimum_size.x and size.x <= generator.limb_maximum_size.x)
			assert(size.z >= generator.limb_minimum_size.z and size.z <= generator.limb_maximum_size.z)
			var preview: MeshInstance3D = foot.get_node("Limb/Segment_%d" % [index + 1])
			var collision: CollisionShape3D = container.get_node("%s_Limb_%d/CollisionShape3D" % [name, index + 1])
			assert(collision.shape.size.is_equal_approx(size * generator.overall_scale))
			assert((preview.global_transform * Vector3(0, -size.y * 0.5, 0)).is_equal_approx(foot.global_transform * points[index]))
			assert((preview.global_transform * Vector3(0, size.y * 0.5, 0)).is_equal_approx(foot.global_transform * points[index + 1]))
			assert((collision.global_transform * Vector3(0, -collision.shape.size.y * 0.5, 0)).is_equal_approx(foot.global_transform * points[index]))
	# Even when paired sizes are blended, matching uses each limb's own segment.
	var synthetic: Array[Dictionary] = [
		{"role": "ForeLeg", "limb_points": PackedVector3Array([Vector3.ZERO, Vector3.UP, Vector3.UP * 3])},
		{"role": "ForeLeg", "limb_points": PackedVector3Array([Vector3.ZERO, Vector3.UP * 4, Vector3.UP * 9])}]
	generator.unsymmetrie = 50.0
	generator._assign_limb_block_sizes(synthetic)
	assert(synthetic[1].limb_block_sizes[0].y == 4.0 and synthetic[1].limb_block_sizes[1].y == 5.0)
	generator.limb_y_matches_segment = false
	generator._assign_limb_block_sizes(synthetic)
	for layout: Dictionary in synthetic:
		for size: Vector3 in layout.limb_block_sizes:
			assert(size.y >= generator.limb_minimum_size.y and size.y <= generator.limb_maximum_size.y)
	character.queue_free()
	await process_frame
	print("LIMB_BLOCK_DIMENSIONS_VALIDATION_PASSED")
	quit()
