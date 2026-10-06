extends SceneTree

const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
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
	box.size = Vector3(300, 1, 300)
	collision.shape = box
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	actor.planar_constraints_enabled = false
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.foreleg_count = 4 if "--four-forelegs" in OS.get_cmdline_user_args() else 2
	generator.neck_number = 0
	generator._random.seed = 43
	check(actor.generate_creature(), "Generation failed")
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	var data = movement.slow_gait_data.duplicate()
	data.automatic_motion = true
	data.speed_based_gait = true
	data.target_speed = 3.0
	data.gallop_enabled = true
	movement.slow_gait_data = data
	for frame: int in range(240): await physics_frame
	check(not movement.recovery_control_active, "Fixture must be standing before the walk")
	# Exercise two real stop/start transitions, not only a synthesized demand.
	var total_landings := 0
	var front_landings := 0
	var forward_landings := 0
	var seen_contacts: Dictionary = {}
	var liftoff_timeouts := 0
	for attempt: int in range(2):
		for body: RigidBody3D in movement.get_torso_parts(): body.linear_velocity = Vector3.ZERO
		Input.action_press("Right")
		var first_start := -1
		var startup_lifted := false
		var completed_ramp := false
		var previous_failures: int = movement._failed_step_count
		for frame: int in range(360):
			await physics_frame
			if frame < 4: print("START_TRACE attempt=", attempt, " frame=", frame, " state=", movement._startup_status, " pending=", movement._startup_pending, " input=", movement.get_input_movement_direction(), " root_speed=", movement._torso.linear_velocity.slide(Vector3.UP).length(), " turn=", movement._turn_planning_active, " steps=", movement._active_steps.size())
			if movement._failed_step_count > previous_failures:
				if movement._last_step_failure == "liftoff_timeout": liftoff_timeouts += 1
				previous_failures = movement._failed_step_count
			for motion in movement._active_steps:
				if motion.extra.get("extension_trigger", {}).get("reason", "") == "startup":
					if first_start < 0: first_start = frame
					if motion.extra.get("liftoff_complete", false): startup_lifted = true
				if not motion.extra.get("liftoff_complete", true):
					check(motion.elapsed <= 0.00001, "Lift must not consume the travel clock")
					check(is_zero_approx(float(motion.extra.get("horizontal_tracking_weight", 0.0))), "Lift must not chase horizontally")
				if motion.extra.get("gallop_touchdown_braking", false):
					var key := "%s:%s:%s" % [attempt, motion.sequence, motion.extra.get("gallop_contact_epoch", 0)]
					if not seen_contacts.has(key):
						seen_contacts[key] = true
						total_landings += 1
						if movement._has_body_tag(motion.leg, movement.FORELEG_TAG):
							front_landings += 1
							var chain: Dictionary = movement._chains[motion.leg]
							var anchor: Vector3 = chain.root.to_global(chain.anchor)
							var advance: float = (motion.leg.global_position-anchor).dot(Vector3.RIGHT)
							if advance > 0.0: forward_landings += 1
							print("FRONT_TOUCHDOWN advance=", advance, " sequence=", motion.sequence)
			if movement._startup_drive_blend >= 0.999: completed_ramp = true
		check(first_start >= 0 and first_start <= 2, "Start must launch a safe foot within two physics ticks")
		check(startup_lifted, "Startup swing must clear the ground")
		check(completed_ramp, "Startup acceleration must return to full drive")
		Input.action_release("Right")
		for frame: int in range(240): await physics_frame
		check(not movement._startup_pending and movement._startup_status == "idle", "Stopping must rearm startup")
	check(front_landings >= 2, "Front feet must complete repeated real touchdowns")
	check(forward_landings * 2 >= front_landings, "Most front touchdowns must extend past their actual root joint")
	check(liftoff_timeouts == 0, "Normal flat-ground walking must not repeatedly time out during lift")
	print("WALK_START_SUMMARY touchdowns=", total_landings, " front=", front_landings, " forward=", forward_landings, " lift_timeouts=", liftoff_timeouts)
	print("GENERATED_WALK_START_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
