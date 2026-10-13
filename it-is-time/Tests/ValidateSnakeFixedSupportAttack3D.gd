extends "res://Tests/ValidateSnakeAttacks3D.gd"

func run() -> void:
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
	for scale: float in [0.5,1.0,4.0]: await measure_fixed_bite(level,scale)
	await validate_safety(level,floor_body)
	level.free()
	await process_frame
	if not failed: print("SNAKE_FIXED_SUPPORT_VALIDATION_PASSED")
	quit(1 if failed else 0)

func measure_fixed_bite(level: Node3D, size: float) -> void:
	var npc := NPC.instantiate()
	enable_attacks(npc)
	npc.generate_on_ready = false
	npc.get_node("SnakeGenerator").overall_scale = size
	npc.position.y = 0.01
	level.add_child(npc)
	check(npc.generate_creature(),"Generate fixed support bite")
	npc.get_node("NPCStateMachine3D").set_physics_process(false)
	var movement := npc.get_node("SnakeMovementController3D")
	var attack := npc.get_node("SnakeBiteAttackController3D")
	for tick: int in 150: await physics_frame
	var victim := CHARACTER.instantiate()
	victim.faction_id = 2
	var target := PART.instantiate() as PhysicalBodyPart3D
	target.tags.assign([PhysicalBodyPart3D.BodyPartTag.Torso,PhysicalBodyPart3D.BodyPartTag.Head])
	target.max_hp = 10000000.0
	target.armor = 0.0
	target.left_distance = 1.5*size
	target.right_distance = 1.5*size
	target.top_distance = 2.0*size
	target.bottom_distance = 2.0*size
	target.collision_thickness = 2.0*size
	target.freeze = true
	victim.add_child(target)
	level.add_child(victim)
	target.global_position = attack.head.to_global(attack._mouth_offset())+Vector3.RIGHT*6.0*size
	await physics_frame
	check(attack.try_start_npc_attack(attack.ACTION,target,0.0),"Start physically reachable fixed-root bite")
	var positions: Dictionary = {}
	var fixed_reference := Transform3D.IDENTITY
	var maximum_ground_displacement := 0.0
	var maximum_head_slide := 0.0
	var maximum_head_speed := 0.0
	var phases: Dictionary = {}
	var support_started := false
	for tick: int in 1200:
		await physics_frame
		phases[attack._phase] = true
		if movement.is_attack_support_locked():
			if not support_started:
				support_started = true
				fixed_reference = movement.get_pose_reference()
				for row: Dictionary in movement._belly: positions[row.body] = row.body.global_position
			check(fixed_reference.is_equal_approx(movement.get_pose_reference()),"Attack reference remains fixed in world space")
			check(movement._attack_velocity.is_zero_approx() and is_zero_approx(movement._turn_rate),"Locked support receives no translation or whole-body turn command")
			for row: Dictionary in movement._belly:
				var offset: Vector3 = row.body.global_position-Vector3(positions[row.body])
				maximum_ground_displacement = maxf(maximum_ground_displacement,offset.slide(Vector3.UP).length())
				check(Vector3(row.movement_force).is_zero_approx(),"Ground blocks receive support forces instead of attack propulsion")
			var joint: Generic6DOFJoint3D = attack._links[-1].joint
			var parent: Node3D = joint.get_node(joint.node_a)
			var a: Transform3D = parent.global_transform*Transform3D(joint.get_meta(&"generated_joint_frame_a"))
			var b: Transform3D = attack.head.global_transform*Transform3D(joint.get_meta(&"generated_joint_frame_b"))
			maximum_head_slide = maxf(maximum_head_slide,(a.affine_inverse()*b.origin).length())
			maximum_head_speed = maxf(maximum_head_speed,attack.head.linear_velocity.length())
		if not attack.is_npc_attack_active(): break
	check(support_started and phases.has(&"lunging") and phases.has(&"rejoining"),"Fixed support remains active through attack and recovery")
	check(target.current_hp<target.max_hp,"Upper-body-only bite causes actual damage")
	check(maximum_ground_displacement<0.15*size,"Ground blocks remain near their captured world positions")
	check(maximum_head_slide<0.65*size,"Head stays connected to its raised chain")
	check(attack._last_reason == &"completed","Fixed-root bite completes verified recovery")
	print("SNAKE_FIXED_SUPPORT_RESULT scale=",size," max_ground_displacement=",maximum_ground_displacement," head_slide=",maximum_head_slide," head_speed=",maximum_head_speed," phases=",phases," reason=",attack._last_reason)
	var near := target.global_position
	target.global_position += Vector3.RIGHT*100.0*size
	attack._cooldown = 0.0
	await physics_frame
	check(not attack.predict_npc_attack(attack.ACTION,target,0.0).hit,"Removing whole-body travel rejects unreachable victims")
	target.global_position = near
	npc.free()
	victim.free()
	await process_frame

