extends SceneTree

const LEVEL = preload("res://Scenes/Levels/TestLevel.tscn")
const NPC = preload("res://Scenes/Creatures/Characters/Generate_Snake_NPC.tscn")
const CHARACTER = preload("res://Scenes/Creatures/Characters/_SampleCharacter.tscn")
const PART = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCreature_Part.tscn")
var failed := false

class Command extends Node:
	func get_movement_direction() -> Vector3: return Vector3.RIGHT
	func get_generated_facing_direction(_delta: float) -> Vector3: return Vector3.RIGHT

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func run() -> void:
	# Replay the reported matchup without changing its scale, joint limits, target AI or speed.
	var level := LEVEL.instantiate()
	root.add_child(level)
	current_scene = level
	await physics_frame
	await physics_frame
	var snake := level.get_node("GenerateSnakeNPC")
	var attack := snake.get_node("SnakeBiteAttackController3D")
	var ai := snake.get_node("NPCStateMachine3D")
	var movement := snake.get_node("SnakeMovementController3D")
	var victim := level.get_node("CharacterTestNPC")
	var target := victim.get_node("Torso") as PhysicalBodyPart3D
	var original_hp := target.current_hp
	var phases := {}
	var approach_speed := 0.0
	var joint_limits: Dictionary = {}
	for link: Dictionary in attack._links:
		joint_limits[link.joint] = Vector2(link.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),link.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT))
	var launched := false
	var recovered := false
	var maximum_head_slide := 0.0
	var maximum_ground_error := 0.0
	# A fixed-root bite may need another approach after the target reverses during braking.
	for tick: int in 4200:
		await physics_frame
		if not phases.has(attack._phase): print("SNAKE_INTERCEPT_PHASE frame=",tick," data=",attack.get_attack_diagnostics())
		phases[attack._phase] = true
		if attack._phase == &"idle" and not launched:
			approach_speed = maxf(approach_speed,target.linear_velocity.slide(Vector3.UP).length())
		if attack._phase == &"lunging" and not launched:
			launched = true
			var plan: Dictionary = attack._plan
			check(plan.target_locked and is_equal_approx(plan.contact_time,plan.preparation_time+plan.duration),"Launch retains the forecast committed before preparation")
			check(plan.target_supported and is_zero_approx(plan.target_velocity.y),"Grounded gait bobbing does not extrapolate the torso vertically")
			check(Vector3(plan.pose_error).length() < attack._head_size.length(),"Constrained IK reaches the predicted target rather than stopping metres above it")
			print("SNAKE_INTERCEPT_LAUNCH frame=",tick," target_velocity=",plan.target_velocity," contact_time=",plan.contact_time," pose_error=",plan.pose_error)
		for row: Dictionary in movement._parts:
			check(row.body.global_position.is_finite() and row.body.linear_velocity.is_finite(),"Intercept remains physically finite")
		if attack.is_npc_attack_active():
			var joint: Generic6DOFJoint3D = attack._links[-1].joint
			var parent: Node3D = joint.get_node(joint.node_a)
			var fa: Transform3D = parent.global_transform*Transform3D(joint.get_meta(&"generated_joint_frame_a"))
			var fb: Transform3D = attack.head.global_transform*Transform3D(joint.get_meta(&"generated_joint_frame_b"))
			maximum_head_slide = maxf(maximum_head_slide,absf((fa.affine_inverse()*fb.origin).x))
			for index: int in range(1,floori(attack._links.size()*attack.data.preserved_root_ratio)):
				check(absf(attack._angles[index])<=maxf(absf(attack._links[index].lower),absf(attack._links[index].upper))*0.3+0.00001,"Root-side S curvature stays inside its restricted flex range")
			if movement._attack_entry_elapsed > movement.motion_data.path_transition_time:
				var inverse: Transform3D = movement.get_pose_reference().affine_inverse()
				for row: Dictionary in movement._belly:
					var expected: Vector3 = movement._attack_ground_poses[row.body].origin
					var requested: Vector3 = movement._attack_poses[row.body].origin
					check(Vector2(expected.x-requested.x,expected.z-requested.z).length()<0.0001,"Belly targets retain the captured S shape")
					var actual: Vector3 = inverse*row.body.global_position
					maximum_ground_error = maxf(maximum_ground_error,Vector2(actual.x-expected.x,actual.z-expected.z).length())
		if launched and attack._phase == &"idle":
			recovered = true
			break
	check(approach_speed > 6.0,"Regression includes the original fast approaching target")
	check(launched and recovered,"Moving target triggers a bite and complete recovery")
	check(phases.has(&"positioning") and phases.has(&"preparing") and (phases.has(&"closing") or attack._last_hits>0),"Intercept physically aligns, prepares and contacts before a killed target cancels closing")
	check(target.current_hp < original_hp,"The original moving human target takes actual damage")
	check(movement._attack_owner == null,"Recovery returns control to Snake locomotion")
	check(attack._last_reason == &"completed","Recovery completes through verified connections instead of timing out")
	check(maximum_head_slide < 0.9,"Head never separates by the former multi-unit sliding range")
	check(maximum_ground_error < 0.6,"Physical belly follows the preserved S shape")
	if not recovered:
		level.free()
		quit(1)
		return
	for joint: Generic6DOFJoint3D in joint_limits:
		check(joint_limits[joint].is_equal_approx(Vector2(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT))),"Standing chain limits remain unchanged")
	print("SNAKE_INTERCEPT_RESULT approach_speed=",approach_speed," damage=",original_hp-target.current_hp," phases=",phases)
	var held: Vector3 = movement._held_heading
	var idle_error := 0.0
	var idle_yaw := 0.0
	for tick: int in 600:
		await physics_frame
		var inverse: Transform3D = movement.get_pose_reference().affine_inverse()
		for row: Dictionary in movement._belly:
			var expected: Vector3 = movement._idle_ground_poses[row.body].origin
			var actual: Vector3 = inverse*row.body.global_position
			idle_error = maxf(idle_error,Vector2(actual.x-expected.x,actual.z-expected.z).length())
		var heading: Vector3 = movement._update_anchor().heading
		idle_yaw = maxf(idle_yaw,rad_to_deg(held.angle_to(heading)))
	check(idle_error < 0.5 and idle_yaw < 5.0,"Ten seconds of targetless Idle preserve the body shape and heading")
	check(not movement._attack_slide_release_pending,"Joint profiles finish returning after the bite")
	print("SNAKE_STRUCTURE_RESULT max_head_slide=",maximum_head_slide," max_ground_error=",maximum_ground_error," idle_error=",idle_error," idle_yaw_degrees=",idle_yaw," connections=",movement.get_attack_connection_diagnostics())
	var command := Command.new()
	level.add_child(command)
	movement.command_source = command
	for tick: int in 180: await physics_frame
	check(movement._path_ready and movement._idle_ground_poses.is_empty() and movement.get_snake_motion_diagnostics(false).actual_speed>3.0,"Movement releases the held shape and resumes the normal route")
	movement.command_source = null
	command.free()
	await validate_reposition(level)
	level.free()
	await process_frame
	if not failed: print("SNAKE_INTERCEPT_VALIDATION_PASSED")
	quit(1 if failed else 0)

