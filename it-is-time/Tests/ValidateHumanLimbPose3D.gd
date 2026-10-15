extends SceneTree

var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	# Reproduce the distant diagonal enemy in the user's level, holding it still.
	var level: Node3D = load("res://Scenes/Levels/TestLevel.tscn").instantiate()
	root.add_child(level)
	var npc := level.get_node("GenerateHumanNPC")
	var movement := npc.get_node("GeneratedLegStepMovementController3D")
	var other := level.get_node("CharacterTestNPC")
	other.process_mode = Node.PROCESS_MODE_DISABLED
	for body: Node in other.find_children("*", "RigidBody3D", true, false): body.freeze = true
	var start := Vector3.ZERO
	var maximum_yaw := 0.0
	var maximum_foot_speed := 0.0
	var blocked_frames := 0
	for tick: int in 900:
		await physics_frame
		if tick == 540: start = npc.get_node("GeneratedParts/Torso").global_position
		if tick >= 540:
			maximum_yaw = maxf(maximum_yaw,absf(rad_to_deg(movement._get_physical_heading_yaw())))
			if movement.get_input_movement_direction().is_zero_approx(): blocked_frames += 1
			for foot: RigidBody3D in movement.get_leg_parts(): maximum_foot_speed = maxf(maximum_foot_speed,foot.linear_velocity.length())
	var torso := npc.get_node("GeneratedParts/Torso") as RigidBody3D
	var displacement := torso.global_position-start
	print("HUMAN_DIAGONAL displacement=",displacement," max_yaw=",maximum_yaw," max_foot_speed=",maximum_foot_speed," blocked_frames=",blocked_frames)
	check(displacement.x > 4.5 and displacement.z > 0.0, "Distant diagonal pursuit must make continuous progress toward the enemy")
	check(maximum_yaw < 15.0 and maximum_foot_speed < 10.0 and blocked_frames < 30, "Walking correction must not oscillate into turn holds or explosive foot tracking")
	check(torso.global_basis.y.dot(Vector3.UP)>0.9, "Human must remain upright during diagonal navigation")
	level.free()
	await process_frame
	# Hold the shoulder anchor still to measure actual recovery after a disturbance.
	var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_Human.tscn").instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	check(actor.generate_creature(), "Human must generate for pose verification")
	movement = actor.get_node("GeneratedLegStepMovementController3D")
	for body: Node in actor.get_node("GeneratedParts").get_children():
		if body is RigidBody3D: body.freeze = not str(body.name).begins_with("Arm_")
	var upper := actor.get_node("GeneratedParts/Arm_L_Limb_2") as PhysicalBodyPart3D
	var parent_body := actor.get_node("GeneratedParts/Torso") as PhysicalBodyPart3D
	var link: Dictionary
	for entry: Dictionary in movement._human_pose._arms:
		if entry.child == upper: link = entry
	for tick: int in 180: await physics_frame
	var baseline: float = movement._stance_rotation_error(upper,parent_body,link.rest).length()
	var pivot := parent_body.to_global(movement._human_pose._frame(link.joint,parent_body).origin)
	var rotation := Basis(parent_body.global_basis.z,deg_to_rad(45.0))
	upper.global_transform = Transform3D(rotation*upper.global_basis,pivot+rotation*(upper.global_position-pivot))
	var disturbed: float = movement._stance_rotation_error(upper,parent_body,link.rest).length()
	for tick: int in 180: await physics_frame
	var restored: float = movement._stance_rotation_error(upper,parent_body,link.rest).length()
	print("HUMAN_POSE_RECOVERY baseline=",rad_to_deg(baseline)," disturbed=",rad_to_deg(disturbed)," restored=",rad_to_deg(restored))
	check(restored < disturbed*0.7 and restored < baseline+deg_to_rad(10.0), "Idle arm chain must physically return toward its captured relative pose")
	var swing := actor.get_node("LimbSwingController3D")
	check(swing.begin_charge(0), "Shoulder swing must remain available")
	movement._human_pose.apply(movement,1.0/60.0)
	var yielded := 0
	for row: Dictionary in movement._human_pose.rows:
		if str(row.body).begins_with("Arm_R"):
			check(row.owner == "attack" and row.torque.is_zero_approx(), "Pose servo must yield every link of the attacking arm")
			yielded += 1
	check(yielded == 3, "Upper arm, forearm and hand must all yield to the swing controller")
	swing.cancel_player_actions()
	movement.human_limb_pose_enabled = false
	await physics_frame
	await physics_frame
	check(link.joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING), "Disabling the pose servo must restore authored arm springs")
	check(movement._get_passive_limb_damping(null)>0.0, "Disabling pose control must restore passive leg damping")
	movement.human_limb_pose_enabled = true
	movement.recovery_control_active = true
	movement._human_pose.apply(movement,1.0/60.0)
	for row: Dictionary in movement._human_pose.rows: check(row.torque.is_zero_approx(), "Recovery must own all pose control")
	movement.recovery_control_active = false
	check(actor.generate_creature(), "Pose control must rebuild after regeneration")
	await physics_frame
	await physics_frame
	check(movement._human_pose._arms.size() == 6, "Regeneration must replace cached arm links")
	actor.free()
	await process_frame
	print("HUMAN_LIMB_POSE_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
