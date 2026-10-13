extends SceneTree

const ACTOR = preload("res://Scenes/Creatures/Characters/Generate_Snake.tscn")
var failed := false

class Command extends Node:
	var direction := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta: float) -> Vector3: return Vector3.RIGHT

func _initialize() -> void: call_deferred("run")

func check_layout(m: Node, physical: bool) -> float:
	var leader: Dictionary = m._path_leader
	var inverse: Basis = m._path_pose_basis.inverse()
	var maximum := 0.0
	for row: Dictionary in m._parts:
		if row.belly: continue
		var rest: Vector3 = row.rest.origin-leader.rest.origin
		var target: Vector3 = inverse*(Vector3(row.path_target)-Vector3(leader.path_target))
		var error := Vector2(target.x-rest.x,target.y-rest.y).length()
		if error > .0001 and not failed:
			failed = true
			push_error("Generated raised XY layout changed: part=%s expected=%s target=%s error=%f" % [row.body.name,rest,target,error])
		if not physical: continue
		var actual: Vector3 = inverse*(row.body.global_position-leader.body.global_position)
		maximum = maxf(maximum,Vector2(actual.x-rest.x,actual.y-rest.y).length())
	return maximum

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(2000,1,2000)
	ground.add_child(shape)
	ground.position.y = -.5
	level.add_child(ground)
	var actor := ACTOR.instantiate()
	actor.generate_on_ready = false
	level.add_child(actor)
	if not actor.generate_creature():
		push_error("Generate raised-layout fixture")
		quit(1)
		return
	var m := actor.get_node("SnakeMovementController3D")
	var command := Command.new()
	level.add_child(command)
	m.command_source = command
	m._direction = Vector3.RIGHT
	m._contact_count = 1
	m._update_ground_path(.5,5.0,m._update_anchor())
	check_layout(m,false)
	if failed:
		quit(1)
		return
	var backward_pairs := 0
	for index: int in range(1,m._parts.size()):
		if not m._parts[index].belly and m._parts[index].rest.origin.x < m._parts[index-1].rest.origin.x: backward_pairs += 1
	if backward_pairs < 3:
		push_error("Regression fixture must include the original backward bend")
		quit(1)
		return
	for tick: int in 180: await physics_frame
	var forward_error := 0.0
	var reverse_error := 0.0
	var wave_min := INF
	var wave_max := -INF
	for direction: Vector3 in [Vector3.RIGHT,Vector3.LEFT]:
		command.direction = direction
		for tick: int in 480:
			await physics_frame
			if not m._path_ready: continue
			var error := check_layout(m,tick >= 120)
			if direction == Vector3.RIGHT: forward_error = maxf(forward_error,error)
			else: reverse_error = maxf(reverse_error,error)
			var middle: Dictionary = m._parts[m._spacing_anchor+3]
			var offset: Vector3 = m._path_pose_basis.inverse()*(Vector3(middle.path_target)-Vector3(m._path_leader.path_target))
			wave_min = minf(wave_min,offset.z)
			wave_max = maxf(wave_max,offset.z)
	print("SNAKE_RAISED_LAYOUT backward_pairs=",backward_pairs," forward_error=",forward_error," reverse_error=",reverse_error," z_wave_range=",wave_max-wave_min)
	if forward_error > .25 or reverse_error > .25 or wave_max-wave_min < .1: failed = true
	if not failed: print("SNAKE_RAISED_LAYOUT_VALIDATION_PASSED")
	actor.free()
	command.free()
	level.free()
	quit(1 if failed else 0)
