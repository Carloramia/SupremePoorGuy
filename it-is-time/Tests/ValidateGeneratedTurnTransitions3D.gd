extends SceneTree
## Check progress and integrity; log heading/tilt separately from convergence goals.

class Commands extends Node:
	var direction := Vector3.ZERO
	var facing := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta: float) -> Vector3: return facing
	func is_jump_requested() -> bool: return false
	func is_fast_movement_requested() -> bool: return false

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var scene := "Generate_Wolf"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="): scene = argument.trim_prefix("--scene=")
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1000, 1, 1000)
	collision.shape = shape
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var actor: Node = load("res://Scenes/Creatures/Characters/" + scene + ".tscn").instantiate()
	actor.generate_on_ready = false
	var ai := actor.get_node_or_null("NPCStateMachine3D")
	if ai != null: ai.enabled = false
	root.add_child(actor)
	var generator: Node = actor.get_node(actor.generator_path)
	generator._random.seed = 43
	assert(actor.generate_creature())
	var movement: Node = actor.get_node("GeneratedLegStepMovementController3D")
	var commands := Commands.new()
	actor.add_child(commands)
	movement.command_source = commands
	movement.input_enabled = true
	for frame: int in 180: await physics_frame
	var rows: Array[Dictionary] = []
	for phase: Dictionary in [
		{"name": "left_turn_walk", "facing": Vector3.LEFT, "direction": Vector3.LEFT, "frames": 720},
		{"name": "right_turn_walk", "facing": Vector3.RIGHT, "direction": Vector3.RIGHT, "frames": 720},
		{"name": "diagonal_walk", "facing": Vector3.RIGHT, "direction": Vector3(1, 0, 1).normalized(), "frames": 360}
	]:
		commands.direction = phase.direction
		commands.facing = phase.facing
		var start: Vector3 = movement._torso.global_position
		var peak_tilt := 0.0
		for frame: int in int(phase.frames):
			await physics_frame
			for body: RigidBody3D in actor._get_physical_body_parts():
				assert(body.global_position.is_finite() and body.linear_velocity.is_finite() and body.angular_velocity.is_finite())
				assert(not body.is_broken, "Motion alone must not break a part")
			for body: RigidBody3D in movement.get_torso_parts():
				peak_tilt = maxf(peak_tilt, rad_to_deg(body.global_basis.y.angle_to(Vector3.UP)))
		var displacement: Vector3 = movement._torso.global_position - start
		assert(displacement.dot(commands.direction) > 0.5, "Turning must retain progress in the commanded direction")
		rows.append({"phase": phase.name, "along_displacement": displacement.dot(commands.direction), "heading_error": rad_to_deg(movement._get_maximum_heading_error(PI if commands.facing.x < 0.0 else 0.0)), "peak_tilt": peak_tilt})
	print("TRANSITION_RESULT ", scene, " ", JSON.stringify(rows))
	actor.queue_free()
	await process_frame
	print("GENERATED_TURN_TRANSITIONS_PASSED")
	quit()
