extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var generator = load("res://Scripts/Creatures/CreatureGenerator.gd").new()
	root.add_child(generator)
	generator.part_width = 2.0
	generator.max_neck_overlap_diameter = 4.0
	generator.head_minimum_size = Vector3.ONE * 0.3
	generator.head_maximum_size = Vector3.ONE * 0.3
	generator.neck_number = 3
	generator.unsymmetrie = 0.0
	for segments: int in range(11):
		generator.neck_segment_count = segments
		generator._random.seed = 42
		var plan: Dictionary = generator._create_valid_plan()
		assert(not plan.is_empty() and plan.necks.size() == 3)
		for point: Vector3 in plan.necks[0].points: assert(is_zero_approx(point.z))
		for index: int in range(plan.necks[1].points.size()):
			assert(generator._mirror_point(plan.necks[1].points[index]).is_equal_approx(plan.necks[2].points[index]))
		for neck: Dictionary in plan.necks:
			assert(neck.blocks.size() == segments + 1 and neck.blocks[-1].name == "Head")
			var length := 0.0
			for index: int in range(segments): length += neck.points[index].distance_to(neck.points[index + 1])
			assert(is_equal_approx(length, neck.length) if segments > 0 else is_zero_approx(length))
		assert(generator.generate_torso())
		var packed := PackedScene.new()
		assert(packed.pack(generator) == OK)
		var restored = packed.instantiate()
		assert(restored.has_node("NeckLine/Head") and restored.has_node("NeckLine_3/Head"))
		assert(restored.get_node("NeckLine").get_child_count() == segments + 1)
		restored.free()
	generator.neck_segment_count = 11
	assert(generator._create_valid_plan().is_empty())
	generator.label_font_size = 72
	assert(generator.get_node("Torso/NameLabel").font_size == 72)
	generator.free()
	print("CREATURE_NECKS_VALIDATION_PASSED")
	quit()
