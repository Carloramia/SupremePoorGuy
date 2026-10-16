extends SceneTree
const Scene = preload("res://Scenes/GameDemo.tscn")
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
const Card = preload("res://Scenes/UI/Components/MonsterCard.tscn")
const Workshop = preload("res://Scenes/UI/UIWorkshop.tscn")
var checks := 0
var failures := 0
var app
var capture := false

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("LAYOUT FAILED: "+description)

func settle() -> void:
	for i in 8:
		await process_frame

func same_rect(a: Rect2, b: Rect2) -> bool:
	return a.position.distance_to(b.position) < 1.0 and a.size.distance_to(b.size) < 1.0

func save_capture(file: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://Tests/screenshots/"+file+".png")

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	root.content_scale_size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	app = Scene.instantiate()
	app.animate_panels = false
	app.state.save_path = "user://native_layout_test_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app._show("world")
	await settle()
	check(app.view.summon_book.visible,"book is on map")
	app.view.summon_book.pressed.emit()
	await settle()
	check(app.modal_stack.size()==1 and app.overlay.visible,"book opens native ritual")
	check(app.board.scene_file_path.ends_with("RuneBoard.tscn"),"board is scene component")
	check(app.modal_box.get_child(0).scene_file_path.ends_with("RitualPanel.tscn"),"ritual uses editable scene")
	for resolution in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(1024,768),Vector2i(1920,800)]:
		root.size = resolution
		await settle()
		var before: Rect2 = app.board.get_global_rect()
		check(absf(before.size.x-before.size.y)<1.0,"square board "+str(resolution))
		check(before.size.x>=300,"readable design board "+str(resolution))
		check(app.modal_scroll.get_global_rect().encloses(before),"board inside modal "+str(resolution))
		check(app.overlay.get_global_rect().encloses(app.summon_button.get_global_rect()),"summon button inside overlay "+str(resolution))
		for cell in Rules.cells():
			check(app.board.cell_at(app.board.point(cell))==cell,"draw hit target matches visual "+str(resolution))
		# UI stress fixture only: not a legal saved or summoned layout.
		for i in 30:
			app.rules.placed.append({"uid":"stress_"+str(i),"runeId":"ember","cells":Rules.RUNES[0].cells.duplicate(true),"enabled":true})
		app._refresh_ritual()
		await settle()
		check(same_rect(before,app.board.get_global_rect()),"long active list does not resize board "+str(resolution))
		check(app.ritual_left_scroll.get_v_scroll_bar().max_value > app.ritual_left_scroll.size.y,"active list scrolls")
		app._notice("用于验证长反馈文字不会挤压法阵。".repeat(14))
		await settle()
		check(same_rect(before,app.board.get_global_rect()),"feedback does not resize board")
		app.ritual_left_scroll.scroll_vertical = 300
		app.ritual_right_scroll.scroll_vertical = 180
		await settle()
		check(same_rect(before,app.board.get_global_rect()),"independent scroll does not move board")
		app.rules.placed.clear()
		app._refresh_ritual()
		app._notice("")
		await settle()
		check(same_rect(before,app.board.get_global_rect()),"deleting list preserves board")
		app._term("布局回归","说明内容")
		app._close_modal()
		await settle()
		check(same_rect(before,app.board.get_global_rect()),"nested popup returns to same layout")
		await save_capture("layout_%dx%d" % [resolution.x,resolution.y])
		print("LAYOUT_RESOLUTION ",resolution," logical=",app.size," board=",app.board.size)
	# Scene-authored visual overrides survive runtime binding and refresh.
	var panel: Control = app.modal_box.get_child(0)
	app.ritual_left_scroll.custom_minimum_size.x = 240
	app._refresh_ritual()
	await settle()
	check(app.ritual_left_scroll.size.x>=240,"designer width is not overwritten")
	check(panel.scene_file_path.ends_with("RitualPanel.tscn"),"panel remains instanced scene")
	app._close_all()
	app._show("world")
	app.view.summon_book.custom_minimum_size = Vector2(120,110)
	app.view.configure("world","forest",[])
	await settle()
	check(app.view.summon_book.custom_minimum_size==Vector2(120,110),"book sizing not overwritten")
	var card := Card.instantiate()
	card.get_node("%Portrait").custom_minimum_size = Vector2(200,160)
	root.add_child(card)
	await settle()
	check(card.get_node("%Portrait").custom_minimum_size==Vector2(200,160),"portrait scene size preserved")
	var pixels := Image.create(4,4,false,Image.FORMAT_RGBA8)
	pixels.fill(Color.CORAL)
	card.get_node("%Portrait").get_node("Artwork").texture = ImageTexture.create_from_image(pixels)
	await settle()
	check(card.get_node("%Portrait").get_node("Artwork").texture!=null,"art texture slot accepts replacement")
	card.queue_free()
	var workshop := Workshop.instantiate()
	root.size = Vector2i(1280,720)
	root.add_child(workshop)
	await settle()
	check(workshop.get_node("Scroll/Margin/Examples/PaperPanel/Ritual")!=null,"component workshop loads")
	await save_capture("10_component_workshop")
	workshop.queue_free()
	app.queue_free()
	await settle()
	print("UI_LAYOUT_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
