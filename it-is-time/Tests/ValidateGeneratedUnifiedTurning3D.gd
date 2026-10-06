extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
class Commands extends Node:
	var direction := Vector3.ZERO
	var facing := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta: float) -> Vector3: return facing
	func is_jump_requested() -> bool: return false
	func is_fast_requested() -> bool: return false
var failed := false
func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300,1,300)
	collision.shape = box
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var count := 4
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--feet="): count = argument.trim_prefix("--feet=").to_int()
	for frequency: float in [4.0,16.0]:
		var actor = CHARACTER.instantiate()
		actor.generate_on_ready = false
		actor.planar_constraints_enabled = false
		root.add_child(actor)
		var generator = actor.get_node("CreatureGenerator")
		generator.rear_leg_count = count-2
		generator.foreleg_count = 2
		generator.body_length = 4.0
		generator.unsymmetrie = 0.0
		generator.neck_number = 0
		generator._random.seed = 43
		check(actor.generate_creature(), "Generation failed")
		var movement = actor.get_node("GeneratedLegStepMovementController3D")
		var manual = movement.slow_gait_data.duplicate()
		manual.automatic_motion = false
		movement.slow_gait_data = manual
		var walking_speed: float = movement.get_expected_horizontal_speed()
		movement._layout_turn_owned = true
		check(is_equal_approx(walking_speed,movement.get_expected_horizontal_speed()),"Turning cadence must not change manual walking speed")
		movement._layout_turn_owned = false
		var data = movement.slow_gait_data.duplicate()
		data.automatic_motion = true
		data.target_speed = 5.0
		data.turning_speed_degrees = 60.0
		data.maximum_step_frequency = frequency
		movement.slow_gait_data = data
		var commands := Commands.new()
		actor.add_child(commands)
		movement.command_source = commands
		for frame: int in range(180): await physics_frame
		var previous: float = movement._get_physical_heading_yaw()
		var total := 0.0
		var max_steps := 0
		var elapsed := 0.0
		var complete := false
		commands.facing = Vector3.LEFT
		for frame: int in range(720):
			await physics_frame
			var yaw: float = movement._get_physical_heading_yaw()
			total += wrapf(yaw-previous,-PI,PI)
			previous = yaw
			max_steps = maxi(max_steps,movement._active_steps.size())
			elapsed += 1.0/60.0
			if frame % 120 == 119: print("TURN_PROGRESS cap=",frequency," elapsed=",elapsed," yaw=",rad_to_deg(total)," steps=",movement._active_steps.size()," drive=",movement._turn_drive_diagnostics," status=",movement._layout_turn_status)
			check(movement._active_steps.size() <= movement.get_maximum_stepping_feet(),"Exceeded support budget")
			if absf(wrapf(PI-yaw,-PI,PI)) < deg_to_rad(6.0):
				complete = true
				break
		print("UNIFIED_TURN_RESULT cap=",frequency," elapsed=",elapsed," angle=",rad_to_deg(total)," mean_rate=",absf(rad_to_deg(total))/elapsed," concurrent=",max_steps," completed=",complete)
		check(complete,"Turn must reach target in 12 seconds")
		# Turning and walking must share the same budget and retain translation.
		commands.direction = Vector3.RIGHT
		commands.facing = Vector3.RIGHT
		var start: Vector3 = movement._torso.global_position
		for frame: int in range(360): await physics_frame
		print("BLENDED_RESULT cap=",frequency," displacement=",movement._torso.global_position-start," yaw=",rad_to_deg(movement._get_physical_heading_yaw())," shape_yaw_error=",rad_to_deg(movement._get_maximum_heading_error(movement._get_physical_heading_yaw())))
		check(movement._torso.global_position.x > start.x+1.0,"Walking must continue during turn")
		check(movement._get_maximum_heading_error(movement._get_physical_heading_yaw()) < deg_to_rad(30.0),"Body segments must retain a shared heading")
		for body: RigidBody3D in actor._get_physical_body_parts(): check(body.global_position.is_finite(),"Nonfinite body")
		actor.queue_free()
		await process_frame
	ground.queue_free()
	print("GENERATED_UNIFIED_TURNING_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
