extends SceneTree
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
var failed := false
var console: Node
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("MAP_LOG_CHECK ",ok," ",message)
	if not ok: failed=true; push_error(message)
func rows(event: String = "") -> Array:
	var result: Array = []
	for line: String in console._output_lines:
		if not line.begins_with("[map_event] "): continue
		var parsed: Dictionary = JSON.parse_string(line.trim_prefix("[map_event] "))
		if event.is_empty() or parsed.event==event: result.append(parsed)
	return result
func run() -> void:
	root.size = Vector2i(1280,720)
	console = root.get_node("RuntimeConsole")
	console.maximum_output_lines = 1000
	check(not console.is_map_tracking_enabled(),"Map tracing is off by default")
	check("disabled" in console.execute_command("trackmap status") and not console.is_map_tracking_enabled(),"Status is read-only")
	check("trackmap" in console.execute_command("help") and "mapstate" in console.execute_command("help"),"Help lists both new commands")
	check("waiting for GameRoot" in console.execute_command("trackmap ON"),"Tracing can be enabled before map initialization")
	check("Usage:" in console.execute_command("trackmap on extra") and console.is_map_tracking_enabled(),"Malformed command does not change tracking state")
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.save_path = "res://Tests/.runtime/integration/map_logging_"+str(Time.get_ticks_usec())+".json"
	app.display_settings_path = "res://Tests/.runtime/integration/map_logging_display.cfg"
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	app.start_new_game()
	for tick: int in 600:
		if app.phase=="world": break
		await physics_frame
	check(app.phase=="world" and app.delivery_map.runtime.diagnostic_logging,"Map inherits console tracing on initialization")
	check(rows("map_loaded").size()==1,"Map initialization emits one structured event")
	check(not app.session.integration_logging,"Map logs are independent of integration logs")
	check(not app.delivery_map.request_move(Vector2(-500,-500)) and not rows("travel_rejected").back().reason.is_empty(),"Movement refusal records its reason")
	console.execute_command("mapstate wizard_wolf_gate_rock")
	var snapshot: Dictionary = rows("snapshot").back()
	check(snapshot.location.id=="wizard_wolf_gate_rock" and not snapshot.location.interaction_error.is_empty(),"Location snapshot includes unmet interaction conditions")
	check("Usage:" in console.execute_command("mapstate id extra"),"Snapshot command rejects extra arguments")
	for frame: int in 5: await process_frame
	var point: Vector2 = app.delivery_map.get_global_transform_with_canvas()*app.delivery_map.world_to_screen(app.delivery_map.runtime.player())
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position=point; event.global_position=point; event.pressed=pressed
		root.push_input(event,true)
		await process_frame
	for tick: int in 180:
		if app.ui.overlay.visible: break
		await physics_frame
	check(not rows("map_click").is_empty() and not rows("interaction_arrived").is_empty(),"Real click and arrival are logged")
	check(not rows("event_routed").is_empty() and rows("event_opened").back().event_id=="summon","Summoning hut routes into the real event UI")
	app.ui._perform_summon()
	check(rows("event_rejected").back().event_id=="summon" and not rows("event_rejected").back().reason.is_empty(),"Rejected summon does not claim successful execution")
	app.ui._close_all()
	check(app.ui.rules.import_layout({"version":3,"stage":1,"placed":[{"uid":"logging","runeId":"health","cells":[[-1,0],[0,0],[1,0]],"enabled":true}],"placedRelics":[]}),"Prepare actual summon")
	app.ui._perform_summon()
	check(rows("event_completed").back().event_id=="summon" and rows("event_completed").back().pending_ids.size()==5,"Successful summon records committed IDs and cost state")
	app.ui.view.skip_eruption()
	for frame: int in 5: await process_frame
	check(app.session.store_pending(),"Store summon result")
	app.ui._close_all()
	app.ui._show("world")
	var runtime = app.delivery_map.runtime
	var wolf := CATALOG.location("layout_wolf_den_001")
	var centre := CATALOG.v(wolf.position)
	runtime.data.player = [centre.x-350,centre.y]
	var before: Dictionary = runtime.snapshot()
	runtime.rng.seed = 27
	var encounter: Dictionary = runtime.move_to(centre)
	check(not rows("encounter_roll").is_empty(),"Entering encounter range records the actual random roll")
	var roll: Dictionary = rows("encounter_roll").back()
	check(roll.has("probability") and roll.has("roll") and roll.has("triggered") and roll.location_id==wolf.id,"Roll includes threshold, outcome and location ID")
	var after: Dictionary = runtime.snapshot()
	var random_state: int = runtime.rng.state
	console.execute_command("trackmap off")
	var count := rows().size()
	runtime.data = before.duplicate(true)
	runtime.rng.seed = 27
	check(runtime.move_to(centre)==encounter and runtime.snapshot()==after and runtime.rng.state==random_state,"Logging does not change encounter RNG or gameplay state")
	check(rows().size()==count and not runtime.diagnostic_logging,"Off suppresses runtime and UI event logs")
	console.execute_command("mapstate no_such_location")
	check(rows().size()==count+1 and rows("snapshot").back().location.error=="地点不存在。","Explicit snapshot works with tracing off and unknown IDs")
	console.execute_command("trackmap on")
	check(app.session.move_monster(app.session.monsters("warehouse")[0].id,"team"),"Prepare actual battle request")
	app.delivery_battle_settings = app.delivery_battle_settings.duplicate(true)
	app.delivery_battle_settings.unit_scale = 0.0
	check(app.delivery_map.begin_battle(wolf.id,"clear"),"Commit request before intentionally failed deployment")
	check(not rows("battle_request_committed").is_empty() and not rows("battle_load_failed").is_empty() and not rows("battle_cancelled").is_empty(),"Battle request, loading refusal and cancellation are correlated")
	app.ui._close_all()
	var town := CATALOG.location("layout_sargate_city")
	runtime.data.player = town.position.duplicate()
	app.delivery_map._arrived(town.id,"location")
	check(rows("event_unavailable").back().location_id==town.id,"Unimplemented event is explicitly identified")
	app.ui._close_all()
	count = rows().size()
	for frame: int in 20: await process_frame
	check(rows().size()==count,"Idle frames do not spam map events")
	check(rows().all(func(row):return row.has("sequence") and row.has("time_ms")),"Structured rows carry sequence and time")
	console.set_console_open(true)
	app.refresh_input_gate()
	console.execute_command("mapstate")
	check(rows("snapshot").back().console_open and "console" in rows("snapshot").back().input_blockers,"Snapshot explains intentional console input blocking")
	console.set_console_open(false)
	app.refresh_input_gate()
	var probe := "map_archive_"+str(Time.get_ticks_usec())
	console.log_map_event("archive_probe",{"probe":probe})
	var archive: String = console.create_logs_archive("res://Tests/.runtime/integration/map_logging_archive")
	var reader := ZIPReader.new()
	var archived := false
	if reader.open(archive)==OK:
		for path: String in reader.get_files():
			if path.ends_with(".log") and probe in reader.read_file(path).get_string_from_utf8(): archived=true
		reader.close()
	check(archived,"getlogs archive includes the actual newly printed map event")
	console.execute_command("trackmap off")
	app.queue_free()
	await process_frame
	await process_frame
	print("MAP_LOGGING_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