func validate_reposition(level: Node3D) -> void:
	var npc := NPC.instantiate()
	npc.position = Vector3(-250,1.51,150)
	level.add_child(npc)
	var ai := npc.get_node("NPCStateMachine3D")
	ai.set_physics_process(false)
	var attack := npc.get_node("SnakeBiteAttackController3D")
	var victim := CHARACTER.instantiate()
	victim.faction_id = 2
	var target := PART.instantiate() as PhysicalBodyPart3D
	target.tags.assign([PhysicalBodyPart3D.BodyPartTag.Torso,PhysicalBodyPart3D.BodyPartTag.Head])
	target.freeze = true
	victim.add_child(target)
	level.add_child(victim)
	for tick: int in 150: await physics_frame
	target.global_position = npc.get_node("SnakeMovementController3D").get_control_anchor().global_position+Vector3(20,1,0)
	ai._target = target
	ai._enemy = victim
	ai._scan_elapsed = 1000.0
	var center: Vector3 = npc.get_node("SnakeMovementController3D").get_control_anchor().global_position
	target.global_position = center+Vector3(90,1,8)
	target.linear_velocity = Vector3(-6.7,0,2)
	attack._velocity_frame = -1
	var intercept: Dictionary = attack._make_plan(target,true)
	check(Vector3(intercept.aim).is_equal_approx(target.global_position+target.linear_velocity*float(intercept.contact_time)),"XYZ aim uses the same contact time as the downstroke")
	check(absf((Transform3D(intercept.reference).affine_inverse()*Vector3(intercept.aim)).z-npc.get_node("SnakeMovementController3D").get_attack_root_offset().z)<0.01,"Attack plane points towards the future Z position")
	for index: int in attack._links.size():
		var link: Dictionary = attack._links[index]
		check(intercept.strike[index]>=link.lower-0.0001 and intercept.strike[index]<=link.upper+0.0001,"Intercept respects each saved bend limit")
	target.global_position = center+Vector3(100,1,0)
	target.linear_velocity = Vector3.ZERO
	attack._velocity_frame = -1
	attack._cached_plan = {}
	var attacks: Array = ai._available_attacks()
	var miss: Dictionary = ai._predict_attack(attacks[0],target)
	check(not miss.hit and miss.reason == &"outside_fixed_root_reach","Far target exercises a real fixed-root rejection")
	var distance: float = ai._horizontal_distance_to(target.global_position)
	ai._plan_attack_distance(distance,attacks)
	var sample: int = ai._prediction_distance_sample
	var held: float = ai._preferred_attack_distance(attacks[0])
	for retry: int in 20:
		ai._predict_attack(attacks[0],target)
		ai._plan_attack_distance(distance,attacks)
		check(ai._prediction_distance_sample == sample and is_equal_approx(ai._preferred_attack_distance(attacks[0]),held),"Repeated misses retain the same candidate instead of cycling distances")
	ai._update_combat(maxf(ai.behavior.scan_interval*3.0,0.8)+0.01)
	check(ai._prediction_distance_sample == sample+1,"A genuinely stalled candidate advances to the next distance")
	ai.stop()
	check(ai._reposition_distance < 0.0,"Manual cancellation releases the held stand-off")
	print("SNAKE_REPOSITION_RESULT held_distance=",held," sample_before=",sample," sample_after=",ai._prediction_distance_sample)
	npc.free()
	victim.free()
