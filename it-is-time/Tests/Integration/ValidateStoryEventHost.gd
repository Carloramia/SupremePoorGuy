extends SceneTree
var checks := 0
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(message)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.enable_hex_map = false
	app.save_path = "res://Tests/.runtime/story_events/host_%d.json" % Time.get_ticks_usec()
	app.display_settings_path = app.save_path+".cfg"
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	app.start_new_game()
	for frame: int in 600:
		if app.phase=="world": break
		await physics_frame
	check(app.phase=="world","Native world enters")
	app.ui._close_all()
	await process_frame
	check(app.story_event_bindings.is_empty(),"No level placement supplied by framework")
	check(app.story_presentation_safe(),"Unobstructed map is safe")
	var notifications := {"count":0}
	app.story_event_due.connect(func(ids): notifications.count += ids.size())
	# Simulate authoritative existing summon proof while real fixture supplies party.
	preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(app.session)
	app.session.data.serial = 1
	app.session.data.last_summon = {"succeeded":1}
	app.ui._warehouse()
	await process_frame
	check(not app.story_presentation_safe(),"Inventory paper blocks automatic presentation")
	app.session.save()
	app.ui._close_all()
	for frame: int in 3: await process_frame
	check(notifications.count==1 and app.session.ready_story_events(true)==["QST_GRASS_002"],"Return from summon/party interface detects prerequisites without reloading map")
	for frame: int in 3: await process_frame
	check(notifications.count==1,"Pending notification is not emitted each frame")
	check(app.open_story_event("QST_GRASS_002","tree").ok,"Presenter explicitly acknowledges actual event start")
	check(app.session.ready_story_events(true).is_empty(),"Actual presentation consumes only trigger queue")
	var location: Dictionary = app.delivery_map.Catalog.location("summoning_hut")
	# The native hut uses a distinct object ID; locate it without changing the map.
	for object: Dictionary in app.delivery_map.Catalog.world().objects:
		if object.get("location_id","")=="summoning_hut": location = object; break
	check(not location.is_empty(),"Existing real map object located")
	var key: String = str(app.delivery_map.runtime.data.map_id)+":"+str(location.id)
	app.story_event_bindings[key] = {"event_id":"QST_GRASS_007","entrance":"donkey"}
	var entrances := {"count":0}
	app.story_event_entry_ready.connect(func(_id,_entry): entrances.count += 1)
	app.delivery_map.runtime.data.player = location.position.duplicate()
	app.delivery_map._arrived(location.id,"event")
	check(entrances.count==1 and "donkey" in app.session.story_event_view("QST_GRASS_007").seen,"Native confirmed arrival routes configured entry")
	check(key in app.session.data.new_player_tasks.facts.locations,"Story-bound arrivals also count toward tutorial exploration")
	check(app.session.story_event_view("QST_GRASS_007").conversation.is_empty(),"Arrival never fabricates finished dialogue or starts presentation")
	app.phase = "battle"
	check(not app.story_presentation_safe() and not app.route_story_arrival(str(app.delivery_map.runtime.data.map_id),str(location.id)),"Combat blocks event entry routing")
	app.phase = "world"
	app.ui._warehouse()
	check(not app.open_story_event("QST_GRASS_007","donkey").ok,"Open interface cannot interrupt another paper")
	app.ui._close_all()
	app.queue_free()
	await process_frame
	print("STORY_EVENT_HOST_", "FAILED" if failed else "PASSED", " checks=",checks)
	quit(1 if failed else 0)
