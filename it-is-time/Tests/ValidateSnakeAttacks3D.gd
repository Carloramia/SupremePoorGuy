extends SceneTree

const NPC = preload("res://Scenes/Creatures/Characters/Generate_Snake_NPC.tscn")
const CHARACTER = preload("res://Scenes/Creatures/Characters/_SampleCharacter.tscn")
const PART = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCreature_Part.tscn")
var failed := false

func _initialize() -> void: call_deferred("run")
func enable_attacks(npc: Node) -> void:
	npc.get_node("NPCStateMachine3D").enabled = true
	npc.get_node("NPCStateMachine3D").attack_execution_enabled = true
	npc.get_node("SnakeBiteAttackController3D").enabled = true
	var movement := npc.get_node("SnakeMovementController3D")
	movement.locomotion_enabled = true
	movement.motion_data = movement.motion_data.duplicate()
	movement.motion_data.head_orbit_enabled = false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func run() -> void:
	var settings := preload("res://Scripts/Creatures/SnakeBiteAttackData.gd").new()
	check(settings.is_valid(),"Attack defaults are valid")
	for invalid: float in [-1.0,NAN,INF]:
		settings.lunge_extra_wait = invalid
		check(not settings.is_valid(),"Invalid lunge catch-up time is rejected")
	settings.lunge_extra_wait = 0.5
	for invalid: float in [-0.1,0.7,NAN,INF]:
		settings.preserved_root_ratio = invalid
		check(not settings.is_valid(),"Invalid S preservation ratio is rejected")
	settings.preserved_root_ratio = 0.3
	for invalid: float in [0.9,3.1,NAN,INF]:
		settings.head_extension_speed_multiplier = invalid
		check(not settings.is_valid(),"Invalid head extension multiplier is rejected")
	var level := Node3D.new()
	root.add_child(level)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000,1,2000)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -0.5
	level.add_child(ground)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-900,0,-900),Vector3(900,0,-900),Vector3(900,0,900),Vector3(-900,0,900)])
	mesh.add_polygon(PackedInt32Array([0,1,2,3]))
	region.navigation_mesh = mesh
	level.add_child(region)
	for scenario: Vector2 in [Vector2(0.5,1),Vector2(1,1),Vector2(4,1),Vector2(1,0),Vector2(4,0)]:
		var size := scenario.x
		var npc := NPC.instantiate()
		enable_attacks(npc)
		npc.generate_on_ready = false
		npc.get_node("SnakeGenerator").overall_scale = size
		npc.position.y = 0.01
		level.add_child(npc)
		check(npc.generate_creature(),"Generate Snake attack fixture")
		var ai := npc.get_node("NPCStateMachine3D")
		ai.set_physics_process(false)
		var attacks := npc.get_node("SnakeBiteAttackController3D")
		attacks.data = attacks.data.duplicate()
		check(attacks._head_forward_source == &"joint_in_to_out" and attacks._head_forward_local.y > 0.3,"Natural Head direction comes from the fitted mouth markers, not local X")
		var movement := npc.get_node("SnakeMovementController3D")
		for tick: int in 150: await physics_frame
		var victim := CHARACTER.instantiate()
		victim.faction_id = 2
		var target := PART.instantiate() as PhysicalBodyPart3D
		target.name = "Target"
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
		target.global_position = attacks.head.to_global(attacks._mouth_offset())+Vector3.RIGHT*6.0*size
		if scenario.y == 0:
			target.global_position.y = 2.0*size
		await physics_frame
		print("SNAKE_ATTACK_GEOMETRY scale=",size," head=",attacks.head.global_position," target=",target.global_position," length=",attacks._chain_length)
		var prediction: Dictionary = attacks.predict_npc_attack(attacks.ACTION,target,0.0)
		print("SNAKE_ATTACK_PREDICTION scale=",size," hit=",prediction.get("hit")," reason=",prediction.get("reason"))
		check(prediction.get("hit",false),"Prediction must hit reachable elevated target")
		var lower: float = attacks._jaw_joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)
		var upper: float = attacks._jaw_joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)
		check(attacks.try_start_npc_attack(attacks.ACTION,target,0.0),"NPC can begin Snake bite")
		for body: Node3D in movement._attack_poses:
			var initial_pose: Transform3D = movement.get_pose_reference()*Transform3D(movement._attack_poses[body])
			check(initial_pose.origin.distance_to(body.global_position)<0.0001*size,"Attack takeover starts at the actual body positions")
		if attacks._weapon != null: attacks._weapon.damage_logging_enabled = true
		var phases: Dictionary = {}
		var maximum_height: float = attacks.head.global_position.y
		var maximum_speed := 0.0
		var maximum_opening := 0.0
		var initial_hp := target.current_hp
		var launched := false
		for tick: int in 1000:
			await physics_frame
			if attacks._phase == &"lunging" and not launched:
				launched = true
				check(attacks._head_aim_error_degrees <= attacks.data.aim_tolerance_degrees,"Preparation physically aims the visual Head axis at the live target")
				check(is_equal_approx(attacks._plan.extension_duration,attacks._plan.duration),"Prediction and execution share the fixed-root extension duration")
			if not phases.has(attacks._phase): print("SNAKE_ATTACK_PHASE scale=",size," data=",attacks.get_attack_diagnostics())
			phases[attacks._phase] = true
			maximum_height = maxf(maximum_height,attacks.head.global_position.y)
			maximum_speed = maxf(maximum_speed,float(movement.get_snake_motion_diagnostics(false).actual_speed))
			maximum_opening = maxf(maximum_opening,absf(attacks._jaw_angle))
			for row: Dictionary in movement._parts:
				check(row.body.global_position.is_finite() and row.body.linear_velocity.is_finite(),"Attack body remains finite")
			if not attacks.is_npc_attack_active(): break
		print("SNAKE_ATTACK_RESULT scale=",size," phases=",phases," peak_height=",maximum_height," peak_speed=",maximum_speed," jaw_open=",maximum_opening," damage=",initial_hp-target.current_hp," data=",attacks.get_attack_diagnostics())
		check(phases.has(&"lunging") and phases.has(&"closing") and phases.has(&"recovering") and phases.has(&"idle"),"Snake completes every attack stage")
		check(phases.has(&"rejoining") and attacks._last_reason == &"completed","Attack returns through verified physical connections")
		check(launched and attacks._plan.distance > 0.0,"Raised chain performs an extension without whole-body propulsion")
		check(maximum_opening > attacks.data.jaw_open_degrees*0.65,"Jaw physically opens")
		check(absf(attacks._jaw_angle) < 8.0,"Jaw closes again before handing control back")
		if size >= 1.0: check(target.current_hp < initial_hp,"Snake bite inflicts damage")
		check(attacks._last_hits <= 1,"Each Part takes damage at most once per bite")
		check(not target in attacks.head.get_collision_exceptions(),"Temporary mouth collision exception restored")
		check(movement._attack_owner == null and attacks._weapon == null,"Attack relinquishes movement and destroys weapon")
		check(is_equal_approx(attacks._jaw_joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),lower) and is_equal_approx(attacks._jaw_joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT),upper),"Jaw limits restored")
		npc.free()
		victim.free()
		await process_frame
	await validate_ai_and_interruptions(level)
	await validate_rotated_ai(level)
	level.free()
	await process_frame
	if not failed: print("SNAKE_ATTACK_VALIDATION_PASSED")
	quit(1 if failed else 0)

