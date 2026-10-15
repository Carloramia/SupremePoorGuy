extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 800)
	var world: WorldMapController = load("res://world_map/demo/WorldMapDemo.tscn").instantiate()
	world.auto_load = false
	root.add_child(world)
	await world.initialized
	world.player.global_position = Vector2(550, 490)
	world.fog.update_vision(world.player.global_position)
	world.camera.focus_on_player()
	for _frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()
	before.save_png("res://world_map/debug/preview_roads.png")
	var click := InputEventMouseButton.new()
	click.position = root.get_canvas_transform() * Vector2(630, 530)
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click, true)
	click.pressed = false
	root.push_input(click, true)
	var snapped := world.player.movement_target == Vector2(630, 490)
	for _frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://world_map/debug/preview_road_snap.png")
	var pixel := before.get_pixel(700, 400)
	var surface_visible := pixel.r > pixel.g and pixel.g > pixel.b
	print("ROAD RENDER: centerline_snap=", snapped, " visible_surface=", surface_visible, " speed=", world.player.effective_speed())
	world.player.cancel_movement()
	world.player.global_position = Vector2(200, 340)
	world.fog.update_vision(world.player.global_position)
	world.camera.mode = WorldMapCameraController.Mode.FREE
	world.camera.global_position = Vector2(350, 425)
	world.set_move_target(Vector2(640, 510), true)
	world.player.pause_movement("route preview")
	for _frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://world_map/debug/preview_road_bends.png")
	var bends_visible := world.player.path_line.points.has(Vector2(200, 490))
	print("ROAD BENDS RENDER: centerline_corner=", bends_visible)
	world.queue_free()
	await process_frame
	quit(0 if snapped and surface_visible and bends_visible else 1)
