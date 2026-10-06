extends SceneTree
const BEAST = preload("res://Scripts/Creatures/Generators/BeastGenerator.gd")
const BIRD = preload("res://Scripts/Creatures/Generators/BirdGenerator.gd")
const DATA = preload("res://Scripts/Creatures/Generators/CreatureGeneratorDefaults.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var beast := BEAST.new()
	var bird := BIRD.new()
	var base_path := "res://Scripts/Creatures/Generators/BaseCreatureGenerator.gd"
	var original := FileAccess.get_file_as_string(base_path)
	var bird_file := FileAccess.get_file_as_string(bird._get_defaults_path())
	assert(beast._get_defaults_path()!=bird._get_defaults_path())
	beast.body_length = 7.25
	beast.sub_torso_x_offset = -0.25
	beast.rear_leg_count = 8
	beast.torso_upper_curve.set_point_right_tangent(0,0.75)
	var path := "res://Tests/.generator_defaults_test.tres"
	assert(beast._save_default_preset(path))
	var saved := load(path) as DATA
	assert(saved.parameters.body_length==7.25 and saved.parameters.rear_leg_count==8)
	assert(saved.parameters.sub_torso_x_offset==-0.25)
	assert(saved.parameters.torso_upper_curve.get_point_right_tangent(0)==0.75)
	assert(saved.parameters.torso_upper_curve!=beast.torso_upper_curve)
	# Simulate cache refresh without changing the real preset files.
	var beast_preset := load(beast._get_defaults_path()) as DATA
	var original_parameters := beast_preset.parameters
	beast_preset.parameters = saved.parameters
	var restored_beast := BEAST.new()
	var unchanged_bird := BIRD.new()
	assert(restored_beast.body_length==7.25 and restored_beast.rear_leg_count==8)
	assert(restored_beast.property_get_revert(&"body_length")==7.25)
	assert(unchanged_bird.body_length==bird.body_length)
	assert(unchanged_bird.wing_tip_length==bird.wing_tip_length)
	restored_beast.torso_upper_curve.set_point_right_tangent(0,1.25)
	assert(beast_preset.parameters.torso_upper_curve.get_point_right_tangent(0)==0.75)
	beast_preset.parameters = original_parameters
	# Scene overrides remain authoritative over species defaults.
	var scene := PackedScene.new()
	assert(scene.pack(beast)==OK)
	var restored_scene := scene.instantiate()
	assert(restored_scene.body_length==7.25 and restored_scene.sub_torso_x_offset==-0.25)
	assert(FileAccess.get_file_as_string(base_path)==original)
	assert(FileAccess.get_file_as_string(bird._get_defaults_path())==bird_file)
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(path))==OK)
	for instance: Node in [beast,bird,restored_beast,unchanged_bird,restored_scene]: instance.free()
	print("CREATURE_GENERATOR_DEFAULTS_VALIDATION_PASSED")
	quit()
