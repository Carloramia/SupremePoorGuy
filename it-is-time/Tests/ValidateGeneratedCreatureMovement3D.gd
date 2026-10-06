extends SceneTree

const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	collision.shape = shape
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var counts := [2, 4, 7, 10]
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--feet="): counts = [argument.trim_prefix("--feet=").to_int()]
	for count: int in counts:
		var character := CHARACTER.instantiate() as Node3D
		character.generate_on_ready = false
		root.add_child(character)
		var generator := character.get_node("CreatureGenerator")
		generator.rear_leg_count = maxi((count) - 2, 0)
		generator.foreleg_count = mini((count), 2)
		generator.unsymmetrie = 100.0 if "--asymmetric" in OS.get_cmdline_user_args() else 0.0
		generator.neck_number = 0
		generator.body_length = maxf(4.0, float(count) * 1.2)

		generator._random.seed = 42
		assert(character.generate_creature())
		var controller := character.get_node("GeneratedLegStepMovementController3D")
		assert(controller.get_script().get_base_script().resource_path.ends_with("LegStepMovementControllerBase3D.gd"))
		assert(controller.get_leg_parts().size() == count)
		assert(controller._chains.size() == count)
		assert(controller._leg_initial_local_positions.size() == count)
		assert(not controller.is_fast_speed_active())
		if count == 2:
			var console := root.get_node("RuntimeConsole")
			assert(console.execute_command("trackgenerated").ends_with("enabled."))
			assert(controller.diagnostic_logging_enabled)
			assert(console.execute_command("trackgenerated").ends_with("disabled."))
			assert(not controller.diagnostic_logging_enabled)
		for foot: RigidBody3D in controller.get_leg_parts():
			var chain: Dictionary = controller._chains[foot]
			assert(chain.length > 0.0 and controller._chain_is_intact(foot))
			var expected := 4 if 1 in foot.tags else 3
			assert(chain.joints.size() == expected)
			for joint: Generic6DOFJoint3D in chain.joints:
				var a: Node = joint.get_node(joint.node_a)
				var b: Node = joint.get_node(joint.node_b)
				var expected_slack: float = character.limb_joint_linear_slack.x if 5 in a.tags and 5 in b.tags else 0.0
				assert(is_equal_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), expected_slack))
		Input.action_press("Right")
		Input.action_press("Up")
		assert(controller.get_input_movement_direction().is_equal_approx(Vector3(1, 0, -1).normalized()))
		Input.action_press("Shift")
		assert(not controller.is_fast_speed_active())
		Input.action_release("Shift")
		Input.action_release("Right")
		Input.action_release("Up")
		assert(controller.get_input_movement_direction() == Vector3.ZERO)
		# A target far beyond the chain must not be accepted even on a walkable surface.
		var foot: RigidBody3D = controller.get_leg_parts()[0]
		assert(not controller._is_landing_point_valid(foot, controller._get_foot_world_position(foot), {"position": foot.global_position + Vector3(100, -0.1, 0), "normal": Vector3.UP, "rid": ground.get_rid()}))
		# Single-foot gait and stable sequential selection on actual ground.
		for frame: int in range(180): await physics_frame
		var initial: Vector3 = controller._torso.global_position
		Input.action_press("Right")
		var steady_speeds: Array[float] = []
		for frame: int in range(360):
			await physics_frame
			if frame >= 240:
				var velocity := Vector3.ZERO
				var mass := 0.0
				for body: RigidBody3D in controller.get_torso_parts():
					velocity += body.linear_velocity * body.mass
					mass += body.mass
				steady_speeds.append((velocity / maxf(mass,0.001)).slide(Vector3.UP).length())
		var mean_speed := 0.0
		for speed: float in steady_speeds: mean_speed += speed / steady_speeds.size()
		print("AUTOMATIC_WALK_SPEED requested=",controller.slow_gait_data.target_speed," planned=",controller._get_expected_horizontal_speed()," steady_mean=",mean_speed)
		Input.action_release("Right")
		var displacement: Vector3 = controller._torso.global_position - initial
		print("[generated_gait_test] feet=%d steps=%d touchdown=%s displacement=%s diagnostics=%s" % [count, controller._step_sequence, controller._last_touchdown_leg, displacement, controller.get_generated_movement_diagnostics()])
		assert(controller._step_sequence > 0, "Generated character did not start walking")
		assert(not controller._last_touchdown_leg.is_empty(), "Generated character never completed a grounded step")
		assert(displacement.x > 0.05, "Right input must produce actual forward motion")
		assert(absf(displacement.z) < 1.0, "Right gait must not drift sideways excessively")
		assert(absf(displacement.y) < 1.0, "Walking must not launch the Torso")
		for part: RigidBody3D in character._get_physical_body_parts():
			assert(part.global_position.is_finite() and part.linear_velocity.is_finite())
			assert(part.linear_velocity.length() < 30.0)
		# A broken intermediate Limb disables its attached foot without controlling a detached chain.
		controller.cancel_step()
		foot = controller.get_leg_parts()[0]
		var intermediate: PhysicalBodyPart3D = controller._chains[foot].bodies[1]
		intermediate.break_part(null)
		await process_frame
		controller._remove_invalid_legs()
		assert(foot not in controller.get_leg_parts())
		generator._random.seed = 99
		assert(character.generate_creature())
		assert(controller.get_leg_parts().size() == count)
		assert(controller.get_active_leg() == null)
		assert(controller._support_anchors.is_empty() and controller._last_grounded_force_legs.is_empty())
		assert(controller._leg_initial_local_positions.size() == count)
		controller.forelegs_participate_in_walking = false
		controller.refresh_physics_query_cache()
		for leg: RigidBody3D in controller.get_leg_parts(): assert(1 in leg.tags and 4 not in leg.tags)
		character.queue_free()
		await process_frame
	ground.queue_free()
	await process_frame
	print("GENERATED_CREATURE_MOVEMENT_VALIDATION_PASSED")
	quit()
