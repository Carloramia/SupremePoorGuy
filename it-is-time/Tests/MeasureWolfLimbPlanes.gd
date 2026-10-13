extends SceneTree

class Command:
	extends Node
	var direction := Vector3.ZERO
	func get_movement_direction() -> Vector3: return direction
	func is_fast_movement_requested() -> bool: return false
	func is_jump_requested() -> bool: return false

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1000, 1, 100)
	collider.shape = shape
	floor_body.add_child(collider)
	floor_body.position.y = 0.5
	root.add_child(floor_body)
	var modes := [true] if "--enabled-only" in OS.get_cmdline_user_args() else [false, true]
	for enabled: bool in modes:
		var actor = load("res://Scenes/Creatures/Characters/Generate_Wolf.tscn").instantiate()
		actor.generate_on_ready = false
		actor.position.y = 4.0
		root.add_child(actor)
		var command := Command.new()
		actor.add_child(command)
		var move = actor.get_node("GeneratedLegStepMovementController3D")
		var data = move.slow_gait_data.duplicate()
		data.target_speed = 8.0
		data.maximum_step_frequency = 4.0
		data.limb_plane_stabilization_enabled = enabled
		move.slow_gait_data = data
		move.fast_gait_data = data
		move.command_source = command
		actor.get_node("CreatureRecoveryStateMachine3D").set_physics_process(false)
		move.recovery_control_active = false
		var error_sum := 0.0
		var maximum_error := 0.0
		var speed_sum := 0.0
		var samples := 0
		var maximum_yaw := 0.0
		for index: int in range(1500):
			await physics_frame
			if index == 120: command.direction = Vector3.RIGHT
			move.input_enabled = true
			move.set_physics_process(true)
			if index >= 600:
				var frame_error := 0.0
				for link: Dictionary in move._wolf_plane_links:
					var a: Vector3 = (link.a.global_basis * Vector3(link.normal_a)).normalized()
					var b: Vector3 = (link.b.global_basis * Vector3(link.normal_b)).normalized()
					frame_error = maxf(frame_error, rad_to_deg(a.angle_to(b)))
				error_sum += frame_error
				maximum_error = maxf(maximum_error, frame_error)
				speed_sum += move._torso.linear_velocity.slide(Vector3.UP).length()
				maximum_yaw = maxf(maximum_yaw, absf(rad_to_deg(move._get_physical_heading_yaw())))
				samples += 1
			assert(move._torso.global_position.is_finite())
		print("WOLF_PLANE_MEASURE enabled=%s mean_max_plane_error=%.3f peak_plane_error=%.3f mean_speed=%.3f maximum_yaw=%.3f failed_steps=%d" % [enabled, error_sum / samples, maximum_error, speed_sum / samples, maximum_yaw, move._failed_step_count])
		if enabled:
			assert(error_sum / samples < 5.0 and maximum_error < 15.0, "All limb planes must remain near the shared torso plane")
			assert(speed_sum / samples > data.target_speed * 0.9, "Plane stabilization must preserve forward speed")
			assert(maximum_yaw < 15.0, "Straight walking must not develop a large yaw drift")
		actor.free()
		await physics_frame
	quit()
