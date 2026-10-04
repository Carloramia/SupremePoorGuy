@tool
extends Node
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
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
	check(is_instance_valid(actor._control_perf), "Editor must initialize a real statistics object")
	check(not actor._control_perf.enabled, "Editor must not activate runtime tracking automatically")
	# Simulate an uninitialized member on a live tool instance.
	actor._control_perf = null
	actor.set_control_performance_tracking_enabled(true)
	check(is_instance_valid(actor._control_perf), "Statistics must recover after initialization loss")
	var generator := actor.get_node("CreatureGenerator")
	generator.feets = 4
	generator.unsymmetrie = 0.0
	generator.overall_scale = 1.0
	generator.neck_number = 0
	generator.torso_core_extra_blocks = 0
	generator._random.seed = 42
	check(actor.generate_creature(), "Editor tool generation must succeed")
	var stats: Dictionary = actor.consume_control_performance_stats()
	check(stats.timings.has("generation_total") and stats.timings.has("physics_assembly"), "Editor must be able to call timing methods")
	check(stats.counters.get("generated_parts", 0) > 0, "Editor must be able to call counting methods")
	actor.set_control_performance_tracking_enabled(false)
	actor._control_perf.count(&"disabled")
	check(actor.consume_control_performance_stats().counters.is_empty(), "Disabled tracking must remain inert")
	if not failed: print("GENERATED_EDITOR_PERFORMANCE_VALIDATION_PASSED")
	get_tree().quit(1 if failed else 0)
