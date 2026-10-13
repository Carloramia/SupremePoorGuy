extends SceneTree

class RouteSource extends Node3D:
	var ready_route := true
	var excluded: Array[RID] = []
	func get_ground_path_debug_snapshot() -> Dictionary:
		if not ready_route: return {}
		return {"points":PackedVector3Array([Vector3(-3,0,0),Vector3(-1,0,1),Vector3(1,0,-1),Vector3(3,0,0)]),
			"distances":PackedFloat32Array([-2,-1,1,2]),"progress":0.0,"excludes":excluded,
			"ray_top":8.0,"ray_bottom":-5.0,"line_width":0.1}

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var console := root.get_node("RuntimeConsole")
	assert(console._snake_path_display == null)
	assert(console.execute_command("help").contains("showsnakepath"))
	assert(console.execute_command("showsnakepath invalid").begins_with("Usage:"))
	assert(console._snake_path_display == null)
	var level := Node3D.new()
	root.add_child(level)
	var ground := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	collider.shape.size = Vector3(20,1,20)
	ground.add_child(collider)
	ground.position.y = 1.25
	level.add_child(ground)
	var actor := Node3D.new()
	actor.name = "SnakeDisplayFixture"
	level.add_child(actor)
	var source := RouteSource.new()
	actor.add_child(source)
	source.add_to_group(&"snake_movement_controllers")
	var own_body := RigidBody3D.new()
	own_body.freeze = true
	var own_shape := CollisionShape3D.new()
	own_shape.shape = BoxShape3D.new()
	own_shape.shape.size = Vector3(10,1,10)
	own_body.add_child(own_shape)
	own_body.position.y = 4.0
	actor.add_child(own_body)
	source.excluded.append(own_body.get_rid())
	await physics_frame
	await physics_frame
	assert(console.execute_command("showsnakepath on SnakeDisplayFixture").contains("enabled"))
	var display = console._snake_path_display
	display.set_physics_process(false)
	display._physics_process(.2)
	assert(display._meshes.size() == 1)
	var mesh: ImmediateMesh = display._meshes[source.get_instance_id()].mesh
	assert(mesh.get_surface_count() == 1)
	var arrays := mesh.surface_get_arrays(0)
	assert(arrays[Mesh.ARRAY_VERTEX].size() == 18)
	for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]: assert(absf(vertex.y-1.785) < .001,"Route is projected to terrain, not to an owned body or Y=0")
	# Mesh vertex colors are stored as normalized bytes.
	assert(absf(arrays[Mesh.ARRAY_COLOR][0].g-display.HISTORY_COLOR.g) < .005)
	assert(absf(arrays[Mesh.ARRAY_COLOR][-1].g-display.PREVIEW_COLOR.g) < .005)
	assert(display._material.no_depth_test)
	console.execute_command("showsnakepath on MissingSnake")
	display._physics_process(.2)
	assert(display._meshes.is_empty())
	console.execute_command("showsnakepath on %s" % actor.get_instance_id())
	display._physics_process(.2)
	assert(display._meshes.size() == 1)
	source.ready_route = false
	display._physics_process(.2)
	assert(display._meshes.is_empty(),"Cancelled routes remove stale debug lines")
	source.ready_route = true
	console.execute_command("showsnakepath on %s" % actor.get_path())
	display._physics_process(.2)
	assert(display._meshes.size() == 1)
	level.free()
	display._physics_process(.2)
	assert(display._meshes.is_empty(),"Scene replacement removes all old actor meshes")
	console.execute_command("showsnakepath off")
	assert(not display.is_physics_processing() and display.get_child_count() == 0)
	assert(console.execute_command("showsnakepath").contains("enabled"))
	console.execute_command("showsnakepath off")
	var test_level: Node3D = load("res://Scenes/Levels/TestLevel.tscn").instantiate()
	root.add_child(test_level)
	current_scene = test_level
	console.execute_command("showsnakepath on GenerateSnakeNPC")
	display.set_physics_process(true)
	for tick: int in 240: await physics_frame
	assert(display._meshes.size() == 1,"The real TestLevel Snake is discovered automatically")
	var controller := test_level.get_node("GenerateSnakeNPC/SnakeMovementController3D")
	var real_mesh: ImmediateMesh = display._meshes[controller.get_instance_id()].mesh
	assert(real_mesh.get_surface_count() == 1 and real_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() > 0,"Real Snake route projects to TestLevel terrain")
	print("SNAKE_LEVEL_PATH_DISPLAY amplitude=",controller._path_amplitude," surfaces=",real_mesh.get_surface_count())
	console.execute_command("showsnakepath off")
	test_level.free()
	print("SNAKE_PATH_DISPLAY_VALIDATION_PASSED")
	quit()
