extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
var failed: bool = false
func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ground := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	collider.shape = shape
	ground.add_child(collider)
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
	generator.neck_number = 1

	var generated := false
	for seed_value: int in range(43, 49):
		generator._random.seed = seed_value
		if character.generate_creature():
			generated = true
			break
	if not generated:
		push_error("Could not generate a dense six-foot fixture")
		quit(1)
		return
	var controller := character.get_node("GeneratedLegStepMovementController3D")
	var count: int = character._get_physical_body_parts().size()
	for frame: int in range(600): await physics_frame
	var start: Vector3 = controller._torso.global_position
	Input.action_press("Right")
	var largest_force := 0.0
	var moving_rows := 0
	for frame: int in range(900):
		await physics_frame
		var diagnostic: Dictionary = controller.get_contact_drive_diagnostics()
		largest_force = maxf(largest_force, Vector3(diagnostic.get("applied_force", Vector3.ZERO)).length())
		for row: Dictionary in diagnostic.get("legs", []):
			check(not str(row.driver).begins_with("Torso") and not str(row.driver).begins_with("SubTorso"), "Generated drive must act through the leg chain")
			moving_rows += 1
	Input.action_release("Right")
	var distance: float = controller._torso.global_position.x - start.x
	print("CONTACT_DRIVE distance=", distance, " force=", largest_force, " allocations=", moving_rows, " recovery=", controller.recovery_control_active)
	check(distance > 0.5 and largest_force > 0.0, "Contact traction must actually move the generated creature")
	controller.set_physics_process(false)
	controller._reset_contact_drive_diagnostics()
	var stepping: RigidBody3D = controller._legs[0]
	controller._current_step.leg = stepping
	controller._step_state = controller.StepState.MOVING
	check(controller._apply_contact_drive([stepping], Vector3(100, 0, 0), 10.0, Vector3.UP).is_zero_approx(), "An explicitly stepping foot must reject drive allocation")
	controller.cancel_step()
	for body: RigidBody3D in character._get_physical_body_parts(): body.global_position.y += 50.0
	controller._begin_ground_probe_frame()
	controller._reset_contact_drive_diagnostics()
	controller.set_contact_force_request(Vector3(1000, 500, 0))
	controller._apply_torso_response()
	check(Vector3(controller.get_contact_drive_diagnostics().applied_force).is_zero_approx(), "Airborne feet must reject even an explicit force request")
	controller.clear_contact_force_request()
	controller.set_recovery_control_active(true)
	controller._physics_process(1.0 / 60.0)
	check(Vector3(controller.get_contact_drive_diagnostics().applied_force).is_zero_approx(), "Recovery must disable contact movement demand")
	var console := root.get_node("RuntimeConsole")
	var lines: Array = console._collect_leg_motion_lines(controller)
	check(not lines.is_empty(), "Existing leg diagnostic output must remain available")
	print("CONTACT_DRIVE_VALIDATION_", "FAILED" if failed else "PASSED")
	character.queue_free()
	ground.queue_free()
	quit(1 if failed else 0)
