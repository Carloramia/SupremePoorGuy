extends SceneTree
const SCENE = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var actor = SCENE.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.rear_leg_count = maxi((6) - 2, 0)
	generator.foreleg_count = mini((6), 2)
	generator.unsymmetrie = 0.0
	generator.overall_scale = 4.0
	generator.neck_number = 0

	generator._random.seed = 43
	check(actor.generate_creature(), "Generation must succeed")
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	var recovery = actor.get_node("CreatureRecoveryStateMachine3D")
	var parts: Array = actor._get_physical_body_parts()
	var center := Vector3.ZERO
	var mass := 0.0
	for body: RigidBody3D in parts:
		check(body.gravity_scale == 0.0, "Every generated body must disable gravity")
		center += body.global_position * body.mass
		mass += body.mass
	center /= mass
	for frame: int in range(180): await physics_frame
	var after := Vector3.ZERO
	for body: RigidBody3D in parts: after += body.global_position * body.mass / mass
	check(after.distance_to(center) < 0.05, "Ungrounded zero-gravity assembly must not fall or receive artificial lift")
	check(not movement.recovery_control_active and recovery.state == recovery.State.STANDING, "Gravity test must bypass recovery")
	check(movement._gravity_acceleration().is_zero_approx(), "Controllers must not compensate disabled gravity")
	var locks: Array[Generic6DOFJoint3D] = []
	var springs: Array = []
	for node: Node in actor.get_node("GeneratedParts/Joints").get_children():
		if node.has_meta(&"segment_rotation_constraint"): locks.append(node)
		if node.has_method("is_segment_spring"): springs.append(node)
	check(locks.size() == springs.size() and locks.size() > 0, "Every cross-segment spring needs one angular constraint")
	for joint: Generic6DOFJoint3D in locks:
		for axis: String in ["x", "y", "z"]:
			check(not joint.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT), "Translation must stay free")
			check(not joint.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING), "No second translation spring")
			check(bool(joint.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT)) == (axis != "z"), "Only X/Y rotation is locked")
	# Displace and rotate an entire rigid segment: radial spring returns translation,
	# angular constraints remove relative X/Y motion without anchoring the whole creature.
	var selected = springs[0]
	var endpoint: RigidBody3D = selected.get_node(selected.node_a)
	var segment: int = endpoint.get_meta("body_segment_id")
	var torso_group: Array[RigidBody3D] = []
	for body: RigidBody3D in movement.get_torso_parts():
		if int(body.get_meta("body_segment_id", -1)) == segment: torso_group.append(body)
	for body: RigidBody3D in torso_group:
		body.apply_torque_impulse(Vector3(body.mass * 2, body.mass * 2, 0))
		body.apply_central_impulse(Vector3(body.mass * 2, 0, 0))
	var initial_distance: float = selected.rest_distance
	var peak_extension := 0.0
	for frame: int in range(300):
		await physics_frame
		peak_extension = maxf(peak_extension, absf(selected.last_distance - initial_distance))
	var a: RigidBody3D = selected.get_node(selected.node_a)
	var b: RigidBody3D = selected.get_node(selected.node_b)
	check(absf(wrapf(a.global_rotation.y - b.global_rotation.y, -PI, PI)) < 0.1, "Relative yaw must remain locked")
	check(absf(wrapf(a.global_rotation.x - b.global_rotation.x, -PI, PI)) < 0.1, "Relative X rotation must remain locked")
	var diagnostics: Dictionary = movement.get_stance_support_diagnostics()
	check(diagnostics.zero_gravity_test_mode and not diagnostics.auto_allocation, "Trackmotion must identify simplified control")
	check(diagnostics.segment_rotation_constraints.size() == locks.size(), "Trackmotion must report all angular-only links")
	# Saved assemblies must receive the same mode without regeneration.
	var saved = SCENE.instantiate()
	saved.generate_on_ready = false
	root.add_child(saved)
	for body: RigidBody3D in saved._get_physical_body_parts(): check(body.gravity_scale == 0.0, "Saved parts also need disabled gravity")
	saved.queue_free()
	check(peak_extension > 0.001, "Angular lock must allow measurable spring extension")
	check(absf(selected.last_distance - initial_distance) < 0.1, "Radial spring must still restore distance")
	actor.zero_gravity_test_mode = false
	for body: RigidBody3D in parts: check(body.gravity_scale == 1.0, "Toggle must restore original gravity scale")
	check(not movement.simplified_physics_mode, "Toggle must restore normal control mode")
	actor.zero_gravity_test_mode = true
	actor._sync_segment_rotation_constraints(actor.get_node("GeneratedParts"))
	check(actor.get_node("GeneratedParts/Joints").find_children("Rotation_*", "Generic6DOFJoint3D", false, false).size() == locks.size(), "Saved-scene synchronization must not duplicate locks")
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	collision.shape = shape
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	for frame: int in range(120): await physics_frame
	var start: Vector3 = movement._torso.global_position
	Input.action_press("Right")
	for frame: int in range(600): await physics_frame
	Input.action_release("Right")
	var distance: float = movement._torso.global_position.x - start.x
	check(distance > 0.1, "Zero-gravity mode must retain grounded movement")
	print("ZERO_GRAVITY_MOVEMENT distance=", distance)
	ground.queue_free()
	print("ZERO_GRAVITY_SEGMENTS_", "FAILED" if failed else "PASSED", " com_drift=", after.distance_to(center), " spring_peak_extension=", peak_extension)
	actor.queue_free()
	quit(1 if failed else 0)
