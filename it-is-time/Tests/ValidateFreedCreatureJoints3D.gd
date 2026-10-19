extends SceneTree

const CAPTURE = preload("res://Scripts/Debug/RuntimeErrorLogCapture.gd")
const LIMBS = preload("res://Scripts/Creatures/GeneratedLimbControl3D.gd")
var capture := CAPTURE.new()
var failed := false
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed = true
		print("FREED_JOINT_CHECK_FAILED ",message)

func clean_errors(context: String) -> void:
	var error := capture.take_error()
	check(error.is_empty(),context+": "+str(error))

func fixture(name: String) -> Node3D:
	var actor: Node3D = load("res://Scenes/Creatures/Characters/"+name+".tscn").instantiate()
	actor.generate_on_ready = false
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(actor)
	actor.get_node(actor.generator_path)._random.seed = 43
	check(actor.generate_creature(),name+" generation")
	for body: RigidBody3D in actor._get_physical_body_parts(): body.freeze = true
	return actor

func exercise(actor: Node3D, foot: RigidBody3D, context: String) -> void:
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	movement._movement_batch_active = false
	movement._batch_intact_chains.clear()
	movement.update_leg_surface_adhesion()
	clean_errors(context+" adhesion")
	movement._apply_passive_limb_damping()
	clean_errors(context+" damping")
	movement.restore_base_hip_joint_limits()
	movement._apply_joint_spring_scale(1.0)
	clean_errors(context+" spring restoration")
	var limbs := LIMBS.new()
	var feet: Array[RigidBody3D] = [foot]
	limbs.expand_action_limits(movement,feet,75.0)
	check(limbs.action_joint_limits.is_empty(),context+" must not expand disconnected chains")
	limbs.restore_action_limits()
	clean_errors(context+" action limits")
	movement.get_generated_movement_diagnostics()
	movement.get_stance_support_diagnostics()
	if movement.has_method("get_support_foot_diagnostics"): movement.get_support_foot_diagnostics(foot)
	clean_errors(context+" diagnostics")
	root.get_node("RuntimeConsole")._collect_motion_snapshot(actor)
	clean_errors(context+" console diagnostics")
	movement._physics_process(1.0/60.0)
	if actor.has_method("_bind_spider_root_anchors"):
		actor._bind_spider_root_anchors()
		actor._physics_process(1.0/60.0)
	clean_errors(context+" physics")
	check(not movement._chain_is_intact(foot) and foot not in movement.get_leg_parts(),context+" disconnected foot excluded")

func validate_walking(name: String) -> void:
	var actor := fixture(name)
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	var feet: Array = movement.get_leg_parts().duplicate()
	check(not feet.is_empty(),name+" must have legs")
	if feet.is_empty(): actor.free(); return
	var foot: RigidBody3D = feet[0]
	var chain: Dictionary = movement._chains[foot]
	var joint: Generic6DOFJoint3D = chain.joints[0]
	movement.scale_joint_angular_springs = true
	movement._hip_joint_base_limits[joint] = Vector4(-0.1,0.1,-0.1,0.1)
	movement._joint_base_springs[joint] = Vector2(30.0,5.0)
	joint.queue_free()
	exercise(actor,foot,name+" queued joint")
	await process_frame
	await process_frame
	check(not is_instance_valid(chain.joints[0]),name+" joint actually freed")
	exercise(actor,foot,name+" freed joint")
	var pin := Generic6DOFJoint3D.new()
	movement._support_pins[foot] = {"joint":pin}
	pin.free()
	if movement.has_method("_set_touchdown_pin_slack"): movement._set_touchdown_pin_slack(foot,0.01)
	movement._release_support_pin(foot)
	clean_errors(name+" deleted support pin")
	var survivors: Array = movement.get_leg_parts().duplicate()
	if not survivors.is_empty():
		var other: RigidBody3D = survivors[0]
		var upper: PhysicalBodyPart3D = movement._chains[other].bodies[1]
		upper.break_part()
		for tick: int in 4: await process_frame
		exercise(actor,other,name+" real broken part")
	actor.free()
	await process_frame
	clean_errors(name+" teardown")
	print("FREED_JOINT_SPECIES_CHECKED ",name)

