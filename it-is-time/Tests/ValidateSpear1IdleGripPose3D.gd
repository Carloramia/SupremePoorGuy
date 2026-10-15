extends SceneTree

const HUMAN = preload("res://Scenes/Creatures/Characters/Generate_Human.tscn")
const SPEAR = preload("res://Scenes/Items/Weapons/Human/Human1Spear.tscn")
var failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func verify(primary_point: int, facing: float) -> void:
	var actor := HUMAN.instantiate() as Node3D
	actor.generate_on_ready = false
	actor.initial_weapon_scene = null
	actor.require_head_and_torso_connectivity = false
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.rotation.y = facing
	root.add_child(actor)
	for body: RigidBody3D in actor.find_children("*", "RigidBody3D", true, false): body.freeze = true
	var inventory := actor.get_node("InventoryController3D")
	inventory.inventory_ui_enabled = false
	inventory.attachment_debug_logging = false
	check(inventory.equip_initial_weapon(SPEAR), "Equip Spear1")
	var item := inventory.get_equipped_item() as SampleWeapon3D
	check(item.idle_grip_pose != null, "Spear1 has an idle grip pose")
	if primary_point != item.active_grip_point: check(item.select_grip_point(primary_point), "Swap primary hand")
	var right := actor.get_node("GeneratedParts/Arm_R") as PhysicalBodyPart3D
	var left := actor.get_node("GeneratedParts/Arm_L") as PhysicalBodyPart3D
	var primary := item.rigid_attachment_holder
	# Both complete arms remain dynamic, with the normal Human rest controller active.
	for hand: RigidBody3D in [right, left]:
		var chain: Dictionary = inventory._multi_grips._capture_chain(hand, hand.get_node("ItemSocket3D"), actor.find_children("*", "Generic6DOFJoint3D", true, false))
		for body: RigidBody3D in chain.bodies:
			body.freeze = false
			body.linear_damp = 2.0
			body.angular_damp = 2.0
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	var saved_poses := item.grip_point_poses.duplicate()
	var saved_model: Transform3D = item.get_node("Model").transform
	var saved_collider: Transform3D = item.get_node("CollisionShape3D").transform
	var first_height := right.global_position.y-left.global_position.y
	var torso := actor.get_node("GeneratedParts/Torso") as RigidBody3D
	var support_origin := torso.global_position
	var settled_angles: Array[float] = []
	for tick: int in 900:
		if tick>=600 and primary == right:
			var time := float(tick-600)/60.0
			torso.global_position = support_origin+Vector3(sin(time*4.0)*0.15,sin(time*5.0)*0.04,0.0)
		movement._human_pose.apply(movement, 1.0/60.0)
		await physics_frame
		if tick>=600 and item.idle_grip_pose.use_line_angle: settled_angles.append(inventory.get_weapon_grip_diagnostics().idle_pose.actual_angle_degrees)
		if tick % 120 == 119: print("IDLE_POSE_SAMPLE primary=",primary_point," facing=",facing," frame=",tick," diagnostic=",inventory.get_weapon_grip_diagnostics().idle_pose)
	var diagnostic: Dictionary = inventory.get_weapon_grip_diagnostics().idle_pose
	var final_height := right.global_position.y-left.global_position.y
	print("IDLE_POSE_RESULT primary=",primary_point," facing=",facing," initial_height=",first_height," final_height=",final_height," diagnostic=",diagnostic," auxiliary=",inventory.get_weapon_grip_diagnostics().grips)
	check(diagnostic.state == "tracking" and diagnostic.higher_arm == "Arm_R" and diagnostic.lower_arm == "Arm_L", "Height roles do not change when the primary hand changes")
	if primary == right:
		if item.idle_grip_pose.use_line_angle:
			check(absf(diagnostic.actual_angle_degrees-item.idle_grip_pose.line_angle_degrees)<4.0 and final_height>0.0, "Arm_R-to-Arm_L line physically settles at the requested world inclination")
			print("SPEAR_IDLE_STABILITY facing=",facing," min=",settled_angles.min()," max=",settled_angles.max())
			check(settled_angles.min()>27.0 and settled_angles.max()<33.0,"Settled inclination remains near 30 degrees throughout the final five seconds")
		else: check(absf(final_height-item.idle_grip_pose.height_difference) < 0.12 and final_height > 0.0, "Arm_R physically settles slightly above Arm_L along world Y")
		check(inventory.get_weapon_grip_diagnostics().grips[0].error_length < 0.4, "Height correction preserves auxiliary grip tracking within the soft reach margin")
	else:
		check((diagnostic.force.y <= 0.0) == (diagnostic.height_error >= 0.0), "Left primary receives the opposite correction sign")
	check(item.grip_point_poses == saved_poses, "Idle posture never edits authored grip poses")
	check(item.get_node("Model").transform == saved_model and item.get_node("CollisionShape3D").transform == saved_collider, "Idle posture never changes the visual model or collider")
	check(diagnostic.force.length() <= item.idle_grip_pose.maximum_force+0.001, "Posture force is bounded")
	if primary == right:
		var swing := actor.get_node("LimbSwingController3D") as LimbSwingController3D
		check(swing.begin_charge(0), "Idle posture does not block attacking")
		await physics_frame
		await physics_frame
		check(inventory.get_weapon_grip_diagnostics().idle_pose.state == "attacking", "Attack owns the entire charge and recovery interval")
		swing.add_charge_time(0, 0.3)
		check(swing.release_charge(0), "Release a normal weapon attack")
		var member: Dictionary = swing._states[0].members[0]
		var active_ticks := 0
		for tick: int in 240:
			swing._process_member(0, member, false, 1.0/60.0)
			await physics_frame
			if swing.is_body_attacking(primary):
				active_ticks += 1
				check(inventory.get_weapon_grip_diagnostics().idle_pose.state == "attacking", "Swing, follow-through and recovery keep idle forces suspended")
			else: break
		check(active_ticks > 0, "Attack test includes physical swing frames")
		swing.cancel_attacks_for_holder(primary)
		await physics_frame
		await physics_frame
		check(inventory.get_weapon_grip_diagnostics().idle_pose.state == "tracking", "Idle posture resumes after attack cancellation")
	item.idle_grip_pose = item.idle_grip_pose.duplicate()
	item.idle_grip_pose.enabled = false
	await physics_frame
	await physics_frame
	check(inventory.get_weapon_grip_diagnostics().idle_pose.state == "disabled", "Preset switch releases posture control")
	item.idle_grip_pose.enabled = true
	await physics_frame
	await physics_frame
	inventory.cancel_player_actions()
	check(inventory.get_weapon_grip_diagnostics().idle_pose.state == "suspended", "Ragdoll cancellation releases idle control")
	await physics_frame
	await physics_frame
	check(inventory.get_weapon_grip_diagnostics().idle_pose.state == "tracking", "Rebinding restores idle control")
	var auxiliary: PhysicalBodyPart3D = left if primary == right else right
	inventory._multi_grips.release_part(auxiliary)
	await physics_frame
	await physics_frame
	check(inventory.get_weapon_grip_diagnostics().idle_pose.state == "unbound_pair", "Losing a hand disables the two-hand posture")
	item.idle_grip_pose.lower_arm_path = ^"MissingArm"
	check(inventory.refresh_equipped_item_attachment(item), "Rebind with a missing idle posture role")
	await physics_frame
	await physics_frame
	check(inventory.get_weapon_grip_diagnostics().idle_pose.state == "missing_pair", "A missing second Arm leaves ordinary equipment intact without idle force")
	inventory._unequip_current_item()
	check(inventory.get_weapon_grip_diagnostics().idle_pose.state == "suspended", "Unequip suspends idle posture")
	actor.queue_free()
	await process_frame

func run() -> void:
	await verify(1, 0.0)
	await verify(1, PI)
	await verify(0, 0.0)
	print("SPEAR1_IDLE_GRIP_POSE_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
