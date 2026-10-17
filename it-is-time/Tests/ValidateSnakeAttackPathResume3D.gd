extends "res://Tests/ValidateSnakeAttacks3D.gd"

class Command extends Node:
	var direction := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta: float) -> Vector3: return Vector3.RIGHT

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000,1,2000)
	collider.shape = box
	floor_body.add_child(collider)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	var npc := NPC.instantiate()
	enable_attacks(npc)
	npc.generate_on_ready = false
	npc.get_node("SnakeGenerator").overall_scale = 1.0
	npc.position.y = 0.01
	level.add_child(npc)
	check(npc.generate_creature(),"Generate moving Snake bite fixture")
	npc.get_node("NPCStateMachine3D").set_physics_process(false)
	var movement := npc.get_node("SnakeMovementController3D")
	var attack := npc.get_node("SnakeBiteAttackController3D")
	var command := Command.new()
	level.add_child(command)
	movement.command_source = command
	for tick: int in 360:
		command.direction = Vector3(1,0,0.25).normalized() if tick>=180 and tick<270 else Vector3.RIGHT
		await physics_frame
	movement.command_source = null
	for tick: int in 120: await physics_frame
	check(movement._path_ready and movement._path_progress>1.0,"Walking builds a nonzero route before attack")
	var history: Array = movement._ground_path.points.duplicate(true)
	var corners: Array = movement._ground_path.corners.duplicate(true)
	var progress: float = movement._path_progress
	var distances: Array = movement._parts.map(func(row: Dictionary): return row.path_distance)
	check(not corners.is_empty(),"The retained route includes turns, not just a straight initialization")
	var victim := CHARACTER.instantiate()
	victim.faction_id = 2
	var target := PART.instantiate() as PhysicalBodyPart3D
	target.tags.assign([PhysicalBodyPart3D.BodyPartTag.Torso,PhysicalBodyPart3D.BodyPartTag.Head])
	target.max_hp = 10000000.0
	target.armor = 0.0
	target.left_distance = 1.5
	target.right_distance = 1.5
	target.top_distance = 2.0
	target.bottom_distance = 2.0
	target.collision_thickness = 2.0
	target.freeze = true
	victim.add_child(target)
	level.add_child(victim)
	target.global_position = attack.head.to_global(attack._mouth_offset())+Vector3.RIGHT*6.0
	await physics_frame
	# Capture after the final ordinary movement tick, immediately before attack takeover.
	history = movement._ground_path.points.duplicate(true)
	corners = movement._ground_path.corners.duplicate(true)
	progress = movement._path_progress
	distances = movement._parts.map(func(row: Dictionary): return row.path_distance)
	check(attack.try_start_npc_attack(attack.ACTION,target,0.0),"Start a real bite from an established S route")
	var retained := true
	var phases: Dictionary = {}
	var positions: Dictionary = {}
	var maximum_ground_drift := 0.0
	for tick: int in 1200:
		await physics_frame
		phases[attack._phase] = true
		if not attack.is_npc_attack_active(): break
		retained = retained and movement._path_ready and not movement._uses_ground_path() and is_equal_approx(movement._path_progress,progress)
		retained = retained and movement._parts.map(func(row: Dictionary): return row.path_distance)==distances
		if movement.is_attack_support_locked():
			for row: Dictionary in movement._belly:
				if not positions.has(row.body): positions[row.body] = row.body.global_position
				maximum_ground_drift = maxf(maximum_ground_drift,Vector3(row.body.global_position-positions[row.body]).slide(Vector3.UP).length())
	check(retained and movement._ground_path.points==history and movement._ground_path.corners==corners,"Bite freezes the exact route, follower distances and progress")
	check(phases.has(&"lunging") and phases.has(&"rejoining") and attack._last_reason==&"completed","Bite and recovery still complete")
	check(target.current_hp<target.max_hp,"Retaining a route does not block real bite damage")
	check(maximum_ground_drift<0.15,"Attack retains the grounded S footprint")
	for tick: int in 240:
		await physics_frame
		if not movement.is_connection_recovering(): break
	check(movement._path_ready and not movement.is_connection_recovering(),"Post-attack connections resume the route")
	check(movement._ground_path.points==history and movement._ground_path.corners==corners and is_equal_approx(movement._path_progress,progress),"Post-attack recovery preserves old history and nonzero progress")
	var minimum_progress: float = movement._path_progress
	movement.command_source = command
	command.direction = Vector3.RIGHT
	for tick: int in 180:
		await physics_frame
		minimum_progress = minf(minimum_progress,movement._path_progress)
	check(minimum_progress>=progress-0.01 and movement._path_progress>progress+1.0,"Travel continues forward along the same route without resetting progress")
	print("SNAKE_ATTACK_PATH_RESULT start_progress=",progress," minimum_progress=",minimum_progress," final_progress=",movement._path_progress," ground_drift=",maximum_ground_drift," phases=",phases," reason=",attack._last_reason)
	level.free()
	await process_frame
	if not failed: print("SNAKE_ATTACK_PATH_RESUME_PASSED")
	quit(1 if failed else 0)
