extends SceneTree

const MOVEMENT = preload("res://Scripts/Creatures/LegStepMovementControllerBase3D.gd")
class Command extends Node:
	var direction := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func is_fast_movement_requested() -> bool: return false

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	for scene: String in ["Generate_Wolf", "Generate_Wolf_NPC"]:
		var actor = load("res://Scenes/Creatures/Characters/" + scene + ".tscn").instantiate()
		actor.generate_on_ready = false
		root.add_child(actor)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		var movement = actor.get_node("GeneratedLegStepMovementController3D")
		var data = movement.slow_gait_data.duplicate()
		movement.slow_gait_data = data
		movement.fast_gait_data = data
		movement.input_enabled = true
		movement.recovery_control_active = false
		var command := Command.new()
		actor.add_child(command)
		movement.command_source = command
		movement._startup_pending = false
		movement._walk_start_pending.clear()
		for body in actor.get_node("GeneratedParts").get_children():
			if body is RigidBody3D: body.freeze = true
		await physics_frame
		var feet: Array = movement.get_leg_parts()
		for foot: RigidBody3D in feet: foot.freeze = false
		var urgent: RigidBody3D = feet[2]
		urgent.global_position.y -= movement._get_foot_world_position(urgent).y
		movement._begin_ground_probe_frame()
		var bounds: Dictionary = movement._wolf_stride_bounds(urgent, Vector3.RIGHT)
		urgent.global_position.x = bounds.center.x - float(bounds.radius) * 0.98
		movement._begin_ground_probe_frame()
		for i in 2:
			var motion := MOVEMENT.StepMotion.new()
			motion.leg = feet[i]
			motion.state = movement.StepState.MOVING
			movement._active_steps.append(motion)
		assert(not movement._can_start_step_with_support(urgent),"Normal two-foot budget must be full")
		movement._update_automatic_wolf_gallop(0.016)
		assert(movement._gallop_active())
		assert(movement._wolf_gallop_reason == "traction_or_extension_relief")
		assert(movement.get_maximum_stepping_feet() == 4)
		assert(movement._gallop_intensity() >= data.traction_gallop_intensity)
		assert(movement._can_start_step_with_support(urgent))
		var demand: Dictionary = movement._get_extension_step_demand(urgent, Vector3.RIGHT)
		assert(demand.requested and demand.reason == "wolf_support_relief")
		var third := MOVEMENT.StepMotion.new()
		third.leg = feet[3]
		third.state = movement.StepState.MOVING
		movement._active_steps.append(third)
		assert(movement._can_start_step_with_support(urgent),"Last planted urgent foot must be allowed to launch using its real contact lease")
		# A lost or expired ground lease must never admit an all-air launch.
		movement._gallop_contacts.clear()
		movement._gallop_pin_release_until = -1.0
		assert(not movement._can_start_step_with_support(urgent))
		urgent.global_position.x = bounds.center.x
		movement._wolf_traction.clear()
		movement._wolf_profiles_frame = -1
		movement._update_automatic_wolf_gallop(0.4)
		assert(movement._gallop_active())
		command.direction = Vector3.ZERO
		movement._update_automatic_wolf_gallop(0.016)
		assert(not movement._gallop_active() and is_zero_approx(movement._wolf_relief_remaining))
		command.direction = Vector3.RIGHT
		data.traction_gallop_enabled = false
		movement._wolf_traction[urgent] = {"confirmed": true}
		movement._update_automatic_wolf_gallop(0.016)
		assert(is_zero_approx(movement._wolf_relief_remaining))
		data.traction_gallop_enabled = true
		movement._update_automatic_wolf_gallop(0.016)
		assert(movement._wolf_relief_remaining > 0.0,"Confirmed traction must trigger relief even away from the rear boundary")
		movement._action_feet[urgent] = true
		movement._update_automatic_wolf_gallop(0.016)
		assert(not movement._gallop_active(),"An attack action must keep its support reservation")
		actor.free()
	print("PASS: Wolf/NPC urgent support relief, full stepping capacity, last-support admission, lease expiry, bounded flight intensity, hold and disable/reset.")
	quit()
