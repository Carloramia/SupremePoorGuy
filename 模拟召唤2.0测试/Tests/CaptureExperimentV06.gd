extends SceneTree
const Scene = preload("res://Scenes/GameDemo.tscn")
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
var app

func _initialize() -> void:
	call_deferred("_run")

func capture(name: String) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "res://Tests/screenshots/"+"v06_"+name+".png"
	check_image(root.get_texture().get_image(),path)

func check_image(img: Image, path: String) -> void:
	if img == null or img.is_empty() or img.save_png(path) != OK:
		push_error("Screenshot failed: "+path)
		quit(1)

func _run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	app = Scene.instantiate()
	app.animate_panels = false
	app.state.save_path = "user://native_v06_capture_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app._show("world")
	app._open_ritual()
	await capture("array7")
	for c in Rules.definition("health").cells:
		app.rules.extend(c)
	app.rules.commit()
	app._refresh_ritual()
	await capture("basic")
	app._summon()
	app.view.skip_eruption()
	await capture("results5")
	app._close_modal()
	app._open_ritual()
	app._upgrade_stage()
	app._load_example(2)
	app.modal_box.get_child(0).get_node("%Commands").get_child(0).pressed.emit()
	await capture("mutation")
	app._upgrade_stage()
	app._load_example(4)
	app.modal_box.get_child(0).get_node("%Commands").get_child(0).pressed.emit()
	await capture("ultra")
	app._load_example(7)
	app.modal_box.get_child(0).get_node("%Commands").get_child(0).pressed.emit()
	app._summon()
	app.view.skip_eruption()
	app._close_modal()
	app._open_ritual()
	app._load_example(6)
	app.modal_box.get_child(0).get_node("%Commands").get_child(0).pressed.emit()
	app._summon()
	app.view.skip_eruption()
	app._close_modal()
	app._warehouse("")
	await capture("warehouse")
	app.warehouse_page.get_node("%RightScroll").scroll_vertical = 380
	await capture("warehouse_details")
	app.warehouse_page.get_node("%RightScroll").scroll_vertical = 0
	root.size = Vector2i(1024,768)
	await capture("warehouse_1024")
	app._close_all()
	app.queue_free()
	for i in 8:
		await process_frame
	print("V06_SCREENSHOTS_SAVED")
	quit()
