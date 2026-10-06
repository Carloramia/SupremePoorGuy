extends SceneTree
## Render smoke test; run with a real display backend, not --headless.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(15).timeout.connect(func():
		push_error("Capture timed out")
		quit(1))
	var demo = load("res://demo/demo.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/00_shell.png")
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
	assert(ui.get_state() == "reward_ready" and demo.mana == 320)
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/02b_reward_preview.png")
	ui.advance()
	assert(ui.get_state() == "end" and demo.mana == 420)
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/03_reward.png")
	var title_position: Vector2 = ui._title.global_position
	ui._scroll.scroll_vertical = 0
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/04_history.png")
	if not ui._title.global_position.is_equal_approx(title_position):
		push_error("Scrolling moved header: %s -> %s" % [title_position, ui._title.global_position])
		quit(1)
		return
	ui._info.open_details("事件说明", [{"title": "对话记录", "text": "继续逐句追加到同一个窗口；可以滚动回看，不需要退出当前事件。"}, {"title": "选择与奖励", "text": "双列比较，选择后追加玩家选择；奖励预览、领取和返回互相分离。"}])
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/05_glossary.png")
	ui._info.close()
	ui._info.show_hint(Rect2(1040, 90, 100, 36), "变硬硬", [{"title": "符文效果", "text": "召唤怪物更容易具备甲壳特征。"}])
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/06_hint.png")
	ui._info.close()
	demo.queue_free()
	await process_frame
	print("RENDER_CAPTURE_PASSED")
	quit(0)
