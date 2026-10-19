extends SceneTree

const POSE = preload("res://Scripts/Combat/WeaponArmPose3D.gd")
const HUMAN = preload("res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Spear1_NPC.tscn")
var failed := false
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	print("HAND_DRIVE_CHECK ",value," ",message)
	if not value: failed = true; push_error(message)

func verify(side: float) -> void:
	var actor := HUMAN.instantiate() as Node3D
	actor.generate_on_ready = false
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	if side < 0.0: actor.rotation.y = PI
	root.add_child(actor)
	await process_frame
	await physics_frame
	for body: RigidBody3D in actor.find_children("*","RigidBody3D",true,false):
		body.freeze = true
		body.gravity_scale = 0.0
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	var swing := actor.get_node("LimbSwingController3D") as LimbSwingController3D
	var inventory := actor.get_node("InventoryController3D")
	inventory.suspend_idle_grip_pose()
	swing.refresh_weapon_presets()
	var state: Dictionary = swing._states[0].members[0]
	var preset := state.preset as WeaponArmAttackPreset
	var hand: RigidBody3D = state.effector
	check(POSE.uses_hand_drive(state,preset) and state.pose_chain.size() == 3,"Spear enables hand drive on the two-link Human arm")
	var legacy := preset.duplicate() as WeaponArmAttackPreset
	legacy.hand_driven_motion = false
	check(not POSE.uses_hand_drive(state,legacy),"The old full-chain motor remains selectable")
	check(not POSE.uses_hand_drive({"pose_chain":[state.pose_chain[0]]},preset),"A single-body Arm keeps its lever-based motion")
	var saved: Array[Dictionary] = []
	for link: Dictionary in state.pose_chain:
		for axis: String in ["x","y","z"]:
			for section: String in ["angular_limit","angular_spring"]:
				var key := section+"_"+axis+"/enabled"
				saved.append({"joint":link.joint,"key":key,"value":link.joint.get(key)})
		link.body.freeze = false
	for binding: Dictionary in inventory._multi_grips._bindings:
		for body: RigidBody3D in binding.chain.bodies: body.freeze = false
	await physics_frame
	check(swing.begin_charge(0),"Charge acquires the arm")
	check(saved.all(func(row): return not str(row.key).begins_with("angular_limit") or row.joint.get(row.key) == row.value),"Hand drive preserves authored angular limits")
	var direction := Vector3(side,-0.25,0).normalized()
	state.pose_direction = direction
	var targets := POSE.poses(state,preset,direction,Vector3.UP,0.0)
	var desired: Vector3 = targets[-1]*Vector3(state.pose_chain[-1].proximal)
	var initial_error := hand.to_global(state.pose_chain[-1].proximal).distance_to(desired)
	var initial_link: Transform3D = state.pose_chain[0].body.global_transform
	var maximum_gap := 0.0
	var bounded := true
	for tick: int in 120:
		POSE.apply(state,preset,targets,1.0/60.0,1.0)
		inventory._multi_grips.update(1.0/60.0)
		bounded = bounded and state.hand_drive_diagnostics.force_length <= preset.hand_maximum_force+0.001
		await physics_frame
		for link: Dictionary in state.pose_chain:
			var joint: Generic6DOFJoint3D = link.joint
			var a := joint.get_node(joint.node_a) as RigidBody3D
			var b := joint.get_node(joint.node_b) as RigidBody3D
			maximum_gap = maxf(maximum_gap,a.to_global(POSE.local_anchor(joint,a)).distance_to(b.to_global(POSE.local_anchor(joint,b))))
	var final_error := hand.to_global(state.pose_chain[-1].proximal).distance_to(desired)
	print("HAND_DRIVE_PHYSICS side=",side," start_error=",initial_error," end_error=",final_error," joint_gap=",maximum_gap)
	print("HAND_DRIVE_FINAL actual=",hand.to_global(state.pose_chain[-1].proximal)," desired=",desired," diagnostics=",state.hand_drive_diagnostics)
	check(final_error < initial_error*0.4 and final_error < 0.6,"Physical hand force converges toward its target")
	check(not state.pose_chain[0].body.global_transform.is_equal_approx(initial_link),"The upper limb follows through the connected joints")
	check(maximum_gap < POSE.reach(state.pose_chain)*0.02,"The moving arm remains connected")
	check(bounded,"Hand tracking respects its configured force cap")
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	movement._human_pose.apply(movement,1.0/60.0)
	check(movement._human_pose.rows.filter(func(row): return str(row.body).begins_with("Arm_R")).all(func(row): return row.owner == "attack" and row.torque.is_zero_approx()),"The normal Human pose controller yields the active chain")
	swing.cancel_npc_attack()
	swing.cancel_player_actions()
	check(saved.all(func(row): return row.joint.get(row.key) == row.value),"Cancellation restores every original angular limit and spring")
	check(not state.has("hand_previous_target") and not state.has("hand_drive_diagnostics"),"Cancellation clears trajectory history")
	check(swing.begin_charge(0),"A second attack can start after cancellation")
	swing.add_charge_time(0,0.6)
	swing.release_charge(0)
	for tick: int in 150:
		swing._process_member(0,state,false,1.0/60.0)
		inventory._multi_grips.update(1.0/60.0)
		await physics_frame
	check(int(state.mode) == swing.SwingState.IDLE and not state.weapon.swing_damage_active,"Release and recovery finish with the damage window closed")
	inventory.suspend_idle_grip_pose()
	check(saved.all(func(row): return row.joint.get(row.key) == row.value),"Normal completion restores the chain constraints")
	actor.queue_free()
	await process_frame
	await process_frame

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var audio := root.get_node("CombatAudio")
	audio.settings = audio.settings.duplicate()
	audio.settings.enabled = false
	await verify(1.0)
	await verify(-1.0)
	print("SPEAR_HAND_DRIVE_","FAILED" if failed else "PASSED"," checks=",checks)
	quit(1 if failed else 0)
