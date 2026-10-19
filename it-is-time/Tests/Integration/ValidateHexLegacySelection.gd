extends SceneTree
var failed := false
func _initialize() -> void:
	create_timer(60).timeout.connect(func(): push_error("LEGACY_SELECTION_TIMEOUT"); quit(1))
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("HEX_LEGACY ",ok," ",message)
	if not ok: failed=true; push_error(message)
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	var session := preload("res://Scripts/Application/GameSession.gd").new()
	session.save_path="res://Tests/.runtime/integration/legacy_backend_"+str(Time.get_ticks_usec())+".json"
	var world := WorldMapRuntimeState.new()
	world.map_id=&"frontier"
	check(session.save_world(world.to_dict()),"legacy Frontier fixture saves")
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.save_path=session.save_path
	app.display_settings_path=app.save_path+".display.cfg"
	root.add_child(app)
	app.ui.animate_panels=false
	check(not app.use_delivery_map and app.session.data.worlds.has("frontier"),"legacy save without a pending battle retains its original backend")
	app.start_new_game()
	for frame: int in 300:
		if app.phase=="world": break
		await process_frame
	check(app.use_delivery_map and app.session.delivery_version()=="20261019" and app.delivery_map!=null,"starting a new game restores configured new-map defaults")
	app.queue_free()
	await process_frame
	await process_frame
	print("HEX_LEGACY_SELECTION_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
