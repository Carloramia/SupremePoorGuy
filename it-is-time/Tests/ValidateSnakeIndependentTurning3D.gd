extends SceneTree

const ROUTE = preload("res://Scripts/Creatures/SnakeGroundPath.gd")
class Commands extends Node:
	var direction := Vector3.RIGHT
	var facing := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta: float) -> Vector3: return facing

var failed := false
var checks := 0
func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failed = true; print("SNAKE_INDEPENDENT_TURN_FAILED ",message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var route := ROUTE.new()
	route.reset(Vector3.ZERO,Vector3.RIGHT,30.0,8.0,1.0,0.1)
	route.ensure(0.0,20.0,Vector3.RIGHT)
	var geometry := route.points.duplicate(true)
	route.mark_turn(1.0,Vector3.LEFT)
	check(route.facing_at(0.99)==Vector3.RIGHT and route.facing_at(1.01)==Vector3.LEFT,"Turn markers change heading only after arrival")
	check(route.points==geometry,"A heading marker must never redraw the S route")
	route.mark_turn(1.0,Vector3.RIGHT)
	check(route.facing_at(1.01)==Vector3.RIGHT,"Replace an unvisited command at the same marker")
	check(route.turn_markers.size()==1,"Cancelling an unvisited turn removes its marker")
	for index: int in 40:
		var distance := float(index)*10.0
		route.mark_turn(distance,Vector3.RIGHT if index%2==0 else Vector3.LEFT)
		route.ensure(distance,20.0,Vector3.RIGHT)
	check(route.turn_markers.size()<10,"Facing markers share the route's bounded history")
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2000,1,2000)
	collision.shape = box
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	for scene: String in ["Generate_Snake","Generate_Snake_NPC"]:
		var actor: Node3D = load("res://Scenes/Creatures/Characters/"+scene+".tscn").instantiate()
		actor.generate_on_ready = false
		actor.get_node("SnakeGenerator").overall_scale = 1.0
		level.add_child(actor)
		check(actor.generate_creature(),scene+" generation")
		var ai := actor.get_node_or_null("NPCStateMachine3D")
		if ai!=null: ai.set_physics_process(false)
		var movement := actor.get_node("SnakeMovementController3D")
		var command := Commands.new()
		actor.add_child(command)
		movement.command_source = command
		for tick: int in 360: await physics_frame
		check(movement._path_ready,scene+" must build a ground path")
		movement.set_physics_process(false)
		for body: RigidBody3D in actor._get_physical_body_parts(): body.freeze = true
		var progress: float = movement._path_progress
		var visited: Array = movement._ground_path.points.filter(func(p: Dictionary): return float(p.s)<=progress).duplicate(true)
		command.direction = Vector3.ZERO
		command.facing = Vector3.LEFT
		for tick: int in 180: movement._tick(1.0/60.0)
		check(movement._path_ready and movement._uses_ground_path(),scene+" turning retains path ownership")
		check(movement._ground_path.points.filter(func(p: Dictionary): return float(p.s)<=progress)==visited,scene+" retains exact visited geometry")
		check(movement._raised_heading.dot(Vector3.LEFT)>.99,scene+" raised body turns independently")
		check(movement._ground_path.turn_markers.size()>=2,scene+" must leave a marker on the route")
		for row: Dictionary in movement._belly:
			check(Vector3(row.turn_goal).dot(Vector3.RIGHT)>.99 and absf(float(row.turn_rate))<0.0001,scene+" unvisited belly must not receive raised turning")
		var marker: Dictionary = movement._ground_path.turn_markers[-1]
		var front: Dictionary = movement._belly[-1]
		front.path_distance = float(marker.s)+0.01
		front.turn_distance = front.path_distance
		var target: Vector3 = movement._ground_path.sample(front.turn_distance).position
		target.y = front.body.global_position.y
		front.body.global_position = target
		movement._update_path_turning(1.0/60.0,Vector3.LEFT)
		check(Vector3(front.turn_goal).dot(Vector3.LEFT)>.99,scene+" arrived front belly consumes marker")
		check(Vector3(movement._belly[0].turn_goal).dot(Vector3.RIGHT)>.99,scene+" tail before marker keeps old facing")
		for row: Dictionary in movement._belly:
			row.path_distance = float(marker.s)+0.01
			row.turn_distance = row.path_distance
			var position: Vector3 = movement._ground_path.sample(row.turn_distance).position
			position.y = row.body.global_position.y
			row.body.global_position = position
		for tick: int in 300: movement._update_path_turning(1.0/60.0,Vector3.LEFT)
		for row: Dictionary in movement._belly: check(Vector3(row.turn_heading).dot(Vector3.LEFT)>.98,scene+" all arrived pieces eventually turn")
		var debug: Dictionary = movement.get_ground_path_debug_snapshot()
		check(not debug.turns.is_empty(),scene+" debug overlay exposes turn markers")
		var display := preload("res://Scripts/Debug/SnakePathDisplay3D.gd").new()
		var drawn := display._build_mesh(debug,actor.get_world_3d().direct_space_state)
		check(drawn.get_surface_count()==1,scene+" path overlay builds")
		var purple := 0
		for color: Color in drawn.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
			if color.r>0.8 and color.g<0.3 and color.b>0.8: purple += 1
		check(purple>0,scene+" path overlay draws purple facing arrows")
		display.free()
		actor.free()
		await process_frame
	# Run the real rigid bodies through a moving turn, not only target calculations.
	var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_Snake.tscn").instantiate()
	actor.generate_on_ready = false
	actor.get_node("SnakeGenerator").overall_scale = 1.0
	level.add_child(actor)
	check(actor.generate_creature(),"Physical fixture generation")
	var movement := actor.get_node("SnakeMovementController3D")
	var command := Commands.new()
	actor.add_child(command)
	movement.command_source = command
	for tick: int in 360: await physics_frame
	var progress: float = movement._path_progress
	command.facing = Vector3.LEFT
	var best_alignment := -1.0
	var recovery_frames := 0
	for tick: int in 720:
		await physics_frame
		var head: Dictionary = movement._parts[-1]
		var heading: Vector3 = (head.body.global_basis*Basis(head.rest.basis).inverse()).x.slide(Vector3.UP).normalized()
		best_alignment = maxf(best_alignment,heading.dot(Vector3.LEFT))
		if movement.is_connection_recovering(): recovery_frames += 1
		if tick%180==179: print("SNAKE_PHYSICAL_TURN tick=",tick," head=",heading," progress=",movement._path_progress," recovery=",movement._connection_diagnostics)
	check(best_alignment>.85,"Physical raised head must reach the new facing")
	check(movement._path_progress>progress+5.0,"Turning retains forward route travel")
	check(recovery_frames<120,"Turning must not repeatedly destroy connection structure")
	for body: RigidBody3D in actor._get_physical_body_parts(): check(body.global_position.is_finite() and not body.is_broken,"Physical parts remain finite and intact")
	print("SNAKE_PHYSICAL_TURN_RESULT alignment=",best_alignment," progress=",movement._path_progress-progress," recovery_frames=",recovery_frames)
	level.free()
	await process_frame
	print("SNAKE_INDEPENDENT_TURNING_","FAILED" if failed else "PASSED"," checks=",checks)
	quit(1 if failed else 0)
