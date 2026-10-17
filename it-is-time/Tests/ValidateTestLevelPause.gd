extends SceneTree
var failures: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value or failures.has(message): return
	failures[message] = true
	push_error(message)

func space(echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.unicode = 32
	event.pressed = true
	event.echo = echo
	root.push_input(event,true)
	await process_frame
	event.pressed = false
	event.echo = false
	root.push_input(event,true)
	await process_frame

func run() -> void:
	var console: Node = root.get_node("RuntimeConsole")
	console.auto_getlogs_enabled = false
	var level := preload("res://Scenes/Levels/TestLevel.tscn").instantiate()
	root.add_child(level)
	for tick: int in 12: await physics_frame
	var control: CanvasLayer = level.get_node("TestLevelPause")
	var body: RigidBody3D = level.get_node("GenerateHumanBowNPC/GeneratedParts/Torso")
	check(not paused and not control._hint.visible,"TestLevel starts running with no pause overlay")
	await space()
	check(paused and control._hint.is_visible_in_tree(),"Space pauses standalone TestLevel and displays the hint")
	var position := body.global_position
	var velocity := body.linear_velocity
	for tick: int in 8: await physics_frame
	check(body.global_position.is_equal_approx(position) and body.linear_velocity.is_equal_approx(velocity),"Pausing stops real rigid-body simulation without resetting its velocity")
	await space(true)
	check(paused,"Holding Space does not repeatedly resume the scene")
	console.set_console_open(true)
	await space()
	check(paused and console.is_console_open(),"Console remains usable during pause and typing Space does not resume")
	console.set_console_open(false)
	await space()
	check(not paused and not control._hint.visible,"A second Space resumes and hides the hint")
	for tick: int in 8: await physics_frame
	check(not body.global_position.is_equal_approx(position),"Physical motion continues after resuming")
	var field := LineEdit.new()
	root.add_child(field)
	field.grab_focus()
	await space()
	check(not paused,"Text field Space does not pause the scene")
	field.free()
	var interface := CanvasLayer.new()
	interface.add_to_group(&"ui_interface_2d")
	root.add_child(interface)
	await space()
	check(not paused,"Visible workshop-style interfaces retain their Space input")
	interface.free()
	paused = true
	await space()
	check(paused and not control._paused_by_space,"Space cannot release a pause owned elsewhere")
	paused = false
	var host := Node.new()
	root.add_child(host)
	host.add_to_group(&"application_host")
	var hosted_event := InputEventAction.new()
	hosted_event.action = &"Space"
	hosted_event.pressed = true
	control._unhandled_input(hosted_event)
	check(not paused,"TestLevel defers to the existing GameRoot pause handler when hosted")
	host.free()
	await space()
	check(paused,"The level can pause again after resuming")
	level.free()
	check(not paused,"Removing a manually paused level does not leave the tree paused")
	await process_frame
	print("TEST_LEVEL_PAUSE_PASSED" if failures.is_empty() else "TEST_LEVEL_PAUSE_FAILED "+str(failures))
	quit(0 if failures.is_empty() else 1)
