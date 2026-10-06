extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
const BASE = preload("res://Scripts/Creatures/LegStepMovementControllerBase3D.gd")
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300,1,300)
	collision.shape = box
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	actor.planar_constraints_enabled = false
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.rear_leg_count = 2
	generator.foreleg_count = 2
	generator.neck_number = 0
	generator._random.seed = 43
	check(actor.generate_creature(),"Fixture generation failed")
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	var data = movement.slow_gait_data.duplicate()
	data.automatic_motion = true
	data.speed_based_gait = true
	data.gallop_enabled = true
	data.target_speed = 10.0
	movement.slow_gait_data = data
	for frame: int in range(180): await physics_frame
	movement.set_physics_process(false)
	Input.action_press("Right")
	var foot: RigidBody3D = movement._legs[0]
	var hit: Dictionary = movement._support_surface_contact(foot)
	check(not hit.is_empty(),"Fixture foot must have a real ground surface")
	for normal_speed: float in [-1.0,1.0]:
		movement.cancel_step(&"test_reset")
		movement._current_step = BASE.StepMotion.new()
		movement._begin_leg_motion(foot,movement._body_position_for_ground_contact(foot,hit.position)+Vector3.RIGHT,Vector3.UP,Vector3.RIGHT)
		movement._step_has_lifted = true
		movement._current_step.extra["liftoff_complete"] = true
		movement._step_elapsed = movement._active_step_duration*0.1
		foot.linear_velocity = Vector3(4,normal_speed,0)
		movement._update_active_step(1.0/60.0)
		check(movement._step_state==BASE.StepState.LANDING,"Real recontact at ten percent progress must immediately enter landing")
		check(movement._current_step.extra.get("gallop_touchdown_braking",false),"Descending and bouncing recontacts must brake in the same tick")
		check(movement._current_step.extra.get("gallop_target_frozen",false),"Recontact must freeze pursuit")
		check(movement._support_pins.has(foot),"High-speed real recontact must create a ground constraint before landing confirmation")
		var pin: Generic6DOFJoint3D = movement._support_pins[foot].joint
		check(is_equal_approx(pin.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT),data.touchdown_pin_initial_slack),"New touchdown constraint must start with bounded transition slack")
		var anchor: Vector3 = movement._support_anchors[foot]
		movement._update_touchdown_support_pin(foot,Vector3.UP,data.touchdown_pin_transition_time)
		movement._update_touchdown_support_pin(foot,Vector3.UP,0.0)
		check(is_zero_approx(pin.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)),"Touchdown constraint must close its slack after transition")
		check(movement._support_anchors[foot].is_equal_approx(anchor),"Touchdown anchor must not follow a sliding foot")
		movement._current_step.state = BASE.StepState.LANDING
		movement.update_leg_surface_adhesion()
		check(movement._support_pins.has(foot) and movement._support_pins[foot].joint==pin,"Landing adhesion update must retain the existing ground constraint")
		check(Vector3(movement._current_step.extra.get("_tracking_force",Vector3.ZERO)).x<0,"Horizontal force must oppose motion at recontact")
		check(is_equal_approx(float(movement._current_step.extra.touchdown_swing_progress),0.1),"Touchdown must not wait for fifty percent progress")
	# Independent braking parameters must control actual tangential force, not
	# merely alter a profile still clamped by the old swing acceleration.
	for config: Vector3 in [Vector3(0.04,300,4),Vector3(0.12,300,4),Vector3(0.04,50,20)]:
		data.touchdown_stop_time = config.x
		data.touchdown_maximum_braking_acceleration = config.y
		movement.cancel_step(&"test_reset")
		movement._current_step = BASE.StepMotion.new()
		movement._begin_leg_motion(foot,movement._body_position_for_ground_contact(foot,hit.position)+Vector3.RIGHT,Vector3.UP,Vector3.RIGHT)
		movement._step_has_lifted = true
		movement._current_step.extra["liftoff_complete"] = true
		movement._step_elapsed = movement._active_step_duration*0.1
		foot.linear_velocity = Vector3(config.z,0,0)
		movement._update_active_step(1.0/60.0)
		var brake: Dictionary = movement._current_step.extra.touchdown_brake
		var expected := -float(brake.effective_mass)*minf(config.z/float(brake.effective_stop_time),config.y)
		check(absf(Vector3(brake.applied_force).x-expected)<0.01,"Applied braking force must follow mass, stop time and independent acceleration cap")
		check(bool(brake.acceleration_limited)==(config.z/float(brake.effective_stop_time)>config.y),"Acceleration cap must be reported correctly")
	var before_loss := foot.global_position
	foot.global_position += Vector3.UP
	movement._update_active_step(1.0/60.0)
	check(not movement._support_pins.has(foot),"Lost real contact must release the provisional ground constraint")
	foot.global_position = before_loss
	movement.cancel_step(&"test_reset")
	movement._current_step = BASE.StepMotion.new()
	movement._begin_leg_motion(foot,movement._body_position_for_ground_contact(foot,hit.position)+Vector3.RIGHT,Vector3.UP,Vector3.RIGHT)
	movement._update_active_step(1.0/60.0)
	check(movement._step_state==BASE.StepState.MOVING,"Initial contact before actual lift must remain in liftoff")
	check(not movement._current_step.extra.get("gallop_touchdown_braking",false),"Initial contact must not be mistaken for touchdown")
	check(not movement._support_pins.has(foot),"Liftoff must release the touchdown constraint")
	# A historical lift flag alone must not start horizontal pursuit after a
	# shallow bounce. Actual clearance is required, including beyond the short adhesion ray.
	var resting_position := foot.global_position
	foot.global_position.y += movement.minimum_step_lift_clearance*1.1
	movement._step_has_lifted = true
	movement._update_active_step(1.0/60.0)
	check(not movement._current_step.extra.get("liftoff_complete",false),"Shallow lift must not complete the clearance phase")
	check(is_zero_approx(movement._step_elapsed),"Clearance phase must leave the swing clock untouched")
	foot.global_position.y = resting_position.y+maxf(movement._get_effective_step_height()*0.8,movement.surface_adhesion_probe_distance+0.05)
	movement._update_active_step(1.0/60.0)
	check(movement._current_step.extra.get("liftoff_complete",false),"A raised foot outside the adhesion probe must still complete liftoff")
	foot.global_position = resting_position
	for direction: Vector3 in [Vector3.RIGHT,Vector3.LEFT]:
		var chain: Dictionary = movement._chains[foot]
		# Exercise a reachable stance; some settled generated poses consume
		# the whole chain radius vertically and have no horizontal room.
		var available_offset := Vector3(0,-float(chain.length)*0.6,float(chain.length)*0.1)
		var offset: Vector3 = movement._forward_landing_offset(foot,available_offset,direction)
		check(offset.dot(direction)>0.0,"Landing must restore leading stance room in either travel direction")
		check(offset.length()<=float(chain.length)*movement.chain_reach_ratio,"Restored landing offset must remain inside the chain reach")
	var lift_mid: Vector2 = movement._automatic_swing_lift(0.4)
	var lift_late: Vector2 = movement._automatic_swing_lift(0.6)
	check(lift_mid.x>=0.99 and lift_late.x>=0.99,"Travel must maintain clearance instead of descending at midpoint")
	check(is_zero_approx(lift_mid.y) and is_zero_approx(lift_late.y),"Clearance plateau must not request downward velocity")
	Input.action_release("Right")
	actor.queue_free()
	await process_frame
	await process_frame
	print("EARLY_TOUCHDOWN_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
