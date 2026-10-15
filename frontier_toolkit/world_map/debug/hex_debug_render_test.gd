extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 800)
	var world: WorldMapController = load("res://world_map/demo/WorldMapDemo.tscn").instantiate()
	world.auto_load = false
	root.add_child(world)
	await world.initialized
	var toggle: CheckButton
	for node in world.ui.find_children("*", "CheckButton", true, false):
		if node.text == "Hex debug":
			toggle = node
	var before := await capture("off")
	click(toggle)
	var enabled := await capture("on")
	var changed := changed_map_pixels(before, enabled)
	var signal_worked := toggle.button_pressed and world.terrain.show_hex_debug
	click(toggle)
	var disabled := await capture("off_again")
	var restored := changed_map_pixels(before, disabled)
	print("HEX DEBUG RENDER: signal=", signal_worked, " changed_map_pixels=", changed, " restored_difference=", restored)
	var passed := signal_worked and changed > 1000 and restored == 0 and not world.player.has_target
	world.queue_free()
	await process_frame
	quit(0 if passed else 1)

func click(button: CheckButton) -> void:
	var event := InputEventMouseButton.new()
	event.position = button.get_global_rect().get_center()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)

func capture(label: String) -> Image:
	for _frame in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	screenshot.save_png("res://.tools/hex_debug_%s.png" % label)
	return screenshot

func changed_map_pixels(first: Image, second: Image) -> int:
	var count := 0
	# Exclude HUD and toolbar, count only the visible map center.
	for y in range(220, 700):
		for x in range(400, 1000):
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				count += 1
	return count
