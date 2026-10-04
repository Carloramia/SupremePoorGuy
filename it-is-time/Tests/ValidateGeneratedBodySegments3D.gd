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
	var generator = character.get_node("CreatureGenerator")
	generator.feets = 6
	generator.unsymmetrie = 60.0
	generator.overall_scale = 4.0
	generator.neck_number = 0
	generator.torso_core_extra_blocks = 0
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
		if str(body.name).begins_with("SubTorso"):
			check(6 in body.tags and 0 in body.tags, "SubTorso must preserve both tags")
			sub_count += 1
	check(regions.size() == sub_count, "Each SubTorso seeds one segment")
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
		else:
			cross_count += 1
			var key := "%d:%d" % [mini(first, second), maxi(first, second)]
			check(not pairs.has(key), "Only one Joint per segment pair")
			pairs[key] = true
			check(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT) > 0.0, "Segment joint must permit rotation")
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
	Input.action_press("Right")
	for frame: int in range(1800):
		await physics_frame
		check(movement._last_torso_response_force.is_finite(), "Movement force must stay finite")
		check(movement._last_auxiliary_support_force.is_finite(), "Auxiliary force must stay finite")
		auxiliary_seen = auxiliary_seen or movement._last_auxiliary_support_force.y > 0.0
		var recovery: Dictionary = character.get_node("CreatureRecoveryStateMachine3D").get_recovery_diagnostics()
		maximum_angle = maxf(maximum_angle, float(recovery.metrics.get("angle", 0.0)))
		minimum_height = minf(minimum_height, float(recovery.get("height_ratio", 1.0)))
		if frame % 60 == 0:
			for foot: RigidBody3D in movement.get_torso_movement_force_legs(true):
				check(movement.is_leg_grounded(foot) and not movement.is_leg_stepping(foot), "Only grounded stance soles may transfer force, even in fast mode")
	check(maximum_angle < 35.0, "Thirty-second walking must keep Torso tilt bounded")
	check(minimum_height > 0.85, "Thirty-second walking must preserve standing height")
	check(movement._torso.global_position.x - initial.x > 2.0, "Grounded feedback must actually move the character")
	Input.action_release("Right")
	check(auxiliary_seen, "SubTorso must supply auxiliary support")
	for frame: int in range(20): await physics_frame
	check(movement._last_torso_response_force.slide(Vector3.UP).length() < 0.001, "Pose offsets must not drive horizontal motion without input")
	movement.set_physics_process(false)
	movement._adhesion_release_time_remaining = 1.0
	movement._apply_torso_response()
	check(movement._last_auxiliary_support_force.length() < 0.001, "Jump release must immediately disable auxiliary support")
	print("BODY_SEGMENT_MOTION delta=", movement._torso.global_position - initial, " maximum_angle=", maximum_angle, " minimum_height_ratio=", minimum_height)
	# Retained editor-generated scenes must also migrate, with fully free rotation supported.
	var saved = CHARACTER.instantiate()
	saved.generate_on_ready = false
	saved.segment_free_rotation = true
	root.add_child(saved)
	var saved_torsos: Array = saved.get_node("GeneratedLegStepMovementController3D").get_torso_parts()
	var saved_crosses := 0
	for body: RigidBody3D in saved_torsos:
		check(body.has_meta(&"body_segment_id"), "Saved Torso layout must migrate")
		if str(body.name).begins_with("SubTorso"): check(6 in body.tags, "Saved SubTorso must receive its tag")
	for joint: Node in saved.get_node("GeneratedParts/Joints").get_children():
		var a: RigidBody3D = joint.get_node(joint.node_a)
		var b: RigidBody3D = joint.get_node(joint.node_b)
		if a not in saved_torsos or b not in saved_torsos: continue
		if a.get_meta(&"body_segment_id") == b.get_meta(&"body_segment_id"): continue
		saved_crosses += 1
		check(not joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT), "Free segment joint must disable angular limits")
		check(not joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING), "Free segment joint must disable angular springs")
	check(saved_crosses > 0, "Saved scene must contain articulated segment links")
	saved.queue_free()
	character.queue_free()
	ground.queue_free()
	await process_frame
	print("BODY_SEGMENTS_VALIDATION_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
