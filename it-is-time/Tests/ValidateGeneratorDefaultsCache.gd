extends SceneTree

const BASE = preload("res://Scripts/Creatures/Generators/BaseCreatureGenerator.gd")
const STUMP = preload("res://Scripts/Creatures/Generators/StumpBeastGenerator.gd")
const BEAST = preload("res://Scripts/Creatures/Generators/BeastGenerator.gd")
const BIRD = preload("res://Scripts/Creatures/Generators/BirdGenerator.gd")
const DATA = preload("res://Scripts/Creatures/Generators/CreatureGeneratorDefaults.gd")

class TestGenerator extends BASE:
	var defaults_path: String = ""
	func _get_defaults_path() -> String: return defaults_path

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var source := STUMP.new()
	var beast := BEAST.new()
	var bird := BIRD.new()
	assert(source._get_default_preset() != beast._get_default_preset())
	assert(source._get_default_preset() != bird._get_default_preset())
	var path := "res://Tests/.generator_cache_validation.tres"
	assert(source._save_default_preset(path))
	var first := TestGenerator.new()
	var second := TestGenerator.new()
	first.defaults_path = path
	second.defaults_path = path
	first._apply_default_preset()
	second._apply_default_preset()
	var cached := first._get_default_preset()
	assert(cached == second._get_default_preset())
	for index: int in range(500):
		assert(first._get_default_preset() == cached)
		assert(first._property_can_revert(&"body_length"))
		assert(first._property_get_revert(&"body_length") == source.body_length)
	first.part_scene_rules[0].size_multiplier = 1.7
	first.torso_upper_curve.set_point_right_tangent(0,0.75)
	assert(second.part_scene_rules[0].size_multiplier == 1.0)
	assert(cached.parameters.part_scene_rules[0].size_multiplier == 1.0)
	assert(cached.parameters.torso_upper_curve.get_point_right_tangent(0) != 0.75)
	var revert_rules: Array = first._property_get_revert(&"part_scene_rules")
	revert_rules[0].size_multiplier = 3.0
	assert(cached.parameters.part_scene_rules[0].size_multiplier == 1.0)
	var notifications := {"count":0}
	second.property_list_changed.connect(func(): notifications.count += 1)
	# Saving through one instance updates the other instance's revert value, not its live settings.
	first.body_length = 6.25
	second.body_length = 4.5
	assert(first._save_default_preset(path))
	assert(first._get_default_preset() == cached)
	assert(second._property_get_revert(&"body_length") == 6.25)
	assert(second.body_length == 4.5)
	assert(notifications.count > 0)
	# Simulate an external file edit and the real editor resource reload callback.
	var external := DATA.new()
	external.parameters = source._capture_default_parameters()
	external.parameters.body_length = 8.75
	assert(ResourceSaver.save(external,path) == OK)
	first._on_defaults_resources_changed(PackedStringArray([path]))
	assert(first._property_get_revert(&"body_length") == 8.75)
	assert(second._property_get_revert(&"body_length") == 8.75)
	assert(first.body_length == 6.25 and second.body_length == 4.5)
	# Filesystem scans do not reload unchanged snapshots; deletion disables revert controls.
	first._on_defaults_filesystem_changed()
	assert(first._get_default_preset() == cached)
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
	first._on_defaults_filesystem_changed()
	assert(not first._property_can_revert(&"body_length"))
	assert(first._property_get_revert(&"body_length") == null)
	# A recreated file and a changed path must recover without replacing live values.
	assert(ResourceSaver.save(external,path) == OK)
	first._on_defaults_filesystem_changed()
	assert(first._property_get_revert(&"body_length") == 8.75)
	first.defaults_path = source._get_defaults_path()
	assert(first._get_default_preset() == source._get_default_preset())
	assert(first.body_length == 6.25)
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
	for instance: Node in [source,beast,bird,first,second]: instance.free()
	print("GENERATOR_DEFAULTS_CACHE_VALIDATION_PASSED")
	quit()
