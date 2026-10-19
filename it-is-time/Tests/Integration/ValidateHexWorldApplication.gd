extends SceneTree
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
var failed := false
var count := 0

func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("HEX_APPLICATION_TIMEOUT"); quit(1))
	call_deferred("run")

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless" or "--capture" not in OS.get_cmdline_user_args(): return
	for frame: int in 5: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(image!=null and image.save_png("res://Reports/HexMapIntegration_20261019/"+label+".png")==OK,"capture "+label)
func check(ok: bool, message: String) -> void:
	count+=1
	print("HEX_APPLICATION ",ok," ",message)
	if not ok: failed=true; push_error(message)

func wait_phase(app: Node, phase: String) -> bool:
	for frame: int in 600:
		if app.phase==phase: return true
		await process_frame
	return false

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	root.size=Vector2i(1280,720)
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.save_path="res://Tests/.runtime/integration/hex_app_"+str(Time.get_ticks_usec())+".json"
	app.display_settings_path=app.save_path+".display.cfg"
	root.add_child(app)
	app.ui.animate_panels=false
	app.start_new_game()
	check(await wait_phase(app,"world"),"new game enters world")
	if app.delivery_map==null: quit(1); return
	var map: Control=app.delivery_map
	check(app.session.delivery_version()=="20261019" and map.runtime.hex!=null,"new game selects native hex navigation")
	app.story_controller._process(0.3)
	check(not app.ui.modal_stack.is_empty() and app.ui.modal_stack.back().kind=="story","new-game opening precedes tutorial guide")
	var opening: String = app.session.STORIES.OPENING
	for step: int in 8:
		app.story_controller._choose(opening,"next",int(app.session.STORIES.entry(app.session.data,opening).revision))
	app.story_controller._choose(opening,"confirm",int(app.session.STORIES.entry(app.session.data,opening).revision))
	check(not app.ui.modal_stack.is_empty() and app.ui.modal_stack.back().kind=="tasks","tutorial guide opens after opening credential commits")
	app.ui._close_all()
	await process_frame
	await capture("world_spawn")
	check(map.input_enabled and not map.runtime.busy,"closing guide permits travel")
	var graph: RefCounted=map.runtime.hex
	var coordinate: Vector2i=graph.axial(map.runtime.player())
	var destination := Vector2.ZERO
	for direction: Vector2i in graph.DIRECTIONS:
		if graph.can_pass(coordinate+direction): destination=graph.centre(coordinate+direction); break
	var minutes: float=app.session.data.world_time.total_minutes
	var start: Vector2=map.runtime.player()
	check(map.request_move(destination),"real map accepts a nearby hex route")
	map.set_process(false)
	for tick: int in 200:
		if map.path.is_empty(): break
		map._process(0.05)
	check(map.runtime.player().distance_to(destination)<1 and map.runtime.player().distance_to(start)>50,"travel follows the route")
	check(float(app.session.data.world_time.total_minutes)>minutes,"travel advances existing game clock")
	var checkpoint: Vector2=map.runtime.player()
	var checkpoint_time: float=app.session.data.world_time.total_minutes
	var save_path: String=app.session.save_path
	graph.sync(map.runtime.data,0)
	for direction: Vector2i in graph.DIRECTIONS:
		var next: Vector2i=graph.axial(checkpoint)+direction
		if not graph.can_pass(next): continue
		map.runtime.move_to(checkpoint.move_toward(graph.centre(next),10))
		app.session.advance_world_travel(10)
		break
	app.session.save_path=save_path+"/blocked.json"
	check(not map.save_progress() and map.runtime.player()==checkpoint and is_equal_approx(float(app.session.data.world_time.total_minutes),checkpoint_time),"failed save rolls hex position and clock back together")
	app.session.save_path=save_path
	app.ui._close_all()
	app.ui.status.text="点击地点后前往，抵达后交互。"
	var position: Array=map.runtime.data.player.duplicate()
	var graph_count: int=graph.nav.get_point_count()
	map.fit_map()
	await process_frame
	if DisplayServer.get_name()!="headless":
		CATALOG.world().fog.enabled=false
		map.draw_fog=false
		map.present("world","",[])
		map._refresh_objects()
		await capture("world_overview")
		CATALOG.world().fog.enabled=true
		map.draw_fog=true
		map.present("world","",[])
	check(map.world_scene.get_node("Objects").get_child_count()==CATALOG.world().objects.size(),"all source map objects are present")
	check(graph_count==10877 and map.nav.region.size==Vector2i.ZERO,"rectangular navigation is not allocated")
	var record := FACTORY.template("wolf")
	record.id="hex_party_wolf"
	record.position="team"
	record.traits=[]
	app.session.data.monsters.append(record)
	check(app.session.save(),"real party saves without changing map backend")
	map.sync_party()
	var camp := CATALOG.location("layout_wolf_den_002")
	map.runtime.data.player=camp.position.duplicate()
	map.runtime._visible_origin=Vector2.INF
	map.runtime._record(map.runtime.player(),map.runtime.player())
	check(map.begin_battle(camp.id,"clear"),"available camp submits real battle request")
	check(await wait_phase(app,"deployment"),"new map deploys through the existing BattleHost")
	if app.battle==null or app.phase!="deployment":
		app.queue_free(); await process_frame; quit(1); return
	check(app.battle.actors.size()==6,"source roster produces five enemies and one party member")
	check(app.battle.delivery_adapter.layout.id=="battle_wolf_savanna_site_2","battle ID resolves to the new scene")
	check(app.battle.actors[0].get_combat_anchor().global_position.x<0 and app.battle.actors[1].get_combat_anchor().global_position.x>0,"friendly left, enemy right remains intact")
	await capture("battle_deployment")
	app.start_battle()
	check(app.phase=="battle","deployment starts actual combat")
	for tick: int in 8: await physics_frame
	app.battle.finish("retreat")
	check(await wait_phase(app,"settlement"),"real battle result commits settlement")
	app.return_to_world()
	check(await wait_phase(app,"world"),"settlement returns to the new world")
	check(app.session.data.battle.is_empty() and app.session.data.battle_results.size()==1,"receipt is committed once")
	check(map.runtime.data.player==camp.position,"return preserves the originating map position")
	check(map.save_progress(),"returned exploration saves")
	var saved_path: String=app.session.save_path
	app.return_to_main_menu()
	check(app.phase=="main","return to menu is available")
	app.queue_free()
	await process_frame
	await process_frame
	var loaded := preload("res://Scripts/Application/GameSession.gd").new()
	loaded.save_path=saved_path
	check(loaded.load_save() and loaded.delivery_version()=="20261019","reopening the saved game keeps its map version")
	check(loaded.data.worlds.frontier_layout.player==camp.position,"reopening keeps position and progress")
	print("HEX_WORLD_APPLICATION_","FAILED" if failed else "PASSED"," checks=",count," travel_start=",position)
	quit(1 if failed else 0)
