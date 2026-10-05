extends SceneTree

const GENERATOR = preload("res://Scripts/Creatures/CreatureGenerator.gd")
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
const GEOMETRY = preload("res://Scripts/Creatures/CreatureBoxGeometry.gd")

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var generator = GENERATOR.new()
	generator.rear_leg_count = 3
	generator.foreleg_count = 2
	generator.body_length = 12.0
	generator.torso_count = 5
	generator.inhomogeneity = 100.0
	generator.minimum_feet_distance = 0.05
	generator.torso_upper_curve = GENERATOR._make_torso_curve([[Vector2(0,0.25),0.0,0.0,0,0], [Vector2(1,2.0),0.0,0.0,0,0]])
	for width: float in [0.12, 0.4, 1.2]:
		generator.part_width = width
		for segments: int in range(4):
			generator.neck_segment_count = segments
			generator.unsymmetrie = 70.0
			generator._random.seed = 43
			print("WIDTH_CASE width=", width, " segments=", segments)
			var plan: Dictionary = generator._create_valid_plan()
			assert(not plan.is_empty())
			for body: Dictionary in plan.network_torsos:
				assert(is_equal_approx(body.size.z, width))
			for index: int in range(plan.torsos.size()):
				var support: Dictionary = plan.torsos[index]
				var parent: Dictionary = plan.network_torsos[support.parent_torso_index]
				var foot: Dictionary = plan.layouts[index]
				assert(is_equal_approx(support.size.z, width) and is_equal_approx(foot.size.z, width))
				assert(is_equal_approx(support.position.z, foot.final_position.y))
				var a := AABB(support.position - support.size * 0.5, support.size)
				var b := AABB(parent.position - parent.size * 0.5, parent.size)
				if is_zero_approx(foot.position.y):
					assert(is_equal_approx(a.end.y, b.position.y))
				else:
					assert(is_equal_approx(a.position.z, b.end.z) if support.position.z > 0 else is_equal_approx(a.end.z, b.position.z))
				assert(GEOMETRY.connected(GEOMETRY.box(support.size, Transform3D(Basis.IDENTITY,support.position)), GEOMETRY.box(parent.size,Transform3D(Basis.IDENTITY,parent.position)),0.00001))
				for size: Vector3 in foot.limb_block_sizes: assert(is_equal_approx(size.z,width))
				for point: Vector3 in foot.limb_points: assert(is_zero_approx(point.z))
			var front: Dictionary = plan.network_torsos[-1]
			for neck: Dictionary in plan.necks:
				assert(is_equal_approx(neck.points[0].x, front.position.x + front.size.x * 0.5))
				for block: Dictionary in neck.blocks:
					assert(is_equal_approx(block.size.z,width))
					var box: Dictionary = GEOMETRY.box(block.size, Transform3D(block.basis,block.position))
					assert(is_equal_approx(box.aabb.size.z,width))
				var first: Dictionary = neck.blocks[0]
				var root_box: Dictionary = GEOMETRY.box(first.size,Transform3D(first.basis,first.position))
				assert(is_equal_approx(root_box.aabb.position.x,front.position.x + front.size.x * 0.5))
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var embedded = actor.get_node("CreatureGenerator")
	embedded.part_width = 0.7
	embedded.overall_scale = 2.0
	embedded._random.seed = 43
	assert(actor.generate_creature())
	for part: RigidBody3D in actor._get_physical_body_parts():
		assert(is_equal_approx(part.get_node("CollisionShape3D").shape.size.z,1.4))
		assert(is_equal_approx(part.get_meta("generated_size").z,1.4))
	actor.free()
	generator.free()
	print("UNIFORM_WIDTH_ATTACHMENT_PASSED")
	quit()
