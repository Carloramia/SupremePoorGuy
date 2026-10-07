@tool
extends Node
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	check(Engine.is_editor_hint(), "Run this scene with --editor")
	var actor := CHARACTER.instantiate()
	actor.generate_on_ready = false
	add_child(actor)
	check(actor.generate_character_button.is_valid(), "Beast inspector button must bind to a valid method")
	check(is_instance_valid(actor._control_perf), "Editor must initialize a real statistics object")
	check(not actor._control_perf.enabled, "Editor must not activate runtime tracking automatically")
	# Simulate an uninitialized member on a live tool instance.
	actor._control_perf = null
	actor.set_control_performance_tracking_enabled(true)
	check(is_instance_valid(actor._control_perf), "Statistics must recover after initialization loss")
	var generator := actor.get_node("CreatureGenerator")
	generator.rear_leg_count = maxi((4) - 2, 0)
	generator.foreleg_count = mini((4), 2)
	generator.unsymmetrie = 0.0
	generator.overall_scale = 1.0
	generator.neck_number = 0

	generator._random.seed = 42
	check(actor.generate_creature(), "Editor tool generation must succeed")
	var stats: Dictionary = actor.consume_control_performance_stats()
	check(stats.timings.has("generation_total") and stats.timings.has("physics_assembly"), "Editor must be able to call timing methods")
	check(stats.counters.get("generated_parts", 0) > 0, "Editor must be able to call counting methods")
	actor.set_control_performance_tracking_enabled(false)
	actor._control_perf.count(&"disabled")
	check(actor.consume_control_performance_stats().counters.is_empty(), "Disabled tracking must remain inert")
	var bird := preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn").instantiate()
	bird.generate_on_ready = false
	add_child(bird)
	var bird_generator := bird.get_node("BirdGenerator")
	check(bird_generator.scene_file_path.is_empty(), "Bird generator must be local, not a nested scene with duplicate previews")
	var template := preload("res://Scenes/Creatures/Generators/BirdGenerator.tscn").instantiate()
	for property: Dictionary in template.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or int(property.usage) & PROPERTY_USAGE_STORAGE == 0: continue
		var name: StringName = property.name
		var expected: Variant = template.get(name)
		var actual: Variant = bird_generator.get(name)
		# Character-local scale is intentionally editable independently of the template.
		if name == &"overall_scale":
			check(is_finite(float(actual)) and float(actual)>0.0,"Bird local scale must stay valid")
			continue
		if expected is Callable: continue
		if expected is Curve:
			check(actual is Curve, "Bird curve must be preserved: " + str(name))
			if actual is Curve:
				for sample: int in range(11):
					check(is_equal_approx(expected.sample(float(sample)/10.0),actual.sample(float(sample)/10.0)), "Bird curve values must be preserved: " + str(name))
		else: check(expected == actual, "Bird generator parameter must be preserved: " + str(name))
	template.free()
	check(typeof(bird.mass_limits_enabled)==TYPE_BOOL, "Editor must read the inherited mass-limit switch")
	check(bird.generate_character_button.is_valid(), "Bird inspector button must bind to a valid method")
	check(bird.generate_character_button.call(), "Bird inspector button must generate with its tool wing controller")
	await get_tree().process_frame
	check(not bird.get_node("WingPoseController3D").bindings.is_empty(), "Editor generation must refresh wing bindings without calling placeholder scripts")
	check(not bird.get_node("WingPoseController3D").feather_bindings.is_empty(), "Editor character generation must include physical feather bindings")
	check(bird_generator.has_node("Feets/Leg_1") and bird_generator.has_node("Feets/Leg_2"), "Original framework paths must remain usable")
	# This fixture edits an outer test scene. Transfer only externally owned output
	# to the bird before packing it as a standalone scene, preserving nested parts.
	for node: Node in bird.find_children("*", "", true, false):
		if node.owner != null and node.owner != bird and not bird.is_ancestor_of(node.owner): node.owner = bird
	var packed := PackedScene.new()
	check(packed.pack(bird)==OK, "Generated bird must remain saveable")
	var restored := packed.instantiate()
	check(restored.get_node("BirdGenerator").scene_file_path.is_empty(), "Saved bird must retain a local generator")
	check(restored.get_node("BirdGenerator").get_node_or_null("Feets") != null, "Saved framework must survive a scene round trip")
	restored.free()
	if not failed: print("GENERATED_EDITOR_PERFORMANCE_VALIDATION_PASSED")
	get_tree().quit(1 if failed else 0)
