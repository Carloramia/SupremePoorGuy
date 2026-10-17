extends SceneTree
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
var failed := false

class Commands extends Node:
	func get_movement_direction() -> Vector3: return Vector3.RIGHT
	func get_generated_facing_direction(_delta: float) -> Vector3: return Vector3.RIGHT
	func is_jump_requested() -> bool: return false
	func is_fast_requested() -> bool: return false

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)

func joint_settings(joint: Generic6DOFJoint3D) -> Array:
	var result: Array = []
	for axis: String in ["x", "y", "z"]:
		for flag: int in Generic6DOFJoint3D.FLAG_MAX: result.append(joint.call("get_flag_"+axis, flag))
		for parameter: int in Generic6DOFJoint3D.PARAM_MAX: result.append(joint.call("get_param_"+axis, parameter))
	return result

func target_actor(level: Node, team: int, at: Vector3) -> Node3D:
	var actor := Node3D.new()
	actor.set_script(CHARACTER)
	actor.require_head_and_torso_connectivity = false
	actor.faction_id = team
	var body := PhysicalBodyPart3D.new()
	body.name = "Torso"
	body.tags.append(PhysicalBodyPart3D.BodyPartTag.Torso)
	body.max_hp = 10000.0
	body.armor = 0.0
	body.damage_number_scene = null
	body.geometry_mode = PhysicalBodyPart3D.GeometryMode.CUSTOM_MODEL
	body.freeze = true
	body.collision_layer = 1 if "physical" in OS.get_cmdline_user_args() else 2
	body.collision_mask = 1 if "physical" in OS.get_cmdline_user_args() else 0
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 4.0, 3.0)
	collision.shape = box
	body.add_child(collision)
	var sprite := Sprite3D.new()
	sprite.name = "Sprite3D"
	body.add_child(sprite)
	actor.add_child(body)
	level.add_child(actor)
	actor.global_position = at
	return actor

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	if "off" in OS.get_cmdline_user_args(): load("res://Resources/Settings/PerformanceOptimization.tres").set(&"enabled", false)
	var level := Node3D.new()
	root.add_child(level)
	current_scene = level
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	collision.shape = box
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-70, 0, -70), Vector3(-70, 0, 70), Vector3(70, 0, 70), Vector3(70, 0, -70)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	level.add_child(region)
	var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_Spider_NPC.tscn").instantiate()
	level.add_child(actor)
	await process_frame
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	var module := actor.get_node("CreatureActionController3D")
	module.data = module.data.duplicate()
	module.data.preparation_pose_max_wait = 0.51
	check(not module.data.is_valid(), "Pose waiting must never exceed half a second")
	module.data.preparation_pose_max_wait = 0.5
	if "wait_timeout" in OS.get_cmdline_user_args():
		module.data.preparation_angle_tolerance_degrees = 0.0
		module.data.preparation_position_tolerance_ratio = 0.0
	elif "ready" in OS.get_cmdline_user_args():
		module.data.preparation_angle_tolerance_degrees = 20.0
		module.data.preparation_position_tolerance_ratio = 0.2
	actor.get_node("NPCStateMachine3D").enabled = false
	module.diagnostic_logging = true
	for tick: int in 240: await physics_frame
	var torso: RigidBody3D = movement._torso
	module.has_npc_attack(&"spider_pounce")
	var initial_distance: float = module._body_length * 5.9 if "extended" in OS.get_cmdline_user_args() else 6.0
	var enemy := target_actor(level, 2, torso.global_position+Vector3.RIGHT*initial_distance)
	var ally := target_actor(level, actor.faction_id, enemy.global_position)
	var target := enemy.get_node("Torso") as PhysicalBodyPart3D
	var friendly := ally.get_node("Torso") as PhysicalBodyPart3D
	await physics_frame
	check(module.has_input_action(&"MouseLeft"), "Spider attack must route the existing player action")
	check(actor.get_node("NPCStateMachine3D").behavior.attacks[0].action_id == &"spider_pounce", "NPC must expose the new attack option")
	check(module.has_npc_attack(&"spider_pounce"), "Spider must expose its attack receiver")
	var names: Array[String] = []
	for foot: RigidBody3D in module._front_feet(): names.append(str(foot.name))
	names.sort()
	check(names == ["Leg_1", "Leg_2", "Leg_5", "Leg_6"], "The front four feet must be selected from the rest roots")
	check(not module.predict_npc_attack(&"spider_pounce", friendly, 0.0).hit, "Friendly targets must be rejected")
	check(module.predict_npc_attack(&"spider_pounce", target, 0.0).hit, "A reachable enemy must pass the ballistic prediction")
	var target_origin := target.global_position
	var attack_range: float = module.get_npc_attack_maximum_range(&"spider_pounce", target)
	check(is_equal_approx(attack_range, module._body_length * 6.0), "Spider range must increase to six body lengths")
	target.global_position = torso.global_position + Vector3.RIGHT * 7.29
	target.linear_velocity = Vector3.RIGHT * 2.89
	check(module.predict_npc_attack(&"spider_pounce", target, 0.0).hit, "The logged same-speed pursuit must permit an intercept")
	target.global_position = torso.global_position + Vector3.RIGHT * attack_range * 0.95
	var moving_prediction: Dictionary = module.predict_npc_attack(&"spider_pounce", target, 0.0)
	check(moving_prediction.hit and float(moving_prediction.distance) > attack_range, "A reachable moving endpoint beyond the admission range must remain valid")
	print("SPIDER_EXTENDED_PREDICTION ", moving_prediction)
	var moved_position := target.global_position
	target.global_position = torso.global_position + Vector3.RIGHT * (attack_range + 0.1)
	check(module.predict_npc_attack(&"spider_pounce", target, 0.0).get("reason") == &"distance", "Attack admission must still reject targets outside the expanded range")
	check(module._trajectory(target, 0.0, false).hit, "A committed leap may intercept a target that moves just beyond the start range")
	target.global_position = moved_position
	target.linear_velocity = Vector3.RIGHT * 30.0
	check(module.predict_npc_attack(&"spider_pounce", target, 0.0).get("reason") == &"launch_speed", "Unreachable moving targets must retain the physical launch-speed limit")
	target.linear_velocity = Vector3.ZERO
	target.global_position = torso.global_position + Vector3.RIGHT * module._body_length * 4.0
	check(module.predict_npc_attack(&"spider_pounce", target, 0.0).hit, "A stationary target beyond the old three-body-length limit must be reachable")
	target.global_position = target_origin
	movement._turn_planning_active = true
	check(not module.try_start_npc_attack(&"spider_pounce", target, 0.0), "Physical turns must block attack start")
	movement._turn_planning_active = false
	var torso_joint := actor.get_node("GeneratedParts/Joints/Joint_001_Torso") as Generic6DOFJoint3D
	var torso_settings := joint_settings(torso_joint)
	check(module.try_start_npc_attack(&"spider_pounce", target, 0.0), "NPC must start the physical attack")
	var committed_endpoint: Vector3 = module._plan.endpoint
	var target_local_position := target.position
	if "escape" in OS.get_cmdline_user_args():
		target.global_position += Vector3(500,0,100)
		check(not module._trajectory(target,0.0,false).hit,"Escape fixture must invalidate a fresh launch prediction")
	check(not torso_joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT), "Preparation must release the relative Torso Z rotation")
	for axis: String in ["x", "y"]:
		check(torso_joint.call("get_flag_"+axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT), "Other Torso rotation axes must remain constrained")
	for axis: String in ["x", "y", "z"]:
		check(torso_joint.call("get_flag_"+axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT), "Torso position constraints must remain enabled")
	check(movement._action_feet.size() == 8, "The pause/leap must own all feet so ordinary stepping cannot pin the jump")
	var knee_flags: Dictionary = {}
	for row: Dictionary in module._feet:
		if not row.front: continue
		knee_flags[row.knee] = row.knee_flags.duplicate()
		check(row.knee_rotation > 0.0, "Front legs must rotate opposite to the previous negative-Z fold")
		check(not row.knee.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT), "Only the front knees must release their walking Z bounds")
		for axis: String in ["x", "y"]:
			check(row.knee.call("get_flag_"+axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT), "Knee X/Y rotation locks must remain enabled")
		for axis: String in ["x", "y", "z"]:
			check(row.knee.call("get_flag_"+axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT), "Knee connection holes must retain all position locks")
	var phases: Dictionary = {}
	var maximum_speed := 0.0
	var maximum_height := torso.global_position.y
	var initial_height := maximum_height
	var front_lift := 0.0
	var maximum_root_gap := 0.0
	var maximum_knee_gap := 0.0
	var maximum_relative_pitch := 0.0
	var knee_angles: Dictionary = {}
	var sampled_launch := false
	var preparation_time := 0.0
	var maximum_preparation_wait := 0.0
	var launch_pose: Dictionary = {}
	for tick: int in 300:
		await physics_frame
		phases[module.Phase.keys()[module.phase]] = true
		if module.phase in [module.Phase.PAUSING, module.Phase.RISING]:
			preparation_time += 1.0 / Engine.physics_ticks_per_second
			maximum_relative_pitch = maxf(maximum_relative_pitch, float(module.get_action_diagnostics().front_relative_pitch_degrees))
			check(is_equal_approx(target.current_hp, target.max_hp), "Preparation must not deal damage")
			if module.phase == module.Phase.RISING and module._elapsed > module.data.rise_time:
				maximum_preparation_wait = maxf(maximum_preparation_wait, module._elapsed-module.data.rise_time)
			for row: Dictionary in module._feet:
				if row.front:
					front_lift = maxf(front_lift, movement._get_foot_world_position(row.body).y)
		if module.phase == module.Phase.LEAPING:
			if not sampled_launch:
				sampled_launch = true
				check(module._plan.endpoint == committed_endpoint and module._plan.velocity.is_finite(),"Actual launch retains the admitted endpoint and finite velocity")
				check(Vector3(module._plan.velocity).length() <= module.data.maximum_launch_speed*module._time_scale+0.001,"Committed leap retains its physical speed limit")
				launch_pose = module.get_action_diagnostics().preparation_pose.duplicate()
				for part: Dictionary in launch_pose.parts:
					if part.has("relative_angle_degrees"): knee_angles[part.part] = part.relative_angle_degrees
			maximum_speed = maxf(maximum_speed, torso.linear_velocity.x)
			check(module._hitboxes.size() == 4, "Only the four front feet get temporary attack boxes")
			check(movement._support_pins.is_empty(), "No stance pin may hold the leap in the air")
		maximum_height = maxf(maximum_height, torso.global_position.y)
		for foot: RigidBody3D in movement._chains:
			for joint: Generic6DOFJoint3D in movement._chains[foot].joints:
				var a: Node3D = joint.get_node(joint.node_a)
				var b: Node3D = joint.get_node(joint.node_b)
				var fa: Transform3D = joint.get_meta(&"generated_joint_frame_a")
				var fb: Transform3D = joint.get_meta(&"generated_joint_frame_b")
				var gap := a.to_global(fa.origin).distance_to(b.to_global(fb.origin))
				if joint.get_meta(&"spider_axial_slide").connection == "root": maximum_root_gap = maxf(maximum_root_gap, gap)
				else: maximum_knee_gap = maxf(maximum_knee_gap, gap)
		if not module.is_active(): break
	print("SPIDER_POUNCE_TEST phases=", phases, " speed=", maximum_speed, " body_rise=", module._maximum_front_rise, " foot_lift=", front_lift, " jump_height=", maximum_height-initial_height, " damage=", target.max_hp-target.current_hp, " hits=", module._hits, " root_gap=", maximum_root_gap, " knee_gap=", maximum_knee_gap, " reason=", module._reason)
	print("SPIDER_PREPARATION relative_pitch=", maximum_relative_pitch, " knee_angles=", knee_angles, " time=", preparation_time, " launch_pose=", launch_pose)
	check(maximum_relative_pitch > 25.0 and maximum_relative_pitch < 35.0, "Front Torso must physically rise to about 30 degrees relative to the rear")
	for angle: float in knee_angles.values(): check(absf(angle-module.data.front_leg_relative_angle_degrees) < 5.0, "Every front Leg must reach about 150 degrees relative to its LegLimb before launch")
	for knee: Generic6DOFJoint3D in knee_flags:
		check(not knee.has_meta(&"spider_attack_knee"), "Completed attacks must remove the knee limit override")
		for flag: int in knee_flags[knee]: check(knee.get_flag_z(flag) == knee_flags[knee][flag], "Completed attacks must restore knee flags")
	check(preparation_time >= module.data.pause_time+module.data.rise_time-0.03 and preparation_time <= module.data.pause_time+module.data.rise_time+module.data.preparation_pose_max_wait+0.04, "Pose waiting must remain inside its half-second allowance")
	check(maximum_preparation_wait <= module.data.preparation_pose_max_wait+0.02, "Unfinished legs must not cause an unbounded delay")
	if "wait_timeout" in OS.get_cmdline_user_args():
		check(launch_pose.get("wait_expired", false) and not launch_pose.get("ready", true), "Unreachable exact poses must launch after the bounded extra wait")
		check(absf(float(launch_pose.get("extra_wait", -1.0))-0.5) < 0.02, "The timeout path must allow the full half second")
	elif "ready" in OS.get_cmdline_user_args():
		check(launch_pose.get("ready", false) and preparation_time < module.data.pause_time+module.data.rise_time+0.06, "Already-completed poses must launch without a fixed wait")
	check(joint_settings(torso_joint) == torso_settings, "Completed attacks must restore every Torso joint setting")
	check(phases.has("RISING") and phases.has("LEAPING") and phases.has("RECOVERING"), "Attack must physically pass through lift, leap and recovery")
	check(module._maximum_front_rise > 0.08 and front_lift > 0.15, "Front torso and front feet must visibly lift before launch")
	check(maximum_speed > 3.5 and maximum_height-initial_height > 0.35, "Leap must have a real burst and upward motion")
	if "escape" in OS.get_cmdline_user_args():
		check(target.current_hp == target.max_hp and module._hits == 0,"Executing a committed miss must not fabricate remote damage")
	else: check(target.current_hp < target.max_hp and module._hits > 0, "Sweeping feet must deal real damage through DamageService")
	check(friendly.current_hp == friendly.max_hp, "Overlapping friend must remain undamaged")
	check(module._hits <= 4, "Each front-foot hitbox must damage the same Part at most once")
	# An immovable target is an impact stress test; allow a brief solver overshoot,
	# then require ordinary walking to close the joint gaps again below 0.12.
	var root_impact_limit := 0.3 if "physical" in OS.get_cmdline_user_args() else 0.25
	var knee_impact_limit := 0.4 if "physical" in OS.get_cmdline_user_args() else 0.2
	check(maximum_root_gap < root_impact_limit and maximum_knee_gap < knee_impact_limit, "Attack must retain bounded physical joint connections")
	check(not module.is_active() and module._hitboxes.is_empty() and movement._action_feet.is_empty(), "Landing must clean up hitboxes and return control to walking")
	check(not module.try_start_npc_attack(&"spider_pounce", target, 0.0), "Cooldown must prevent immediate repeat attacks")
	check(not module.get_action_diagnostics().active, "Existing trackmotion must expose the completed action")
	# Exercise the real AI selector, rather than only calling its receiver directly.
	target.position = target_local_position
	for tick: int in 180: await physics_frame
	enemy.global_position = torso.global_position + Vector3.RIGHT*7.29
	ally.global_position = enemy.global_position + Vector3.BACK*10.0
	var machine := actor.get_node("NPCStateMachine3D")
	machine.enabled = true
	var selected := false
	for tick: int in 240:
		target.linear_velocity = Vector3.RIGHT * 2.89
		enemy.global_position += Vector3.RIGHT * 2.89 / Engine.physics_ticks_per_second
		await physics_frame
		if module.is_npc_attack_active():
			selected = machine.current_state == machine.State.ATTACK
			break
	print("SPIDER_POUNCE_AI ", machine.get_state_diagnostics(), " ranges=", machine.get_attack_range_diagnostics())
	check(selected, "NPC state machine must acquire a receding enemy and select Spider pounce automatically")
	target.linear_velocity = Vector3.ZERO
	machine.enabled = false
	await physics_frame
	check(not module.is_active() and movement._action_feet.is_empty(), "Disabling AI must cancel its action and release the legs")
	check(joint_settings(torso_joint) == torso_settings, "Cancelling the AI action must restore the Torso joint")
	for tick: int in 60: await physics_frame
	module._cooldown = 0.0
	var click := InputEventAction.new()
	click.action = &"MouseLeft"
	click.pressed = true
	check(module.handle_input(click) and module.is_active(), "Player MouseLeft route must start the same attack")
	for tick: int in 34: await physics_frame
	module.set_character_control_enabled(false)
	check(not module.is_active() and movement._action_feet.is_empty(), "Character disable must release action ownership")
	check(joint_settings(torso_joint) == torso_settings, "Disabling during the lift must restore the Torso joint")
	for knee: Generic6DOFJoint3D in knee_flags:
		check(not knee.has_meta(&"spider_attack_knee"), "Cancelling during the lift must release knee ownership")
		for flag: int in knee_flags[knee]: check(knee.get_flag_z(flag) == knee_flags[knee][flag], "Cancelling during the lift must restore knee flags")
	module.set_character_control_enabled(true)
	enemy.queue_free()
	ally.queue_free()
	var commands := Commands.new()
	actor.add_child(commands)
	movement.command_source = commands
	var speed_sum := 0.0
	for tick: int in 480:
		await physics_frame
		if tick >= 240: speed_sum += torso.linear_velocity.slide(Vector3.UP).length()
	print("SPIDER_POST_ATTACK_WALK mean_speed=", speed_sum / 240.0, " target=", movement._get_gait_data().target_speed)
	check(speed_sum / 240.0 > 2.85, "Normal walking must regain its original target speed after the attack")
	for foot: RigidBody3D in movement._chains:
		for joint: Generic6DOFJoint3D in movement._chains[foot].joints:
			var a: Node3D = joint.get_node(joint.node_a)
			var b: Node3D = joint.get_node(joint.node_b)
			var fa: Transform3D = joint.get_meta(&"generated_joint_frame_a")
			var fb: Transform3D = joint.get_meta(&"generated_joint_frame_b")
			check(a.to_global(fa.origin).distance_to(b.to_global(fb.origin)) < 0.12, "Impact joint overshoot must recover to the walking range")
	for part: RigidBody3D in actor._get_physical_body_parts():
		check(not part.is_broken and part.transform.is_finite(), "Attacking and recovering must retain all nineteen physical parts")
	level.free()
	await process_frame
	if not failed: print("PASS: Spider front-four selection, pause/lift/leap/sweep, impulse damage, friendly filtering, physical roots, cleanup and NPC wiring.")
	quit(1 if failed else 0)