func validate_ai_and_interruptions(level: Node3D) -> void:
	var npc := NPC.instantiate()
	enable_attacks(npc)
	npc.name = "SnakeAttackAI"
	npc.generate_on_ready = false
	npc.get_node("SnakeGenerator").overall_scale = 1.0
	level.add_child(npc)
	check(npc.generate_creature(),"Generate autonomous Snake")
	var movement := npc.get_node("SnakeMovementController3D")
	var attacks := npc.get_node("SnakeBiteAttackController3D")
	var ai := npc.get_node("NPCStateMachine3D")
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
	target.global_position = Vector3(80,2,0)
	var completed := 0
	var successful_bites := 0
	var active_before := false
	var used_path := false
	var used_alignment := false
	for tick: int in 2400:
		await physics_frame
		var active: bool = attacks.is_npc_attack_active()
		used_path = used_path or movement._path_ready
		if attacks._phase == &"positioning":
			used_alignment = true
			check(movement._attack_ground_poses.size()==movement._belly.size(),"Attack alignment retains an S-shaped target for every belly part")
		if active_before and not active:
			completed += 1
			if attacks._last_hits > 0: successful_bites += 1
			check(attacks._last_reason in [&"completed",&"rejoin_timeout"],"Repeated attacks either verify recovery or safely retain the held shape")
			check(not movement._idle_ground_poses.is_empty() and movement._attack_owner == null,"Repeated attacks hand back ownership with an intact ground shape")
		active_before = active
		if tick % 300 == 0: print("SNAKE_AI_PROGRESS tick=",tick," state=",ai.get_state_diagnostics()," attack=",attacks.get_attack_diagnostics())
		if successful_bites >= 2: break
	print("SNAKE_AI_RESULT attacks=",completed," successful_bites=",successful_bites," hp=",target.current_hp," phase=",attacks._phase)
	check(completed >= 2 and successful_bites >= 2,"AI independently approaches and lands two repeated bites")
	check(target.current_hp < target.max_hp,"Autonomous AI bite hits ground target")
	check(used_path and used_alignment,"AI approaches on the S route and aligns before attacking")
	ai._cancel_attack()
	attacks.enabled = false
	target.global_position += Vector3.RIGHT*80.0
	for tick: int in 180: await physics_frame
	check(movement._path_ready and float(movement.get_snake_motion_diagnostics(false).actual_speed)>4.0,"AI resumes normal S-route walking after attacking")
	attacks.enabled = true
	ai.set_physics_process(false)
	ai._cancel_attack()
	for tick: int in 180: await physics_frame
	target.global_position = attacks.head.to_global(attacks._mouth_offset())+Vector3.RIGHT*6.0
	await physics_frame
	attacks._cooldown = 0.0
	victim.faction_id = npc.faction_id
	check(not attacks.predict_npc_attack(attacks.ACTION,target,0.0).hit,"Friendly target rejected")
	victim.faction_id = 2
	var near := target.global_position
	target.global_position.x += 1000
	check(not attacks.predict_npc_attack(attacks.ACTION,target,0.0).hit,"Unreachable target rejected")
	target.global_position = near
	await physics_frame
	var console := root.get_node("RuntimeConsole")
	check(console.execute_command("help").contains("tracksnakeattacks"),"Console help lists Snake attack tracking")
	console.execute_command("tracksnakeattacks on SnakeAttackAI")
	check(attacks.diagnostic_logging,"Console enables filtered Snake attack tracking")
	console.execute_command("tracksnakeattacks on OtherActor")
	check(not attacks.diagnostic_logging,"Console filter excludes unmatched Snake")
	console.execute_command("tracksnakeattacks off")
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(10,100,100)
	collision.shape = wall_box
	wall.add_child(collision)
	level.add_child(wall)
	wall.global_position = near-Vector3.RIGHT*3.0
	await physics_frame
	check(not attacks.predict_npc_attack(attacks.ACTION,target,0.0).hit,"Terrain blocks a predicted bite")
	wall.free()
	await physics_frame
	# A frozen fixture advances at constant velocity to exercise predicted target motion without solver noise.
	target.linear_velocity = Vector3.RIGHT*1.0
	attacks._cooldown = 0.0
	var hp_before := target.current_hp
	check(attacks.try_start_npc_attack(attacks.ACTION,target,0.0),"Predict a slowly moving target")
	if attacks._weapon != null: attacks._weapon.damage_logging_enabled = true
	for tick: int in 700:
		target.global_position += Vector3.RIGHT/60.0
		await physics_frame
		if not attacks.is_npc_attack_active(): break
	print("SNAKE_MOVING_RESULT ",attacks.get_attack_diagnostics()," target=",target.global_position," hp_delta=",hp_before-target.current_hp)
	check(target.current_hp < hp_before,"Bite lands on a slowly moving target")
	check(attacks._last_contacts == 1,"Moving target overlaps the actual mouth damage volume")
	target.linear_velocity = Vector3.ZERO
	for tick: int in 180: await physics_frame
	for interruption: StringName in [&"disabled",&"ragdoll",&"removed_target",&"regenerated"]:
		attacks._cooldown = 0.0
		target.global_position = attacks.head.to_global(attacks._mouth_offset())+Vector3.RIGHT*6.0
		await physics_frame
		check(attacks.try_start_npc_attack(attacks.ACTION,target,0.0),"Start interruption fixture "+str(interruption))
		if interruption == &"disabled":
			attacks.set_character_control_enabled(false)
			check(not attacks.is_npc_attack_active(),"Disable immediately cancels attack")
			attacks.set_character_control_enabled(true)
		elif interruption == &"ragdoll":
			npc.set_temporary_ragdoll(level,true)
			check(not attacks.is_npc_attack_active(),"Ragdoll cancels attack")
			npc.set_temporary_ragdoll(level,false)
			ai.set_physics_process(false)
		elif interruption == &"removed_target":
			victim.remove_child(target)
			await physics_frame
			await physics_frame
			check(attacks._phase == &"recovering","Missing target enters safe recovery")
			attacks.cancel_action()
			victim.add_child(target)
		else:
			check(npc.generate_creature(),"Regeneration succeeds during attack")
			ai.set_physics_process(false)
		check(movement._attack_owner == null and attacks._weapon == null,"Interruption cleans ownership and damage volume")
		for tick: int in 180: await physics_frame
		ai.set_physics_process(false)
	attacks._cooldown = 0.0
	target.global_position = attacks.head.to_global(attacks._mouth_offset())+Vector3.RIGHT*6.0
	await physics_frame
	check(attacks.try_start_npc_attack(attacks.ACTION,target,0.0),"Begin before Jaw breaks")
	attacks.jaw.break_part()
	await physics_frame
	await physics_frame
	check(not attacks.is_npc_attack_active() and movement._attack_owner == null,"Broken Jaw cancels attack")
	npc.free()
	victim.free()
	await process_frame

