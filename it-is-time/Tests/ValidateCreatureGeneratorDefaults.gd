extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var script_path := "res://Scripts/Creatures/CreatureGenerator.gd"
	var original := FileAccess.get_file_as_string(script_path)
	var generator := (load(script_path) as GDScript).new() as Node3D
	var initial_rear_count: int = generator.rear_leg_count
	var found_button := false
	for property: Dictionary in generator.get_property_list():
		if property.name == &"save_defaults_button":
			found_button = property.hint_string.contains("将当前参数写为脚本默认值")
	assert(found_button)
	assert(original.contains('@export_group("Torso Generation")'))
	generator.rear_leg_count = maxi((8) - 2, 0)
	generator.foreleg_count = mini((8), 2)
	generator.label_font_size = 64
	generator.part_width = 0.35

	generator.limb_endpoint_merge_distance = 0.55
	generator.network_extra_endpoint_count = 7
	generator.network_extra_endpoint_padding = 0.8


	generator.torso_connection_distance = 0.25
	generator.torso_overlap_percent = 25.0
	generator.body_length = 8.0
	generator.torso_count = 4
	generator.neck_segment_count = 0

	generator.unsymmetrie = 37.5
	generator.inhomogeneity = 64.0

	generator.wireframe_color = Color(0.12, 0.34, 0.56, 0.78)
	generator.base_limb_length = 3.75
	generator.limb_minimum_size = Vector3(0.35, 0.5, 0.25)
	generator.limb_maximum_size = Vector3(0.6, 0.9, 0.45)
	var source: String = generator._build_default_source(original)
	assert(not source.is_empty() and source != original)
	assert(source.contains("var label_font_size: int = 64:"), "Saving defaults must preserve the setter colon")
	assert(source.contains("func _generate_limb_blocks("))
	assert(source.contains('@export_tool_button("生成随机框架", "Node3D") var generate_torso_button: Callable = generate_torso'))
	assert(source.contains("var save_defaults_button: Callable = save_current_parameters_as_defaults"))
	assert(generator._build_default_source(source) == source, "Repeated saves must be idempotent")
	var commented: String = generator._build_default_source(original.replace("var rear_leg_count: int = %d" % initial_rear_count, "var rear_leg_count: int = %d # keep comment" % initial_rear_count))
	assert(commented.contains("var rear_leg_count: int = 6 # keep comment"))
	var test_path := "res://Tests/.creature_generator_defaults.gd"
	assert(not FileAccess.file_exists(test_path))
	assert(generator._write_default_source(test_path, source))
	assert(FileAccess.get_file_as_string(test_path) == source)
	var candidate := GDScript.new()
	candidate.source_code = FileAccess.get_file_as_string(test_path)
	assert(candidate.reload() == OK)
	var restored := candidate.new() as Node3D
	for property: Dictionary in generator.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_EDITOR) != 0 and property.type in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_VECTOR3, TYPE_COLOR]:
			var current: Variant = generator.get(property.name)
			var saved: Variant = restored.get(property.name)
			if current is float:
				assert(is_equal_approx(current, saved), str(property.name))
			elif current is Vector3 or current is Color:
				assert(current.is_equal_approx(saved), str(property.name))
			else:
				assert(current == saved, str(property.name))
	assert(FileAccess.get_file_as_string(script_path) == original, "Testing must not change real defaults")
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path)) == OK)
	generator.free()
	restored.free()
	print("CREATURE_GENERATOR_DEFAULTS_VALIDATION_PASSED")
	quit()
