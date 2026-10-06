extends SceneTree
## Render smoke test; run with a real display backend, not --headless.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var demo = load("res://demo/demo.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.start_event()
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/01_dialogue.png")
	var ui = demo.event_window
	ui.advance()
	ui.advance()
	ui.advance()
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/02_choices.png")
	ui.select_choice("take")
	ui.advance()
	ui.advance()
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/03_reward.png")
	var title_position: Vector2 = ui._title.global_position
	ui._scroll.scroll_vertical = 0
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/04_history.png")
	assert(ui._title.global_position.is_equal_approx(title_position), "Scrolling must not move the fixed header")
	print("RENDER_CAPTURE_PASSED")
	quit(0)
