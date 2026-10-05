extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ground := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(300, 1, 300)
	collider.shape = shape
	ground.add_child(collider)
	ground.position.y = -0.5
	root.add_child(ground)
	var character = CHARACTER.instantiate()
	character.generate_on_ready = false
	root.add_child(character)
	# Transitive merging and X-only ownership, independent of Y/Z and decay scale.
	var sample: Array[Dictionary] = []
	var indices: Array[int] = []
	for index: int in range(5):
		var x: float = [0.0, 0.8, 1.6, 10.0, 3.0][index]
		indices.append(index)
		sample.append({"sub_torso": index < 4, "size": Vector3.ONE, "transform": Transform3D(Basis.IDENTITY, Vector3(x, 100.0 if index == 4 else 0.0, -100.0 if index == 4 else 0.0))})
	var empty_edges: Array[Dictionary] = []
	var assigned: Array[int] = character._partition_torso_graph(sample, indices, empty_edges)
	check(assigned[0] == assigned[1] and assigned[1] == assigned[2], "SubTorso merge must be transitive")
	check(assigned[3] != assigned[0] and assigned[4] == assigned[0], "Assignment must use only X distance")
	character.segment_weight_decay_ratio = 0.001
	check(character._partition_torso_graph(sample, indices, empty_edges) == assigned, "Uniform exponential decay must not change nearest-X ownership")
	character.segment_weight_decay_ratio = 0.2
	var generator = character.get_node("CreatureGenerator")
	generator.rear_leg_count = maxi((6) - 2, 0)
	generator.foreleg_count = mini((6), 2)
	generator.unsymmetrie = 60.0
	generator.overall_scale = 4.0
	generator.neck_number = 0

	generator._random.seed = 43
	if not character.generate_creature():
		push_error("Generation failed")
		quit(1)
		return
	var movement = character.get_node("GeneratedLegStepMovementController3D")
	var torsos: Array[RigidBody3D] = movement.get_torso_parts()
	var sub_count := 0
	var regions: Dictionary = {}
	for body: RigidBody3D in torsos:
		check(body.has_meta(&"body_segment_id"), "Every Torso must own exactly one segment")
		var id := int(body.get_meta(&"body_segment_id", -1))
		regions[id] = true
		if 6 in body.tags:
			check(6 in body.tags and 0 in body.tags, "SubTorso must preserve both tags")
			sub_count += 1
	check(regions.size() <= sub_count, "Nearby SubTorsos may merge into fewer segments")
	var cross_count := 0
	var pairs: Dictionary = {}
	var internal: Dictionary = {}
	for joint: Node in character.get_node("GeneratedParts/Joints").get_children():
		var a: RigidBody3D = joint.get_node(joint.node_a)
		var b: RigidBody3D = joint.get_node(joint.node_b)
		if a not in torsos or b not in torsos: continue
		var first := int(a.get_meta(&"body_segment_id"))
		var second := int(b.get_meta(&"body_segment_id"))
		if first == second:
			internal[first] = int(internal.get(first, 0)) + 1
			check(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT) == 0.0, "Internal Torso joints must stay rigid")
		elif not joint.has_method("get_constraint_diagnostics"):
			cross_count += 1
			check(not joint is Joint3D and joint.has_method("is_segment_spring"), "Cross-segment links must apply forces without a physics Joint")
			var key := "%d:%d" % [mini(first, second), maxi(first, second)]
			check(not pairs.has(key), "Only one Joint per segment pair")
			pairs[key] = true
	check(cross_count == regions.size() - 1, "Segment graph must be a connected tree")
	for id: int in regions:
		var count := 0
		for body: RigidBody3D in torsos:
			if int(body.get_meta(&"body_segment_id")) == id: count += 1
		check(int(internal.get(id, 0)) == count - 1, "Each segment must have a rigid connected tree")
	for frame: int in range(300): await physics_frame
	check(movement.unbalanced_stance_multiplier > 0.0, "Unbalanced support must retain load compensation")
	var auxiliary_seen := false
	var initial: Vector3 = movement._torso.global_position
	var maximum_angle := 0.0
	var minimum_height := INF
	var maximum_layout_error := 0.0
	Input.action_press("Right")
	for frame: int in range(1800):
		await physics_frame
		check(movement._last_torso_response_force.is_finite(), "Movement force must stay finite")
		check(movement._last_auxiliary_support_force.is_finite(), "Auxiliary force must stay finite")
		auxiliary_seen = auxiliary_seen or movement._last_auxiliary_support_force.y > 0.0
		var recovery: Dictionary = character.get_node("CreatureRecoveryStateMachine3D").get_recovery_diagnostics()
		maximum_angle = maxf(maximum_angle, float(recovery.metrics.get("angle", 0.0)))
		minimum_height = minf(minimum_height, float(recovery.get("height_ratio", 1.0)))
		for link: Dictionary in movement._get_segment_spring_diagnostics():
			maximum_layout_error = maxf(maximum_layout_error, absf(link.layout_angle_error_degrees))
		if frame % 60 == 0:
			for foot: RigidBody3D in movement.get_torso_movement_force_legs(true):
				check(movement.is_leg_grounded(foot) and not movement.is_leg_stepping(foot), "Only grounded stance soles may transfer force, even in fast mode")
	check(maximum_layout_error < 35.0, "Walking must preserve cross-segment layout direction")
	check(maximum_angle < 35.0, "Thirty-second walking must keep Torso tilt bounded")
	check(minimum_height > 0.85, "Thirty-second walking must preserve standing height")
	check(movement._torso.global_position.x - initial.x > 2.0, "Grounded feedback must actually move the character")
	Input.action_release("Right")
	check(auxiliary_seen, "SubTorso must supply auxiliary support")
	for frame: int in range(20): await physics_frame
	check(movement._last_torso_response_force.slide(Vector3.UP).length() < 0.001, "Pose offsets must not drive horizontal motion without input")
	# Check actual physical yaw response on every segment, rather than only target assignment.
	movement.set_segment_facing_direction(Vector3.LEFT)
	var turn_lost_support := false
	for frame: int in range(7200):
		await physics_frame
		if movement.recovery_control_active and not turn_lost_support: print("TURN_RECOVERY_ENTERED ", character.get_node("CreatureRecoveryStateMachine3D").get_recovery_diagnostics())
		turn_lost_support = turn_lost_support or movement.recovery_control_active
		if frame % 600 == 0: print("WALK_TURN_PROGRESS seconds=", frame / 60.0, " heading=", rad_to_deg(movement._get_physical_heading_yaw()), " reference=", rad_to_deg(movement._segment_layout_yaw), " state=", movement._layout_turn_status)
	check(not turn_lost_support, "Walking-to-turn transition must preserve standing support")
	check(not movement._layout_turn_owned and not movement._turn_planning_active, "Finished turn must release gait ownership")
	var heading_errors: Array[float] = []
	for id: int in movement._segments:
		var part: RigidBody3D = movement._segments[id].bodies[0]
		var forward := part.global_basis.x.slide(Vector3.UP).normalized()
		var error := rad_to_deg(acos(clampf(forward.dot(Vector3.LEFT), -1.0, 1.0)))
		heading_errors.append(error)
		check(error < 15.0, "Every segment must follow a changed heading")
	for link: Dictionary in movement._get_segment_spring_diagnostics():
		check(not link.layout_enabled, "Springs must not independently drive yaw")
		check(link.distance <= link.maximum_distance + 0.05, "Turn must retain the cross-segment distance bound")
	print("SEGMENT_TURN heading_errors=", heading_errors, " layout=", movement._get_segment_spring_diagnostics())
	movement.set_physics_process(false)
	movement._adhesion_release_time_remaining = 1.0
	movement._apply_torso_response()
	check(movement._last_auxiliary_support_force.length() < 0.001, "Jump release must immediately disable auxiliary support")
	print("BODY_SEGMENT_MOTION delta=", movement._torso.global_position - initial, " maximum_angle=", maximum_angle, " minimum_height_ratio=", minimum_height, " maximum_layout_error=", maximum_layout_error)
	# Retained editor-generated scenes must also migrate, with fully free rotation supported.
	var saved = CHARACTER.instantiate()
	saved.generate_on_ready = false
	root.add_child(saved)
	var saved_torsos: Array = saved.get_node("GeneratedLegStepMovementController3D").get_torso_parts()
	var saved_crosses := 0
	for body: RigidBody3D in saved_torsos:
		check(body.has_meta(&"body_segment_id"), "Saved Torso layout must migrate")
		if 6 in body.tags: check(6 in body.tags, "Saved SubTorso must receive its tag")
	for joint: Node in saved.get_node("GeneratedParts/Joints").get_children():
		var a: RigidBody3D = joint.get_node(joint.node_a)
		var b: RigidBody3D = joint.get_node(joint.node_b)
		if a not in saved_torsos or b not in saved_torsos: continue
		if a.get_meta(&"body_segment_id") == b.get_meta(&"body_segment_id") or joint.has_method("get_constraint_diagnostics"): continue
		saved_crosses += 1
		check(not joint is Joint3D and joint.has_method("is_segment_spring"), "Saved scene must migrate to central-force springs")
	check(saved_crosses > 0, "Saved scene must contain articulated segment links")
	saved.queue_free()
	# At idle, a Y rotation must be corrected toward the held heading, rather than recaptured.
	movement._adhesion_release_time_remaining = 0.0
	movement._apply_segment_balance(1.0 / 60.0)
	var saved_bases: Dictionary = {}
	for body: RigidBody3D in torsos:
		saved_bases[body] = body.global_basis
		body.global_basis = Basis(Vector3.UP, 0.25)
		body.angular_velocity = Vector3.ZERO
	movement._apply_segment_balance(1.0 / 60.0)
	var balance_total := Vector3.ZERO
	for data: Dictionary in movement.get_body_segment_diagnostics(): balance_total += Vector3(data.balance_torque)
	check(absf(balance_total.y) < 0.01, "Heading drift must not command a direct Torso Y torque")
	for body: RigidBody3D in torsos: body.global_basis = saved_bases[body]
	var previous_goal: float = movement._segment_goal_yaw
	movement.set_segment_facing_direction(Vector3.FORWARD)
	check(absf(wrapf(movement._segment_goal_yaw - PI * 0.5, -PI, PI)) < 0.001, "Heading commands must update the Y balance target")
	movement._segment_goal_yaw = previous_goal
	# A blocked footprint must release gait ownership rather than trap movement forever.
	movement.cancel_step(&"layout_watchdog_fixture")
	movement.set_turn_planning_active(false)
	movement._layout_turn_owned = false
	movement._layout_turn_retry = 0.0
	movement._segment_layout_yaw = movement._get_actual_layout_yaw(0.0) + 0.5
	movement._segment_target_yaw = movement._segment_layout_yaw
	var watchdog_released := false
	for frame: int in range(360):
		movement._update_layout_turn_steps(1.0 / 60.0)
		if movement._layout_turn_status == &"stalled_retry":
			watchdog_released = not movement._layout_turn_owned and not movement._turn_planning_active
			break
	check(watchdog_released, "Blocked turn planning must release movement ownership")
	character.queue_free()
	ground.queue_free()
	await process_frame
	print("BODY_SEGMENTS_VALIDATION_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
