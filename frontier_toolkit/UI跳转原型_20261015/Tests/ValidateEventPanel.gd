extends SceneTree
const Scene = preload("res://Scenes/GameDemo.tscn")
var checks := 0
var failures := 0
var selected := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("EVENT PANEL: "+label)
func settle() -> void:
	for i in 10:
		await process_frame
func capture(name: String) -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://Tests/screenshots/"+name+".png")
func run() -> void:
	var app = Scene.instantiate()
	app.animate_panels = false
	app.state.save_path = ProjectSettings.globalize_path("res://Tests/.runtime") + "/event_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app._show("world")
	app._open_event("traveler")
	for resolution in [Vector2i(1120,680),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		await settle()
		var page = app.modal_box.get_child(0)
		var commands = page.get_node("%Commands")
		var scroll = page.get_node("%DescriptionScroll")
		check(app.modal_stack.back().kind == "event", "explicit event layout type")
		check(page.size.x > resolution.x*0.7 and page.size.y > resolution.y*0.5, "expanded reading area "+str(resolution))
		check(page.get_node("%Description").get_theme_font_size("font_size") == 20, "stable readable event font")
		check(scroll.get_v_scroll_bar().max_value <= scroll.size.y+1, "short event needs no scroll")
		check(app.modal_scroll.get_global_rect().encloses(commands.get_global_rect()), "choice fully visible")
		if resolution.x == 1280:
			await capture("11_event")
	var page = app.modal_box.get_child(0)
	page.get_node("%Description").text = "长事件测试：旅行者详细讲述沿途的见闻，纸页上仍清楚记录着每一次选择。\n\n".repeat(60)
	for i in 3:
		app._btn(page.get_node("%Commands"),"测试选项 %d" % i,func(): selected+=1)
	root.size = Vector2i(1280,720)
	await settle()
	var scroll = page.get_node("%DescriptionScroll")
	check(scroll.get_v_scroll_bar().max_value > scroll.size.y, "long event scrolls only narrative")
	check(app.modal_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "outer content does not scroll choices away")
	var before: Rect2 = page.get_node("%Commands").get_global_rect()
	scroll.scroll_vertical = 300
	await settle()
	check(page.get_node("%Commands").get_global_rect() == before, "choices fixed while reading")
	for button in page.get_node("%Commands").get_children():
		check(button.size.y >= 42 and app.modal_scroll.get_global_rect().encloses(button.get_global_rect()), "all four choices remain reachable")
	page.get_node("%Commands").get_child(1).pressed.emit()
	check(selected == 1, "choice callback once")
	await capture("12_event_long")
	var money: int = app.state.data.magic
	page.get_node("%Commands").get_child(0).pressed.emit()
	check(app.state.data.magic == money+20 and app.modal_stack.is_empty(), "original claim still saves and closes")
	app._open_event("traveler")
	await settle()
	check(app.modal_stack.is_empty() and not app.view.get_node("Traveler").visible, "finished event cannot reopen and marker disappears")
	check(app.state.data.magic == money+20, "reopening cannot duplicate reward")
	app.queue_free()
	await process_frame
	print("EVENT_PANEL_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
