extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var generator = load("res://Scripts/Creatures/CreatureGenerator.gd").new()
	generator.body_length = 12.0
	generator.neck_number = 0
	generator.inhomogeneity = 100.0
	for counts: Vector2i in [Vector2i(2,2), Vector2i(3,3), Vector2i(8,2), Vector2i(0,5)]:
		generator.rear_leg_count = counts.x
		generator.foreleg_count = counts.y
		for seed_value: int in [12,42,99]:
			generator._random.seed = seed_value
			var plan: Dictionary = generator._create_valid_plan()
			assert(not plan.is_empty())
			for foot: Dictionary in plan.layouts:
				if foot.partner_index < 0: continue
				var partner: Dictionary = plan.layouts[foot.partner_index]
				assert(foot.size.is_equal_approx(partner.size))
				for index: int in range(foot.limb_points.size()):
					assert(foot.limb_points[index].is_equal_approx(generator._mirror_point(partner.limb_points[index])))
			for body: Dictionary in plan.network_torsos: assert(is_zero_approx(body.position.z))
	generator.unsymmetrie = 100.0
	generator.rear_leg_count = 2
	generator.foreleg_count = 2
	generator._random.seed = 42
	var asymmetric: Dictionary = generator._create_valid_plan()
	assert(not asymmetric.is_empty())
	var a: Vector2 = asymmetric.layouts[0].final_position
	var b: Vector2 = asymmetric.layouts[1].final_position
	assert(not a.is_equal_approx(Vector2(b.x,-b.y)))
	generator.free()
	print("CREATURE_SYMMETRY_HEADS_VALIDATION_PASSED")
	quit()
