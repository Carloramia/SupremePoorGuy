extends SceneTree

var events := {"enter": 0, "exit": 0}

func _initialize() -> void:
	call_deferred("_validate")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func _validate() -> void:
	var console := root.get_node("RuntimeConsole")
	var character := load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate() as Node3D
	for node: Node in character.find_children("*", "PhysicalBodyPart3D", true, false):
		(node as PhysicalBodyPart3D).freeze = true
	root.add_child(character)
	var torso := character.get_node("Torso") as PhysicalBodyPart3D
	var leg := character.get_node("Leg_R") as PhysicalBodyPart3D
	if not _check(not torso.is_collision_logging_enabled(), "Collision logging must default to off"):
		return
	console.execute_command("trackcollision")
	if not _check(torso.is_collision_logging_enabled() and leg in torso.get_collision_exceptions(), "Tracking must enable without changing collision exceptions"):
		return
	var host := Node3D.new()
	host.name = "CollisionLogTest"
	root.add_child(host)
	var scene := load("res://Scenes/Creatures/Bodyparts/_PhysicalSampleBodyParts.tscn") as PackedScene
	var a := scene.instantiate() as PhysicalBodyPart3D
	a.name = "ContactA"
	a.position = Vector3(0.0, 100.0, 0.0)
	a.freeze = true
	host.add_child(a)
	var b := scene.instantiate() as PhysicalBodyPart3D
	b.name = "ContactB"
	b.position = Vector3(2.0, 100.0, 0.0)
	b.gravity_scale = 0.0
	host.add_child(b)
	b.body_entered.connect(func(body: Node3D):
		if body == a:
			events.enter += 1
	)
	b.body_exited.connect(func(body: Node3D):
		if body == a:
			events.exit += 1
	)
	if not _check(a.is_collision_logging_enabled() and b.is_collision_logging_enabled(), "Newly spawned parts must inherit active tracking"):
		return
	for frame: int in range(30):
		await physics_frame
	if not _check(events.enter > 0, "Actual BodyPart collision must emit an enter event"):
		return
	b.global_position = Vector3(20.0, 100.0, 0.0)
	b.linear_velocity = Vector3.ZERO
	for frame: int in range(10):
		await physics_frame
	if not _check(events.exit > 0, "Separating BodyParts must emit an exit event"):
		return
	console.execute_command("trackcollision")
	if not _check(not a.is_collision_logging_enabled() and not torso.is_collision_logging_enabled(), "Turning tracking off must disable all parts"):
		return
	print("COLLISION_LOGGING_DISABLED_CHECK_BEGIN")
	a._on_collision_body_entered(b)
	a._on_collision_body_exited(b)
	a.emit_collision_snapshot()
	print("COLLISION_LOGGING_DISABLED_CHECK_END")
	print("PART_COLLISION_LOGGING_VALIDATION_PASSED")
	host.queue_free()
	character.queue_free()
	quit()
