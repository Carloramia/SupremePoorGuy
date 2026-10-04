extends SceneTree

class TestCommandSource extends Node:
	func get_movement_direction() -> Vector3:
		return Vector3(Input.get_action_strength(&"Right") - Input.get_action_strength(&"Left"), 0, Input.get_action_strength(&"Down") - Input.get_action_strength(&"Up")).normalized()
	func is_fast_requested() -> bool:
		return Input.is_action_pressed(&"Shift")
	func is_jump_requested() -> bool:
		return false

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var ground := StaticBody3D.new()
	ground.name = "TestGround"
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(20.0, 1.0, 4.0)
	ground_collision.shape = ground_shape
	ground.add_child(ground_collision)
	ground.position.y = -0.5
	root.add_child(ground)

	var character: Node3D = load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate()
	root.add_child(character)
	await physics_frame
	var controller := character.get_node("LegStepMovementController3D")
	var commands := TestCommandSource.new()
	character.add_child(commands)
	controller.command_source = commands
	var torso := character.get_node("Torso") as RigidBody3D
	var leg_r := character.get_node("Leg_R") as RigidBody3D
	var leg_l := character.get_node("Leg_L") as RigidBody3D
	controller.input_enabled = false
	controller.use_slow_movement_scale = false
	controller.use_fast_movement_scale = false
	controller.maximum_horizontal_leg_reach = 4.5
	var legs: Array[RigidBody3D] = controller.get_leg_parts()
	assert(legs.size() == 2)
	assert(controller.is_in_group(&"leg_step_movement_controllers"))
	controller.set_performance_tracking_enabled(true)
	controller._begin_ground_probe_frame()
	assert(controller.is_leg_grounded(leg_l))
	assert(controller.is_leg_grounded(leg_l))
	controller._get_surface_below_leg(leg_l, controller.surface_adhesion_probe_distance)
	var cached_probe_stats: Dictionary = controller.consume_performance_stats()
	assert(cached_probe_stats.ray_queries == 1, "Ground, adhesion and support reads must share one ray per Leg per physics frame")
	controller.set_performance_tracking_enabled(false)
	controller.update_leg_surface_adhesion()
	var runtime_console := root.get_node("RuntimeConsole")
	assert(runtime_console.execute_command("trackmotion").ends_with("enabled."))
	assert(runtime_console.execute_command("trackmotion").ends_with("disabled."))

	Input.action_press(&"Right")
	Input.action_press(&"Up")
	var diagonal_direction: Vector3 = controller.get_input_movement_direction()
	assert(diagonal_direction.is_equal_approx(Vector3(1.0, 0.0, -1.0).normalized()))
	Input.action_press(&"Left")
	assert(controller.get_input_movement_direction().is_equal_approx(Vector3.FORWARD))
	Input.action_release(&"Right")
	Input.action_release(&"Left")
	Input.action_release(&"Up")
	assert(controller.get_current_speed_preset_name() == "SLOW")
	assert(is_equal_approx(controller.get_current_step_distance(), controller.slow_step_distance))
	assert(is_equal_approx(controller.get_current_step_duration(), controller.slow_step_duration))
	controller.use_slow_movement_scale = true
	controller.slow_movement_scale = 2.0
	assert(is_equal_approx(controller.get_current_step_distance(), controller.slow_step_distance * sqrt(2.0)))
	assert(is_equal_approx(controller.get_current_step_duration(), controller.slow_step_duration / sqrt(2.0)))
	assert(is_equal_approx(
		controller.get_current_step_distance() / controller.get_current_step_duration(),
		(controller.slow_step_distance / controller.slow_step_duration) * 2.0
	))
	leg_r.freeze = true
	leg_l.freeze = true
	leg_l.global_position += Vector3.UP * 2.0
	leg_r.global_position += Vector3.UP * 2.0
	assert(
		not controller._can_start_step_with_support(leg_l),
		"Slow mode must still require another grounded Leg"
	)
	Input.action_press(&"Shift")
	assert(controller.get_current_speed_preset_name() == "FAST")
	assert(is_equal_approx(
		controller.get_current_step_distance() * controller.get_fast_step_frequency(),
		controller.fast_target_speed
	))
	assert(is_equal_approx(
		controller.get_current_step_duration(),
		controller.get_fast_step_interval() * controller.fast_swing_duration_ratio
	))
	controller.use_fast_movement_scale = true
	controller.fast_movement_scale = 1.5
	assert(is_equal_approx(
		controller.get_current_step_distance() * controller.get_fast_step_frequency(),
		controller.fast_target_speed * 1.5
	))
	assert(not controller.fast_torso_velocity_drive_enabled)
	assert(
		controller._can_start_step_with_support(leg_l),
		"Fast mode must not require any Leg to touch the ground"
	)
	leg_l.global_position -= Vector3.UP * 2.0
	leg_r.global_position -= Vector3.UP * 2.0
	leg_l.freeze = false
	leg_r.freeze = false
	var full_stride_landing: Dictionary = controller.find_landing_point(leg_r, Vector3.RIGHT)
	assert(not full_stride_landing.is_empty())
	var projected_fast_rest: Vector3 = controller._get_projected_landing_rest_position(
		leg_r,
		Vector3.RIGHT
	)
	assert(is_equal_approx(
		(full_stride_landing.position - projected_fast_rest).dot(Vector3.RIGHT),
		controller.get_current_step_distance()
	), "Torso height must not shorten an otherwise legal horizontal fast stride")
	assert(controller.try_start_step(Vector3.RIGHT), "Fast gait must start with a legal landing point")
	var anchored_leg_rest: Vector3 = controller._get_projected_landing_rest_position(
		leg_r,
		Vector3.RIGHT
	)
	torso.global_position += Vector3.RIGHT
	assert(
		controller._get_projected_landing_rest_position(leg_r, Vector3.RIGHT).is_equal_approx(
			anchored_leg_rest
		),
		"Both Legs in one fast gait cycle must use the same center anchor"
	)
	torso.global_position -= Vector3.RIGHT
	assert(is_equal_approx(
		controller._get_effective_step_height(),
		minf(
			controller.fast_step_height * sqrt(controller.fast_movement_scale),
			controller.maximum_scaled_step_height
		)
	))
	assert(controller.get_step_sequence() == 1)
	assert(controller.get_fast_lift_time_remaining() > 0.0)
	controller._update_fast_float_lift(1.0 / 60.0, Vector3.RIGHT, true)
	assert(controller.get_current_fast_lift_force() > 0.0)
	assert(controller.get_step_target_normal().is_equal_approx(Vector3.UP))
	leg_l.global_position += Vector3.UP * 0.2
	controller._apply_fast_landing_assist(1.0)
	assert(controller.get_current_fast_landing_force().dot(Vector3.UP) < 0.0)
	assert(is_zero_approx(controller.get_fast_lift_time_remaining()))
	leg_l.global_position -= Vector3.UP * 0.2
	controller.cancel_step()
	assert(is_equal_approx(
		controller._get_effective_landing_tolerance(),
		controller.landing_tolerance
			* sqrt(controller.fast_movement_scale)
			* controller.fast_landing_tolerance_multiplier
	))
	assert(controller.try_start_step(Vector3.RIGHT))
	controller._step_state = 2 # StepState.LANDING
	controller._step_target = controller.get_active_leg().global_position + Vector3.RIGHT * 5.0
	controller._landing_elapsed = 0.0
	controller._update_active_step(controller.fast_grounded_landing_timeout + 0.01)
	assert(
		controller.get_active_leg() == null,
		"A grounded fast Leg must not block the alternating gait on horizontal residual error"
	)
	controller._next_leg_index = 0
	assert(controller.try_start_step(Vector3.RIGHT))
	var unfinished_fast_leg: RigidBody3D = controller.get_active_leg()
	unfinished_fast_leg.global_position += Vector3.UP * 0.5
	controller._next_fast_step_start_time = controller._physics_elapsed
	controller._update_fast_gait_clock(Vector3.RIGHT)
	assert(
		controller.get_active_leg() != unfinished_fast_leg,
		"The fast gait clock must switch Legs without waiting for the previous Leg to land"
	)
	unfinished_fast_leg.global_position -= Vector3.UP * 0.5
	controller.cancel_step()
	controller._next_leg_index = 0
	Input.action_release(&"Shift")
	controller._update_fast_float_lift(1.0 / 60.0, Vector3.RIGHT, false)
	assert(is_zero_approx(controller.get_fast_lift_time_remaining()))
	controller.use_slow_movement_scale = false
	assert(is_equal_approx(controller.get_current_step_distance(), controller.slow_step_distance))
	assert(is_equal_approx(controller.get_current_step_duration(), controller.slow_step_duration))

	assert(controller.is_leg_grounded(leg_l), "The left foot ray must detect the test ground")
	assert(controller.is_leg_grounded(leg_r), "The right foot ray must detect the test ground")
	controller.update_leg_surface_adhesion()
	assert(controller.get_leg_adhesion_surface_normal(leg_l).is_equal_approx(Vector3.UP))
	assert(controller.get_leg_adhesion_surface_normal(leg_r).is_equal_approx(Vector3.UP))
	assert(controller.get_leg_adhesion_surface_normals().size() == 2)
	var initial_leg_separation := Vector2(
		leg_r.global_position.x - leg_l.global_position.x,
		leg_r.global_position.z - leg_l.global_position.z
	)
	for horizontal_direction: Vector3 in [Vector3.LEFT, Vector3.RIGHT]:
		var horizontal_landing_l: Dictionary = controller.find_landing_point(leg_l, horizontal_direction)
		var horizontal_landing_r: Dictionary = controller.find_landing_point(leg_r, horizontal_direction)
		assert(not horizontal_landing_l.is_empty() and not horizontal_landing_r.is_empty())
		var landing_separation := Vector2(
			horizontal_landing_r.position.x - horizontal_landing_l.position.x,
			horizontal_landing_r.position.z - horizontal_landing_l.position.z
		)
		var correction_strength: float = controller.get_directional_projection_correction_strength()
		var expected_separation := initial_leg_separation * (1.0 - correction_strength)
		assert(
			landing_separation.is_equal_approx(expected_separation),
			"Landing selection must apply the speed-scaled longitudinal stance correction"
		)
	var landing: Dictionary = controller.find_landing_point(leg_l)
	assert(not landing.is_empty(), "A walkable landing point must be found to the right")
	assert(landing.position.x > leg_l.global_position.x, "The landing point must be to the right")
	var original_landing_position: Vector3 = landing.position
	leg_l.global_position += Vector3(-0.1, 0.0, 0.0)
	var landing_after_leg_error: Dictionary = controller.find_landing_point(leg_l)
	assert(
		landing_after_leg_error.position.is_equal_approx(original_landing_position),
		"Landing sampling must use the initial Torso-relative position, not the displaced leg"
	)
	leg_l.global_position += Vector3(0.1, 0.0, 0.0)
	assert(controller.try_start_step(), "A supported character must be able to start a step")
	assert(controller.get_active_leg() == leg_l, "The stable alternating order must start at the left leg")
	var slight_navigation_turn := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(2.0))
	assert(
		not controller._should_replan_active_step_direction(slight_navigation_turn),
		"Small navigation direction changes must not restart the active step"
	)
	assert(
		controller._should_replan_active_step_direction(Vector3.LEFT),
		"A true direction reversal must bypass the ordinary replan cooldown"
	)
	controller._physics_elapsed += controller.replan_cooldown
	assert(
		controller._should_replan_active_step_direction(Vector3.FORWARD),
		"A significant turn must replan after the cooldown"
	)
	controller.update_leg_surface_adhesion()
	assert(
		controller.get_leg_adhesion_surface_normal(leg_l).is_zero_approx(),
		"The stepping leg must not receive surface adhesion"
	)
	assert(controller.get_leg_adhesion_surface_normal(leg_r).is_equal_approx(Vector3.UP))
	assert(controller.replan_active_step(Vector3.FORWARD), "A direction change must find a replacement target")
	assert(controller.get_active_leg() == leg_l, "Direction changes must replan the same active leg")
	controller.cancel_step()
	torso.freeze = true
	leg_l.freeze = true
	leg_r.freeze = true
	controller.slow_step_duration = 0.01
	controller.landing_timeout = 0.01
	controller.minimum_scaled_landing_timeout = 0.01
	controller.landing_confirmation_time = 0.0
	assert(controller.try_start_step(Vector3.RIGHT))
	await physics_frame
	await physics_frame
	await physics_frame
	assert(controller.get_active_leg() == null, "A grounded timeout must finish instead of retrying forever")
	assert(controller.try_start_step(Vector3.RIGHT))
	assert(controller.get_active_leg() == leg_r, "A grounded timeout must advance to the next Leg")
	controller.cancel_step()
	controller.update_leg_surface_adhesion()
	assert(controller.get_torso_parts().size() == 1)
	assert(controller.try_surface_burst(), "Attached Leg normals must produce a Torso burst")
	assert(controller.get_adhesion_release_time_remaining() > 0.0)
	assert(controller.get_combined_adhesion_surface_normal().is_zero_approx())
	assert(controller.get_leg_adhesion_surface_normal(leg_l).is_zero_approx())
	assert(controller.get_leg_adhesion_surface_normal(leg_r).is_zero_approx())

	leg_l.global_position += Vector3(1.0, 0.0, 0.0)
	leg_r.global_position += Vector3(0.5, 2.0, 0.0)
	assert(controller.get_torso_movement_force_legs(false) == [leg_l])
	var combined_offset: Vector3 = controller.get_combined_leg_offset()
	assert(combined_offset.is_equal_approx(Vector3(1.0, 0.0, 0.0)))
	var expected_force: Vector3 = combined_offset * float(controller.torso_force_per_unit)
	if expected_force.length() > controller.maximum_torso_force:
		expected_force = expected_force.normalized() * controller.maximum_torso_force
	assert(controller.calculate_torso_force().is_equal_approx(expected_force))
	leg_l.global_position += Vector3.UP * 2.0
	assert(controller.get_torso_movement_force_legs(false).is_empty())
	assert(controller.calculate_torso_force().is_zero_approx())
	Input.action_press(&"Shift")
	assert(controller.get_fast_airborne_force_grace_remaining() > 0.0)
	assert(controller.get_torso_movement_force_legs(true) == [leg_l])
	assert(not controller.calculate_torso_force().is_zero_approx())
	controller._physics_elapsed += controller.fast_airborne_force_grace_duration + 0.01
	assert(is_zero_approx(controller.get_fast_airborne_force_grace_remaining()))
	assert(controller.get_torso_movement_force_legs(true).is_empty())
	assert(controller.calculate_torso_force().is_zero_approx())
	Input.action_release(&"Shift")
	print("LEG_STEP_MOVEMENT_CONTROLLER_VALIDATION_PASSED")
	character.queue_free()
	ground.queue_free()
	quit()
