extends SceneTree

const STUMP = preload("res://Scripts/Creatures/Generators/StumpBeastGenerator.gd")
const BEAST = preload("res://Scripts/Creatures/Generators/BeastGenerator.gd")
const BIRD = preload("res://Scripts/Creatures/Generators/BirdGenerator.gd")
const RULE = preload("res://Scripts/Creatures/Generators/GeneratedPartSceneRule.gd")
const CHARACTER = preload("res://Scripts/Creatures/GeneratedCreatureCharacter3D.gd")
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const DATA = preload("res://Scripts/Creatures/Generators/CreatureGeneratorDefaults.gd")
const PAPER = preload("res://Scenes/Creatures/Bodyparts/PaperParts/ToSplit_1/Base/02_body_main.tscn")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var beast := BEAST.new()
	var bird := BIRD.new()
	var generator := STUMP.new()
	assert(generator is BEAST)
	assert(generator._get_defaults_path() != beast._get_defaults_path() and generator._get_defaults_path() != bird._get_defaults_path())
	var before_beast := FileAccess.get_file_as_string(beast._get_defaults_path())
	var before_bird := FileAccess.get_file_as_string(bird._get_defaults_path())
	var other := STUMP.new()
	assert(generator.part_scene_rules.size() >= 4)
	generator.part_scene_rules[0].size_multiplier = 1.5
	assert(other.part_scene_rules[0].size_multiplier == 1.0)
	generator.part_scene_rules[0].size_multiplier = 1.0
	var exact := RULE.new()
	exact.part_name = "Torso_2"
	exact.part_scene = PAPER
	exact.size_mode = RULE.SizeMode.FIT_BOX
	generator.part_scene_rules.append(exact)
	assert(generator.get_part_scene_rule("Torso", "Torso_2") == exact)
	var support_rule := RULE.new()
	support_rule.part_key = "SubTorso_ForeLeg_1"
	support_rule.part_scene = PAPER
	generator.part_scene_rules.append(support_rule)
	assert(generator.get_part_scene_rule("SubTorso", "SubTorso_3", "SubTorso_ForeLeg_1") == support_rule)
	assert(generator.get_part_scene_rule("SubTorso", "SubTorso_7", "SubTorso_ForeLeg_1") == support_rule)
	generator.part_scene_rules.erase(support_rule)
	assert(generator.get_part_scene_rule("SubTorso", "SubTorso") == null)
	var temp := "res://Tests/.part_scene_defaults_test.tres"
	assert(generator._save_default_preset(temp))
	var saved := load(temp) as DATA
	assert(saved.parameters.part_scene_rules[-1].part_scene.resource_path == PAPER.resource_path)
	assert(saved.parameters.part_scene_rules[-1] != exact)
	assert(FileAccess.get_file_as_string(beast._get_defaults_path()) == before_beast)
	assert(FileAccess.get_file_as_string(bird._get_defaults_path()) == before_bird)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
	var packed := PackedScene.new()
	assert(packed.pack(generator) == OK)
	var restored := packed.instantiate()
	assert(restored.get_part_scene_rule("Torso", "Torso_2").part_scene.resource_path == PAPER.resource_path)
	var restored_other := packed.instantiate()
	restored.get_part_scene_rule("Torso", "Torso_2").size_multiplier = 2.0
	assert(restored_other.get_part_scene_rule("Torso", "Torso_2").size_multiplier == 1.0)
	var actor := CHARACTER.new()
	actor.mass_limits_enabled = false
	var layouts: Array[Dictionary] = [{"name":"Torso_2", "role":"Torso", "size":Vector3(2,3,0.2), "transform":Transform3D.IDENTITY, "scene_rule":exact}]
	var blueprint := {"parts": layouts, "connections": []}
	var stage := actor._instantiate_blueprint(blueprint, Transform3D.IDENTITY)
	assert(stage != null)
	var part := stage.get_child(0) as PhysicalBodyPart3D
	assert(GEOMETRY.bounds(part).size.is_equal_approx(Vector3(2,3,0.2)))
	assert(GEOMETRY.bounds(part).get_center().is_equal_approx(Vector3.ZERO))
	assert(part.scale.is_equal_approx(Vector3.ONE))
	assert(part.get_meta("generated_scene_path") == PAPER.resource_path)
	var hp := part.max_hp
	var armor := part.armor
	root.add_child(stage)
	assert(part.max_hp == hp and part.armor == armor)
	part.prepare_generated_geometry()
	assert(GEOMETRY.bounds(part).size.is_equal_approx(Vector3(2,3,0.2)), "Ready must not undo custom collision fitting")
	stage.free()
	exact.use_joint_markers = true
	var second := layouts[0].duplicate()
	second.name = "Second"
	second.transform = Transform3D(Basis.IDENTITY, Vector3(3,0,0))
	var marker_layouts: Array[Dictionary] = [layouts[0], second]
	stage = actor._instantiate_blueprint({"parts":marker_layouts,"connections":[{"a":0,"b":1,"kind":"Torso","anchor":Vector3(1,1,0),"basis":Basis.IDENTITY}]},Transform3D.IDENTITY)
	var expected_anchor := (GEOMETRY.connection_marker(stage.get_child(0),Vector3(1,1,0)) + GEOMETRY.connection_marker(stage.get_child(1),Vector3(1,1,0))) * 0.5
	assert((stage.get_node("Joints").get_child(0) as Node3D).position.is_equal_approx(expected_anchor))
	stage.free()
	exact.use_joint_markers = false
	for mode: int in [RULE.SizeMode.KEEP_SIZE, RULE.SizeMode.FIT_UNIFORM]:
		var source := PAPER.instantiate() as PhysicalBodyPart3D
		source.prepare_generated_geometry()
		var original := GEOMETRY.bounds(source).size
		exact.size_mode = mode
		var fitted := GEOMETRY.fit(source, Vector3(2,3,0.2), exact).size
		if mode == RULE.SizeMode.KEEP_SIZE: assert(fitted.is_equal_approx(original))
		else: assert(is_equal_approx(fitted.x / fitted.y, original.x / original.y))
		source.free()
	exact.size_mode = RULE.SizeMode.FIT_BOX
	# Regeneration must re-resolve persistent rules, including after temporarily reducing counts.
	root.add_child(generator)
	generator._random.seed = 7
	var plan := generator._create_valid_plan()
	assert(not plan.is_empty())
	var frame := actor._build_blueprint(plan, generator.torso_connection_distance)
	for layout: Dictionary in frame.parts:
		layout.scene_rule = generator.get_part_scene_rule(actor._get_generated_part_type(layout), str(layout.name))
	stage = actor._instantiate_blueprint(frame, Transform3D.IDENTITY)
	assert(stage != null)
	assert(stage.get_node("Torso").get_meta("generated_scene_path") == PAPER.resource_path)
	stage.free()
	var rule_count := generator.part_scene_rules.size()
	generator.rear_leg_count = 0
	generator.foreleg_count = 0
	assert(generator.generate_torso())
	generator.rear_leg_count = 2
	generator.foreleg_count = 2
	assert(generator.generate_torso())
	assert(generator.part_scene_rules.size() == rule_count)
	assert(generator.get_part_scene_rule("Torso", "Torso_2") == exact)
	# Exercise the real framework signal and transactional physical rebuild, not only blueprint helpers.
	generator.reparent(actor)
	actor.generator_path = NodePath("StumpBeastGenerator")
	generator.name = "StumpBeastGenerator"
	actor.generate_on_ready = false
	root.add_child(actor)
	assert(actor.generate_creature())
	var previous := actor.get_node("GeneratedParts")
	assert(previous.get_node("Torso").get_meta("generated_scene_path") == PAPER.resource_path)
	assert(actor.generate_creature())
	assert(actor.get_node("GeneratedParts") != previous)
	var broken_rule := RULE.new()
	broken_rule.part_name = "Torso"
	generator.part_scene_rules.push_front(broken_rule)
	previous = actor.get_node("GeneratedParts")
	assert(not actor.generate_creature(), "Missing mapped scene must reject the rebuild")
	assert(actor.get_node("GeneratedParts") == previous, "Invalid mappings must retain the previous character")
	for instance: Node in [actor, other, beast, bird, restored, restored_other]: instance.free()
	var sample := load("res://Scenes/Creatures/Characters/Generate_StumpBeast.tscn").instantiate() as Node3D
	sample.generate_on_ready = false
	root.add_child(sample)
	assert(sample.generate_creature())
	assert(sample.get_node("GeneratedParts/Leg_1_Limb_1").get_meta("generated_scene_path").ends_with("LeftLeg/03_lower_leg.tscn"))
	assert(sample.get_node("GeneratedParts/Leg_2_Limb_3").get_meta("generated_scene_path").ends_with("RightLeg/01_upper_leg.tscn"))
	assert(sample.get_node("StumpBeastGenerator").scene_file_path.is_empty())
	var scene_state := PackedScene.new()
	assert(scene_state.pack(sample) == OK)
	var saved_sample := scene_state.instantiate() as Node3D
	var stored_part := saved_sample.get_node("GeneratedParts/Leg_1_Limb_1") as PhysicalBodyPart3D
	stored_part.prepare_generated_geometry()
	assert(GEOMETRY.bounds(stored_part).size.is_equal_approx(sample.get_node("GeneratedParts/Leg_1_Limb_1").get_meta("generated_size")), "Saved generated geometry must retain fitting")
	saved_sample.free()
	sample.free()
	print("GENERATED_PART_SCENES_VALIDATION_PASSED")
	quit()
