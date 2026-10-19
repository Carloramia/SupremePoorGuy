extends SceneTree
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
var failed := false
var checks := 0

func _initialize() -> void:
	create_timer(30).timeout.connect(func(): push_error("HEX_STONE_TIMEOUT"); quit(1))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks+=1
	print("HEX_STONE ",ok," ",message)
	if not ok: failed=true; push_error(message)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.save_path="res://Tests/.runtime/integration/stone_"+str(Time.get_ticks_usec())+".json"
	app.display_settings_path=app.save_path+".display.cfg"
	root.add_child(app)
	app.ui.animate_panels=false
	app.start_new_game()
	for frame: int in 300:
		if app.phase=="world": break
		await process_frame
	app.story_controller._process(0.3)
	var opening: String = app.session.STORIES.OPENING
	for step: int in 8: app.story_controller._choose(opening,"next",int(app.session.STORIES.entry(app.session.data,opening).revision))
	app.story_controller._choose(opening,"confirm",int(app.session.STORIES.entry(app.session.data,opening).revision))
	app.ui._close_all()
	var map: Control=app.delivery_map
	var stone := {}
	for object: Dictionary in CATALOG.objects_in_role("obstacles"):
		map.runtime.hex.sync(map.runtime.data,1)
		if not map.runtime.hex.obstacle_neighbors(object).is_empty(): stone=object; break
	check(not stone.is_empty(),"source stone has a walkable adjacent cell")
	if stone.is_empty(): app.queue_free(); await process_frame; quit(1); return
	var point: Vector2=map.runtime.hex.centre(map.runtime.hex.obstacle_neighbors(stone)[0])
	map.runtime.data.player=[point.x,point.y]
	map.runtime.party_count=0
	var minutes: float=app.session.data.world_time.total_minutes
	await map._destroy_hex_obstacle(stone)
	check(stone.id not in map.runtime.data.destroyed and is_equal_approx(app.session.data.world_time.total_minutes,minutes),"without monsters the action charges nothing")
	var unit: Dictionary=app.session.FACTORY.template("human")
	unit.merge({"id":"stone_test","position":"warehouse","traits":[]},true)
	app.session.data.monsters.append(unit)
	check(app.session.save(),"owned warehouse creature satisfies the condition")
	map.sync_party()
	map._destroy_hex_obstacle(stone)
	check(map.runtime.busy,"break enters timed state")
	map.set_enabled(false)
	map.set_enabled(true)
	check(not map.runtime.busy,"menu cancellation releases the action")
	await create_timer(0.30).timeout
	map._destroy_hex_obstacle(stone)
	var seconds: float=sqrt(3.0)*float(CATALOG.world().hex_grid.cell_width)*0.5*3/float(CATALOG.world().travel_animation_speed)
	await create_timer(seconds-0.15).timeout
	check(map.runtime.busy and stone.id not in map.runtime.data.destroyed,"cancelled timer cannot release or finish a newer action")
	await create_timer(0.30).timeout
	var expected: float=sqrt(3.0)*float(CATALOG.world().hex_grid.cell_width)*0.5*3/float(app.session.data.world_time.travel_speed)*60
	check(stone.id in map.runtime.data.destroyed and not map.runtime.busy,"new action commits destruction")
	check(is_equal_approx(float(app.session.data.world_time.total_minutes)-minutes,expected),"exactly three walking steps of game time charged once")
	await map._destroy_hex_obstacle(stone)
	check(is_equal_approx(float(app.session.data.world_time.total_minutes)-minutes,expected),"duplicate destruction never charges again")
	var loaded := preload("res://Scripts/Application/GameSession.gd").new()
	loaded.save_path=app.save_path
	check(loaded.load_save() and stone.id in loaded.delivery_snapshot().destroyed,"destruction survives reload")
	app.queue_free()
	await process_frame
	await process_frame
	print("HEX_STONE_ACTIONS_","FAILED" if failed else "PASSED"," checks=",checks)
	quit(1 if failed else 0)
