extends SceneTree
const Scene = preload("res://Scenes/GameDemo.tscn")
const ThemeAsset = preload("res://Assets/UI/PaperRelief/PaperReliefTheme.tres")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SCROLL PRESENTATION: "+label)
func settle() -> void:
	for i in 12:
		await process_frame
func snapshot(app) -> Array:
	var result: Array = []
	for path in ["Columns/C1","Columns/C2","Columns/C3"]:
		result.append(app.ritual_page.get_node(path).get_global_rect())
	result.append(app.board.get_global_rect())
	result.append(app.summon_button.get_global_rect())
	result.append(app.board.point([1,0]))
	return result
func inspect_bars(node: Node) -> void:
	if node is ScrollBar:
		check(node.get_theme_stylebox("grabber")==ThemeAsset.get_stylebox("grabber",node.get_class()),"shared copper grip "+node.get_class())
		check(node.get_theme_stylebox("grabber").get_minimum_size()==node.get_theme_stylebox("grabber_highlight").get_minimum_size() and node.get_theme_stylebox("grabber").get_minimum_size()==node.get_theme_stylebox("grabber_pressed").get_minimum_size(),"hover and drag keep identical geometry")
	for child in node.get_children():
		inspect_bars(child)
func capture(name: String) -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://Tests/screenshots/"+name+".png")
func run() -> void:
	var app = Scene.instantiate()
	app.animate_panels = false
	app.state.save_path = ProjectSettings.globalize_path("res://Tests/.runtime")+"/scroll_presentation_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app._show("world")
	app._open_ritual()
	for resolution in [Vector2i(1120,680),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		await settle()
		app.ritual_page.get_node("%RuneTab").pressed.emit()
		await settle()
		var before := snapshot(app)
		var content_width: float = app.ritual_page.get_node("%References").size.x
		var bar = app.ritual_right_scroll.get_v_scroll_bar()
		check(bar.visible == (bar.max_value > bar.page),"thumb follows actual overflow")
		app.ritual_page.get_node("%RelicTab").pressed.emit()
		await settle()
		check(not bar.visible,"short reference list hides thumb")
		check(snapshot(app)==before,"reference switch never shifts leaves, array or actions "+str(resolution))
		check(app.ritual_page.get_node("%Relics").size.x==content_width,"short and long reference widths match")
		for i in 3:
			app.ritual_page.get_node("%RuneTab").pressed.emit()
			await settle()
			check(snapshot(app)==before,"repeated long page remains stable")
			app.ritual_page.get_node("%RelicTab").pressed.emit()
			await settle()
			check(snapshot(app)==before,"repeated short page remains stable")
		if resolution.x==1280:
			await capture("scroll_relic_stable")
			app.ritual_page.get_node("%RuneTab").pressed.emit()
			await settle()
			await capture("scroll_runes_stable")
			bar.value = bar.max_value
			await settle()
			check(app.ritual_right_scroll.scroll_vertical>0,"native scrolling still changes list offset")
			var last = app.ritual_page.get_node("%References").get_child(13)
			check(app.ritual_right_scroll.get_global_rect().intersects(last.get_global_rect()),"last rune remains reachable")
	inspect_bars(app)
	app._close_all()
	app._open_event("traveler")
	await settle()
	var text = app.modal_box.get_child(0).get_node("%Description")
	var width: float = text.size.x
	text.text = "长事件滚动测试，保持文字区宽度与标题位置稳定。\n".repeat(50)
	await settle()
	check(text.size.x==width,"event narrative width stays stable when overflowing")
	inspect_bars(app)
	await capture("scroll_event_copper")
	app._close_all()
	app._tasks()
	await settle()
	var tasks = app.modal_box.get_child(0)
	var list_width: float = tasks.get_node("%PendingRows").size.x
	var many: Array = []
	for i in 20:
		many.append({"title":"待办%d" % i,"description":"滚动条样式和留白验证","done":false})
	tasks.present_tasks(many)
	await settle()
	check(tasks.get_node("%PendingRows").size.x==list_width,"tasks keep width when overflowing")
	inspect_bars(app)
	var horizontal := HScrollBar.new()
	horizontal.theme = ThemeAsset
	root.add_child(horizontal)
	inspect_bars(horizontal)
	horizontal.queue_free()
	app.queue_free()
	await process_frame
	print("SCROLL_PRESENTATION_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
