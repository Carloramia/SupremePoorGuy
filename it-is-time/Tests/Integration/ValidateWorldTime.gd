extends SceneTree
const SESSION = preload("res://Scripts/Application/GameSession.gd")
var failed := false
var checks := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	print("WORLD_TIME_CHECK ", ok, " ", message)
	if not ok: failed = true; push_error(message)

func run() -> void:
	var session := SESSION.new()
	session.save_path = "user://world_time_math.json"
	check(session.world_time_status().hour == 8 and session.data.day == 1, "New game starts on day one at 08:00")
	var start: float = session.data.world_time.total_minutes
	check(session.advance_world_travel(600.0) and is_equal_approx(session.data.world_time.total_minutes-start,60.0), "600 units at 600 units/hour costs one game hour")
	check(session.set_world_travel_speed(1200.0), "Travel speed is a saved player attribute")
	start = session.data.world_time.total_minutes
	session.advance_world_travel(600.0)
	check(is_equal_approx(session.data.world_time.total_minutes-start,30.0), "Double speed halves the time for the same distance")
	for i in 100: session.advance_world_travel(0.01)
	check(is_equal_approx(session.data.world_time.total_minutes-start,30.05), "Small movement segments retain fractional minutes")
	for speed: float in [0.0,-1.0,INF,NAN]:
		var before := session.data.duplicate(true)
		check(not session.set_world_travel_speed(speed) and session.data == before, "Reject invalid speed without changing the save")
	for distance: float in [-1.0,INF,NAN]: check(not session.advance_world_travel(distance), "Reject invalid distance")
	session.advance_world_minutes(1445.0-session.data.world_time.total_minutes)
	check(session.world_time_status().day == 2 and session.world_time_status().hour == 0 and session.world_time_status().minute == 5 and session.data.day == 2, "Midnight rolls the clock and existing day field together")
	check(session.save(), "Clock saves")
	var restored := SESSION.new()
	restored.save_path = session.save_path
	check(restored.load_save() and restored.data.world_time == session.data.world_time, "Reload retains time and travel speed")
	var previous := session.data.duplicate(true)
	session.save_path += "/blocked.json"
	check(not session.record_task_arrival("frontier_layout","fixture") and session.data == previous, "Failed interaction save rolls back its time cost")
	check(not session.set_world_travel_speed(900.0) and session.data == previous, "Failed speed save rolls back the player attribute")
	session.save_path = "user://world_time_legacy.json"
	var legacy := session.data.duplicate(true)
	legacy.erase("world_time")
	legacy.day = 7
	var file := FileAccess.open(session.save_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy)); file.close()
	restored.save_path = session.save_path
	check(restored.load_save() and restored.data.day == 7 and restored.world_time_status().hour == 8, "Old saves gain a clock without resetting the saved day")
	check(restored.save() and not JSON.parse_string(FileAccess.get_file_as_string(restored.save_path+".bak")).has("world_time"), "First clock save retains the original file in the rotating backup")
	for bad: Variant in [null,{}, {"total_minutes":-1.0,"travel_speed":1.0}, {"total_minutes":1.0,"travel_speed":0.0}, {"total_minutes":"bad","travel_speed":600.0}]:
		var invalid := restored.data.duplicate(true)
		invalid.world_time = bad
		check(not restored._valid_save(invalid), "Malformed clock data is rejected")
	var runtime = preload("res://Modules/FrontierDelivery/Scripts/Map/WorldMapRuntime.gd").new()
	restored.data.battle = {"battle_id":"time_receipt"}
	start = restored.data.world_time.total_minutes
	var receipt := {"battle_id":"time_receipt","outcome":"victory","reward":0,"parts":{}}
	check(restored.commit_battle(receipt,runtime.snapshot()) and is_equal_approx(restored.data.world_time.total_minutes-start,20.0), "Committed battle consumes configured time")
	check(restored.commit_battle(receipt,runtime.snapshot()) and is_equal_approx(restored.data.world_time.total_minutes-start,20.0), "Duplicate battle receipt cannot charge time twice")
	await check_map()
	print("WORLD_TIME_", "FAILED" if failed else "PASSED", " checks=", checks)
	quit(1 if failed else 0)