func validate_bird_connections() -> void:
	var actor := fixture("Generate_Bird")
	var wings := actor.get_node("WingPoseController3D")
	check(not wings.bindings.is_empty(),"Bird has wing bindings")
	if not wings.bindings.is_empty():
		var binding: Dictionary = wings.bindings[0]
		binding.joint.free()
		check(not wings._binding_intact(binding),"Freed wing joint invalidates binding")
		wings._physics_process(1.0/60.0)
		clean_errors("Bird wing physics")
	var flight := actor.get_node("BirdFlightController3D")
	if not flight._joints.is_empty():
		var joint: Variant = flight._joints[0].joint
		if is_instance_valid(joint): joint.free()
		flight._landing_transition = true
		flight._update_landing_transition(1.0/60.0)
		clean_errors("Bird landing joint restoration")
	var head_support := actor.get_node_or_null("HeadPositionSupport3D")
	if head_support != null and not head_support.bindings.is_empty():
		var binding: Dictionary = head_support.bindings[0]
		if is_instance_valid(binding.joints[0]): binding.joints[0].free()
		head_support._sync_direct_head_slack(binding)
		head_support._physics_process(1.0/60.0)
		clean_errors("Bird head joint support")
	actor.free()
	await process_frame
	clean_errors("Bird connection teardown")

func validate_equipment_references() -> void:
	var actor := fixture("Generate_Human")
	var inventory := actor.get_node("InventoryController3D")
	var item: SampleItem3D = load("res://Scenes/Items/Weapons/Human/Human1Spear.tscn").instantiate()
	item.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(item)
	item.idle_grip_pose = ItemGripIdlePose.new()
	item.idle_grip_pose.use_line_angle = true
	var right: PhysicalBodyPart3D = actor.get_node("GeneratedParts/Arm_R")
	var left: PhysicalBodyPart3D = actor.get_node("GeneratedParts/Arm_L")
	right.freeze = false
	var right_socket := Marker3D.new()
	var left_socket := Marker3D.new()
	right.add_child(right_socket)
	left.add_child(left_socket)
	var grips := preload("res://Scripts/Items/EquipmentMultiGrip3D.gd").new()
	grips._inventory = inventory
	grips._item = item
	grips._primary = right
	grips._idle_bodies = [right,left]
	grips._idle_pair.assign([{"hand":right,"point":0,"socket":right_socket},{"hand":left,"point":0,"socket":left_socket}])
	left.set_meta(grips.OWNER,inventory)
	var joint := Generic6DOFJoint3D.new()
	actor.add_child(joint)
	grips._idle_joints = [joint]
	grips._update_idle_pose(1.0/60.0)
	check(grips.idle_pose_diagnostics.state == "tracking","Healthy equipment idle pose remains enabled")
	clean_errors("Healthy equipment idle pose")
	grips.suspend_idle_pose()
	var pose := {"pose_chain":[{"joint":joint,"body":right}]}
	joint.free()
	grips._update_idle_pose(1.0/60.0)
	check(grips.idle_pose_diagnostics.state == "broken_chain","Idle pose releases a disconnected chain")
	preload("res://Scripts/Combat/WeaponArmPose3D.gd").unlock(pose)
	clean_errors("Equipment and attack pose with a freed joint")
	grips.release()
	item.free()
	actor.free()
	await process_frame
	clean_errors("Equipment teardown")

func run() -> void:
	var console := root.get_node("RuntimeConsole")
	console.auto_getlogs_enabled = false
	console.execute_command("motiondetail full")
	OS.add_logger(capture)
	for name: String in ["Generate_Spider","Generate_Wolf","Generate_StumpBeast","Generate_HornedBeast","Generate_Beast","Generate_Ratkin","Generate_Rat_1","Generate_Rat_2","Generate_Human","Generate_Bird"]:
		await validate_walking(name)
	await validate_bird_connections()
	await validate_equipment_references()
	OS.remove_logger(capture)
	print("FREED_CREATURE_JOINTS_", "FAILED" if failed else "PASSED", " checks=",checks)
	quit(1 if failed else 0)
