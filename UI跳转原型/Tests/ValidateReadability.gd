extends SceneTree
const Scene = preload("res://Scenes/GameDemo.tscn")
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("READABILITY: " + label)
func settle() -> void:
	for i in 10:
		await process_frame
func capture(label: String) -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://Tests/.runtime") + "/" + label + ".png")
func run() -> void:
	var app = Scene.instantiate()
	app.animate_panels = false
	app.state.save_path = ProjectSettings.globalize_path("res://Tests/.runtime") + "/readability_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app._show("world")
	check(root.min_size == Vector2i(1120,680), "minimum window")
	check(root.content_scale_mode == Window.CONTENT_SCALE_MODE_DISABLED, "native text sizes")
	for resolution in [Vector2i(1120,680),Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)]:
		root.size = resolution
		app._open_ritual()
		await settle()
		var page = app.modal_box.get_child(0)
		var center = page.get_node("Columns/C2")
		check(center.get_global_rect().encloses(page.get_node("Columns/C2/Center/PageHeader").get_global_rect()), "title inside C2 " + str(resolution))
		for name in ["Commit","Undo","Cancel","Freehand","Save","Clear","Summon"]:
			var button = page.get_node("%" + name)
			check(center.get_global_rect().encloses(button.get_global_rect()), "fixed accessible operation " + name)
			check(button.get_theme_font_size("font_size") >= 16, "readable operation " + name)
		if resolution.y >= 720:
			var scroll = page.get_node("%RightScroll")
			check(scroll.get_v_scroll_bar().max_value <= scroll.size.y + 1, "seven reference rows need no scrolling")
		await capture("ritual_%dx%d" % [resolution.x,resolution.y])
		app._close_all()
	for cell in Rules.RUNES[0].cells:
		app.rules.extend(cell)
	app.rules.commit()
	app._open_ritual()
	app._summon()
	app.view.skip_eruption()
	await settle()
	app._close_all()
	app.state.store_pending()
	for resolution in [Vector2i(1120,680),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		app._warehouse("")
		await settle()
		var page = app.warehouse_page
		var cards = page.get_node("%Cards").get_children()
		check(cards.filter(func(card): return card.button_pressed).size() == 1, "one persistent selected note")
		app._select_monster(cards[-1].get_meta("monster_id"))
		check(cards[-1].button_pressed and cards[-1].text.begins_with("▸ "), "selected note has non-color marker")
		var d1 = page.get_node("D1").get_global_rect()
		check(d1.encloses(page.get_node("D1/Content/PageHeader").get_global_rect()), "title inside D1")
		check(d1.encloses(page.get_node("%DetailCommands").get_global_rect()), "detail operations fixed on page")
		var d2 = page.get_node("D2").get_global_rect()
		var tabs = page.get_node("TagsRail/Tabs").get_global_rect()
		check(tabs.position.x < d2.end.x and tabs.end.x > d2.end.x, "external tabs overlap paper edge")
		check(app.get_global_rect().encloses(tabs), "tabs inside window")
		var detail_scroll = page.get_node("D1/Content/DetailScroll")
		check(detail_scroll.get_v_scroll_bar().max_value <= detail_scroll.size.y + 1, "short monster detail needs no scroll")
		await capture("warehouse_%dx%d" % [resolution.x,resolution.y])
		app._close_all()
	app._settings()
	await settle()
	var selector = app.modal_box.find_child("WindowSize",true,false)
	check(selector != null and selector.item_count == 5, "five selectable sizes")
	app.queue_free()
	await process_frame
	print("READABILITY_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
