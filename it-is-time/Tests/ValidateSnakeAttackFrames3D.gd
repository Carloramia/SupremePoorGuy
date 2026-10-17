extends "res://Tests/ValidateSnakeAttacks3D.gd"

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
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
	for velocity: Vector3 in [Vector3.ZERO,Vector3.LEFT*0.6,Vector3.RIGHT*0.6,Vector3.BACK*0.05]:
		await check_intercept(level,velocity)
	level.free()
	await process_frame
	if not failed: print("SNAKE_ATTACK_FRAMES_PASSED")
	quit(1 if failed else 0)

func check_intercept(level: Node3D, velocity: Vector3) -> void:
	var npc := NPC.instantiate()
	enable_attacks(npc)
	npc.generate_on_ready = false
	npc.get_node("SnakeGenerator").overall_scale = 1.0
	level.add_child(npc)
	check(npc.generate_creature(),"Generate moving intercept fixture")
	npc.get_node("NPCStateMachine3D").set_physics_process(false)
	var attack := npc.get_node("SnakeBiteAttackController3D")
	var movement := npc.get_node("SnakeMovementController3D")
	for tick: int in 150: await physics_frame
	var victim := CHARACTER.instantiate()
	victim.faction_id = 2
	var target := PART.instantiate() as PhysicalBodyPart3D
	target.tags.assign([PhysicalBodyPart3D.BodyPartTag.Torso,PhysicalBodyPart3D.BodyPartTag.Head])
	target.freeze = true
	target.max_hp = 10000000.0
	target.armor = 0.0
	target.left_distance = 1.5
	target.right_distance = 1.5
	target.top_distance = 2.0
	target.bottom_distance = 2.0
	target.collision_thickness = 2.0
	victim.add_child(target)
	level.add_child(victim)
	target.global_position = attack.head.to_global(attack._mouth_offset())+Vector3.RIGHT*6.0
	target.linear_velocity = velocity
	await physics_frame
	check(attack.try_start_npc_attack(attack.ACTION,target,0.0),"Admit reachable moving target")
	var launched := false
	var ground_error := 0.0
	var reference := Transform3D.IDENTITY
	var locked := false
	for tick: int in 1200:
		target.global_position += velocity/60.0
		target.linear_velocity = velocity
		await physics_frame
		if movement.is_attack_support_locked():
			if not locked:
				locked = true
				reference = movement.get_pose_reference()
			check(reference.is_equal_approx(attack._plan.reference),"Locked plan retains the committed support frame")
			ground_error = maxf(ground_error,movement._attack_ground_error)
		launched = launched or attack._phase == &"lunging"
		if locked and attack.is_npc_attack_active(): check(attack._plan.target_locked,"Attack keeps its committed world target")
		if not attack.is_npc_attack_active(): break
	check(launched and target.current_hp<target.max_hp,"Physical intercept damages static, approaching, receding and lateral-moving targets")
	check(ground_error<0.2,"Intercept retains the supporting ground S footprint")
	check(attack._attack_result == &"hit" and attack._recovery_result == &"completed","Recovery does not overwrite attack outcome")
	print("SNAKE_ATTACK_FRAME_RESULT velocity=",velocity," hit=",attack._last_hits," ground_error=",ground_error," locked_aim=",attack._plan.aim," attack_result=",attack._attack_result," recovery_result=",attack._recovery_result)
	npc.free()
	victim.free()
	await process_frame
