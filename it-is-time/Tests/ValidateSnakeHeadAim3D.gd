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
	var baseline := await measure(level,1.0,false)
	var faster := await measure(level,1.5,false)
	await measure(level,1.5,true)
	check(faster.quarter_time < baseline.quarter_time*0.9,"Faster extension physically reaches a common relative travel milestone earlier")
	check(faster.peak_relative_speed > baseline.peak_relative_speed*1.05,"Head extends faster relative to its supporting root, not just through body translation")
	level.free()
	await process_frame
	if not failed: print("SNAKE_HEAD_AIM_VALIDATION_PASSED")
	quit(1 if failed else 0)

func measure(level: Node3D, multiplier: float, move_target: bool) -> Dictionary:
	var npc := NPC.instantiate()
	enable_attacks(npc)
	npc.generate_on_ready = false
	npc.get_node("SnakeGenerator").overall_scale = 1.0
	npc.position.y = 0.01
	level.add_child(npc)
	check(npc.generate_creature(),"Generate head aiming fixture")
	npc.get_node("NPCStateMachine3D").set_physics_process(false)
	var movement := npc.get_node("SnakeMovementController3D")
	var attack := npc.get_node("SnakeBiteAttackController3D")
	attack.data = attack.data.duplicate()
	attack.data.head_extension_speed_multiplier = multiplier
	var pitch := rad_to_deg(atan2(attack._head_rest_forward.y,attack._head_rest_forward.x))
	check(absf(pitch-19.234)<0.1,"Generated Head retains its approximately 19.2 degree natural visual pitch")
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
	target.global_position = attack.head.to_global(attack._mouth_offset())+Vector3.RIGHT*6.0
	await physics_frame
	check(attack.try_start_npc_attack(attack.ACTION,target,0.0),"Start aimed bite")
	var root_body: RigidBody3D = movement._belly[-1].body
	var launched := false
	var shifted := false
	var start_relative := Vector3.ZERO
	var extension := Vector3.ZERO
	var peak_relative_speed := 0.0
	var half_time := INF
	var quarter_time := INF
	var maximum_progress := 0.0
	var launch_error := INF
	var extension_time := 0.0
	for tick: int in 1000:
		await physics_frame
		if move_target and not shifted and attack._phase == &"preparing" and attack._elapsed>0.2:
			target.global_position += Vector3(0,1,0.3)
			shifted = true
		if attack._phase == &"lunging":
			if not launched:
				launched = true
				launch_error = attack._head_aim_error_degrees
				extension_time = attack._plan.extension_duration
				start_relative = attack.head.global_position-root_body.global_position
				var start: Transform3D = attack._poses(attack._plan.preparation)[attack.head]
				var end: Transform3D = attack._poses(attack._plan.strike)[attack.head]
				extension = attack._plan.reference.basis*(end.origin-start.origin)
			var velocity: Vector3 = attack.head.linear_velocity-root_body.linear_velocity
			peak_relative_speed = maxf(peak_relative_speed,velocity.dot(extension.normalized()))
			var distance: Vector3 = attack.head.global_position-root_body.global_position-start_relative
			var progress := distance.dot(extension)/maxf(extension.length_squared(),0.001)
			maximum_progress = maxf(maximum_progress,progress)
			if not is_finite(quarter_time) and progress>=0.25: quarter_time = attack._elapsed
			if not is_finite(half_time) and progress>=0.5: half_time = attack._elapsed
		if not attack.is_npc_attack_active(): break
	check(launched and launch_error<=attack.data.aim_tolerance_degrees,"Bite waits until the real visual forward points at its locked point")
	check(not move_target or shifted,"Target actually moves during preparation")
	# Actual contact can end a bite before full extension; compare a milestone both bites reach.
	check(is_finite(quarter_time),"Head physically reaches the common relative extension milestone")
	check(target.current_hp<target.max_hp,"Aimed bite still inflicts actual damage")
	var result := {"multiplier":multiplier,"moving_preparation_target":move_target,"natural_pitch_degrees":pitch,"launch_aim_error_degrees":launch_error,
		"extension_time":extension_time,"quarter_time":quarter_time,"half_time":half_time,"maximum_progress":maximum_progress,"peak_relative_speed":peak_relative_speed,"end_reason":attack._last_reason}
	print("SNAKE_HEAD_AIM_RESULT ",result)
	npc.free()
	victim.free()
	await process_frame
	return result
