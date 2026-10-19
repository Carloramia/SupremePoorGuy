extends SceneTree
var failed:=false
var checks:=0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failed=true; push_error(message)
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	var app:=preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.save_path="res://Tests/.runtime/approved_%d.json"%Time.get_ticks_usec()
	app.display_settings_path=app.save_path+".cfg"
	root.add_child(app)
	app.ui.animate_panels=false; app.ui.board_motion.enabled=false
	app.start_new_game()
	for frame in 600:
		if app.phase=="world": break
		await process_frame
	check(app.phase=="world" and is_instance_valid(app.hex_map),"New game enters authored hex map")
	if not is_instance_valid(app.hex_map): quit(1); return
	check(app.hex_map.doc.sites.size()==631,"Complete authored sites retained")
	check(app.session.data.has("hex_map"),"Hex world saved")
	app.ui._close_all(); await process_frame
	check(app.hex_map.input_enabled,"Map input resumes after guide")
	check(app.complete_opening_handoff(),"External opening hands over actual item")
	check(app.complete_opening_handoff(),"Opening handoff idempotent")
	var shared: Dictionary={}
	for cell: Dictionary in app.hex_map.model.cells.values():
		if cell.get("obstacle_ids",[]).size()>1: shared=cell; break
	check(not shared.is_empty(),"Authored shared obstacle cell located")
	if not shared.is_empty():
		app.hex_map.progress.destroyed.append(shared.obstacle_ids[0]); app.hex_map._apply_destroyed()
		check(shared.control=="breakable","Destroying one owner preserves shared collision")
		for owner: String in shared.obstacle_ids:
			if owner not in app.hex_map.progress.destroyed: app.hex_map.progress.destroyed.append(owner)
		app.hex_map._apply_destroyed(); app.hex_map._build_navigation()
		check(shared.control=="allowed" and shared.feature=="","All owners destroyed opens shared passage")
		check(app.hex_map.save_progress(),"Destruction persists with map state")
	print("APPROVED_WORLD_", "FAILED" if failed else "PASSED", " checks=",checks)
	app.queue_free(); await process_frame
	quit(1 if failed else 0)
