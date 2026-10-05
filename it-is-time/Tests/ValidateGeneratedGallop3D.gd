extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
var failed := false
func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func speed(movement: Node) -> float:
	var velocity := Vector3.ZERO
	var mass := 0.0
	for body: RigidBody3D in movement.get_torso_parts():
		velocity += body.linear_velocity * body.mass
		mass += body.mass
	return (velocity / maxf(mass,0.001)).slide(Vector3.UP).length()
func run() -> void:
	var budget := LegMovementData.new()
	check(budget.calculate_gallop_capacity(4,false) == 3,"Normal gallop budget should permit three of four feet")
	check(budget.calculate_gallop_capacity(4,true) == 4,"Flight window should permit all feet")
	budget.gallop_minimum_support_feet = 1
	check(budget.calculate_gallop_capacity(4,true) == 3,"Explicit support reservation must survive flight window")
	budget.gallop_minimum_support_feet = 0
	budget.gallop_maximum_stepping_ratio = 1.0
	budget.gallop_allow_all_feet_airborne = false
	check(budget.calculate_gallop_capacity(4,true) == 3,"Disabling all-foot flight must always reserve a support foot")
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(300,1,300)
	collision.shape = shape
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var count := 4
	var asymmetric := OS.get_cmdline_user_args().has("--asymmetric")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--feet="): count = argument.trim_prefix("--feet=").to_int()
	var means: Array[float] = []
	for enabled: bool in [false,true]:
		var actor = CHARACTER.instantiate()
		actor.generate_on_ready = false
		actor.planar_constraints_enabled = false
		root.add_child(actor)
		var generator = actor.get_node("CreatureGenerator")
		generator.rear_leg_count = count-2
		generator.foreleg_count = 2
		generator.body_length = 4.0
		generator.unsymmetrie = 100.0 if asymmetric else 0.0
		generator.neck_number = 0
		generator._random.seed = 43
		check(actor.generate_creature(),"Generation failed")
		var movement = actor.get_node("GeneratedLegStepMovementController3D")
		var data = movement.slow_gait_data.duplicate()
		data.automatic_motion = true
		data.target_speed = 5.0
		data.maximum_step_frequency = 4.0
		data.gallop_enabled = enabled
		movement.slow_gait_data = data
		for frame: int in range(180): await physics_frame
		Input.action_press("Right")
		var mean := 0.0
		var air_frames := 0
		var assisted_frames := 0
		var maximum_height := 0.0
		var maximum_stepping := 0
		var maximum_batch := 0
		var seen_sequences: Dictionary = {}
		var frozen_targets: Dictionary = {}
		var contact_slide_frames := 0
		var touchdown_brake_frames := 0
		var early_pins := 0
		var pinned_drift := 0.0
		for frame: int in range(600):
			await physics_frame
			if frame >= 480: mean += speed(movement)/120.0
			maximum_stepping = maxi(maximum_stepping,movement._active_steps.size())
			var new_steps := 0
			for step in movement._active_steps:
				if step.extra.get("gallop_step",false):
					var timing: Dictionary = step.extra.get("speed_gait",{})
					if not timing.is_empty():
						check(is_equal_approx(float(timing.required_stride),data.target_speed*float(timing.cycle)),"World stride must match target speed times cycle")
						check(is_equal_approx(step.duration,float(timing.air_duration)),"Swing must use the measured-speed air plan")
					check(Vector3(step.extra.gallop_target_shift).slide(Vector3.UP).length() <= float(step.extra.gallop_follow_limit)+0.001,"Landing correction exceeded limb-length budget")
					if step.extra.get("gallop_target_frozen",false):
						if frozen_targets.has(step.sequence): check(Vector3(frozen_targets[step.sequence]).is_equal_approx(step.extra.landing_surface_point),"Frozen terrain target must remain stationary")
						frozen_targets[step.sequence] = step.extra.landing_surface_point
					if step.extra.get("gallop_touchdown_braking",false):
						touchdown_brake_frames += 1
						var normal: Vector3 = step.normal
						var velocity: Vector3 = step.extra.gallop_braking_velocity
						check(Vector3(step.extra.get("_tracking_force",Vector3.ZERO)).slide(normal).dot(velocity) <= 0.1,"Touchdown must brake rather than pursue horizontally")
				if not seen_sequences.has(step.sequence):
					seen_sequences[step.sequence] = true
					new_steps += 1
			maximum_batch = maxi(maximum_batch,new_steps)
			var grounded := 0
			for foot: RigidBody3D in movement._legs:
				if movement.is_leg_grounded(foot):
					grounded += 1
					if foot.linear_velocity.slide(Vector3.UP).length() > 1.0: contact_slide_frames += 1
				var foot_data: Dictionary = movement.get_support_foot_diagnostics(foot)
				if foot_data.locked:
					pinned_drift = maxf(pinned_drift,float(foot_data.drift))
					if movement._physics_elapsed < movement._gallop_pin_release_until: early_pins += 1
			if grounded == 0: air_frames += 1
			if Vector3(movement._gallop_diagnostics.get("airborne_force",Vector3.ZERO)).length() > 0.001: assisted_frames += 1
			maximum_height = maxf(maximum_height,movement._torso.global_position.y)
			check(movement._active_steps.size() <= movement.get_maximum_stepping_feet(),"Gallop exceeded stepping budget frame=%s active=%s capacity=%s enabled=%s recovery=%s turn=%s" % [frame,movement._active_steps.size(),movement.get_maximum_stepping_feet(),movement._gallop_active(),movement.recovery_control_active,movement._turn_planning_active])
		means.append(mean)
		print("GALLOP_PHYSICS enabled=",enabled," requested=",data.target_speed," planned=",movement.get_expected_horizontal_speed()," mean_speed=",mean," takeoffs=",movement._gallop_takeoffs," all_air_frames=",air_frames," assisted_frames=",assisted_frames," max_height=",maximum_height," failures=",movement._failed_step_count," maximum_stepping=",maximum_stepping," maximum_batch=",maximum_batch," starts=",seen_sequences.size()," contact_slide_foot_frames=",contact_slide_frames," braking_foot_frames=",touchdown_brake_frames," restored_in_flight_window=",early_pins," max_pin_drift=",pinned_drift)
		if enabled:
			# Sparse flight support must not invoke the fallen-body reduction, but
			# real tilt and turn ownership must retain that protection.
			var probe := RigidBody3D.new()
			root.add_child(probe)
			var segment := {"balanced": false,"bodies": [probe]}
			check(is_equal_approx(movement._segment_movement_scale(segment,Vector3.UP),1.0),"Upright flight must retain propulsion")
			probe.rotation.z = PI/2.0
			check(is_equal_approx(movement._segment_movement_scale(segment,Vector3.UP),movement.unbalanced_movement_multiplier),"Tilted segment must retain imbalance protection")
			probe.rotation = Vector3.ZERO
			movement.set_turn_planning_active(true)
			check(is_equal_approx(movement._segment_movement_scale(segment,Vector3.UP),movement.unbalanced_movement_multiplier),"Turning must retain contact protection")
			movement.set_turn_planning_active(false)
			probe.queue_free()
			check(is_equal_approx(movement.get_expected_horizontal_speed(),5.0),"Gallop must preserve requested drive speed")
			check(touchdown_brake_frames > 0,"Terrain landing must exercise braking")
			check(pinned_drift < 0.08,"Pinned stance feet must remain close to anchors")
			check(movement._gallop_takeoffs > 0,"Ground-authorized takeoff must occur")
			check(maximum_batch == data.gallop_step_group_size,"Gallop must launch grouped steps")
			check(maximum_stepping > data.calculate_support_capacity(count),"Gallop must permit more concurrent steps than walking")
			check(seen_sequences.size() <= ceili(10.0*data.maximum_step_frequency)+data.gallop_step_group_size,"Group starts must respect total frequency budget")
			if count == 4: check(air_frames > 0,"Four-foot fixture must exercise all-foot flight")
			check(assisted_frames > 0,"Physics run must exercise actual airborne assistance")
			# Wait for a real stance before isolating the expiry check. The final
			# sampled gait frame can legitimately have all feet in the air.
			for settle_frame: int in range(120):
				if not movement._contact_drive_supports(movement._legs).is_empty(): break
				await physics_frame
			# A longer swing need not land inside the short takeoff timer. Exercise
			# independent per-foot reacquisition with an actual returned terrain contact.
			var returned: RigidBody3D = movement._contact_drive_supports(movement._legs)[0]
			movement._gallop_reach_released.erase(returned)
			movement._gallop_landed_feet.erase(returned)
			movement._gallop_launch_time = movement._physics_elapsed-0.1
			movement._gallop_pin_release_until = movement._physics_elapsed+0.2
			movement._update_support_foot_lock(returned,Vector3.UP)
			check(movement.get_support_foot_diagnostics(returned).locked,"A returned contact must regain its pin independently of launch timer")
			# Verify expiry using actual ground probes, not a mocked grounded boolean.
			movement.cancel_step()
			movement.set_physics_process(false)
			actor.get_node("CreatureRecoveryStateMachine3D").set_physics_process(false)
			movement._begin_ground_probe_frame()
			movement._update_gallop_contacts()
			check(not movement._gallop_contacts.is_empty(),"Fixture must record a true stance contact")
			for body: RigidBody3D in actor._get_physical_body_parts(): body.global_position += Vector3.UP*10.0
			movement.release_all_support_pins()
			movement._physics_elapsed += 0.05
			movement._begin_ground_probe_frame()
			movement._reset_contact_drive_diagnostics()
			movement._apply_torso_response()
			check(Vector3(movement._gallop_diagnostics.airborne_force).length()>0.001,"Recent ground contact must authorize airborne drive")
			check(Vector3(movement._gallop_diagnostics.airborne_support).length()>0.001,"SubTorso must support during the flight window")
			var before: int = movement._gallop_takeoffs
			movement._try_gallop_takeoff(movement._legs[0])
			check(movement._gallop_takeoffs == before,"Cannot take off again in air")
			movement._physics_elapsed += data.gallop_maximum_airborne_duration+0.01
			movement._begin_ground_probe_frame()
			movement._reset_contact_drive_diagnostics()
			movement._apply_torso_response()
			check(movement._gallop_contacts.is_empty(),"Airborne commands must not renew ground lease")
			for foot: RigidBody3D in movement._legs:
				check(not movement._can_start_step_with_support(foot),"Expired airborne support must reject new step starts")
			check(movement._last_torso_response_force.is_zero_approx() and movement._last_auxiliary_support_force.is_zero_approx(),"Expired flight must stop propulsion and support")
			data.gallop_enabled = false
			movement._update_gallop_contacts()
			check(not movement._gallop_active() and movement._gallop_contacts.is_empty(),"Off switch must discard flight eligibility")
			check(movement.get_expected_horizontal_speed()<5.0,"Off switch must restore walking speed planning")
			data.gallop_enabled = true
			Input.action_release("Right")
			check(not movement._gallop_active(),"Idle must not apply airborne assistance")
			Input.action_press("Right")
			movement.set_turn_planning_active(true)
			check(not movement._gallop_active(),"Turning must preserve contact-only traction")
			print("GALLOP_EXPIRY_PASSED")
		Input.action_release("Right")
		actor.queue_free()
		await process_frame
	check(means[1]>means[0]*1.2,"Gallop should improve speed over cadence-limited walking")
	print("GENERATED_GALLOP_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

