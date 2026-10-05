extends SceneTree

const GENERATOR = preload("res://Scripts/Creatures/CreatureGenerator.gd")
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.unsymmetrie = 0.0
	generator.overall_scale = 1.0
	generator.neck_number = 0
	generator.torso_count = 5
	generator.rear_leg_count = 3
	generator.foreleg_count = 2
	generator.body_length = 8.0
	generator.torso_upper_curve = GENERATOR._make_torso_curve([[Vector2(0,0.5),0.0,0.0,0,0], [Vector2(1,2.0),0.0,0.0,0,0]])
	generator._random.seed = 43
	var plan: Dictionary = generator._create_valid_plan()
	assert(not plan.is_empty())
	assert(plan.network_torsos.size() == 5 and plan.torsos.size() == 5)
	var bodies: Array = plan.network_torsos
	assert(is_equal_approx(bodies[-1].size.x / bodies[0].size.x, 1.0))
	assert(is_equal_approx(bodies[-1].size.y / bodies[0].size.y, 4.0))
	assert(is_equal_approx(bodies[-1].size.z / bodies[0].size.z, 1.0))
	assert(is_equal_approx(bodies[-1].position.x + bodies[-1].size.x * 0.5 - bodies[0].position.x + bodies[0].size.x * 0.5, generator.body_length))
	for index: int in range(bodies.size()):
		assert(is_zero_approx(bodies[index].position.z))
		if index == 0: continue
		var overlap: float = bodies[index - 1].position.x + bodies[index - 1].size.x * 0.5 - bodies[index].position.x + bodies[index].size.x * 0.5
		assert(is_equal_approx(overlap / minf(bodies[index].size.x, bodies[index - 1].size.x), generator.torso_overlap_percent / 100.0))
	for index: int in range(plan.layouts.size()):
		var foot: Dictionary = plan.layouts[index]
		var support: Dictionary = plan.torsos[index]
		assert(is_equal_approx(support.position.z, foot.final_position.y))
		assert(is_equal_approx(support.position.x, foot.final_position.x))
		var tip: Vector3 = generator._limb_endpoint(foot)
		assert(is_equal_approx(tip.z, foot.final_position.y))
		assert(generator._nearest_neck_torso_distance(tip, plan.torsos.slice(index, index + 1)) < 0.0001)
	plan.overall_scale = 1.0
	var blueprint: Dictionary = actor._build_blueprint(plan, 0.0)
	assert(not blueprint.is_empty(), "Support attachment must survive zero shell connection tolerance")
	assert(blueprint.connections.size() == blueprint.parts.size() - 1)
	for index: int in range(plan.torsos.size()):
		assert(blueprint.parts[index].sub_torso)
		var found := false
		for connection: Dictionary in blueprint.connections:
			if connection.a == index or connection.b == index:
				var other: int = connection.b if connection.a == index else connection.a
				if other == plan.torsos.size() + plan.torsos[index].parent_torso_index: found = true
		assert(found, "Each support must attach to its designated central Torso")
	assert(actor.generate_creature())
	var packed := PackedScene.new()
	assert(packed.pack(actor) == OK)
	var restored = packed.instantiate()
	assert(is_equal_approx(restored.get_node("CreatureGenerator").torso_upper_curve.sample(1.0), 2.0))
	restored.free()
	# The script-default button must preserve curve shape and tangent modes.
	generator.torso_upper_curve.set_point_right_tangent(0, 0.75)
	var source: String = generator._build_default_source(FileAccess.get_file_as_string("res://Scripts/Creatures/CreatureGenerator.gd"))
	var candidate := GDScript.new()
	candidate.source_code = source
	assert(candidate.reload() == OK)
	var saved = candidate.new()
	assert(saved.torso_upper_curve.get_point_right_tangent(0) == 0.75)
	assert(saved._build_default_source(source) == source)
	saved.free()
	generator.torso_count = 1
	generator.rear_leg_count = 2
	generator.foreleg_count = 2
	var single_plan: Dictionary = generator._create_valid_plan()
	var single: Dictionary = actor._build_blueprint(single_plan, 0.0)
	assert(not single.is_empty())
	for index: int in range(single_plan.torsos.size()):
		var found := false
		for connection: Dictionary in single.connections:
			if connection.a == index or connection.b == index:
				var other: int = connection.b if connection.a == index else connection.a
				if other == single_plan.torsos.size():
					assert(connection.kind == "Torso")
					found = true
		assert(found)

	actor.free()
	print("TORSO_CURVE_SUPPORTS_PASSED")
	quit()