func check_map() -> void:
	root.size = Vector2i(1280,720)
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.use_hex_map_for_new_games = false # This fixture verifies the retained 20261015 map.
	app.save_path = "user://world_time_application.json"
	app.display_settings_path = "user://world_time_display.cfg"
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	check(not app.world_time_hud.visible, "Time HUD is hidden on the main menu")
	app.start_new_game()
	for frame in 600:
		if app.phase == "world": break
		await process_frame
	app.ui._close_all()
	var map: Control = app.delivery_map
	map.set_process(false)
	await process_frame
	check(app.world_time_hud.is_visible_in_tree() and app.world_time_hud.position == Vector2(16,16), "Time HUD is anchored at the map's top-left")
	check(app.world_time_hud.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Time panel cannot cover map mouse clicks")
	var start: float = app.session.data.world_time.total_minutes
	for i in 5: map._process(0.05)
	check(app.session.data.world_time.total_minutes == start, "Idle map processing costs no time")
	check(not map.request_move(Vector2(-500,-500)) and app.session.data.world_time.total_minutes == start, "Blocked destinations cost no time")
	var origin: Vector2 = map.runtime.player()
	var accepted := false
	for offset: Vector2 in [Vector2(36,0),Vector2(0,36),Vector2(-36,0),Vector2(0,-36)]:
		if map.request_move(origin+offset): accepted = true; break
	check(accepted, "Plan a real walk from the summoning hut")
	if not accepted: app.queue_free(); await process_frame; return
	var distance := [0.0]
	map.distance_travelled.connect(func(value): distance[0] += value)
	for i in 3: map._process(0.05)
	check(distance[0] > 0 and is_equal_approx(app.session.data.world_time.total_minutes-start,distance[0]*0.1), "Real accepted movement charges actual travelled path length")
	app.ui._warehouse()
	var stopped: Vector2 = map.runtime.player()
	var stopped_time: float = app.session.data.world_time.total_minutes
	for i in 5: map._process(0.05)
	check(map.runtime.player() == stopped and app.session.data.world_time.total_minutes == stopped_time, "Warehouse pauses both travel and game time")
	var reload_session := SESSION.new()
	reload_session.save_path = app.save_path
	check(reload_session.load_save() and reload_session.delivery_snapshot().player == map.runtime.data.player and is_equal_approx(reload_session.data.world_time.total_minutes,stopped_time), "Opening a menu saves the partial journey and clock together")
	app.ui._close_all()
	var saved_position: Vector2 = map.runtime.player()
	var real_path: String = app.session.save_path
	map._process(0.05)
	app.session.save_path = real_path+"/blocked.json"
	check(not map.save_progress() and map.runtime.player() == saved_position and is_equal_approx(app.session.data.world_time.total_minutes,stopped_time), "Failed map save rolls position and clock back to the same checkpoint")
	app.session.save_path = real_path
	app.ui._close_all()
	check(app.set_world_travel_speed(1200.0) and "1200" in app.world_time_hud.get_node("Margin/Rows/Travel/Value").text, "Runtime speed API updates the displayed player attribute")
	start = app.session.data.world_time.total_minutes
	map._arrived("missing_location","location")
	check(app.session.data.world_time.total_minutes == start, "Rejected interactions cost no time")
	app.ui._close_all()
	var hut := {}
	for object: Dictionary in map.Catalog.world().objects:
		if object.get("location_id","") == "summoning_hut": hut = object; break
	map.runtime.data.player = hut.position.duplicate()
	map._arrived(hut.id,"location")
	check(is_equal_approx(app.session.data.world_time.total_minutes-start,5.0), "Successful place visit pays its configured five minutes once")
	app.ui._close_all()
	var rules = preload("res://Modules/PaperUI/Scripts/Ritual/RuneRules.gd").new()
	rules.import_layout({"version":4,"stage":1,"placed":[{"uid":"time","runeId":"health","cells":[[-1,0],[0,0],[1,0]],"enabled":true}],"placedRelics":[]})
	start = app.session.data.world_time.total_minutes
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	check(app.session.summon(rules,"frontier_layout","world",rng) and is_equal_approx(app.session.data.world_time.total_minutes-start,30.0), "Successful real summon consumes configured time")
	start = app.session.data.world_time.total_minutes
	check(not app.session.summon(rules,"frontier_layout","world",rng) and app.session.data.world_time.total_minutes == start, "Duplicate/rejected summon does not consume time")
	check(app.get_map_diagnostics().world_time == app.session.world_time_status(), "Existing mapstate diagnostics include clock and travel speed")
	var hud: Control = app.world_time_hud
	check(hud.background_texture == null and hud.time_icon == null and hud.travel_icon == null, "Default HUD has optional artwork slots")
	var skinned: Control = preload("res://Scenes/Application/WorldTimeHUD.tscn").instantiate()
	skinned.background_texture = GradientTexture2D.new()
	skinned.time_icon = GradientTexture2D.new()
	skinned.travel_icon = GradientTexture2D.new()
	root.add_child(skinned)
	skinned.bind_session(app.session)
	check(skinned.get_node("Background").visible and skinned.get_node("Margin/Rows/Time/Icon").visible and skinned.get_node("Margin/Rows/Travel/Icon").visible, "Replacement background and both icons are applied by the HUD interface")
	skinned.queue_free()
	var localization: Node = root.get_node("GameLocalization")
	localization.set_locale("en",false)
	check("Day " in hud.get_node("Margin/Rows/Time/Value").text and "Travel speed" in hud.get_node("Margin/Rows/Travel/Value").text, "Clock and speed labels follow runtime language changes")
	localization.set_locale("zh_CN",false)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		for resolution: Vector2i in [Vector2i(1120,680),Vector2i(1920,1080)]:
			root.size = resolution
			for frame in 5: await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(args[0]+"/world_time_"+str(resolution.x)+".png") == OK, "Capture real map HUD at "+str(resolution))
	app.queue_free()
	await process_frame
	await process_frame
