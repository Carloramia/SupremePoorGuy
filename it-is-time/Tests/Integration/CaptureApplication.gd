extends SceneTree
var app: Node
var output := "D:/GameJamWorkspace/Reports/FreeCursor_2026-10-15"
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	for frame: int in 4: await process_frame
	RenderingServer.force_draw()
	var picture := root.get_texture().get_image()
	assert(picture!=null and not picture.is_empty(),"Real rendering is required")
	assert(picture.save_png(output+"/"+name+".png")==OK)
	print("APPLICATION_CAPTURE ",name," size=",picture.get_size())
func run() -> void:
	root.size = Vector2i(1280,720)
	app = preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.use_delivery_map = false
	app.save_path = "res://Tests/.runtime/integration/capture_"+str(Time.get_ticks_usec())+".json"
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	await capture("01_main")
	app.start_new_game()
	for tick: int in 600:
		if app.phase=="world": break
		await physics_frame
	assert(app.phase=="world")
	preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(app.session)
	await capture("02_world")
	app.ui._warehouse("team")
	await capture("03_warehouse")
	app.ui._close_all()
	app.ui._open_ritual()
	await capture("04_ritual")
	assert(app.ui.rules.import_layout({"version":3,"stage":1,"placed":[{"uid":"test","runeId":"health","cells":[[-1,0],[0,0],[1,0]],"enabled":true}],"placedRelics":[]}))
	app.ui._perform_summon()
	app.ui.view.skip_eruption()
	for frame: int in 30: await process_frame
	assert(not app.session.data.pending.is_empty())
	await capture("04b_summon_results")
	app.ui._detail(app.session.data.pending[0])
	await capture("04c_summon_detail")
	app.ui._close_all()
	assert(app.session.store_pending())
	app.ui._warehouse()
	await capture("04d_populated_warehouse")
	app.ui._close_all()
	var location: WorldMapLocation = app.world_map.get_location(&"bandits")
	location.state.discovered = true
	app.world_map.player.global_position = location.interaction_point()
	app.world_map.interaction.begin(location)
	await capture("05_location")
	app.world_map.interaction.request_battle()
	for tick: int in 600:
		if app.phase=="deployment": app.start_battle()
		if app.phase=="battle": break
		await physics_frame
	assert(app.phase=="battle")
	for tick: int in 120: await physics_frame
	await capture("06_battle")
	assert(app.get_active_controller()==null and app.battle.cursor.free_cursor_mode)
	await capture("07_free_cursor")
	for size: Vector2i in [Vector2i(1120,680),Vector2i(1920,1080)]:
		root.size = size
		app.ui._warehouse()
		await capture("warehouse_"+str(size.x))
		app.ui._close_all()
	app.request_retreat()
	await capture("09_settlement")
	app.return_to_world()
	for tick: int in 60: await process_frame
	await capture("10_return")
	app.queue_free()
	await process_frame
	await process_frame
	print("APPLICATION_CAPTURE_PASSED")
	quit()
