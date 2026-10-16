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
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-900,0,-900),Vector3(900,0,-900),Vector3(900,0,900),Vector3(-900,0,900)])
	mesh.add_polygon(PackedInt32Array([0,1,2,3]))
	region.navigation_mesh = mesh
	level.add_child(region)
	for side: float in [1.0,-1.0]: await validate_lane(level,side)
	level.free()
	await process_frame
	if not failed: print("SNAKE_AXIS_POSITIONING_PASSED")
	quit(1 if failed else 0)

func validate_lane(level: Node3D, side: float) -> void:
	var npc := NPC.instantiate()
	enable_attacks(npc)
	npc.generate_on_ready = false
	npc.get_node("SnakeGenerator").overall_scale = 1.0
	npc.rotation.y = PI if side < 0.0 else 0.0
	level.add_child(npc)
	check(npc.generate_creature(),"Generate axis positioning fixture")
	var ai := npc.get_node("NPCStateMachine3D")
	ai.set_physics_process(false)
	ai._generated_facing_side = side
	ai._generated_facing_candidate = side
	check(ai.generated_x_axis_facing,"Snake NPC enables left/right facing")
	var movement := npc.get_node("SnakeMovementController3D")
	var attack := npc.get_node("SnakeBiteAttackController3D")
	for tick: int in 150: await physics_frame
	var victim := CHARACTER.instantiate()
	victim.faction_id = 2
	var target := PART.instantiate() as PhysicalBodyPart3D
	target.tags.assign([PhysicalBodyPart3D.BodyPartTag.Torso,PhysicalBodyPart3D.BodyPartTag.Head])
	target.max_hp = 10000000.0
	target.armor = 0.0
	target.left_distance = 1.5
	target.right_distance = 1.5
	target.top_distance = 2.0
	target.bottom_distance = 2.0
	target.collision_thickness = 2.0
	target.freeze = true
	victim.add_child(target)
	level.add_child(victim)
	ai._enemy = victim
	ai._target = target
	target.global_position = attack.head.to_global(attack._mouth_offset())+Vector3(side*6.0,0,side*8.0)
	await physics_frame
	var alignment: Dictionary = attack._alignment(target)
	check(Vector3(alignment.forward).is_equal_approx(Vector3.RIGHT*side),"Off-lane enemies cannot request diagonal body yaw")
	var prediction: Dictionary = attack.predict_npc_attack(attack.ACTION,target,0.0)
	check(not prediction.hit and prediction.reason == &"z_alignment_pending","An off-plane target waits for lane movement before attack takeover")
	check(not attack.try_start_npc_attack(attack.ACTION,target,0.0) and movement._attack_owner == null,"Off-lane attack cannot lock ground support")
	var origin: Vector3 = ai._get_navigation_origin_position()
	var lane_target := target.global_position
	target.global_position = origin-Vector3.RIGHT*side*4.0
	prediction = attack.predict_npc_attack(attack.ACTION,target,0.0)
	check(not prediction.hit and prediction.reason == &"body_turn_pending","A target crossing behind cannot freeze the old side by starting an attack")
	target.global_position = lane_target
	var distance := absf(target.global_position.x-origin.x)
	var raw: Dictionary = attack.get_npc_attack_approach(attack.ACTION,target,distance,origin)
	check(absf(Vector3(raw.goal).x-origin.x)<0.01,"Lane correction keeps the current X station inside its stop band")
	ai._reposition_target = target
	ai._reposition_distance = distance
	var options: Array = ai._available_attacks()
	check(ai._plan_attack_distance(origin.distance_to(target.global_position),options),"Z error schedules movement even inside the X stop band")
	check(absf(ai._requested_target_position.z-raw.goal.z)<0.01,"Navigation compensates the real raised-root lateral offset")
	ai.change_state(ai.State.MOVE_TO_TARGET)
	check(ai.get_npc_movement_speed_scale(5.0)>0.0,"Zero X distance error does not suppress Z propulsion")
	# Exercise hysteresis without changing the physical mouth's authored plane.
	var reference: Transform3D = alignment.reference
	target.global_position = reference*Vector3((reference.affine_inverse()*target.global_position).x,(reference.affine_inverse()*target.global_position).y,movement.get_attack_root_offset().z+float(alignment.tolerance)*0.25)
	check(not ai._attack_approach(options[0]).is_empty() and not ai._lane_alignment_active,"Reaching the inner tolerance ends lane correction")
	target.global_position += reference.basis.z*float(alignment.tolerance)*0.5
	ai._attack_approach(options[0])
	check(not ai._lane_alignment_active,"Small lateral changes inside the outer tolerance do not restart correction")
	# The actual NPC must walk sideways and damage a victim, with no diagonal heading command.
	target.global_position = attack.head.to_global(attack._mouth_offset())+Vector3(side*6.0,0,side*8.0)
	ai._clear_reposition()
	ai.change_state(ai.State.WAITING)
	ai.set_physics_process(true)
	var start_z: float = movement.get_control_anchor().global_position.z
	var used_path := false
	var used_lane := false
	var maximum_command_z := 0.0
	var locked_reference := Transform3D.IDENTITY
	var locked := false
	for tick: int in 2400:
		await physics_frame
		used_path = used_path or movement._path_ready
		used_lane = used_lane or ai._lane_alignment_active
		maximum_command_z = maxf(maximum_command_z,absf(movement._held_heading.z))
		if movement.is_attack_support_locked():
			if not locked:
				locked = true
				locked_reference = movement.get_pose_reference()
			check(movement.get_pose_reference().is_equal_approx(locked_reference),"Attack support stays fixed after lane alignment")
		if target.current_hp < target.max_hp: break
	check(used_lane and used_path,"NPC aligns through its normal S-route locomotion")
	check(absf(movement.get_control_anchor().global_position.z-start_z)>1.0,"The physical Snake translates along Z, accounting for the S route's root offset")
	check(maximum_command_z<0.0001,"Movement and attack commands remain on world +/-X")
	check(locked and target.current_hp<target.max_hp,"Lane-aligned NPC completes preparation and inflicts real damage")
	print("SNAKE_AXIS_RESULT side=",side," damage=",target.max_hp-target.current_hp," z_travel=",movement.get_control_anchor().global_position.z-start_z," command_z=",maximum_command_z," state=",ai.get_state_diagnostics()," attack=",attack.get_attack_diagnostics())
	ai.set_physics_process(false)
	npc.free()
	victim.free()
	await process_frame
