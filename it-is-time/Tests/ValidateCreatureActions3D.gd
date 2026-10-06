extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
const PLAYER = preload("res://Scenes/Player/Controller.tscn")
var failed := false
func check(value: bool,message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300,1,300)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -0.5
	root.add_child(ground)
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	actor.planar_constraints_enabled = false
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.rear_leg_count = 2
	var forelegs := 4 if OS.get_cmdline_user_args().has("--four-forelegs") else 2
	generator.foreleg_count = forelegs
	generator.neck_number = 0
	generator._random.seed = 43
	check(actor.generate_creature(),"Action fixture generation failed")
	var player = PLAYER.instantiate()
	player.initial_character = actor
	root.add_child(player)
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	var module = actor.get_node("CreatureActionController3D")
	# Keep this regression independent of the player's saved action tuning.
	module.actions[0] = module.actions[0].get_script().new()
	module.diagnostic_logging = true
	for frame: int in range(240): await physics_frame
	check(player.get_controlled_character()==actor,"Player must attach to generated actor")
	movement._turn_planning_active = true
	check(not module.try_start_action(),"Turning must block action start")
	movement._turn_planning_active = false
	var event := InputEventAction.new()
	event.action = &"MouseLeft"
	event.pressed = true
	player._unhandled_input(event)
	check(module.is_active(),"A MouseLeft press must start the action through PlayerController")
	check(movement._action_feet.size()==forelegs,"All tagged front feet must be reserved")
	check(not player.is_gameplay_action_pressed(&"MouseLeft"),"Action-bound input must not also drive arm swinging")
	check(not module.try_start_action(),"An active action must not restart on repeated clicks")
	check(not movement._gallop_active(),"Front-leg actions must suspend airborne gait permissions")
	check(movement.get_maximum_stepping_feet()==1,"Two rear legs must leave one real stance foot while the front feet are reserved")
	var rear_feet: Array[RigidBody3D] = movement.get_action_support_feet()
	check(rear_feet.size()==2,"Both rear feet should be available as initial real supports")
	if rear_feet.size()==2:
		check(movement._can_start_step_with_support(rear_feet[0]),"One rear foot may walk during the action")
		var rear_motion = movement.StepMotion.new()
		rear_motion.leg = rear_feet[0]
		movement._active_steps.append(rear_motion)
		check(not movement._can_start_step_with_support(rear_feet[1]),"The last rear support must not launch using a flight lease")
		movement._active_steps.erase(rear_motion)
	module._data.foot_lift_ratio = 4.0
	module._data.torso_lift_ratio = 3.0
	check(not module._surface(module._feet[0].body,module._feet[0].body.global_position+Vector3.UP*15.0).is_empty(),"Large lifts need a terrain ray longer than five units")
	module._data.foot_lift_ratio = 0.18
	module._data.torso_lift_ratio = 0.06
	var planner_row: Dictionary = module._feet[0]
	var saved_plan := planner_row.duplicate()
	var chain: Dictionary = movement._chains[planner_row.body]
	var original_offset: Vector3 = planner_row.offset
	var original_position: Vector3 = planner_row.body.global_position
	var original_root_position: Vector3 = planner_row.root.global_position
	var original_length: float = chain.length
	var forward: Vector3 = planner_row.root.global_basis.x.slide(Vector3.UP).normalized()
	var attachment: Vector3 = planner_row.root.to_global(chain.anchor)
	# Isolate the planner with a known rearward posture, restoring all transforms
	# before the next physics frame. Physical action tests below use real chains.
	chain.length = original_length*2.0
	planner_row.offset = original_offset-forward*(original_offset.dot(forward)+0.5)
	planner_row.body.global_position = attachment+Vector3(planner_row.offset)
	module._capture_forward_plan(planner_row)
	check(planner_row.needs_forward_extension and planner_row.landing_replan==&"extended_forward" and planner_row.landing_forward_before<0.0 and planner_row.landing_forward_after>0.0,"A rearward foot must be identified and planned ahead before lift starts")
	planner_row.root.global_position += Vector3.UP*12.0
	module._plan_stomp_landing(planner_row)
	check(planner_row.landing_replan==&"extended_forward","A lifted root must validate against the expected landing height, not its current height")
	planner_row.root.global_position = original_root_position
	chain.length = 0.1
	module._plan_stomp_landing(planner_row)
	check(planner_row.landing_replan==&"no_valid_forward_point","An unreachable front point must retain the original landing")
	chain.length = original_length
	planner_row.offset = original_offset+forward*(0.2-original_offset.dot(forward))
	planner_row.body.global_position = attachment+Vector3(planner_row.offset)
	module._capture_forward_plan(planner_row)
	check(not planner_row.needs_forward_extension and planner_row.landing_replan==&"already_forward_or_within_tolerance","An existing forward foot must not be extended again")
	planner_row.offset -= forward*0.21
	planner_row.body.global_position = attachment+Vector3(planner_row.offset)
	module._capture_forward_plan(planner_row)
	check(not planner_row.needs_forward_extension,"Small negative offsets must not trigger extension from solver noise")
	planner_row.body.global_position = original_position
	module._feet[0] = saved_plan
	var origins: Dictionary = {}
	for foot: RigidBody3D in movement._action_feet: origins[foot] = foot.global_position.y
	var phases: Dictionary = {}
	var maximum_rise := 0.0
	var torso_rise := 0.0
	var rear_started := false
	var moving_force := false
	Input.action_press("Right")
	for frame: int in range(240):
		await physics_frame
		phases[module.phase] = true
		for foot: RigidBody3D in origins:
			maximum_rise = maxf(maximum_rise,foot.global_position.y-float(origins[foot]))
			check(not movement.is_leg_stepping(foot) or not module.is_active(),"Ordinary stepping must not control a reserved front foot")
		for row: Dictionary in module._torsos: torso_rise = maxf(torso_rise,row.body.global_position.y-float(row.height))
		for motion in movement._active_steps:
			if not origins.has(motion.leg): rear_started = true
		if module.is_active() and movement._last_torso_response_force.slide(Vector3.UP).length()>0.1: moving_force = true
		if not module.is_active(): break
	Input.action_release("Right")
	print("ACTION_RESULT phases=",phases," maximum_foot_rise=",maximum_rise," maximum_torso_rise=",torso_rise," reason=",module._reason," rear_step=",rear_started," horizontal_drive=",moving_force)
	check(phases.has(module.Phase.STOMPING),"Physical lift must reach the stomp phase")
	check(phases.has(module.Phase.LANDING),"Stomp must make real terrain contact")
	check(not module.is_active() and module._reason==&"completed","Action must finish and restore normal control")
	check(movement._action_feet.is_empty() and movement._action_body_weights.is_empty(),"Action completion must release ownership")
	check(maximum_rise>0.1,"Front feet must physically rise")
	check(torso_rise>0.05,"Corresponding torso segments must physically rise")
	check(rear_started and moving_force,"Remaining legs must retain walking and horizontal propulsion during the action")
	for frame: int in range(100): await physics_frame
	# Start a real action with one front foot behind its root, rather than only
	# testing planning with an artificially longer chain.
	var rearward_foot: RigidBody3D
	for foot: RigidBody3D in movement.get_leg_parts():
		if movement._has_body_tag(foot,movement.FORELEG_TAG): rearward_foot = foot; break
	var rearward_chain: Dictionary = movement._chains[rearward_foot]
	var rearward_anchor: Vector3 = rearward_chain.root.to_global(rearward_chain.anchor)
	var rearward_forward: Vector3 = rearward_chain.root.global_basis.x.slide(Vector3.UP).normalized()
	movement._release_support_pin(rearward_foot)
	rearward_foot.global_position -= rearward_forward*((rearward_foot.global_position-rearward_anchor).dot(rearward_forward)+0.3)
	check(module.try_start_action(),"Rearward-foot physical fixture must start")
	var physical_plan: Dictionary
	for plan_row: Dictionary in module._feet:
		if plan_row.body==rearward_foot: physical_plan = plan_row
	check(physical_plan.needs_forward_extension and physical_plan.landing_replan==&"extended_forward","Real rearward posture must select a forward landing at action start")
	var forward_target_during_lift := false
	var physical_forward := false
	for frame: int in range(240):
		await physics_frame
		if not module.is_active(): break
		var current_anchor: Vector3 = rearward_chain.root.to_global(rearward_chain.anchor)
		if module.phase==module.Phase.RISING:
			if (Vector3(physical_plan.get("target",rearward_foot.global_position))-current_anchor).dot(rearward_forward)>0.05: forward_target_during_lift = true
			if (rearward_foot.global_position-current_anchor).dot(rearward_forward)>0.05: physical_forward = true
	print("REARWARD_EXTENSION_RESULT target_during_lift=",forward_target_during_lift," physical_forward=",physical_forward," reason=",module._reason)
	check(forward_target_during_lift and physical_forward,"The front foot must physically extend forward during RISING, before stomping")
	check(not module.is_active() and module._reason==&"completed","Rearward extension must still land and complete")
	for frame: int in range(100): await physics_frame
	check(module.try_start_action(),"Action must be reusable after cooldown")
	for foot: RigidBody3D in movement.get_action_support_feet(): movement._release_support_pin(foot)
	module.update_action(0.05)
	check(module.phase==module.Phase.RISING and module.get_action_diagnostics().lift_paused,"Lifting must pause immediately when all real rear supports are lost")
	check(is_zero_approx(module._rise_elapsed),"Unsupported time must not advance the planned lift")
	for foot_row: Dictionary in module._feet: check(is_zero_approx(Vector3(foot_row.force).y),"Unsupported front feet must have no upward servo or gravity compensation")
	for torso_row: Dictionary in module._torsos: check(Vector3(torso_row.force).is_zero_approx(),"Unsupported torsos must have no lift force")
	module.update_action(0.3)
	check(module.phase==module.Phase.RECOVERING and module._reason==&"support_lost","Prolonged support loss must transition to recovery")
	module.cancel_player_actions()
	check(not module.is_active() and movement._action_feet.is_empty(),"Input suspension must cancel and release the action")
	for frame: int in range(100): await physics_frame
	# Reproduce the user's large lift while walking: completion may be limited
	# by the structure, but all-air launches and missed short terrain rays must not occur.
	module.actions[0].foot_lift_ratio = 1.0
	module.actions[0].torso_lift_ratio = 1.0
	module.actions[0].rise_time = 1.84
	module.actions[0].rise_timeout = 5.0
	check(module.try_start_action(),"Large-lift walking fixture must start")
	Input.action_press("Right")
	var large_lift_maximum := 0.0
	for frame: int in range(450):
		await physics_frame
		if not module.is_active(): break
		check(movement._active_steps.size()<=1,"Large lifts must not launch both rear feet")
		check(not movement._gallop_active(),"Airborne gait must stay suspended throughout the action")
		for large_row: Dictionary in module._feet: large_lift_maximum = maxf(large_lift_maximum,float(large_row.get("ground_gap",0.0)))
		if module.phase==module.Phase.RISING and module._support_count==0:
			for large_row: Dictionary in module._feet: check(is_zero_approx(Vector3(large_row.force).y),"Real loss of stance must stop foot lifting")
	Input.action_release("Right")
	print("LARGE_LIFT_RESULT reason=",module._reason," maximum_gap=",large_lift_maximum)
	check(not module.is_active() and module._reason!=&"terrain_lost","Large-lift walking must recover without losing ground to short rays")
	module.actions[0] = module.actions[0].get_script().new()
	for frame: int in range(150): await physics_frame
	check(module.try_start_action(),"A cancelled action must become reusable")
	var broken_foot: RigidBody3D = module._feet[0].body
	broken_foot.is_broken = true
	await physics_frame
	await physics_frame
	check(not module.is_active() and movement._action_body_weights.is_empty(),"Broken front feet must cancel and release torso control")
	broken_foot.is_broken = false
	for frame: int in range(100): await physics_frame
	check(module.try_start_action(),"Action must restart before regeneration")
	check(actor.generate_creature(),"Regeneration during an action must succeed")
	check(not module.is_active() and movement._action_feet.is_empty(),"Regeneration must release references to the previous parts")
	actor.queue_free()
	await process_frame
	await process_frame
	print("CREATURE_ACTIONS_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
