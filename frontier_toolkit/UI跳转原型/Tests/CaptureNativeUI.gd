extends SceneTree
const Scene = preload("res://Scenes/GameDemo.tscn")
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
var app

func _initialize() -> void:
	call_deferred("_run")

func capture(file: String) -> void:
	while app.board_motion.busy:
		await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://Tests/screenshots/"+file+".png")

func _run() -> void:
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Tests/screenshots"))
	app = Scene.instantiate()
	app.state.save_path = "user://native_capture_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app._show("world")
	await capture("01_world")
	app._open_ritual()
	await capture("02_ritual")
	for c in Rules.RUNES[0].cells:
		app.rules.extend(c)
	app.rules.commit()
	app._refresh_ritual()
	await capture("03_engraved")
	app._summon()
	# Only this isolated visual capture fixes forms to showcase all three illustration slots.
	for i in 3:
		app.state.data.monsters[i].form = ["兽形", "人形", "蛇形"][i]
		app.state.data.monsters[i].name = "纸雕示意·"+app.state.data.monsters[i].form+" %02d" % (i+1)
	app.view.elapsed = 1.2
	await capture("04_eruption")
	app.view.skip_eruption()
	await capture("05_results")
	app._detail(app.state.data.monsters[0].id)
	await capture("06_detail")
	app._term("攻击","普通攻击的基础强度。当前为测试数值。")
	await capture("07_glossary")
	app._close_all()
	app.state.store_pending()
	app.state.move_monster(app.state.data.monsters[0].id,"team")
	app._warehouse("")
	await capture("10_warehouse")
	app._close_all()
	app._show("battle")
	await capture("08_battle")
	app._skip_battle()
	await capture("09_settlement")
	print("NATIVE_UI_SCREENSHOTS_SAVED")
	quit()
