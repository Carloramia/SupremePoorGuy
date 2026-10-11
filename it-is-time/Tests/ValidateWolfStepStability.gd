extends SceneTree

class Command:
	extends Node
	func get_movement_direction() -> Vector3: return Vector3.RIGHT
	func is_fast_movement_requested() -> bool: return false

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var data = load("res://Resources/Movement/WolfWalk.tres").duplicate()
	data.maximum_step_frequency = 12.0
	var raw: Dictionary = data.calculate_motion_profile(4.12, 2.0, 4, 4.12)
	var safe: Dictionary = data.stabilize_profile(raw, 2.0, 4, 0.0)
	assert(safe.swing_duration >= 0.35 and safe.swing_duration > raw.swing_duration)
	assert(safe.position_gain <= data.maximum_tracking_gain)
	assert(safe.step_acceleration <= data.maximum_tracking_acceleration)
	assert(safe.cycle >= safe.wolf_occupied_duration * 2.0)
	var slow: Dictionary = data.stabilize_profile(raw, 2.0, 4, 1.2)
	assert(slow.reachable_speed < safe.reachable_speed)
	assert(data.safe_swing_time(5.0, 0.2, 0.133) > data.safe_swing_time(1.0, 0.2, 0.133))
	var allocation: Dictionary = data.allocate_tracking_force(Vector3(1000.0, 30.0, 0.0), Vector3.UP, 100.0)
	assert(is_equal_approx(allocation.force.y, 30.0))
	assert(allocation.force.length() <= 100.001)
	assert(data.recovery_stride_scale(3) < data.recovery_stride_scale(1))
	assert(data.recovery_stride_scale(100) >= data.minimum_recovery_stride_ratio)
	var deadline: float = data.catch_up_deadline(0.8, 0.5, 2.0, 0.1, 1.0)
	assert(deadline > 1.0 and deadline <= 1.0 + data.maximum_catch_up_extension)
	assert(data.catch_up_deadline(0.9, 0.5, 0.1, 5.0, deadline) >= deadline)
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	collider.shape = box
	floor_body.add_child(collider)
	floor_body.position.y = 0.5
	root.add_child(floor_body)
	for scene in ["Generate_Wolf", "Generate_Wolf_NPC"]:
		var actor = load("res://Scenes/Creatures/Characters/" + scene + ".tscn").instantiate()
		actor.generate_on_ready = false
		root.add_child(actor)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		var movement = actor.get_node("GeneratedLegStepMovementController3D")
		movement.slow_gait_data = data
		movement.fast_gait_data = data
		var command := Command.new()
		actor.add_child(command)
		movement.command_source = command
		for body in actor.get_node("GeneratedParts").get_children():
			if body is RigidBody3D: body.freeze = true
		await physics_frame
		var foot: RigidBody3D = movement._chains.keys()[0]
		foot.global_position.y += 1.0 - movement._get_foot_world_position(foot).y
		movement._begin_leg_motion(foot, foot.global_position + Vector3.RIGHT, Vector3.UP, Vector3.RIGHT)
		var short_height: float = movement._get_effective_step_height()
		movement._step_target = foot.global_position + Vector3.RIGHT * 4.0
		movement._plan_wolf_swing()
		assert(movement._get_effective_step_height() > short_height)
		assert(movement._get_effective_step_height() <= movement._chains[foot].length * data.maximum_lift_length_ratio + 0.001)
		movement._apply_wolf_tracking(foot.global_position + Vector3.UP * 0.2, Vector3.ZERO, 1.0 / 60.0)
		var vertical_force: float = movement._tracking_force.y
		movement._apply_wolf_tracking(foot.global_position + Vector3(100.0, 0.2, 0.0), Vector3.ZERO, 1.0 / 60.0)
		assert(is_equal_approx(movement._tracking_force.y, vertical_force))
		assert(movement._tracking_force.length() <= movement._tracking_force_limit + 0.001)
		movement._update_active_step(1.0 / 60.0)
		assert(movement._current_step.extra.wolf_step.phase == "lift")
		assert(is_zero_approx(movement._step_elapsed))
		assert(absf(movement._tracking_position_error.x) < 0.0001)
		foot.global_position.y += 0.8
		await physics_frame
		movement._update_active_step(1.0 / 60.0)
		assert(movement._current_step.extra.wolf_step.phase == "swing")
		movement._update_active_step(1.0 / 60.0)
		assert(movement._tracking_force.length() <= movement._tracking_mass * data.maximum_tracking_acceleration + 0.001)
		movement._step_elapsed = movement._active_step_duration * 0.8
		movement._update_active_step(1.0 / 60.0)
		var swing: Dictionary = movement._current_step.extra.wolf_step
		assert(swing.target_valid)
		assert(swing.height_progress <= swing.horizontal_progress + 0.1501)
		assert(swing.phase == "swing")
		assert(swing.descent_target_y >= movement._step_target.y + movement._get_effective_step_height() * 0.6 - 0.001)
		# Near-ground pursuit must transition to a downward command, not hover above contact.
		foot.global_position = movement._step_target + Vector3.UP * 0.06
		foot.linear_velocity = Vector3.ZERO
		movement._update_active_step(1.0 / 60.0)
		assert(swing.phase == "descend")
		assert(movement._tracking_position_error.y < -0.05)
		var descent_y: float = swing.descent_target_y
		foot.global_position.x -= 0.1
		movement._update_active_step(1.0 / 60.0)
		assert(swing.phase == "descend")
		assert(is_equal_approx(swing.descent_target_y, descent_y),"Horizontal tracking regression must not lift a descending foot")
		# A real touchdown wins even if the launch target is still far away.
		foot.global_position.x -= 2.0
		foot.global_position.y += 1.0 - movement._get_foot_world_position(foot).y
		foot.linear_velocity = Vector3.RIGHT * 10.0
		await physics_frame
		var limb: RigidBody3D = movement._chains[foot].bodies[1]
		limb.freeze = false
		foot.freeze = false
		movement._update_active_step(1.0 / 60.0)
		assert(movement._current_step.extra.wolf_step.phase == "brake")
		assert(not movement._current_step.extra.wolf_step.horizontal_tracking)
		assert(movement._step_target.is_equal_approx(foot.global_position))
		assert(movement._tracking_position_error.is_zero_approx())
		assert(movement._tracking_force.x < 0.0)
		assert(movement._tracking_mass > foot.mass)
		assert(movement._tracking_force.length() <= movement._tracking_force_limit + 0.001)
		assert(movement._tracking_force.length() > foot.mass * data.maximum_contact_brake_acceleration)
		assert(movement._current_step.extra.touchdown_pin.slack <= data.wolf_touchdown_pin_initial_slack)
		assert(data.wolf_touchdown_pin_initial_slack < data.touchdown_pin_initial_slack)
		foot.freeze = true
		limb.freeze = true
		var diagnostics: Dictionary = movement.get_support_foot_diagnostics(foot)
		assert(diagnostics.gallop.wolf_step.phase == "brake")
		assert(not diagnostics.gallop.wolf_step.completion.valid)
		movement._physics_elapsed += 0.8
		foot.linear_velocity = Vector3.ZERO
		for i in 4: movement._update_active_step(1.0 / 60.0)
		assert(movement._step_state == movement.StepState.IDLE)
		assert(movement._wolf_step_times.has(foot))
		assert(movement._wolf_recovery_steps.has(foot))
		movement._startup_pending = false
		movement._walk_start_pending.clear()
		var demand: Dictionary = movement._get_extension_step_demand(foot, Vector3.RIGHT)
		assert(demand.requested and demand.reason == "wolf_incomplete_landing_recovery")
		# A later landing inside the interval and at the target clears recovery.
		var bounds: Dictionary = movement._wolf_stride_bounds(foot, Vector3.RIGHT)
		foot.global_position = bounds.center
		var verdict: Dictionary = movement._wolf_landing_verdict(foot, foot.global_position, Vector3.RIGHT)
		assert(verdict.valid)
		movement._begin_leg_motion(foot, foot.global_position, Vector3.UP, Vector3.RIGHT)
		movement._current_step.extra.wolf_step["completion"] = verdict
		movement._finish_current_step()
		assert(not movement._wolf_recovery_steps.has(foot))
		var normal_target: Vector3 = movement._get_projected_landing_rest_position(foot, Vector3.RIGHT) + Vector3.RIGHT * movement.get_leg_step_distance(foot)
		movement._wolf_recovery_steps[foot] = 3
		var recovery_target: Vector3 = movement._get_projected_landing_rest_position(foot, Vector3.RIGHT) + Vector3.RIGHT * movement.get_leg_step_distance(foot)
		assert(recovery_target.x < normal_target.x)
		movement._begin_leg_motion(foot, recovery_target, Vector3.UP, Vector3.RIGHT)
		var recovery_duration: float = movement._active_step_duration
		movement.cancel_step()
		movement._wolf_recovery_steps.erase(foot)
		movement._begin_leg_motion(foot, recovery_target, Vector3.UP, Vector3.RIGHT)
		assert(movement._active_step_duration < recovery_duration)
		movement.cancel_step()
		movement._action_feet[foot] = true
		assert(not movement.get_leg_motion_profile(foot).has("wolf_occupied_duration"))
		actor.free()
	print("PASS: Wolf/NPC chase clearance, one-way descent, chain-mass braking, short pin transition, force caps and completion recovery.")
	quit()
