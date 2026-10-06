extends SceneTree

const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
var failed: bool = false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	collision.shape = shape
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var character := CHARACTER.instantiate()
	character.generate_on_ready = false
	root.add_child(character)
	var generator := character.get_node("CreatureGenerator")
	generator.rear_leg_count = maxi((6) - 2, 0)
	generator.foreleg_count = mini((6), 2)
	generator.unsymmetrie = 60.0
	generator.overall_scale = 4.0
	generator.neck_number = 0

	var generated := false
	for seed_value: int in range(43, 49):
		generator._random.seed = seed_value
		if character.generate_creature():
			generated = true
			break
	check(generated, "Six-foot generation failed")
	if not generated:
		quit(1)
		return
	var controller := character.get_node("GeneratedLegStepMovementController3D")
	var hinges := 0
	for foot: RigidBody3D in controller.get_leg_parts():
		var chain: Dictionary = controller._chains[foot]
		for index: int in range(1, chain.bodies.size() - 2):
			var joint: Generic6DOFJoint3D = chain.joints[index]
			hinges += 1
			check(joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT) and joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT), "Hinge X/Y limits must be enabled")
			check(is_zero_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)) and is_zero_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)), "Hinge X must be locked")
			check(is_zero_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)) and is_zero_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)), "Hinge Y must be locked")
			check(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT) > 0.0, "Hinge Z must remain available")
	check(hinges > 0, "Test must include LegLimb pairs")
	for frame: int in range(300): await physics_frame
	var initial: Vector3 = controller._torso.global_position
	var lifted := false
	var successful := 0
	var previous_touchdown: float = controller._last_touchdown_time
	var observed_force := false
	Input.action_press("Right")
	for frame: int in range(480):
		await physics_frame
		if controller._last_touchdown_time > previous_touchdown:
			successful += 1
			previous_touchdown = controller._last_touchdown_time
		var foot = controller.get_active_leg()
		if foot != null:
			var diagnostic: Dictionary = controller.get_support_foot_diagnostics(foot)
			lifted = lifted or diagnostic.step_has_lifted
			observed_force = observed_force or diagnostic.step_tracking_force.length() > 1.0
			check(diagnostic.step_tracking_force.is_finite(), "Tracking force must remain finite")
			check(diagnostic.step_tracking_force.length() <= diagnostic.step_force_limit + 0.01, "Tracking force exceeded cap")
			check(diagnostic.step_effective_mass >= foot.mass, "Drive must include foot mass")
	Input.action_release("Right")
	var displacement: Vector3 = controller._torso.global_position - initial
	print("[step_drive_test] displacement=%s successful=%d failed=%d lifted=%s force=%s" % [displacement, successful, controller._failed_step_count, lifted, observed_force])
	check(displacement.x > 0.5, "Six-foot Right input must produce substantial forward motion")
	check(absf(displacement.y) < 1.0 and absf(displacement.z) < 1.0, "Walking must not launch or drift excessively")
	check(lifted and successful > 1 and observed_force, "Actual lift and successful arrivals must occur")
	# A blocked foot must advance the selection, without incrementing successful touchdown statistics.
	controller.set_physics_process(false)
	controller.cancel_step()
	controller._active_leg = controller.get_leg_parts()[0]
	controller._step_state = controller.StepState.LANDING
	controller._step_has_lifted = false
	controller._current_step.extra["resource_step"] = false
	var previous_time: float = controller._last_touchdown_time
	var previous_index: int = controller._next_leg_index
	var failures: int = controller._failed_step_count
	controller._handle_step_timeout(true)
	check(controller._last_touchdown_time == previous_time, "Timeout must not record successful touchdown")
	check(controller._failed_step_count == failures + 1, "Timeout must record failure")
	check(controller._last_step_failure == &"step_never_lifted", "Failure must distinguish feet that never lifted")
	check(controller._next_leg_index == (previous_index + 1) % 6, "Failure must let another foot attempt movement")
	check(not controller._is_step_target_reached(true), "A foot that never lifted cannot complete a generated step")
	controller._step_has_lifted = true
	check(not controller._is_step_target_reached(false), "A lifted foot still has to reach its target")
	check(controller._is_step_target_reached(true), "A lifted foot at target can complete")
	character.queue_free()
	ground.queue_free()
	await process_frame
	print("GENERATED_STEP_DRIVE_VALIDATION_%s" % ("FAILED" if failed else "PASSED"))
	quit(1 if failed else 0)
