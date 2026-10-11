extends SceneTree

const DIAGNOSTICS = preload("res://Scripts/Debug/JointMotionDiagnostics3D.gd")

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var actor := Node3D.new()
	actor.name = "JointDiagnosticFixture"
	root.add_child(actor)
	var a := RigidBody3D.new()
	var b := RigidBody3D.new()
	a.name = "A"
	b.name = "B"
	a.freeze = true
	b.freeze = true
	actor.add_child(a)
	actor.add_child(b)
	b.position = Vector3(1, 0, 0)
	var joint := Generic6DOFJoint3D.new()
	joint.name = "Joint"
	actor.add_child(joint)
	joint.node_a = joint.get_path_to(a)
	joint.node_b = joint.get_path_to(b)
	joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
	joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
	DIAGNOSTICS.capture_activation(actor)
	var row := DIAGNOSTICS.collect(joint)
	assert(row.reference_source == "activation_snapshot")
	assert(row.relative_euler_xyz_degrees.length() < 0.001)
	assert(row.anchor_gap < 0.001)
	actor.rotation = Vector3(0.2, 0.8, -0.3)
	row = DIAGNOSTICS.collect(joint)
	assert(row.relative_euler_xyz_degrees.length() < 0.001, "Whole character rotation must not count as joint rotation")
	b.rotation.y = deg_to_rad(10.0)
	row = DIAGNOSTICS.collect(joint)
	assert(absf(row.relative_euler_xyz_degrees.y - 10.0) < 0.001)
	assert(absf(row.relative_euler_yxz_degrees.y - 10.0) < 0.001)
	assert(row.limits.y.angular_enabled and row.limits.y.angular_upper_degrees == 0.0)
	assert(not row.solver_angles_available)
	joint.set_meta(&"generated_joint_frame_a", Transform3D(Basis(Vector3.UP, 0.3), Vector3.ZERO))
	joint.set_meta(&"generated_joint_frame_b", Transform3D.IDENTITY)
	row = DIAGNOSTICS.collect(joint)
	assert(row.saved_vs_activation_a.rotation_degrees > 17.0)
	var controller := Node.new()
	controller.name = "Movement"
	actor.add_child(controller)
	controller.add_to_group(&"leg_step_movement_controllers")
	var console := root.get_node("RuntimeConsole")
	assert("trackjoints" in console.execute_command("help"))
	assert("jointstates" in console.execute_command("help"))
	assert(console.execute_command("jointstates JointDiagnosticFixture") == "Joint snapshots: 1")
	assert(console.execute_command("jointstates nonexistent") == "Joint snapshots: 0")
	assert("joints=1" in console.execute_command("trackjoints on JointDiagnosticFixture"))
	var previous_lines: int = console.get("_output_lines").size()
	console._process(0.2)
	assert(console.get("_output_lines").size() == previous_lines, "Repeated physics frame must not produce duplicate joint samples")
	assert(console.execute_command("trackjoints invalid").begins_with("Usage:"))
	assert(console.execute_command("trackjoints off").begins_with("Joint tracking disabled"))
	joint.remove_meta(&"diagnostic_activation_frames")
	assert(DIAGNOSTICS.collect(joint).reference_source == "saved_generated_frames")
	joint.remove_meta(&"generated_joint_frame_a")
	assert(DIAGNOSTICS.collect(joint).reference_source == "unavailable")
	joint.node_b = NodePath("../Missing")
	assert(not DIAGNOSTICS.collect(joint).valid_endpoints)
	actor.free()
	var wolf := load("res://Scenes/Creatures/Characters/Generate_Wolf.tscn").instantiate() as Node3D
	wolf.set("generate_on_ready", false)
	root.add_child(wolf)
	var joints := wolf.find_children("*", "Generic6DOFJoint3D", true, false)
	assert(not joints.is_empty())
	for saved_joint: Generic6DOFJoint3D in joints:
		assert(DIAGNOSTICS.collect(saved_joint).reference_source == "activation_snapshot", "Saved Wolf joints must capture a runtime reference before simulation")
	wolf.free()
	print("JOINT_MOTION_DIAGNOSTICS_PASS")
	quit()
