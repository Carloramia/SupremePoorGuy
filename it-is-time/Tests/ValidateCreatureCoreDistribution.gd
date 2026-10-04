extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var generator := (load("res://Scripts/Creatures/CreatureGenerator.gd") as GDScript).new() as Node3D
	root.add_child(generator)
	var points := PackedVector3Array([Vector3(0.5, 0, 0), Vector3(3, 3, 0)])
	var blockers: Array[Dictionary] = [{"position": Vector3(6, 1.5, 0), "size": Vector3(1, 0.2, 1)}]
	assert(not generator._neckline_front_clear(points, blockers), "A body in front of the segment interior must block it")
	blockers[0].position = Vector3(-3, 1.5, 0)
	assert(generator._neckline_front_clear(points, blockers), "A body behind the neck must not block it")
	blockers[0].position = Vector3(6, 1.5, 2)
	assert(generator._neckline_front_clear(points, blockers), "A body outside the segment's Y/Z projection must not block it")
	blockers[0] = {"position": Vector3.ZERO, "size": Vector3.ONE}
	assert(generator._neckline_front_clear(points, blockers), "Starting exactly on the front face is legal")
	var vertices := PackedVector3Array([Vector3(-6,3,0), Vector3(-3,3,0), Vector3(-3,3,0), Vector3(0,3,0), Vector3(0,3,0), Vector3(3,3,0), Vector3(3,3,0), Vector3(6,3,0)])
	var profile: Dictionary = generator._network_profile(vertices)
	generator._random.seed = 42
	var core_mean := 0.0
	var edge_mean := 0.0
	for sample: int in range(400):
		core_mean += generator._sample_profile_torso_size(Vector3(0,3,0), profile).length()
		edge_mean += generator._sample_profile_torso_size(Vector3(6,3,0), profile).length()
	assert(core_mean > edge_mean * 1.5, "Core size sampling must be substantially larger")
	var endpoints := PackedVector3Array([Vector3(-6,3,-2), Vector3(6,3,2)])
	generator.unsymmetrie = 100.0
	generator.network_extra_endpoint_count = 32
	generator.network_center_bias = 0.75
	var extras: PackedVector3Array = generator._sample_network_extra_endpoints(endpoints)
	for point: Vector3 in extras:
		assert(absf(point.x) <= 1.62501 and absf(point.z) <= 0.62501, "Free vertices must concentrate inside the central sampling volume")
	generator.unsymmetrie = 0.0
	generator.neck_number = 0
	var anchors: Array[Dictionary] = [{"position": Vector3(-6,3,0), "size": Vector3.ONE}, {"position": Vector3(6,3,0), "size": Vector3.ONE}]
	var core_count := 0
	var edge_count := 0
	var core_volume := 0.0
	var edge_volume := 0.0
	for seed_value: int in [12, 42, 99, 123]:
		generator._random.seed = seed_value
		var torsos: Array[Dictionary] = generator._plan_network_torsos(anchors, vertices)
		assert(not torsos.is_empty())
		for torso: Dictionary in torsos:
			var volume: float = torso.size.x * torso.size.y * torso.size.z
			if generator._core_weight(torso.position, profile) >= 0.5:
				core_count += 1
				core_volume += volume
			else:
				edge_count += 1
				edge_volume += volume
	assert(core_count > edge_count, "Across seeded layouts the central half must contain more Torso blocks")
	assert(core_volume / core_count > edge_volume / edge_count, "Accepted core Torso blocks must be larger on average")
	generator.free()
	print("CREATURE_CORE_DISTRIBUTION_VALIDATION_PASSED")
	quit()