func validate_rotated_ai(level: Node3D) -> void:
	var npc := NPC.instantiate()
	npc.generate_on_ready = false
	npc.rotation.y = PI/2.0
	level.add_child(npc)
	check(npc.generate_creature(),"Generate rotated NPC with the saved default scale")
	var victim := CHARACTER.instantiate()
	victim.faction_id = 2
	var target := PART.instantiate() as PhysicalBodyPart3D
	target.tags.assign([PhysicalBodyPart3D.BodyPartTag.Torso,PhysicalBodyPart3D.BodyPartTag.Head])
	target.max_hp = 10000000.0
	target.armor = 0.0
	target.left_distance = 3.0
	target.right_distance = 3.0
	target.top_distance = 4.0
	target.bottom_distance = 4.0
	target.collision_thickness = 4.0
	target.freeze = true
	victim.add_child(target)
	level.add_child(victim)
	target.global_position = npc.global_basis*Vector3(160,0,10)+Vector3.UP*4.0
	var attacks := npc.get_node("SnakeBiteAttackController3D")
	for tick: int in 2400:
		await physics_frame
		if target.current_hp < target.max_hp: break
	print("SNAKE_ROTATED_AI_RESULT hp_damage=",target.max_hp-target.current_hp," phase=",attacks._phase)
	check(target.current_hp<target.max_hp,"Rotated AI aligns and attacks a target offset from its original plane")
	for tick: int in 900:
		await physics_frame
		if not attacks.is_npc_attack_active(): break
	check(not attacks.is_npc_attack_active(),"Rotated bite releases control after recovery")
	npc.get_node("NPCStateMachine3D").set_physics_process(false)
	var movement := npc.get_node("SnakeMovementController3D")
	var held: Vector3 = movement._held_heading
	check(held.angle_to(movement._rest_heading)>0.01,"Idle fixture holds a heading different from its initial orientation")
	for tick: int in 120:
		await physics_frame
		check(Vector3(movement._held_heading).angle_to(held)<0.001,"No command source preserves the last valid heading")
	npc.free()
	victim.free()
	await process_frame
