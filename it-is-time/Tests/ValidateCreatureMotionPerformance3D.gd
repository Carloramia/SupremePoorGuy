extends SceneTree

class Commands extends Node:
	var direction := Vector3.ZERO
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta: float) -> Vector3: return Vector3.RIGHT
	func is_jump_requested() -> bool: return false
	func is_fast_movement_requested() -> bool: return false

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000, 1, 1000)
	collision.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(collision)
	root.add_child(floor_body)
	var actors: Array[Node3D] = []
	var controllers: Array[Node] = []
	for name: String in ["Generate_Wolf_NPC", "Generate_StumpBeast_NPC", "Generate_HornedBeast_NPC", "Generate_Creature_NPC"]:
		for copy: int in 2:
			var actor := load("res://Scenes/Creatures/Characters/" + name + ".tscn").instantiate() as Node3D
			actor.generate_on_ready = false
			actor.get_node("NPCStateMachine3D").enabled = false
			actor.position.z = actors.size() * 40.0
			root.add_child(actor)
			actor.get_node(actor.generator_path)._random.seed = 43
			assert(actor.generate_creature())
			var movement: Node = actor.get_node("GeneratedLegStepMovementController3D")
			var commands := Commands.new()
			actor.add_child(commands)
			movement.command_source = commands
			movement.input_enabled = true
			movement.set_performance_tracking_enabled(true)
			actors.append(actor)
			controllers.append(movement)
	for tick: int in 180: await physics_frame
	for movement: Node in controllers: movement.command_source.direction = Vector3.RIGHT
	for tick: int in 180: await physics_frame
	for movement: Node in controllers: movement.consume_performance_stats()
	var started := Time.get_ticks_usec()
	for tick: int in 180: await physics_frame
	var elapsed := float(Time.get_ticks_usec() - started) / 180000.0
	var movement_ms := 0.0
	var rows: Array[Dictionary] = []
	for movement: Node in controllers:
		var stats: Dictionary = movement.consume_performance_stats()
		if stats.physics_frames < 175:
			push_error("Controller stopped updating: " + str(movement.get_parent().name))
			quit(1)
			return
		var average: float = float(stats.total_usec) / stats.physics_frames / 1000.0
		movement_ms += average
		rows.append({"species": movement.get_parent().name, "movement_ms": average})
	for actor: Node3D in actors:
		for body: RigidBody3D in actor._get_physical_body_parts(): assert(body.global_transform.is_finite() and body.linear_velocity.is_finite())
	print("MOTION_PERFORMANCE_RESULT ", JSON.stringify({"actors": actors.size(), "wall_ms_per_physics_frame": elapsed, "movement_ms": movement_ms, "controllers": rows, "ai": "disabled; measures locomotion and physics only"}))
	for actor: Node3D in actors: actor.queue_free()
	await process_frame
	print("CREATURE_MOTION_PERFORMANCE_PASSED")
	quit()
