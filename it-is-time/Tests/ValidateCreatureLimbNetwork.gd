extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var generator = load("res://Scripts/Creatures/CreatureGenerator.gd").new()
	generator.rear_leg_count = 4
	generator.foreleg_count = 3
	generator.body_length = 8.0
	generator.neck_number = 0
	generator._random.seed = 42
	var plan: Dictionary = generator._create_valid_plan()
	assert(not plan.is_empty())
	var network: Dictionary = plan.limb_network
	assert(network.endpoints.size() == 7)
	var reached := PackedVector3Array([network.vertices[0]])
	for iteration: int in range(network.vertices.size()):
		for index: int in range(0, network.vertices.size(), 2):
			var a: Vector3 = network.vertices[index]
			var b: Vector3 = network.vertices[index + 1]
			if reached.has(a) and not reached.has(b): reached.append(b)
			if reached.has(b) and not reached.has(a): reached.append(a)
	for endpoint: Vector3 in network.endpoints: assert(reached.has(endpoint))
	for endpoint: Vector3 in network.extra_endpoints: assert(reached.has(endpoint))
	generator.free()
	print("CREATURE_LIMB_NETWORK_VALIDATION_PASSED")
	quit()
