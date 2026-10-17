extends "res://Tests/ValidateSnakeAttacks3D.gd"

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var settings := preload("res://Scripts/Creatures/SnakeBiteAttackData.gd").new()
	for value: float in [-1.0,91.0,NAN,INF]:
		settings.attack_bend_limit_degrees = value
		check(not settings.is_valid(),"Invalid attack bend limits are rejected")
	settings.attack_bend_limit_degrees = 45.0
	for value: float in [-1.0,0.0,NAN,INF]:
		settings.bend_restore_speed_degrees = value
		check(not settings.is_valid(),"Invalid restoration speeds are rejected")
	settings.bend_restore_speed_degrees = 60.0
	check(settings.is_valid(),"Independent attack bend settings are valid")
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000,1,2000)
	collider.shape = box
	floor_body.add_child(collider)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	var npc := NPC.instantiate()
	enable_attacks(npc)
	npc.generate_on_ready = false
	level.add_child(npc)
	check(npc.generate_creature(),"Generate independent attack-limit fixture")
	npc.get_node("NPCStateMachine3D").set_physics_process(false)
	var movement := npc.get_node("SnakeMovementController3D")
	var attack := npc.get_node("SnakeBiteAttackController3D")
	attack.data = attack.data.duplicate()
	for tick: int in 150: await physics_frame
	var original: Dictionary = {}
	for joint: Generic6DOFJoint3D in npc.get_node("GeneratedParts/Joints").get_children():
		original[joint] = Vector2(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT))
	var victim := CHARACTER.instantiate()
	victim.faction_id = 2
	var target := PART.instantiate() as PhysicalBodyPart3D
	target.tags.assign([PhysicalBodyPart3D.BodyPartTag.Torso,PhysicalBodyPart3D.BodyPartTag.Head])
	target.max_hp = 10000000.0
	target.armor = 0.0
	target.left_distance = 0.5
	target.right_distance = 0.5
	target.top_distance = 0.5
	target.bottom_distance = 0.5
	target.collision_thickness = 1.0
	target.freeze = true
	victim.add_child(target)
	level.add_child(victim)
	var base: Vector3 = movement._belly[-1].body.global_position
	target.global_position = Vector3(base.x,20.0,base.z)
	await physics_frame
	attack.data.attack_bend_limit_degrees = 0.0
	attack.refresh_physics_query_cache()
	var previous: Dictionary = attack.predict_npc_attack(attack.ACTION,target,0.0)
	attack.data.attack_bend_limit_degrees = 45.0
	attack.refresh_physics_query_cache()
	var expanded: Dictionary = attack.predict_npc_attack(attack.ACTION,target,0.0)
	check(not previous.hit and expanded.hit,"Expanded bend range admits the previously missed near-root target")
	for joint: Generic6DOFJoint3D in original:
		check(original[joint].is_equal_approx(Vector2(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT))),"Prediction cannot widen live joints")
	check(attack.try_start_npc_attack(attack.ACTION,target,0.0),"Start expanded-range bite")
	for link: Dictionary in attack._links:
		check(is_equal_approx(link.lower/0.9,link.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)) and is_equal_approx(link.upper/0.9,link.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)),"Prediction and physical attack limits share the same margin")
	var attack_joints: Array = attack._links.map(func(link: Dictionary): return link.joint)
	for joint: Generic6DOFJoint3D in original:
		if joint in attack_joints or joint==attack._jaw_joint: continue
		check(original[joint].is_equal_approx(Vector2(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT))),"Grounded spine limits remain unchanged")
	var last_active: Dictionary = {}
	for tick: int in 1500:
		await physics_frame
		if attack.is_npc_attack_active():
			last_active = attack.get_attack_diagnostics()
		if not attack.is_npc_attack_active() and not movement.is_connection_recovering(): break
	if attack._last_reason!=&"completed": print("SNAKE_BEND_RECOVERY_DIAGNOSTIC ",last_active)
	check(attack._last_reason==&"completed" and target.current_hp<target.max_hp,"Expanded near-root bite physically hits and completes recovery")
	for joint: Generic6DOFJoint3D in original:
		check(not joint.has_meta(&"snake_bend_restore") and original[joint].is_equal_approx(Vector2(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT))),"Every joint returns to its standing limits")
	var completed_reason: StringName = attack._last_reason
	target.global_position = attack.head.to_global(attack._mouth_offset())+Vector3.RIGHT*6.0
	await physics_frame
	attack._cooldown = 0.0
	check(attack.try_start_npc_attack(attack.ACTION,target,0.0),"Start interruption fixture with expanded limits")
	attack.cancel_action(&"test_interruption")
	for tick: int in 240:
		await physics_frame
		if not movement.is_connection_recovering(): break
	for link: Dictionary in attack._links:
		check(not link.joint.has_meta(&"snake_bend_restore") and original[link.joint].is_equal_approx(Vector2(link.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),link.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT))),"Interrupted attacks also restore standing limits")
	var joint: Generic6DOFJoint3D = attack._links[0].joint
	joint.set_meta(&"snake_bend_restore",{"limits":original[joint],"enabled":true,"speed":deg_to_rad(60.0),"restoring":true})
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,-deg_to_rad(45.0))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,deg_to_rad(45.0))
	for tick: int in 30:
		check(not movement._restore_bend_limit(joint,Basis(Vector3.BACK,deg_to_rad(40.0)),Basis.IDENTITY,0.0,1.0/60.0),"A still-bent limb cannot be forced through the standing stop")
		check(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)>=deg_to_rad(42.0)-0.00001,"Actual bend keeps an angular safety margin")
	for tick: int in 60: movement._restore_bend_limit(joint,Basis.IDENTITY,Basis.IDENTITY,0.0,1.0/60.0)
	check(not joint.has_meta(&"snake_bend_restore"),"Gradual contraction finishes after the pose returns")
	print("SNAKE_ATTACK_BEND_RESULT previous=",previous.reason," expanded=",expanded.reason," damage=",target.max_hp-target.current_hp," recovery=",completed_reason," interruption=",attack._last_reason)
	level.free()
	await process_frame
	if not failed: print("SNAKE_ATTACK_BEND_LIMITS_PASSED")
	quit(1 if failed else 0)
