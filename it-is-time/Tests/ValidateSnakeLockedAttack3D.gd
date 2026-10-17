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
	for interruption: StringName in [&"escape",&"broken_target",&"freed_target",&"armored_target",&"escape_before_commit"]:
		await check_locked_attack(level,interruption)
	level.free()
	await process_frame
	if not failed: print("SNAKE_LOCKED_ATTACK_VALIDATION_PASSED")
	quit(1 if failed else 0)

func check_locked_attack(level: Node3D, interruption: StringName) -> void:
	var npc := NPC.instantiate()
	enable_attacks(npc)
	npc.generate_on_ready = false
	npc.get_node("SnakeGenerator").overall_scale = 1.0
	level.add_child(npc)
	check(npc.generate_creature(),"Generate locked-target fixture")
	var ai := npc.get_node("NPCStateMachine3D")
	ai.set_physics_process(false)
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
	target.linear_velocity = Vector3.RIGHT*0.6
	await physics_frame
	check(attack.try_start_npc_attack(attack.ACTION,target,0.0),"Admit target before fixing its world point")
	if interruption == &"escape_before_commit":
		target.global_position += Vector3(100,0,100)
		target.linear_velocity = Vector3(30,0,30)
	for tick: int in 300:
		target.global_position += Vector3.RIGHT*0.01
		await physics_frame
		if attack._phase != &"positioning": break
	check(attack._phase == &"preparing" and movement.is_attack_support_locked(),"Commit after settling, before formal preparation")
	if attack._phase != &"preparing":
		npc.free()
		victim.free()
		return
	var plan: Dictionary = attack._plan.duplicate(true)
	if interruption == &"escape_before_commit": check(plan.get("reused_valid_plan",false),"A pre-commit prediction miss reuses the admitted poses and continues preparation")
	check(plan.target_locked and Vector3(plan.aim).is_equal_approx(Vector3(plan.target_position)+Vector3(plan.target_velocity)*float(plan.contact_time)),"Lock the one-time forecast including preparation and extension")
	check(Vector3(plan.target_velocity).x>0.5 and Vector3(plan.aim).x>Vector3(plan.target_position).x,"Moving target uses a forecast rather than its current position")
	attack.set_control_performance_tracking_enabled(true)
	attack.consume_control_performance_stats()
	# Exercise the actual NPC active-attack path when the original victim disappears.
	ai._target = target
	ai._enemy = victim
	ai._active_attack = ai._available_attacks()[0]
	ai._attack_receiver = attack
	ai.current_state = ai.State.ATTACK
	if interruption == &"escape":
		target.global_position += Vector3(40,-3,20)
		target.linear_velocity = Vector3(-15,4,20)
	elif interruption == &"broken_target":
		target.break_part()
	elif interruption == &"freed_target":
		target.free()
		target = null
	elif interruption == &"armored_target":
		target.armor = 10000000.0
		target.linear_velocity = Vector3.ZERO
	var phases := {}
	for tick: int in 1200:
		await physics_frame
		if attack.is_npc_attack_active(): ai._update_combat(1.0/60.0)
		phases[attack._phase] = true
		check(attack._plan.preparation == plan.preparation and attack._plan.strike == plan.strike,"Target changes never re-solve either committed pose")
		check(attack._plan.aim == plan.aim and attack._plan.forward == plan.forward and attack._plan.duration == plan.duration,"Target changes never alter the aim, heading or lunge duration")
		check(attack._plan.reference == plan.reference and attack._plan.root_pose == plan.root_pose,"Target changes retain the locked ground reference and root")
		if movement.is_attack_support_locked():
			check(movement.get_pose_reference().is_equal_approx(plan.reference),"Physical support retains the prediction frame")
		var details: Dictionary = attack.get_attack_diagnostics()
		check(details.locked_aim == plan.aim and details.target_locked == attack.is_npc_attack_active(),"Tracking safely reports the fixed aim even after the target is freed")
		check(attack._last_reason not in [&"target_lost",&"target_left_attack_plane",&"intercept_changed"],"Committed attack ignores target-driven cancellation")
		if not attack.is_npc_attack_active(): break
	var stats: Dictionary = attack.consume_control_performance_stats()
	check(stats.counters.get("plan_requests",0)==0 and stats.counters.get("ik_iterations",0)==0 and stats.counters.get("prediction_shape_queries",0)==0,"Committed execution performs no target replanning or prediction sweep")
	check(phases.has(&"lunging") and phases.has(&"closing") and phases.has(&"rejoining"),"Commit completes extension, closure and physical recovery")
	var expected_result: StringName = &"contact_without_damage" if interruption == &"armored_target" else &"lunge_limit_no_contact"
	check(attack._last_reason == &"completed" and attack._attack_result == expected_result,"Actual contact and armor determine the result of the fixed trajectory")
	check(attack._last_contacts == (1 if interruption == &"armored_target" else 0),"Only physical damage-box overlap counts as mouth contact")
	check(attack._last_hits==0 and (target == null or target.current_hp==target.max_hp or target.is_broken),"Locked trajectory never fabricates remote damage")
	check(movement._attack_owner==null and not movement.is_attack_support_locked() and attack._weapon==null,"Completion releases movement ownership and the temporary hitbox")
	check(attack._mouth_collision_pairs.is_empty() and attack._joint_state.is_empty(),"Completion restores temporary mouth collision and Jaw settings")
	print("SNAKE_LOCKED_ATTACK_RESULT case=",interruption," phases=",phases," aim=",plan.aim," result=",attack._attack_result," recovery=",attack._recovery_result," planning_counters=",stats.counters)
	npc.free()
	victim.free()
	await process_frame
