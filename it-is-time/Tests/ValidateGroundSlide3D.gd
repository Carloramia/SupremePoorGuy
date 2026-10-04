extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(500.0, 1.0, 500.0)
	collision.shape = shape
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var character := load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate() as Node3D
	root.add_child(character)
	var movement: Node = character.get_node("LegStepMovementController3D")
	var facing: Node = character.get_node("PhysicalFacingController3D")
	facing.set_diagnostic_logging_enabled(false)
	var torso := character.get_node("Torso") as RigidBody3D
	var cursor := Node3D.new()
	root.add_child(cursor)
	facing.terrain_cursor = cursor
	var starts := {"count": 0}
	facing.turn_started.connect(func(_direction: int) -> void: starts.count += 1)
	var max_speed := 0.0
	var maximum_snapshot := ""
	var total_drift := 0.0
	var speed_window: Array[float] = []
	var peak_mean_speed := 0.0
	var samples := 0
	for frame: int in 900:
		cursor.global_position = torso.global_position + Vector3.RIGHT * 10.0
		if frame == 120:
			Input.action_press("Right")
		if frame == 360:
			Input.action_press("Up")
		if frame == 600:
			Input.action_release("Right")
			Input.action_release("Up")
		await physics_frame
		if frame >= 120 and frame < 600:
			if torso.linear_velocity.slide(Vector3.UP).length() > max_speed:
				max_speed = torso.linear_velocity.slide(Vector3.UP).length()
				maximum_snapshot = "frame=%d support=%d brake=%s state=%s torso_y=%.3f" % [frame, movement.get_torso_movement_force_legs().size(), movement._ground_brake_force, movement.get_step_state_name(), torso.global_position.y]
			speed_window.append(torso.linear_velocity.slide(Vector3.UP).length())
			if speed_window.size() > 30:
				speed_window.pop_front()
			if speed_window.size() == 30:
				var window_sum := 0.0
				for speed: float in speed_window:
					window_sum += speed
				peak_mean_speed = maxf(peak_mean_speed, window_sum / 30.0)
			for leg: RigidBody3D in movement.get_leg_parts():
				var info: Dictionary = movement.get_support_foot_diagnostics(leg)
				if info.locked:
					total_drift += info.drift
					samples += 1
	var stopped_speed := torso.linear_velocity.slide(Vector3.UP).length()
	var mean_drift := total_drift / maxf(float(samples), 1.0)
	print("GROUND_SLIDE_METRICS max_speed=%.3f expected=%.3f stopped_speed=%.3f mean_foot_drift=%.3f turns=%d" % [max_speed, movement.get_expected_horizontal_speed(), stopped_speed, mean_drift, starts.count])
	print("MAXIMUM_SNAPSHOT=" + maximum_snapshot)
	print("PEAK_HALF_SECOND_MEAN_SPEED=%.3f" % peak_mean_speed)
	var passed: bool = peak_mean_speed < movement.get_expected_horizontal_speed() * 1.8
	passed = passed and stopped_speed < 0.5
	passed = passed and samples > 100 and mean_drift < 0.35
	passed = passed and starts.count == 0
	for node: Node in character.find_children("*", "RigidBody3D", true, false):
		(node as RigidBody3D).linear_velocity = Vector3(60.0, 0.0, 0.0)
	for _frame: int in 360:
		cursor.global_position = torso.global_position + Vector3.RIGHT * 10.0
		await physics_frame
	print("GROUND_SLIDE_RECOVERY_SPEED=%.3f" % torso.linear_velocity.slide(Vector3.UP).length())
	passed = passed and torso.linear_velocity.slide(Vector3.UP).length() < 1.0
	print("GROUND_SLIDE_3D_VALIDATION_PASSED" if passed else "GROUND_SLIDE_3D_VALIDATION_FAILED")
	quit(0 if passed else 1)

