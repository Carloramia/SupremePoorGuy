extends SceneTree

const GENERATOR = preload("res://Scripts/Creatures/CreatureGenerator.gd")
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.neck_number = 0
	generator.torso_count = 3
	generator.rear_leg_count = 3
	generator.foreleg_count = 2
	generator.body_length = 8.0
	generator.unsymmetrie = 0.0
	generator.torso_upper_curve = GENERATOR._make_torso_curve()
	generator.torso_lower_curve = null
	generator.torso_height_offset_curve = null
	generator.sub_torso_height_curve = null
	var original: Array[Dictionary] = generator._plan_body(1.0, generator.part_width, 3.0)
	generator.torso_height_offset_curve = GENERATOR._make_torso_curve([[Vector2(0,0),0.0,0.0,0,0],[Vector2(1,0.4),0.0,0.0,0,0]], -3.0,3.0)
	var moved: Array[Dictionary] = generator._plan_body(1.0, generator.part_width, 3.0)
	assert(moved.size() == original.size())
	for index: int in range(moved.size()):
		assert(moved[index].size.is_equal_approx(original[index].size))
		var offset: float = generator.torso_height_offset_curve.sample(moved[index].contour_progress)
		assert(is_equal_approx(moved[index].position.y - original[index].position.y, offset))
	for value: float in [0.0,0.5,1.0]:
		generator.sub_torso_height_curve = GENERATOR._make_torso_curve([[Vector2(0,value),0.0,0.0,0,0],[Vector2(1,value),0.0,0.0,0,0]],0.0,1.0)
		generator._random.seed = 43
		var plan: Dictionary = generator._create_valid_plan()
		assert(not plan.is_empty())
		for index: int in range(plan.torsos.size()):
			var support: Dictionary = plan.torsos[index]
			var parent: Dictionary = plan.network_torsos[support.parent_torso_index]
			var center: bool = is_zero_approx(plan.layouts[index].position.y)
			var low: float = parent.lower_height + support.size.y * (-0.5 if center else 0.5)
			var high: float = parent.upper_height - support.size.y * 0.5
			assert(is_equal_approx(support.position.y, lerpf(low,high,value)))
			var tip: Vector3 = generator._limb_endpoint(plan.layouts[index])
			assert(is_equal_approx(tip.y, support.position.y - support.size.y * 0.5))
			assert(is_equal_approx(tip.z, support.position.z))
		plan.overall_scale = generator.overall_scale
		var blueprint: Dictionary = actor._build_blueprint(plan,0.0)
		assert(not blueprint.is_empty())
		assert(blueprint.connections.size() == blueprint.parts.size() - 1)
	generator.sub_torso_height_curve = GENERATOR._make_torso_curve([[Vector2(0,0),0.0,0.0,0,0],[Vector2(1,1),0.0,0.0,0,0]],0.0,1.0)
	generator._random.seed = 43
	var varying: Dictionary = generator._create_valid_plan()
	for support: Dictionary in varying.torsos:
		var parent: Dictionary = varying.network_torsos[support.parent_torso_index]
		var value: float = generator.sub_torso_height_curve.sample(parent.contour_progress)
		var center: bool = is_zero_approx(varying.layouts[support.source_foot_index].position.y)
		assert(is_equal_approx(support.position.y, lerpf(parent.lower_height + support.size.y * (-0.5 if center else 0.5),parent.upper_height - support.size.y * 0.5,value)))
	assert(actor.generate_creature())
	var packed := PackedScene.new()
	assert(packed.pack(actor) == OK)
	var restored = packed.instantiate()
	assert(is_equal_approx(restored.get_node("CreatureGenerator").sub_torso_height_curve.sample(1.0),1.0))
	restored.free()
	var defaults: Dictionary = generator._capture_default_parameters()
	assert(is_equal_approx(defaults.sub_torso_height_curve.sample(1.0),1.0))
	assert(is_equal_approx(defaults.torso_height_offset_curve.sample(1.0),0.4))
	actor.free()
	print("SUBTORSO_HEIGHT_PASSED")
	quit()
