extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var generator := (load("res://Scripts/Creatures/CreatureGenerator.gd") as GDScript).new() as Node3D
	root.add_child(generator)
	generator._random.seed = 42
	generator.unsymmetrie = 0.0
	generator.neck_number = 3
	generator.max_neck_start_surface_distance = 0.25
	var torsos: Array[Dictionary] = [
		{"size": Vector3.ONE, "position": Vector3(0, 2, 2)},
		{"size": Vector3.ONE, "position": Vector3(0, 2, -2)},
		{"size": Vector3.ONE, "position": Vector3(1, 2, 0)}
	]
	var subtorsos: Array[Dictionary] = []
	var necks: Array[Dictionary] = generator._plan_necks(torsos, subtorsos)
	assert(necks.size() == 3, "Odd neck count must not be reduced")
	for point: Vector3 in necks[0].points:
		assert(is_zero_approx(point.z), "The odd central neck must stay on Z=0")
	assert(is_equal_approx(necks[1].length, necks[2].length))
	for index: int in range(necks[1].points.size()):
		assert(generator._mirror_point(necks[1].points[index]).is_equal_approx(necks[2].points[index]))
	var off_surface := false
	for neck: Dictionary in necks:
		var points: PackedVector3Array = neck.points
		var distance: float = generator._nearest_neck_torso_distance(points[0], torsos)
		assert(distance <= 0.25001)
		off_surface = off_surface or distance > 0.0001
		var total := 0.0
		var previous_length := INF
		for segment: int in range(points.size() - 1):
			var delta := points[segment + 1] - points[segment]
			assert(delta.x > 0.0 and delta.y >= 0.0 and is_zero_approx(delta.z))
			assert(delta.length() < previous_length)
			previous_length = delta.length()
			total += delta.length()
		assert(is_equal_approx(total, neck.length))
		assert(is_zero_approx(points[1].y - points[0].y))
		assert(is_zero_approx(points[-1].y - points[-2].y))
	assert(off_surface, "Roots are free points and need not lie on Torso faces")
	generator.neck_number = 1
	var isolated: Array[Dictionary] = [torsos[0]]
	assert(generator._plan_necks(isolated, subtorsos).is_empty(), "An impossible center-distance constraint must fail, not omit the center neck")
	generator.neck_number = 0
	assert(generator._plan_necks(torsos, subtorsos).is_empty())
	generator.neck_number = 3
	generator.feets = 4
	generator.max_neck_start_surface_distance = 0.5
	generator.max_limb_end_height_difference = 0.3
	for iteration: int in range(2):
		assert(generator.generate_torso())
		var count := 0
		for child: Node in generator.get_children():
			if child.has_meta(&"generated_neck_line"):
				assert(child.get_parent() == generator)
				assert(child.owner == generator)
				assert(child.has_node("Neck") and child.has_node("Head"))
				assert(child.get_child_count() == generator.neck_segment_count + 1)
				count += 1
		assert(count == 3, "Regeneration must replace independent NeckLine nodes")
	generator.label_font_size = 72
	for child: Node in generator.get_children():
		if child.has_node("NameLabel"):
			assert(child.get_node("NameLabel").font_size == 72)
	for foot: Node in generator.get_node("Feets").get_children():
		if foot.has_node("NameLabel"):
			assert(foot.get_node("NameLabel").font_size == 72)
	var packed := PackedScene.new()
	assert(packed.pack(generator) == OK)
	var restored := packed.instantiate() as Node3D
	assert(restored.has_node("NeckLine/Head") and restored.has_node("NeckLine_3/Neck"))
	assert(restored.get_node("NeckLine/Head").get_meta(&"generated_head"))
	assert(restored.label_font_size == 72)
	restored.free()
	generator.free()
	print("CREATURE_NECK_VALIDATION_PASSED")
	quit()
