extends SceneTree

const GENERATOR = preload("res://Scripts/Creatures/CreatureGenerator.gd")
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var generator = GENERATOR.new()
	root.add_child(generator)
	generator.torso_count = 5
	generator.body_length = 8.0
	generator.torso_upper_curve = GENERATOR._make_torso_curve([[Vector2(0,1),0.0,0.0,0,0],[Vector2(0.5,2),0.0,0.0,0,0],[Vector2(1,1),0.0,0.0,0,0]],-3.0,3.0)
	generator.torso_lower_curve = GENERATOR._make_torso_curve([[Vector2(0,0),0.0,0.0,0,0],[Vector2(0.5,0.3),0.0,0.0,0,0],[Vector2(1,-0.2),0.0,0.0,0,0]],-3.0,3.0)
	var bodies: Array[Dictionary] = generator._plan_body(1.0,0.4,3.0)
	assert(bodies.size() == 5)
	for index: int in range(bodies.size()):
		var progress := float(index) / 4.0
		var upper: float = generator.torso_upper_curve.sample(progress)
		var lower: float = generator.torso_lower_curve.sample(progress)
		var body: Dictionary = bodies[index]
		assert(is_equal_approx(body.size.y,upper-lower))
		assert(is_equal_approx(body.position.y + body.size.y * 0.5,3.2+upper))
		assert(is_equal_approx(body.position.y - body.size.y * 0.5,3.2+lower))
		assert(is_equal_approx(body.size.z,0.4) and is_zero_approx(body.position.z))
	generator.torso_lower_curve.set_point_value(1,0.6)
	var changed: Array[Dictionary] = generator._plan_body(1.0,0.4,3.0)
	assert(is_equal_approx(changed[2].upper_height,bodies[2].upper_height))
	assert(is_equal_approx(changed[2].lower_height-bodies[2].lower_height,0.3))
	generator.torso_upper_curve.set_point_value(1,2.4)
	var changed_upper: Array[Dictionary] = generator._plan_body(1.0,0.4,3.0)
	assert(is_equal_approx(changed_upper[2].lower_height,changed[2].lower_height))
	assert(is_equal_approx(changed_upper[2].upper_height-changed[2].upper_height,0.4))
	generator.torso_count = 1
	var single: Array[Dictionary] = generator._plan_body(1.0,0.4,3.0)
	assert(single.size() == 1 and single[0].contour_progress == 0.5)
	assert(is_equal_approx(single[0].size.y,1.8))
	generator.torso_count = 5
	generator.neck_number = 0
	generator._random.seed = 42
	assert(generator.generate_torso())
	var previous := generator.get_node("Torso")
	generator.torso_lower_curve = GENERATOR._make_torso_curve([[Vector2(0,3),0.0,0.0,0,0],[Vector2(1,3),0.0,0.0,0,0]])
	assert(not generator.generate_torso() and generator.get_node("Torso") == previous)
	generator.torso_count = 2
	generator.torso_upper_curve = GENERATOR._make_torso_curve([[Vector2(0,1),0.0,0.0,0,0],[Vector2(1,10),0.0,0.0,0,0]],0.0,10.0)
	generator.torso_lower_curve = GENERATOR._make_torso_curve([[Vector2(0,0),0.0,0.0,0,0],[Vector2(1,9),0.0,0.0,0,0]],0.0,10.0)
	assert(generator._plan_body(1.0,0.4,3.0).is_empty())
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var embedded = actor.get_node("CreatureGenerator")
	embedded.torso_upper_curve = GENERATOR._make_torso_curve([[Vector2(0,1.2),0.0,0.0,0,0],[Vector2(1,1.5),0.0,0.0,0,0]])
	embedded.torso_lower_curve = GENERATOR._make_torso_curve([[Vector2(0,-0.2),0.0,0.0,0,0],[Vector2(1,0.2),0.0,0.0,0,0]],-3.0,3.0)
	embedded._random.seed = 42
	assert(actor.generate_creature())
	var packed := PackedScene.new()
	assert(packed.pack(actor) == OK)
	var restored = packed.instantiate()
	assert(is_equal_approx(restored.get_node("CreatureGenerator").torso_lower_curve.sample(0),-0.2))
	restored.free()
	var source: String = embedded._build_default_source(FileAccess.get_file_as_string("res://Scripts/Creatures/CreatureGenerator.gd"))
	var candidate := GDScript.new()
	candidate.source_code = source
	assert(candidate.reload() == OK)
	var defaults = candidate.new()
	assert(is_equal_approx(defaults.torso_lower_curve.sample(0),-0.2))
	assert(is_equal_approx(defaults.torso_upper_curve.sample(1),1.5))
	assert(defaults._build_default_source(source) == source)
	defaults.free()
	actor.free()
	generator.free()
	print("TORSO_CONTOURS_PASSED")
	quit()
