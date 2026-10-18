extends SceneTree
const SCENE = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
var failed := false

func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var actor = SCENE.instantiate()
	actor.generate_on_ready = false
	actor.planar_constraints_enabled = false
	check(not actor.zero_gravity_test_mode, "Normal mode must retain gravity by default")
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.rear_leg_count = 4
	generator.foreleg_count = 2
	generator.unsymmetrie = 0.0
	generator.overall_scale = 1.0
	generator.neck_number = 0
	generator._random.seed = 43
	if not actor.generate_creature():
		check(false, "Generate the zero-gravity fixture")
		actor.queue_free()
		quit(1)
		return
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	var parts: Array = actor._get_physical_body_parts()
	var original_scales := {}
	for body: RigidBody3D in parts: original_scales[body] = body.gravity_scale
	actor.zero_gravity_test_mode = true
	for body: RigidBody3D in parts: check(body.gravity_scale == 0.0, "Opt-in mode disables every generated body's gravity")
	check(movement.simplified_physics_mode and movement._gravity_acceleration().is_zero_approx(), "Opt-in mode bypasses gravity compensation")
	check(not movement.recovery_control_active, "Zero-gravity test must not run ground recovery")
	await physics_frame
	await physics_frame
	var diagnostic: Dictionary = movement.get_stance_support_diagnostics()
	check(diagnostic.zero_gravity_test_mode and not diagnostic.stance_enabled, "Diagnostics identify passive simplified control")
	actor.zero_gravity_test_mode = false
	for body: RigidBody3D in parts: check(body.gravity_scale == original_scales[body], "Turning mode off restores the authored gravity scale")
	check(not movement.simplified_physics_mode and not movement._gravity_acceleration().is_zero_approx(), "Normal controller gravity is restored")
	var saved = SCENE.instantiate()
	saved.generate_on_ready = false
	saved.planar_constraints_enabled = false
	saved.zero_gravity_test_mode = true
	root.add_child(saved)
	check(not saved._get_physical_body_parts().is_empty(), "Saved assembly fixture has parts")
	for body: RigidBody3D in saved._get_physical_body_parts(): check(body.gravity_scale == 0.0, "Saved assemblies also honor explicit opt-in")
	actor.queue_free()
	saved.queue_free()
	await process_frame
	print("ZERO_GRAVITY_SEGMENTS_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
