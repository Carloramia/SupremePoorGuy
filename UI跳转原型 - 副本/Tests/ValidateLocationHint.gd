extends SceneTree
const Scene = preload("res://Scenes/GameDemo.tscn")
var checks := 0
var failures := 0
var requests: Array = []
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("LOCATION HINT: "+label)
func settle() -> void:
	for i in 10:
		await process_frame
func run() -> void:
	var app = Scene.instantiate()
	app.animate_panels = false
	app.state.save_path = ProjectSettings.globalize_path("res://Tests/.runtime") + "/hint_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app.scene_requested.connect(func(kind,id): requests.append([kind,id]))
	app._show("world")
	await settle()
	var card = app.view.get_node("LocationHint")
	check(not card.visible, "hidden until hover")
	for resolution in [Vector2i(1120,680),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		await settle()
		for name in ["Grassland","Forest","Desert"]:
			var marker = app.view.get_node(name)
			marker.mouse_entered.emit()
			await settle()
			check(card.visible and app.modal_stack.is_empty(), "hover opens local card only "+name)
			check(app.view.get_global_rect().encloses(card.get_global_rect()), "hint fits map "+str(resolution)+name)
			check(card.size.x <= 300 and card.size.y <= 180, "compact hint")
			check(card.mouse_filter==Control.MOUSE_FILTER_IGNORE and card.get_node("%Summary").mouse_filter==Control.MOUSE_FILTER_IGNORE, "card cannot steal hover or click")
			check(card.get_node("%Summary").text.contains("【") and card.get_node("%Summary").text.contains("待侦察"), "tags and honest unknown data")
			marker.mouse_exited.emit()
			check(not card.visible, "exit immediately hides hint")
	app.view.set_location_previews({"desert":{"tags":"【沙漠】【沙】","types":"兽形 / 蛇形","abundance":"少量"}})
	var desert = app.view.get_node("Desert")
	desert.mouse_entered.emit()
	await settle()
	check(card.get_node("%Summary").text.contains("少量") and card.get_node("%Summary").text.contains("蛇形"), "supplied scouting summary renders")
	if "--capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(1280,720)
		await settle()
		desert.mouse_entered.emit()
		await settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://Tests/screenshots/13_location_hint.png")
	desert.pressed.emit()
	check(app.route=="battle" and app.modal_stack.is_empty(), "click directly enters battle without confirmation popup")
	check(requests==[["battle","desert"]], "one scene request with original ID")
	check(not card.visible, "battle clears hover")
	app._show("world")
	app.view.get_node("Grassland").mouse_entered.emit()
	await settle()
	app._open_ritual()
	check(not card.visible, "opening another page dismisses hint")
	app._close_all()
	app.view.get_node("Traveler").pressed.emit()
	check(app.modal_stack.back().kind=="event", "event marker retains event window")
	app.queue_free()
	await process_frame
	print("LOCATION_HINT_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