func validate_safety(level: Node3D, floor_body: StaticBody3D) -> void:
	var npc := NPC.instantiate()
	enable_attacks(npc)
	npc.generate_on_ready = false
	npc.get_node("SnakeGenerator").overall_scale = 1.0
	npc.position.y = 0.01
	level.add_child(npc)
	check(npc.generate_creature(),"Generate interruption fixture")
	npc.get_node("NPCStateMachine3D").set_physics_process(false)
	var movement := npc.get_node("SnakeMovementController3D")
	var attack := npc.get_node("SnakeBiteAttackController3D")
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
	for tick: int in 150: await physics_frame
	target.global_position = attack.head.to_global(attack._mouth_offset())+Vector3.RIGHT*6.0
	attack.data = attack.data.duplicate()
	attack.data.burst_speed = 2.0
	target.linear_velocity = Vector3.RIGHT*0.3
	attack._velocity_frame = -1
	var slow: Dictionary = attack._make_plan(target,true)
	check(slow.timing_ready and slow.duration>attack.data.lunge_time*attack._time_scale()/attack.data.head_extension_speed_multiplier,"Slow Head extends the predicted contact time")
	check(is_equal_approx(slow.contact_time,slow.alignment_time+slow.preparation_time+slow.duration),"Extended contact time matches the complete plan")
	check(Vector3(slow.aim).is_equal_approx(target.global_position+target.linear_velocity*float(slow.contact_time)),"Longer extension extrapolates the target at the same future time")
	attack.data.burst_speed = 16.0
	target.linear_velocity = Vector3.ZERO
	attack._velocity_frame = -1
	attack._cached_plan = {}
	await physics_frame
	check(attack.try_start_npc_attack(attack.ACTION,target,0.0),"Start lateral escape fixture")
	for tick: int in 300:
		await physics_frame
		if attack._phase == &"preparing": break
	check(movement.is_attack_support_locked(),"Ground locks before preparation")
	target.global_position.z += 20.0
	await physics_frame
	await physics_frame
	check(attack._phase == &"recovering" and attack._last_reason == &"target_left_attack_plane","Off-plane target triggers recovery without turning the supporting belly")
	attack.cancel_action()
	for tick: int in 180: await physics_frame
	target.global_position = attack.head.to_global(attack._mouth_offset())+Vector3.RIGHT*6.0
	attack._cooldown = 0.0
	await physics_frame
	check(attack.try_start_npc_attack(attack.ACTION,target,0.0),"Start ground-loss fixture")
	for tick: int in 300:
		await physics_frame
		if attack._phase == &"preparing": break
	floor_body.collision_layer = 0
	floor_body.collision_mask = 0
	for tick: int in 120:
		await physics_frame
		if not attack.is_npc_attack_active(): break
	check(not attack.is_npc_attack_active() and attack._last_reason == &"ground_support_lost","Loss of all supporting ground releases attack control")
	check(not movement.is_attack_support_locked() and movement._attack_owner == null and attack._weapon == null,"Ground loss cleans the lock and damage volume")
	check(attack._mouth_collision_pairs.is_empty() and attack._joint_state.is_empty(),"Interruption restores collision exceptions and Jaw limits")
	print("SNAKE_FIXED_SUPPORT_SAFETY_RESULT slow_contact_time=",slow.contact_time," end_reason=",attack._last_reason)
	npc.free()
	victim.free()
	await process_frame
