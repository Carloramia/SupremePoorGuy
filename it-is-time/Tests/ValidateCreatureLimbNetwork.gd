extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _layouts(points: PackedVector3Array) -> Array[Dictionary]:
	var layouts: Array[Dictionary] = []
	for point: Vector3 in points:
		layouts.append({"size": Vector3.ONE, "final_position": Vector2(point.x, point.z), "limb_points": PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0, point.y - 0.5, 0)])})
	return layouts

func _validate() -> void:
	var generator := (load("res://Scripts/Creatures/CreatureGenerator.gd") as GDScript).new() as Node3D
	root.add_child(generator)
	generator.network_extra_endpoint_count = 0
	var layouts := _layouts(PackedVector3Array([Vector3(0, 3, 0), Vector3(0.1, 3, 0), Vector3(0.2, 3, 0), Vector3(4, 3, 0)]))
	generator.limb_endpoint_merge_distance = 0.15
	var merged: Dictionary = generator._build_limb_network(layouts)
	assert(merged.junctions.size() == 2, "Nearby endpoints must merge transitively")
	_validate_connected(merged)
	generator.limb_endpoint_merge_distance = 0.0
	var separate: Dictionary = generator._build_limb_network(layouts)
	assert(separate.junctions.size() == 4 and separate.vertices.size() == 6)
	_validate_connected(separate)
	generator.limb_endpoint_merge_distance = 100.0
	var all_merged: Dictionary = generator._build_limb_network(layouts)
	assert(all_merged.junctions.size() == 1)
	_validate_connected(all_merged)
	var coincident: Dictionary = generator._build_limb_network(_layouts(PackedVector3Array([Vector3(0, 3, 0), Vector3(0, 3, 0)])))
	assert(coincident.junctions.size() == 1 and coincident.vertices.is_empty())
	_validate_connected(coincident)
	# Strict threshold: endpoints exactly one unit apart do not merge at threshold one.
	generator.limb_endpoint_merge_distance = 1.0
	assert(generator._build_limb_network(_layouts(PackedVector3Array([Vector3(0, 3, 0), Vector3(1, 3, 0)]))).junctions.size() == 2)
	generator.limb_endpoint_merge_distance = 0.0
	var variations: Dictionary = {}
	for seed_value: int in range(12):
		generator._random.seed = seed_value
		var network: Dictionary = generator._build_limb_network(layouts)
		variations[str(network.vertices)] = true
		_validate_connected(network)
	assert(variations.size() > 1, "Random connections must produce different trees")
	# Free endpoints must be distinct, connected, and have direct random links between them.
	for count: int in [1, 4, 32]:
		generator.network_extra_endpoint_count = count
		for threshold: float in [0.0, 100.0]:
			generator.limb_endpoint_merge_distance = threshold
			var free: Dictionary = generator._build_limb_network(layouts)
			_validate_free_endpoints(free, count)
	generator.network_extra_endpoint_count = 4
	generator.feets = 10
	generator.unsymmetrie = 100.0
	generator.max_limb_end_height_difference = 0.3
	generator.narrowty = 200.0
	for threshold: float in [0.0, 0.2, 100.0]:
		generator.limb_endpoint_merge_distance = threshold
		for iteration: int in range(2):
			assert(generator.generate_torso())
			assert(generator.has_node("SubTorso") and generator.has_node("Torso"))
			assert(generator.get_node("SubTorso/NameLabel").text == "SubTorso")
			var nodes := 0
			for child: Node in generator.get_children():
				if child.name == &"LimbNetwork":
					nodes += 1
			assert(nodes == 1, "Regeneration must not accumulate networks")
			var graph := generator.get_node("LimbNetwork") as MeshInstance3D
			_validate_mesh(graph)
			assert(graph.get_meta("extra_endpoints").size() == 4)
			var endpoints: PackedVector3Array = graph.get_meta("limb_endpoints")
			for foot: Node3D in generator.get_node("Feets").get_children():
				if foot.has_meta("limb_points"):
					var points: PackedVector3Array = foot.get_meta("limb_points")
					assert(endpoints.has(foot.position + points[points.size() - 1]))
	var packed := PackedScene.new()
	assert(packed.pack(generator) == OK)
	var path := "res://Tests/.creature_limb_network_roundtrip.tscn"
	assert(not FileAccess.file_exists(path))
	assert(ResourceSaver.save(packed, path) == OK)
	var restored := (load(path) as PackedScene).instantiate() as Node3D
	_validate_mesh(restored.get_node("LimbNetwork"))
	assert(restored.has_node("SubTorso"))
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
	restored.free()
	generator.queue_free()
	print("CREATURE_LIMB_NETWORK_VALIDATION_PASSED")
	quit()

func _validate_mesh(graph: MeshInstance3D) -> void:
	assert(graph.owner != null)
	assert(graph.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_LINES)
	_validate_connected({"endpoints": graph.get_meta("limb_endpoints"), "extra_endpoints": graph.get_meta("extra_endpoints"), "junctions": graph.get_meta("junctions"), "vertices": graph.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]})

func _validate_connected(network: Dictionary) -> void:
	var vertices: PackedVector3Array = network.vertices
	var endpoints: PackedVector3Array = network.endpoints
	var junctions: PackedVector3Array = network.junctions
	if vertices.is_empty():
		assert(junctions.size() == 1)
		for point: Vector3 in endpoints:
			assert(point == junctions[0])
		return
	var adjacency: Dictionary = {}
	for index: int in range(0, vertices.size(), 2):
		var first := vertices[index]
		var second := vertices[index + 1]
		assert(first != second, "Network must not emit degenerate lines")
		if not adjacency.has(first):
			adjacency[first] = []
		if not adjacency.has(second):
			adjacency[second] = []
		adjacency[first].append(second)
		adjacency[second].append(first)
	var visited: Dictionary = {vertices[0]: true}
	var pending: Array[Vector3] = [vertices[0]]
	while not pending.is_empty():
		var point: Vector3 = pending.pop_back()
		for neighbor: Vector3 in adjacency[point]:
			if not visited.has(neighbor):
				visited[neighbor] = true
				pending.append(neighbor)
	assert(visited.size() == adjacency.size(), "All segments must belong to one connected component")
	endpoints = endpoints.duplicate()
	endpoints.append_array(network.get("extra_endpoints", PackedVector3Array()))
	for point: Vector3 in endpoints:
		assert(visited.has(point), "Every original Limb tip must remain on the network")

func _validate_free_endpoints(network: Dictionary, count: int) -> void:
	var extra: PackedVector3Array = network.extra_endpoints
	var limbs: PackedVector3Array = network.endpoints
	var vertices: PackedVector3Array = network.vertices
	assert(extra.size() == count)
	_validate_connected(network)
	var links := 0
	for point: Vector3 in extra:
		assert(not limbs.has(point))
		assert(point.x >= -0.5 and point.x <= 4.5 and point.y >= 2.5 and point.y <= 3.5 and point.z >= -0.5 and point.z <= 0.5)
	for index: int in range(0, vertices.size(), 2):
		if extra.has(vertices[index]) and extra.has(vertices[index + 1]):
			links += 1
	assert(links >= maxi(count - 1, 0), "Free points must have a direct random chain")
