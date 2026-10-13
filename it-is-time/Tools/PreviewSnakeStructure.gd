extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var actor := (load("res://Scenes/Creatures/Characters/Generate_Snake.tscn") as PackedScene).instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	# The saved editor preview is the object under inspection, rather than a separate renderer/layout.
	var bounds := AABB()
	var mouth_bounds := AABB()
	var initialized := false
	var mouth_initialized := false
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if not part is RigidBody3D: continue
		part.freeze = true
		var local_bounds := preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd").bounds(part)
		var world_bounds: AABB = part.global_transform * local_bounds
		bounds = bounds.merge(world_bounds) if initialized else world_bounds
		initialized = true
		if part.name in [&"Head", &"Jaw"]:
			mouth_bounds = mouth_bounds.merge(world_bounds) if mouth_initialized else world_bounds
			mouth_initialized = true
	root.size = Vector2i(1500, 900)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0.23, 0.26, 0.30)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.9
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, -20, 0)
	light.light_energy = 0.6
	root.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	root.add_child(camera)
	camera.current = true
	var views := {"structure_preview": bounds}
	var directory := "D:/GameJamWorkspace/Reports/SnakeGenerator_2026-10-12/"
	if "--head-jaw" in OS.get_cmdline_user_args():
		directory = "D:/GameJamWorkspace/Reports/SnakeHeadJaw_2026-10-12/"
		views["head_jaw_preview"] = mouth_bounds
	for key: String in views:
		var view: AABB = views[key]
		camera.size = maxf(view.size.y, view.size.x / (1500.0 / 900.0)) * 1.2
		camera.position = view.get_center() + Vector3(0, 0, 40)
		camera.look_at(view.get_center(), Vector3.UP)
		for index: int in 4: await process_frame
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image()
		assert(result != null and not result.is_empty())
		var output := directory + key + ".png"
		assert(result.save_png(output) == OK)
		print("PASS: saved actual Godot Snake structure render: ", output)
	actor.free()
	quit()
