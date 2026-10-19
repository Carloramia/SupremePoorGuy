extends SceneTree
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
var app: Node
var output := "D:/GameJamWorkspace/Reports/DeliveryIntegration_2026-10-16"
func _initialize() -> void: call_deferred("run")
func capture(title: String) -> void:
	for frame: int in 6: await process_frame
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(picture!=null and not picture.is_empty())
	assert(picture.save_png(output+"/"+title+".png")==OK)
	print("DELIVERY_CAPTURE ",title," size=",picture.get_size())
func run() -> void:
	root.size = Vector2i(1280,720)
	app = preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.use_hex_map_for_new_games = false # This fixture verifies the retained 20261015 map.
	app.save_path = "res://Tests/.runtime/integration/delivery_capture_"+str(Time.get_ticks_usec())+".json"
	app.display_settings_path = "res://Tests/.runtime/integration/delivery_capture_display.cfg"
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	app.start_new_game()
	while app.phase!="world": await process_frame
	await capture("delivery_spawn_1280")
	app.ui._close_all()
	app.delivery_map.draw_fog = false
	app.delivery_map.present("world","",[])
	app.delivery_map.fit_map()
	await capture("delivery_world_overview")
	for resolution: Vector2i in [Vector2i(1120,680),Vector2i(1920,1080)]:
		root.size = resolution
		app.ui._settings()
		await capture("delivery_settings_"+str(resolution.x))
		app.ui._close_all()
	root.size = Vector2i(1280,720)
	preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(app.session)
	var camp := {}
	for object: Dictionary in CATALOG.world().objects:
		if object.type=="camp" and "wolf" in str(object.get("enemy_config_id","")): camp=object; break
	app.delivery_map.runtime.data.player = camp.position.duplicate()
	app.delivery_map.runtime.data.discovered.append(camp.id)
	assert(app.delivery_map.begin_battle(camp.id,"clear"))
	for tick: int in 900:
		if app.phase=="deployment": app.start_battle()
		if app.phase=="battle": break
		await physics_frame
	assert(app.phase=="battle")
	app.set_pause_reason(&"manual",true)
	app.refresh_input_gate()
	await capture("delivery_battle_paused")
	app.battle.finish("victory")
	await capture("delivery_settlement")
	await app.return_to_world()
	await capture("delivery_return")
	app.queue_free()
	await process_frame
	await process_frame
	print("DELIVERY_CAPTURE_PASSED")
	quit()
