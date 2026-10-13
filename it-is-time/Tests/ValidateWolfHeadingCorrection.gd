extends SceneTree

class Command:
	extends Node
	var direction := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func is_fast_movement_requested() -> bool: return false

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 1, 100)
	collision.shape = box
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	for scene in ["Generate_Wolf", "Generate_Wolf_NPC"]:
		var actor = load("res://Scenes/Creatures/Characters/" + scene + ".tscn").instantiate()
		actor.generate_on_ready = false
		root.add_child(actor)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		var movement = actor.get_node("GeneratedLegStepMovementController3D")
		var data = movement.slow_gait_data.duplicate()
		data.target_speed = 8.0
		movement.slow_gait_data = data
		movement.fast_gait_data = data
		movement.input_enabled = true
		movement.recovery_control_active = false
		var command := Command.new()
		actor.add_child(command)
		movement.command_source = command
		for body in actor.get_node("GeneratedParts").get_children():
			if body is RigidBody3D: body.freeze = true
		await physics_frame
		for foot: RigidBody3D in movement._legs: foot.freeze = false
		movement._segment_heading_initialized = true
		movement._segment_goal_yaw = deg_to_rad(3.0)
		movement._wolf_auto_gallop = true
		assert(not movement._foot_heading_turn_active(), "Foot locking must use the same turn threshold as gallop")
		assert(not movement._wolf_heading_turn_active())
		movement._update_automatic_wolf_gallop(0.016)
		assert(movement._gallop_active(), "Small drift must not reset gallop")
		movement._update_layout_turn_steps(0.016)
		assert(not movement._layout_turn_owned and not movement._turn_planning_active)
		assert(movement._layout_turn_status == &"heading_correction")
		var correction: Dictionary = movement._turn_traction_control(deg_to_rad(2), deg_to_rad(20), deg_to_rad(45))
		assert(correction.mode == "heading_correction")
		assert(absf(correction.requested_rate) <= deg_to_rad(data.heading_correction_speed_degrees))
		assert(absf(correction.acceleration) <= deg_to_rad(data.heading_correction_acceleration_degrees) + 0.0001)
		assert(correction.acceleration < 0.0, "Correction must damp existing yaw velocity")
		var foot: RigidBody3D = movement._legs[0]
		foot.global_position.y -= movement._get_foot_world_position(foot).y
		foot.freeze = false
		movement._begin_ground_probe_frame()
		movement._begin_leg_motion(foot, foot.global_position + Vector3.RIGHT, Vector3.UP, Vector3.RIGHT)
		var motion = movement._current_step
		assert(motion.extra.has("wolf_step") and motion.extra.gallop_step)
		movement._segment_goal_yaw = PI
		movement._turn_command_pending = true
		movement._wolf_turn_state_frame = -1
		movement._update_wolf_heading_state(0.016)
		assert(movement._wolf_heading_turn_active(), "A real turn must still activate")
		movement._update_automatic_wolf_gallop(0.016)
		assert(not movement._gallop_active())
		movement._update_active_step(0.016)
		assert(movement._current_step == motion and movement.is_leg_stepping(foot), "An airborne step must finish rather than be canceled by a turn")
		command.direction = Vector3.ZERO
		movement._gallop_contacts[foot] = {"time": movement._physics_elapsed, "position": Vector3.ZERO, "normal": Vector3.UP, "duration": 0.5}
		movement._update_gallop_contacts()
		assert(movement._height_support_carries_limb_weight())
		assert(movement._gallop_support(movement._legs).weight > 0.0, "Retain height support for the unfinished flight even after input stops")
		assert(movement._gallop_diagnostics.retained_height_support)
		movement._physics_elapsed += 0.6
		movement._update_gallop_contacts()
		assert(movement._gallop_contacts.is_empty() and is_zero_approx(movement._gallop_support(movement._legs).weight))
		movement._segment_goal_yaw = deg_to_rad(15)
		assert(movement._wolf_heading_turn_active(), "Turn hysteresis must prevent threshold chatter")
		movement._segment_goal_yaw = deg_to_rad(5)
		assert(movement._wolf_heading_turn_active(), "Reading a diagnostic must not advance the settle timer")
		for body: RigidBody3D in movement.get_torso_parts():
			body.global_rotation.y = deg_to_rad(5)
			body.angular_velocity = Vector3.ZERO
		for index: int in range(40):
			movement._wolf_turn_state_frame = -1
			movement._update_wolf_heading_state(0.016)
		assert(not movement._wolf_heading_turn_active())
		assert(is_zero_approx(movement._wolf_plane_blend), "Completing a deliberate turn must start gradual plane restoration")
		movement._update_wolf_plane_constraints(0.016)
		assert(movement._wolf_plane_blend > 0.0 and movement._wolf_plane_blend < 1.0)
		actor.free()
	print("PASS: Wolf/NPC drift preserves gallop and steps, bounded yaw correction, deliberate-turn hysteresis and finite retained flight support.")
	quit()
