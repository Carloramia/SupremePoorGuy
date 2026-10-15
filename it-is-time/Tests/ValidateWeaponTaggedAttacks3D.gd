extends SceneTree

const POSE = preload("res://Scripts/Combat/WeaponArmPose3D.gd")
const ROOT := "res://Scenes/Creatures/Characters/Human/Armed/"
var failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func run() -> void:
	for name: String in ["Spear1","ClawGauntlet","CurvedSword","Flail","Spear5","Shield"]:
		await verify_weapon(name)
	await verify_multiple_arms()
	await verify_single_arm()
	await verify_npc()
	print("WEAPON_TAGGED_ATTACKS_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func create_actor(name: String) -> Node3D:
	var actor := load(ROOT+"Generate_Human_"+name+".tscn").instantiate() as Node3D
	actor.get_node("InventoryController3D").inventory_ui_enabled = false
	actor.get_node("InventoryController3D").attachment_debug_logging = false
	root.add_child(actor)
	await process_frame
	await process_frame
	for component: Node in actor.get_children(): component.set_physics_process(false)
	for body: RigidBody3D in actor.find_children("*","RigidBody3D",true,false):
		body.freeze = true
		body.gravity_scale = 0.0
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	return actor

func verify_weapon(name: String) -> void:
	var actor := await create_actor(name)
	var swing := actor.get_node("LimbSwingController3D") as LimbSwingController3D
	var inventory := actor.get_node("InventoryController3D")
	var weapon := inventory.get_equipped_item() as SampleWeapon3D
	var state: Dictionary = swing._states[0].members[0]
	check(weapon.primary_attack_tag in weapon.weapon_tags,"Primary tag must be present: "+name)
	check(state.preset == weapon.get_arm_attack_preset(),"Actual holder must load the weapon preset: "+name)
	check(state.binding.swing_preset.resource_path.ends_with("HumanArmSwing.tres"),"Weapon must not mutate the Arm's unarmed preset")
	weapon.weapon_tags.append(SampleWeapon3D.WeaponTag.Sword)
	check(weapon.get_arm_attack_preset() == state.preset,"Extra tags must not change the primary attack")
	var original: LimbSwingPresetBase = state.preset
	weapon.arm_attack_preset_override = original.duplicate() as LimbSwingPresetBase
	swing.refresh_weapon_presets()
	check(state.preset == weapon.arm_attack_preset_override and state.preset != original,"A weapon may use its own independent attack preset")
	weapon.arm_attack_preset_override = null
	swing.refresh_weapon_presets()
	weapon.weapon_tags.clear()
	swing.refresh_weapon_presets()
	check(state.preset == state.binding.swing_preset,"Untagged weapon must retain the original swing")
	weapon.weapon_tags.append(weapon.primary_attack_tag)
	swing.refresh_weapon_presets()
	check(state.preset == original,"Tag restoration must reload the shared preset")
	check(swing.begin_charge(0),"Short charge starts")
	check(swing.release_charge(0) and int(state.mode) == swing.SwingState.IDLE,"Too-short charge must cancel")
	check(state.pose_snapshot.is_empty(),"Short charge must restore all chain constraints")
	var snapshots: Array[Dictionary] = []
	for link: Dictionary in state.pose_chain:
		for axis: String in ["x","y","z"]:
			snapshots.append({"joint":link.joint,"key":"angular_limit_%s/enabled"%axis,"value":link.joint.get("angular_limit_%s/enabled"%axis)})
		link.body.freeze = false
	await physics_frame
	check(swing.begin_charge(0),"Physical charge starts")
	for tick: int in 75:
		swing._process_member(0,state,true,1.0/60.0)
		swing._apply_chain_followers(state)
		await physics_frame
	var hand: RigidBody3D = state.effector
	var start := hand.global_position
	var direction: Vector3 = state.pose_direction
	var maximum_extension := 0.0
	var alignment: float = (hand.global_basis*Vector3(state.weapon_forward_local)).normalized().dot(direction)
	if swing._uses_weapon_pose(state): print("WEAPON_PREP ",name," actual=",hand.global_position," planned=",POSE.poses(state,state.preset,direction,Vector3.UP,0.0)[-1].origin," pivot=",state.anchor_body.to_global(state.anchor_local_position))
	swing.release_charge(0)
	check(weapon.swing_damage_active and weapon.swing_sequence == 1,"Attack must open only its weapon damage window")
	if swing._uses_weapon_pose(state):
		var planned := POSE.poses(state,state.preset,direction,Vector3.UP,0.8)
		var hitbox: CollisionShape3D
		for shape: CollisionShape3D in swing.HIT_PREDICTION.shapes(hand):
			if shape.has_meta(&"equipped_item") and shape.get_meta(&"equipped_item") == weapon: hitbox = shape; break
		var target := RigidBody3D.new()
		target.freeze = true
		target.collision_layer = 2
		target.collision_mask = 0
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE
		collision.shape = box
		target.add_child(collision)
		root.add_child(target)
		var planned_shape: Transform3D = planned[-1]*(hand.global_transform.affine_inverse()*hitbox.global_transform)
		var bounds := hitbox.shape.get_debug_mesh().get_aabb()
		var point := planned_shape*bounds.get_center()
		var center := Vector3.ZERO
		for vertex: Vector3 in (hitbox.shape as ConvexPolygonShape3D).points:
			center += vertex
			var candidate := planned_shape*vertex
			if candidate.dot(direction) > point.dot(direction): point = candidate
		center /= (hitbox.shape as ConvexPolygonShape3D).points.size()
		target.global_position = (planned_shape*center).lerp(point,0.6)
		await physics_frame
		await physics_frame
		# Prediction is normally requested while idle; exercise the same read-only trajectory directly.
		var predicted := swing._predict_weapon_pose(state,target,0.6,24,0.1,actor.get_world_3d().direct_space_state,[])
		print("WEAPON_PREDICTION ",name," result=",predicted)
		check(predicted.hit,"Shared thrust prediction must detect a target on the weapon path: "+name)
		target.position += Vector3(0,0,100)
		await physics_frame
		await physics_frame
		check(not swing._predict_weapon_pose(state,target,0.6,24,0.1,actor.get_world_3d().direct_space_state,[]).hit,"Off-path targets must not authorize an attack")
		target.free()
	for tick: int in 65:
		swing._process_member(0,state,false,1.0/60.0)
		swing._apply_chain_followers(state)
		maximum_extension = maxf(maximum_extension,(hand.global_position-start).dot(direction))
		await physics_frame
	if swing._uses_weapon_pose(state):
		print("WEAPON_POSE_PHYSICS ",name," alignment=",alignment," forward_travel=",maximum_extension," reach=",POSE.reach(state.pose_chain))
		check(alignment > 0.65 and maximum_extension > 0.15,"Charge and release must physically aim and extend the arm: "+name)
	check(not weapon.swing_damage_active,"Damage window must close before recovery")
	# Switching equipment during a released attack must synchronously cancel and restore constraints.
	swing._cancel_all_members()
	check(swing.begin_charge(0),"Switch cancellation charge starts")
	swing.add_charge_time(0,0.5)
	swing.release_charge(0)
	inventory.select_slot(inventory.get_selected_slot())
	check(int(state.mode) == swing.SwingState.IDLE and not weapon.swing_damage_active,"Unequip must cancel the old attack before removing merged colliders")
	check(state.preset == state.binding.swing_preset and state.pose_snapshot.is_empty(),"Unequip must restore the unarmed preset and chain snapshots")
	for saved: Dictionary in snapshots: check(saved.joint.get(saved.key) == saved.value,"All temporary angular limits must be restored")
	actor.queue_free()
	await process_frame
	print("WEAPON_TAGGED_ATTACK_PASS ",name)

func verify_single_arm() -> void:
	var actor := load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate() as Node3D
	root.add_child(actor)
	for component: Node in actor.get_children(): component.set_physics_process(false)
	for body: RigidBody3D in actor.find_children("*","RigidBody3D",true,false): body.freeze = true
	var inventory := actor.get_node("InventoryController3D")
	inventory.inventory_ui_enabled = false
	inventory.attachment_debug_logging = false
	check(inventory.equip_initial_weapon(load("res://Scenes/Items/Weapons/Human/Human5Spear.tscn")),"Single-body Arm must equip a tagged weapon")
	var swing := actor.get_node("LimbSwingController3D") as LimbSwingController3D
	var state: Dictionary = swing._states[0].members[0]
	check(state.pose_chain.size() == 1,"Legacy Arm must retain its single rigid body")
	var prep := POSE.poses(state,state.preset,Vector3.RIGHT,Vector3.UP,0.0)
	var strike := POSE.poses(state,state.preset,Vector3.RIGHT,Vector3.UP,1.0)
	check((strike[0].origin-prep[0].origin).x > 0.1,"Single-body Arm uses an aimed forward arc without stretching the shoulder")
	var root_position: Vector3 = state.anchor_body.to_global(state.pose_anchor_local)
	check((strike[0]*Vector3(state.pose_chain[0].proximal)).distance_to(root_position)<0.001,"Legacy shoulder remains attached")
	actor.queue_free()
	await process_frame

func verify_npc() -> void:
	var actor := load(ROOT+"Generate_Human_Spear5_NPC.tscn").instantiate() as Node3D
	actor.get_node("NPCStateMachine3D").enabled = false
	actor.get_node("InventoryController3D").inventory_ui_enabled = false
	actor.get_node("InventoryController3D").attachment_debug_logging = false
	root.add_child(actor)
	await process_frame
	await process_frame
	for component: Node in actor.get_children(): component.set_physics_process(false)
	for body: RigidBody3D in actor.find_children("*","RigidBody3D",true,false):
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	var swing := actor.get_node("LimbSwingController3D") as LimbSwingController3D
	var state: Dictionary = swing._states[0].members[0]
	for link: Dictionary in state.pose_chain:
		link.body.freeze = false
		link.body.gravity_scale = 0.0
	var target := Node3D.new()
	root.add_child(target)
	target.position = state.anchor_body.global_position+Vector3(10,0,0)
	await physics_frame
	check(swing.get_npc_attack_preferred_distance(&"PrimaryArm",target)>0.0,"NPC must derive spacing from its selected weapon trajectory")
	check(swing.try_start_npc_attack(&"PrimaryArm",target,0.6),"NPC must start the same tagged attack as the player")
	var weapon: SampleWeapon3D = actor.get_node("InventoryController3D").get_equipped_item()
	for tick: int in 120:
		swing._physics_process(1.0/60.0)
		await physics_frame
	check(weapon.swing_sequence == 1,"NPC must aim, charge and release the selected thrust")
	swing.cancel_npc_attack()
	check(not weapon.swing_damage_active and state.pose_snapshot.is_empty(),"NPC cancellation restores chain constraints and damage window")
	target.free()
	actor.queue_free()
	await process_frame
	print("WEAPON_TAGGED_NPC_PASS")

func verify_multiple_arms() -> void:
	var actor := await create_actor("Spear5")
	var left := actor.get_node("GeneratedParts/Arm_L") as PhysicalBodyPart3D
	var binding := ArmSwingBinding.new()
	binding.swing_preset = load("res://Resources/Combat/HumanArmSwing.tres")
	binding.drive_body_path = ^"../Arm_L_Limb_2"
	binding.follower_paths = [^"../Arm_L_Limb_1",^"."]
	for joint: Generic6DOFJoint3D in actor.get_node("GeneratedParts/Joints").get_children():
		if joint.get_node_or_null(joint.node_b) == actor.get_node("GeneratedParts/Arm_L_Limb_2"): binding.joint_path = NodePath("../Joints/"+str(joint.name))
	left.arm_swing_bindings.append(binding)
	var swing := actor.get_node("LimbSwingController3D") as LimbSwingController3D
	swing.refresh_arm_bindings(true)
	swing.refresh_weapon_presets()
	var weapon: SampleWeapon3D = actor.get_node("InventoryController3D").get_equipped_item()
	check(swing.get_group_member_count(0) == 2,"Both Arm chains must remain in the control group")
	for state: Dictionary in swing._states[0].members:
		check((state.preset is WeaponArmAttackPreset) == (state.effector == weapon.rigid_attachment_holder),"Only the actual holder must change its attack")
		if state.effector == left:
			check(swing._begin_member(0,state),"Unarmed group member may still attack")
			state.charge_time = 0.6
			swing._release_member(0,state)
			check(not weapon.swing_damage_active,"A different Arm must not activate the held weapon's damage")
	swing._cancel_all_members()
	actor.queue_free()
	await process_frame
