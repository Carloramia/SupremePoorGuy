extends SceneTree
const DATA = preload("res://Scripts/Creatures/LegMovementData.gd")
const CONSTRAINT = preload("res://Scripts/Creatures/SegmentConstraint3D.gd")
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
var failed := false
func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var data = DATA.new()
	data.automatic_motion = true
	data.target_speed = 1.5
	data.turning_speed_degrees = 30.0
	var small: Dictionary = data.calculate_motion_profile(2.0, 2.0, 6)
	var large: Dictionary = data.calculate_motion_profile(5.0, 3.0, 6)
	check(small.stride < large.stride, "Each leg must receive a stride matching its own reach")
	check(small.swing_duration / small.cycle <= 0.5, "Automatic cadence must fit support duty")
	check(absf(large.stride / large.cycle - large.reachable_speed) < 0.001, "Reachable speed must equal stride divided by foot period")
	data.target_speed = 0.0
	check(data.calculate_motion_profile(5.0, 3.0, 6).frequency == 0.0, "Zero speed must disable gait scheduling")
	data.target_speed = 1.5
	var fixture := Node3D.new()
	root.add_child(fixture)
	var a := RigidBody3D.new()
	a.name = "A"
	a.freeze = true
	fixture.add_child(a)
	var b := RigidBody3D.new()
	b.name = "B"
	b.position.x = 2.0
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	b.add_child(collision)
	fixture.add_child(b)
	var joint = CONSTRAINT.new()
	joint.node_a = NodePath("../A")
	joint.node_b = NodePath("../B")
	joint.position.x = 1.0
	for axis: String in ["x", "y", "z"]:
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, axis != "x")
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.05)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.05)
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, axis != "z")
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	fixture.add_child(joint)
	await physics_frame
	b.apply_central_impulse(Vector3(2, 2, 2))
	for frame: int in range(180): await physics_frame
	var diagnostic: Dictionary = joint.get_constraint_diagnostics()
	print("CONSTRAINT_TEST ", diagnostic)
	check(diagnostic.axial_free and diagnostic.transverse_locked and diagnostic.locked_xy and diagnostic.z_free, "Constraint must preserve spring translation and free Z rotation")
	check(diagnostic.transverse_excess.length() < 0.025, "Y/Z anchor drift must be bounded under normal gravity and transverse impulse")
	check(absf(diagnostic.anchor_gap_local.x) > 0.2, "Axial motion must remain free")
	check(diagnostic.locked_xy_error_degrees.length() < 2.0, "Locked angular axes must hold")
	fixture.queue_free()
	var ground := StaticBody3D.new()
	var ground_shape := CollisionShape3D.new()
	var ground_box := BoxShape3D.new()
	ground_box.size = Vector3(200, 1, 200)
	ground_shape.shape = ground_box
	ground.add_child(ground_shape)
	ground.position.y = -0.5
	root.add_child(ground)
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.rear_leg_count = maxi((6) - 2, 0)
	generator.foreleg_count = mini((6), 2)
	generator.unsymmetrie = 60.0
	generator.overall_scale = 4.0
	generator.neck_number = 0

	generator._random.seed = 43
	check(actor.generate_creature(), "Generated fixture must build")
	var controller = actor.get_node("GeneratedLegStepMovementController3D")
	controller.slow_gait_data = data
	for frame: int in range(3): await physics_frame
	var motion: Dictionary = controller.get_automatic_motion_diagnostics()
	check(motion.enabled and motion.legs.size() == 6, "Automatic profiles must cover all generated feet")
	for profile: Dictionary in motion.legs:
		check(profile.length > 1.0 and profile.position_gain > 0.0, "Generated chain length must determine the automatic force profile")
	var constraints: Array = controller.get_stance_support_diagnostics().segment_rotation_constraints
	check(constraints.size() > 0, "Generated segment springs need audited transverse constraints")
	for entry: Dictionary in constraints:
		check(entry.transverse_locked and entry.axial_free, "Generated joint must limit only transverse translation")
	for frame: int in range(300): await physics_frame
	var start_position: Vector3 = controller._torso.global_position
	var maximum_steps := 0
	Input.action_press("Right")
	for frame: int in range(480):
		await physics_frame
		maximum_steps = maxi(maximum_steps, controller._active_steps.size())
		check(controller._active_steps.size() <= 3, "Automatic support ratio must retain at least half the feet")
		for foot: RigidBody3D in controller.get_leg_parts():
			check(controller.get_support_foot_diagnostics(foot).step_tracking_force.is_finite(), "Automatic tracking force must stay finite")
	Input.action_release("Right")
	var displacement: Vector3 = controller._torso.global_position - start_position
	print("AUTOMATIC_WALK displacement=", displacement, " maximum_steps=", maximum_steps, " failures=", controller._failed_step_count)
	check(displacement.x > 0.5 and maximum_steps >= 1, "Automatic gait must actually walk under normal gravity")
	check(absf(displacement.y) < 2.0 and absf(displacement.z) < 2.0, "Automatic gait must not launch or drift excessively")
	var turn_start: float = controller._segment_target_yaw
	controller._segment_goal_yaw = turn_start + deg_to_rad(45.0)
	for frame: int in range(120): await physics_frame
	var turn_advance: float = absf(wrapf(controller._segment_target_yaw - turn_start, -PI, PI))
	print("AUTOMATIC_TURN target_advance_degrees=", rad_to_deg(turn_advance), " status=", controller._layout_turn_status)
	check(turn_advance <= deg_to_rad(data.turning_speed_degrees * 2.0 + 1.0), "Heading reference must respect the requested turn speed")
	check(turn_advance > deg_to_rad(1.0), "Automatic turn reference must advance")
	actor.segment_rotation_constraints_enabled = false
	for entry: Dictionary in controller.get_stance_support_diagnostics().segment_rotation_constraints:
		check(not entry.locked_xy and entry.transverse_locked, "Linear and angular switches must be independent")
	check(not actor.zero_gravity_test_mode, "Normal gravity must be the default")
	print("AUTOMATIC_PROFILES ", motion)
	actor.queue_free()
	await process_frame
	print("AUTOMATIC_MOTION_CONSTRAINTS_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
