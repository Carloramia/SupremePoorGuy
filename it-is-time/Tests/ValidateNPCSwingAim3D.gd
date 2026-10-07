extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var npc := load("res://Scenes/Creatures/Characters/Character_Test_NPC.tscn").instantiate() as Node3D
	npc.initial_weapon_scene = null
	for body: Node in npc.find_children("*", "RigidBody3D", true, false): body.freeze = true
	root.add_child(npc)
	for component: Node in npc.get_children(): component.set_physics_process(false)
	var swing := npc.get_node("LimbSwingController3D") as LimbSwingController3D
	var arm := npc.get_node("Arm_R") as PhysicalBodyPart3D
	var joint := npc.get_node("ShoulderJoint_R") as Generic6DOFJoint3D
	var target := Node3D.new()
	root.add_child(target)
	target.position = Vector3(2, 4, -10)
	var original_limit: bool = joint.get("angular_limit_y/enabled")
	assert(swing.try_start_npc_attack(&"PrimaryArm", target, 0.3))
	var member: Dictionary = swing._states[0].members[0]
	for frame: int in range(30): swing._physics_process(1.0 / 60.0)
	assert(int(member.mode) == swing.SwingState.CHARGING, "Off-axis attack must wait after its configured charge")
	assert(is_equal_approx(float(member.charge_time), 0.3), "Extra aim wait must not increase attack power")
	assert(not bool(joint.get("angular_limit_y/enabled")), "Yaw joint must be available during aiming")
	for frame: int in range(60): swing._physics_process(1.0 / 60.0)
	assert(swing._npc_aim_release_reason == &"aim_timeout", "A blocked Arm must not wait forever")
	swing.cancel_npc_attack()
	assert(bool(joint.get("angular_limit_y/enabled")) == original_limit)

	# Actual physics must turn the Arm; readiness alone is insufficient.
	arm.freeze = false
	arm.gravity_scale = 0.0
	swing.npc_maximum_aim_wait = 2.0
	assert(swing.try_start_npc_attack(&"PrimaryArm", target, 0.6))
	var initial_error: float = absf(swing._calculate_target_aim(member, target.position).error)
	var released := false
	for frame: int in range(180):
		swing._physics_process(1.0 / 60.0)
		await physics_frame
		if int(member.mode) == swing.SwingState.SWINGING:
			released = true
			break
	var final_error: float = absf(swing._calculate_target_aim(member, target.position).error)
	print("NPC_AIM_PHYSICS initial_deg=%.2f final_deg=%.2f reason=%s" % [rad_to_deg(initial_error), rad_to_deg(final_error), swing._npc_aim_release_reason])
	assert(released and swing._npc_aim_release_reason == &"aligned", "Real Arm must align before releasing")
	assert(final_error < initial_error * 0.75)
	assert(is_equal_approx(float(member.charge_time), 0.6))
	swing.cancel_npc_attack()
	assert(bool(joint.get("angular_limit_y/enabled")) == original_limit)

	arm.freeze = true
	arm.rotation = Vector3.ZERO
	arm.angular_velocity = Vector3.ZERO
	arm.position = Vector3(2.5, 4.8, 0)
	assert(npc.get_node("InventoryController3D").equip_initial_weapon(load("res://Scenes/Items/CustomWeapon_1.tscn")))
	await physics_frame
	arm.freeze = false
	assert(swing.try_start_npc_attack(&"PrimaryArm", target, 0.6))
	initial_error = absf(swing._calculate_target_aim(member, target.position).error)
	released = false
	for frame: int in range(180):
		swing._physics_process(1.0 / 60.0)
		await physics_frame
		if int(member.mode) == swing.SwingState.SWINGING:
			released = true
			break
	final_error = absf(swing._calculate_target_aim(member, target.position).error)
	print("NPC_WEAPON_AIM_PHYSICS initial_deg=%.2f final_deg=%.2f reason=%s" % [rad_to_deg(initial_error), rad_to_deg(final_error), swing._npc_aim_release_reason])
	assert(released and final_error < initial_error * 0.75, "Equipped weapon must turn toward the target before release")
	swing.cancel_npc_attack()

	assert(swing.try_start_npc_attack(&"PrimaryArm", target, 0.6))
	target.free()
	swing._physics_process(0.1)
	assert(not swing.is_npc_attack_active(), "Lost targets must cancel and restore the joint")
	assert(bool(joint.get("angular_limit_y/enabled")) == original_limit)
	print("NPC_SWING_AIM_3D_VALIDATION_PASSED")
	quit()
