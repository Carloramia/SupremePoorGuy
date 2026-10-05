extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
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
	movement.cancel_step(&"test_reset")
	movement._current_step = BASE.StepMotion.new()
	movement._begin_leg_motion(foot,movement._body_position_for_ground_contact(foot,hit.position)+Vector3.RIGHT,Vector3.UP,Vector3.RIGHT)
	movement._update_active_step(1.0/60.0)
	check(movement._step_state==BASE.StepState.MOVING,"Initial contact before actual lift must remain in liftoff")
	check(not movement._current_step.extra.get("gallop_touchdown_braking",false),"Initial contact must not be mistaken for touchdown")
	Input.action_release("Right")
	actor.queue_free()
	await process_frame
	await process_frame
	print("EARLY_TOUCHDOWN_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
