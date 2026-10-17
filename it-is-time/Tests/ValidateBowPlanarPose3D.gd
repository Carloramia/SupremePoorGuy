extends SceneTree
const NPC = preload("res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Bow_NPC.tscn")
const PLANAR = preload("res://Scripts/Combat/BowArmPose3D.gd")
const DIAGNOSTICS = preload("res://Scripts/Debug/JointMotionDiagnostics3D.gd")
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const TORSO = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Torso.tscn")
var failures: Dictionary = {}
var metrics := {"maximum_arm_plane_degrees":0.0,"maximum_arm_anchor_gap":0.0,"maximum_string_plane_drift":0.0,"maximum_arm_angular_speed":0.0}

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if value or failures.has(message): return
	failures[message] = true
	push_error(message)

func sample(actor: Node3D) -> void:
	var controller: Node = actor.get_node("BowAttackController3D")
	if not controller._valid(): return
	var bow: Node3D = controller._bow
	var normal: Vector3 = controller._plane_normal()
	for arm: Dictionary in controller._arms:
		for link: Dictionary in arm.pose_chain:
			for axis: String in ["x","y","z"]:
				check(link.joint.call("get_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT),"Bow preserves the authored arm angular limits")
			var tilt := rad_to_deg(acos(clampf(absf(normal.dot(link.body.global_basis.z.normalized())),0,1)))
			metrics.maximum_arm_plane_degrees = maxf(metrics.maximum_arm_plane_degrees,tilt)
			metrics.maximum_arm_angular_speed = maxf(metrics.maximum_arm_angular_speed,link.body.angular_velocity.length())
			metrics.maximum_arm_anchor_gap = maxf(metrics.maximum_arm_anchor_gap,DIAGNOSTICS.collect(link.joint).anchor_gap)
	var local_center: Vector3 = bow.to_local(bow.get_string_center().global_position)
	metrics.maximum_string_plane_drift = maxf(metrics.maximum_string_plane_drift,absf(local_center.z))
	check(local_center.x>=bow._rest_center.x-bow.maximum_draw_distance-0.05 and local_center.x<=bow._rest_center.x+0.05,"String guide enforces finite drawing travel")
	check(absf(local_center.y)<0.05 and absf(local_center.z)<0.05,"String center remains on the bow's local draw axis")
	var guide := bow.get_node("StringGuide") as Generic6DOFJoint3D
	check(guide.get_node_or_null(guide.node_a)==bow.rigid_attachment_holder,"String guide reacts against the actual rigid equipment holder")
	for arm: Dictionary in controller._arms:
		var poses := PLANAR.poses(arm,arm.angles)
		var parent: Transform3D = arm.anchor_body.global_transform
		for index: int in poses.size():
			var link: Dictionary = arm.pose_chain[index]
			check((parent*Transform3D(link.parent_frame)).origin.distance_to((poses[index]*Transform3D(link.child_frame)).origin)<0.001,"Solved arm poses preserve every joint anchor")
			parent = poses[index]

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	verify_socket_roundtrip()
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200,1,100)
	collision.shape = box
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	var actor := NPC.instantiate() as Node3D
	actor.get_node("NPCStateMachine3D").enabled = false
	actor.get_node("InventoryController3D").attachment_debug_logging = false
	level.add_child(actor)
	# The smoothed initial pose has the same bounded convergence window as attack preparation.
	for tick: int in ceili(actor.get_node("BowAttackController3D").preset.maximum_prepare_time*60.0):
		await physics_frame
		if tick%6==5: sample(actor)
	var controller: Node = actor.get_node("BowAttackController3D")
	check(controller._valid(),"Default regenerated Human has two available planar arm chains")
	metrics.idle_aim_degrees = rad_to_deg(controller._aim_error)
	metrics.idle_grip_error = controller._position_error
	check(controller._aim_error<deg_to_rad(5.0) and controller._position_error<0.3,"Idle holding converges to the jointly solved grip and bow direction")
	verify_anatomy(controller)
	# Exercise a small posture-only draw independently from attack charging.
	controller._pre_draw = controller._full_draw*0.1
	controller._solve_remaining = 0.0
	for tick: int in 120:
		await physics_frame
		if tick%6==5: sample(actor)
	check(controller._pre_draw>0.0 and controller._pre_draw<=controller._full_draw*controller.preset.posture_draw_ratio+0.001,"Posture pre-draw stays within its configured fraction")
	check(controller.phase==controller.Phase.IDLE and controller.shots_fired==0 and controller._charge_draw_ratio<0.1,"Posture-only draw cannot complete charging or fire")
	controller.preset = controller.preset.duplicate()
	var pre_draw_limit: float = controller.preset.posture_draw_ratio
	controller.preset.posture_draw_ratio = 0.0
	for tick: int in 120: await physics_frame
	check(is_zero_approx(controller._pre_draw),"Setting posture draw allowance to zero clears a cached pre-draw")
	controller.preset.posture_draw_ratio = pre_draw_limit
	var movement: Node = actor.get_node("GeneratedLegStepMovementController3D")
	var control: Dictionary = movement.get_contact_drive_diagnostics().get("human_speed_control",{})
	check(not control.get("attacking",true),"Holding Bow is not reported as an active attack by locomotion")
	var enemy := Node3D.new()
	enemy.set_script(CHARACTER)
	enemy.faction_id = actor.faction_id+1
	enemy.require_head_and_torso_connectivity = false
	var target := TORSO.instantiate() as PhysicalBodyPart3D
	target.name = "Torso"
	target.freeze = true
	target.max_hp = 10000.0
	target.current_hp = 10000.0
	target.armor = 0.0
	enemy.add_child(target)
	level.add_child(enemy)
	enemy.global_position = actor.get_node("GeneratedParts/Torso").global_position+Vector3(35,0,0)
	await physics_frame
	await physics_frame
	var enemy_point := enemy.position
	enemy.position.z += 30.0
	check(controller.predict_npc_attack(&"bow_shoot",target,0.8).get("reason")==&"target_out_of_bow_plane","Aiming rejects targets that require breaking the holding plane")
	enemy.position = enemy_point
	check(controller.try_start_npc_attack(&"bow_shoot",target,0.8),"A fully physical planar Human can start shooting")
	for tick: int in 480:
		await physics_frame
		if tick%6==5: sample(actor)
		if controller.shots_fired>0 and not controller.is_npc_attack_active() and controller.hits>0: break
	check(controller.shots_fired==1 and controller.damaging_hits==1,"Planar constraints allow a real damaging shot")
	check(metrics.maximum_arm_plane_degrees<12.0,"Arm paper faces stay within the original shoulder plane allowance")
	check(metrics.maximum_arm_anchor_gap<0.08,"Arm joints remain connected during holding and shooting")
	check(metrics.maximum_arm_angular_speed<12.0,"Bounded joint drives avoid the previous 29 rad/s spin")
	var inventory: Node = actor.get_node("InventoryController3D")
	inventory.select_slot(inventory.get_selected_slot())
	await physics_frame
	check(controller._arms.is_empty(),"Unequipping releases the planar pose owner")
	inventory.select_slot(0)
	for tick: int in 120: await physics_frame
	check(controller._valid(),"Re-equipping reacquires intact arms and the string guide")
	sample(actor)
	print("BOW_PLANAR_METRICS ",JSON.stringify(metrics))
	print("BOW_PLANAR_POSE_","PASSED" if failures.is_empty() else "FAILED")
	level.free()
	for arrow: Node in get_nodes_in_group(&"bow_projectiles"): arrow.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func verify_anatomy(controller: Node) -> void:
	var bow: Node3D = controller._bow
	var stored: Transform3D = bow.grip_point_poses[0]
	var marker: Marker3D = bow.get_node("GripPoints/GripPoint_01")
	check(stored.basis.is_equal_approx(marker.basis),"Bow grip data and editor marker use the same rotation")
	var string_hand: Node3D = controller._arms[1].hand
	check(string_hand.get_node("ItemSocket3D").position.is_equal_approx(string_hand.get_node("JointOut").position),"Human string grip uses its own calibrated palm position")
	var postures: Array = []
	for arm: Dictionary in controller._arms:
		var actual: Array[Transform3D] = []
		var angles: Array[float] = []
		var parent: Node3D = arm.anchor_body
		for link: Dictionary in arm.pose_chain:
			actual.append(link.body.global_transform)
			var relative: Basis = (parent.global_transform*Transform3D(link.parent_frame)).basis.orthonormalized().inverse()*(link.body.global_transform*Transform3D(link.child_frame)).basis.orthonormalized()
			angles.append(relative.get_euler().z)
			parent = link.body
		var posture := PLANAR.posture_metrics(arm,actual,angles,controller._direction,controller.preset)
		postures.append(posture)
		check(posture.elbow_elevation_degrees<=controller.preset.maximum_elbow_elevation_degrees+3.0,"Holding elbows remain below the excessive-lift threshold")
		check(posture.wrist_bend_degrees<=controller.preset.maximum_wrist_bend_degrees+3.0,"Holding wrists stay close to their anatomical neutral angle")
		check(posture.elbow_interior_degrees>=90.0 and posture.elbow_interior_degrees<=175.0,"Holding elbows avoid excessive folding or hyperextension")
	metrics["idle_anatomical_postures"] = postures

func verify_socket_roundtrip() -> void:
	var actor := NPC.instantiate() as Node3D
	actor.generate_on_ready = false
	actor.initial_weapon_scene = null
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(actor)
	var hand: Node3D = actor.get_node("GeneratedParts/Arm_L")
	var model_pose: Transform3D = hand.get_node("Model").transform
	var socket: Marker3D = hand.get_node("ItemSocket3D")
	check(socket.position.is_equal_approx(hand.get_node("JointOut").position),"Saved Human assemblies receive their own left palm socket")
	socket.position.x += 0.05
	var custom_socket := socket.transform
	check(actor._capture_manual_layout() and actor.generate_creature(),"Human socket layout can be captured and regenerated")
	hand = actor.get_node("GeneratedParts/Arm_L")
	check(hand.get_node("ItemSocket3D").transform.is_equal_approx(custom_socket),"Regeneration preserves an authored left palm socket")
	check(hand.get_node("Model").transform.is_equal_approx(model_pose),"Adding a left palm socket preserves the complete visual snapshot")
	actor.free()
