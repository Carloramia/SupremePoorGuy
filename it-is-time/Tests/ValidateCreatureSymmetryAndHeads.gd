extends SceneTree

const GEOMETRY = preload("res://Scripts/Creatures/CreatureBoxGeometry.gd")

func _initialize() -> void:
	call_deferred("_validate")

func _has_point(points: PackedVector3Array, target: Vector3) -> bool:
	for point: Vector3 in points:
		if point.distance_to(target) < 0.0001:
			return true
	return false

func _has_box(boxes: Array[Dictionary], target: Dictionary, generator: Node3D) -> bool:
	for box: Dictionary in boxes:
		if box.position.distance_to(generator._mirror_point(target.position)) < 0.0001 and box.size.distance_to(target.size) < 0.0001:
			return true
	return false

func _validate() -> void:
	var generator := (load("res://Scripts/Creatures/CreatureGenerator.gd") as GDScript).new() as Node3D
	root.add_child(generator)
	generator.unsymmetrie = 0.0
	generator.inhomogeneity = 100.0
	generator.max_limb_end_height_difference = 0.3
	generator.neck_number = 2
	for count: int in [2, 3, 6, 7, 10]:
		for seed_value: int in [12, 42, 99]:
			generator.feets = count
			generator._random.seed = seed_value
			var plan: Dictionary = generator._create_valid_plan()
			assert(not plan.is_empty(), "Symmetric generation must find a legal plan")
			var feet: Array[Dictionary] = plan.layouts
			for index: int in range(0, feet.size() - 1, 2):
				assert(feet[index].size.is_equal_approx(feet[index + 1].size))
				assert(feet[index].role == feet[index + 1].role)
				assert(feet[index].limb_points == feet[index + 1].limb_points)
			if count % 2 == 1:
				assert(is_zero_approx(feet[-1].final_position.y))
			for layouts: Array[Dictionary] in [plan.torsos, plan.network_torsos]:
				for torso: Dictionary in layouts:
					assert(_has_box(layouts, torso, generator), "Every body block must have an equal-sized mirror")
			var network: Dictionary = plan.limb_network
			for points: PackedVector3Array in [network.endpoints, network.extra_endpoints, network.junctions]:
				for point: Vector3 in points:
					assert(_has_point(points, generator._mirror_point(point)))
			var vertices: PackedVector3Array = network.vertices
			for index: int in range(0, vertices.size(), 2):
				var matched := false
				var a: Vector3 = generator._mirror_point(vertices[index])
				var b: Vector3 = generator._mirror_point(vertices[index + 1])
				for other: int in range(0, vertices.size(), 2):
					matched = matched or (vertices[other].distance_to(a) < 0.0001 and vertices[other + 1].distance_to(b) < 0.0001) or (vertices[other].distance_to(b) < 0.0001 and vertices[other + 1].distance_to(a) < 0.0001)
				assert(matched, "Every network edge must have a mirror edge")
	# Exact rotated overlap metric and touching-volume behavior.
	var rotated := GEOMETRY.box(Vector3.ONE, Transform3D(Basis(Vector3.UP, 0.4), Vector3.ZERO))
	assert(is_equal_approx(GEOMETRY.overlap_diameter(rotated, rotated), sqrt(3.0)))
	var cube := GEOMETRY.box(Vector3.ONE, Transform3D.IDENTITY)
	assert(is_zero_approx(GEOMETRY.overlap_diameter(cube, GEOMETRY.box(Vector3.ONE, Transform3D(Basis.IDENTITY, Vector3.RIGHT)))))
	var anchors: Array[Dictionary] = [{"size": Vector3.ONE, "position": Vector3(0, 2, 2)}, {"size": Vector3.ONE, "position": Vector3(0, 2, -2)}]
	var subtorsos: Array[Dictionary] = []
	generator._random.seed = 42
	var necks: Array[Dictionary] = generator._plan_necks(anchors, subtorsos)
	assert(necks.size() == 2)
	assert(is_equal_approx(necks[0].length, necks[1].length))
	assert(necks[0].head_size.is_equal_approx(necks[1].head_size))
	for index: int in range(necks[0].points.size()):
		var a: Vector3 = necks[0].points[index]
		var b: Vector3 = necks[1].points[index]
		assert(generator._mirror_point(a).is_equal_approx(b))
	var boxes: Array[Dictionary] = []
	for anchor: Dictionary in anchors:
		boxes.append(GEOMETRY.box(anchor.size, Transform3D(Basis.IDENTITY, anchor.position)))
	for neck: Dictionary in necks:
		assert(neck.blocks.size() == generator.neck_segment_count + 1)
		assert(neck.blocks[-1].name == "Head")
		assert(is_equal_approx(neck.blocks[-1].position.x - neck.head_size.x * 0.5, neck.points[-1].x))
		for block: Dictionary in neck.blocks:
			var next := GEOMETRY.box(block.size, Transform3D(block.basis, block.position))
			for old: Dictionary in boxes:
				assert(GEOMETRY.overlap_diameter(next, old) <= generator.max_neck_overlap_diameter + 0.00001)
			boxes.append(next)
	# A too-small threshold rejects candidates without bypassing the constraint.
	generator.max_neck_overlap_diameter = 0.0
	generator.max_neck_start_surface_distance = 0.0
	generator.neck_maximum_angle = 60.0
	assert(generator._plan_necks(anchors, subtorsos).is_empty())
	# High Unsymmetrie permits independent geometry.
	generator.unsymmetrie = 100.0
	generator.neck_number = 0
	generator.feets = 6
	generator._random.seed = 42
	var asymmetric: Dictionary = generator._create_valid_plan()
	assert(not asymmetric.is_empty())
	var differs := false
	for torso: Dictionary in asymmetric.network_torsos:
		differs = differs or not _has_box(asymmetric.network_torsos, torso, generator)
	assert(differs)
	generator.free()
	print("CREATURE_SYMMETRY_HEADS_VALIDATION_PASSED")
	quit()
