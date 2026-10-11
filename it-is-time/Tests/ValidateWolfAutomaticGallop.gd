extends SceneTree

class Command:
	extends Node
	var direction := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func is_fast_movement_requested() -> bool: return false

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	collider.shape = box
	floor_body.add_child(collider)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	for scene in ["Generate_Wolf", "Generate_Wolf_NPC"]:
		var actor = load("res://Scenes/Creatures/Characters/" + scene + ".tscn").instantiate()
		actor.generate_on_ready = false
		root.add_child(actor)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		var movement = actor.get_node("GeneratedLegStepMovementController3D")
		var data = movement.slow_gait_data.duplicate()
		data.target_speed = 3.0
		data.maximum_step_frequency = 12.0
		data.gallop_enabled = false
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
		var foot: RigidBody3D = movement._chains.keys()[0]
		foot.global_position.y -= movement._get_foot_world_position(foot).y
		await physics_frame
		foot.freeze = false
		movement._begin_leg_motion(foot, foot.global_position + Vector3.RIGHT, Vector3.UP, Vector3.RIGHT)
		var motion = movement._current_step
		assert(motion.extra.has("wolf_step"))
		movement._wolf_step_times[foot] = 4.0
		movement._wolf_profiles_frame = -1
		movement._update_automatic_wolf_gallop(0.1)
		assert(not movement._gallop_active())
		assert(movement._wolf_walking_speed < data.target_speed * 0.95)
		movement._update_automatic_wolf_gallop(0.11)
		assert(movement._gallop_active())
		assert(movement._current_step == motion and motion.extra.has("wolf_step"))
		assert(not data.gallop_enabled)
		assert(is_equal_approx(movement._get_expected_horizontal_speed(), data.target_speed))
		assert(movement.get_maximum_stepping_feet() == 4)
		assert(movement._gallop_intensity() >= data.minimum_automatic_gallop_intensity)
		var diagnostics: Dictionary = movement.get_automatic_motion_diagnostics()
		assert(diagnostics.wolf_auto_gallop.active and diagnostics.speed_based_gait)
		# Keep calculating walking capacity while galloping; do not feed flight speed back.
		movement._update_automatic_wolf_gallop(0.7)
		assert(movement._gallop_active())
		movement._wolf_step_times.clear()
		movement._wolf_profiles_frame = -1
		movement._update_automatic_wolf_gallop(0.3)
		assert(movement._gallop_active())
		movement._update_automatic_wolf_gallop(0.31)
		assert(not movement._gallop_active())
		assert(movement._current_step == motion)
		command.direction = Vector3.ZERO
		movement._update_automatic_wolf_gallop(1.0)
		assert(not movement._gallop_active())
		data.automatic_gallop_enabled = false
		assert(not movement._gallop_active())
		actor.free()
	print("PASS: Wolf/NPC capacity-triggered gallop, independent walking budget, confirmation hysteresis, full flight capacity and unchanged active step/resource.")
	quit()
