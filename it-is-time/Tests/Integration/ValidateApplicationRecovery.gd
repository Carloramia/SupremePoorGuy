extends SceneTree
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failed=true; push_error(message)
func wait_phase(app: Node, wanted: String) -> bool:
	for frame: int in 600:
		if wanted=="battle" and app.phase=="deployment": app.start_battle()
		if app.phase==wanted: return true
		await physics_frame
	return false
func create_app(path: String) -> Node:
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.use_delivery_map = false
	app.save_path = path
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	return app
func run() -> void:
	var path := "res://Tests/.runtime/integration/recovery_"+str(Time.get_ticks_usec())+".json"
	var app := create_app(path)
	app.start_new_game()
	check(await wait_phase(app,"world"),"Initial world")
	app.ui._close_all()
	preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(app.session)
	var town: WorldMapLocation = app.world_map.get_location(&"town")
	app.world_map.player.global_position = town.interaction_point()
	check(app.world_map.interaction.begin(town),"Open settlement visit")
	app.world_map.interaction.request_scenario()
	await process_frame
	check(app.phase=="scenario" and app.scenario.initialized,"Embedded 2.5D exploration opens with controller references")
	check(app.scenario.get_world_3d()==app.battle_viewport.find_world_3d(),"Exploration uses its isolated World3D")
	app.ui._navigation_requested("world")
	await process_frame
	check(app.phase=="world" and app.scenario==null and not app.world_map.paused,"Navigation returns from exploration without orphaned scene")
	var location: WorldMapLocation = app.world_map.get_location(&"bandits")
	location.state.discovered = true
	app.world_map.player.global_position = location.interaction_point()
	app.world_map.interaction.begin(location)
	app.world_map.interaction.request_battle()
	check(await wait_phase(app,"battle"),"Initial real battle")
	var id: String = app.session.data.battle.battle_id
	app.queue_free()
	await process_frame
	await process_frame
	app = create_app(path)
	app.ui._show("world")
	check(await wait_phase(app,"battle"),"Restart restores committed pending battle")
	check(app.session.data.battle.battle_id==id and app.battle.actors[0].get_meta(&"creature_instance_id")=="test_human","Pending restart preserves request and creature IDs")
	app.battle.finish("victory")
	await process_frame
	var magic: float = app.session.data.magic
	app.queue_free()
	await process_frame
	await process_frame
	app = create_app(path)
	app.ui._show("world")
	check(await wait_phase(app,"settlement"),"Committed result resumes settlement without another fight")
	check(app.battle==null and app.session.data.magic==magic,"Result restart never respawns combat or pays twice")
	app.return_to_world()
	check(await wait_phase(app,"world"),"Recovered settlement can return")
	app.queue_free()
	await process_frame
	await process_frame
	print("APPLICATION_RECOVERY_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
