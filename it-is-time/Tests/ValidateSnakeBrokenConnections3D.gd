extends SceneTree
const ACTOR = preload("res://Scenes/Creatures/Characters/Generate_Snake_NPC.tscn")
var failed := false
var capture := preload("res://Scripts/Debug/RuntimeErrorLogCapture.gd").new()

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("SNAKE_BREAK_CHECK ",ok," ",message)
	failed = failed or not ok

func actor_fixture() -> Node3D:
	var actor := ACTOR.instantiate() as Node3D
	actor.generate_on_ready = false
	root.add_child(actor)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	for body: Node in actor.get_node("GeneratedParts").get_children():
		if body is RigidBody3D: body.freeze = true
	return actor

func exercise(movement: Node) -> void:
	movement._tick(1.0/60.0)
	movement._update_connections(1.0/60.0)
	var poses := {}
	for row: Dictionary in movement._parts: poses[row.body] = row.rest
	movement._constrain_connection_poses(poses,true)
	movement._set_path_slide_limits(true)
	movement._set_path_slide_limits(false)
	var diagnostics: Variant = movement.get_snake_motion_diagnostics(true)
	check(diagnostics is Dictionary,"Full motion diagnostics remain readable")
	var console := root.get_node("RuntimeConsole")
	console.execute_command("motiondetail full")
	check(not console._collect_motion_snapshot(movement.get_parent()).is_empty(),"Console can collect all surviving BodyParts")
	console.execute_command("motiondetail summary")
	var error := capture.take_error()
	check(error.is_empty(),"Movement/constraints/logging ignore removed joints: "+str(error))

func run() -> void:
	root.get_node("RuntimeConsole").execute_command("autogetlogs off")
	OS.add_logger(capture)
	var actor := actor_fixture()
	await process_frame; await process_frame
	var movement := actor.get_node("SnakeMovementController3D")
	var rest := {}
	for row: Dictionary in movement._parts: rest[row.body] = row.rest
	var part := actor.get_node("GeneratedParts/Torso_020") as PhysicalBodyPart3D
	part.break_part()
	for tick: int in 5: await process_frame
	check(part.is_broken and not actor.get_node("GeneratedParts/Head").is_broken,"Logged Torso_020 failure leaves Head alive")
	check(actor.get_node("GeneratedParts/Torso_001").is_broken,"Integrity check breaks the detached tail chain")
	exercise(movement)
	for row: Dictionary in movement._parts: check(row.rest==rest[row.body],"Break cleanup preserves authored rest pose")
	actor.free()
	check(capture.take_error().is_empty(),"Broken actor tears down without invalid references")
	actor = actor_fixture()
	await process_frame; await process_frame
	movement = actor.get_node("SnakeMovementController3D")
	var row: Dictionary = movement._parts[2]
	row.incoming_joint.free()
	exercise(movement)
	check(typeof(row.get("incoming_joint"))==TYPE_NIL and typeof(row.get("sway_joint"))==TYPE_NIL,"Deleted joints are removed from cached connections")
	var dangling := Generic6DOFJoint3D.new()
	for key: StringName in [&"incoming_joint",&"sway_joint",&"follow_joint"]: row[key] = dangling
	dangling.free()
	exercise(movement)
	actor.free()
	check(capture.take_error().is_empty(),"Direct joint removal tears down cleanly")
	OS.remove_logger(capture)
	print("SNAKE_BROKEN_CONNECTIONS_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
