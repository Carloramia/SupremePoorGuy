extends SceneTree
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failed=true; push_error(message)
func key(code: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.physical_keycode = code; event.pressed = true; event.echo = echo
	root.push_input(event,true)
	await process_frame
	event.pressed = false; event.echo = false
	root.push_input(event,true)
	await process_frame
func wait_phase(app: Node, wanted: String) -> bool:
	for tick: int in 600:
		if wanted=="battle" and app.phase=="deployment": app.start_battle()
		if app.phase==wanted: return true
		await physics_frame
	return false
func run() -> void:
	root.size = Vector2i(1280,720)
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.use_delivery_map = false
	var path := "res://Tests/.runtime/integration/display_"+str(Time.get_ticks_usec())
	app.save_path = path+".json"
	app.display_settings_path = path+".cfg"
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	check(app.battle_viewport.audio_listener_enable_3d, "Formal battle viewport enables spatial audio")
	await key(KEY_Q)
	await key(KEY_SPACE)
	check(not app.free_mouse_enabled and not paused,"Battle shortcuts are inactive in the main menu")
	app.ui._settings()
	await process_frame
	check(app.ui.modal_box.find_child("Resolution",true,false)!=null and app.ui.modal_box.find_child("Fullscreen",true,false)!=null,"Settings contains resolution and fullscreen controls")
	check(not app.apply_display_settings(Vector2i(320,200),false),"Reject unreadable display dimensions")
	check(app.apply_display_settings(Vector2i(1280,720),false),"Apply and save windowed display preferences")
	check(root.content_scale_size==Vector2i(1280,720) and root.content_scale_mode==Window.CONTENT_SCALE_MODE_VIEWPORT,"Selected resolution controls the render target")
	var config := ConfigFile.new()
	check(config.load(app.display_settings_path)==OK and config.get_value("display","resolution")==Vector2i(1280,720),"Display preferences persist separately from game progress")
	var previous := root.content_scale_size
	var real_path: String = app.display_settings_path
	app.display_settings_path += "/blocked.cfg"
	check(not app.apply_display_settings(Vector2i(1600,900),false) and root.content_scale_size==previous,"Save failure leaves current display unchanged")
	app.display_settings_path = real_path
	app._apply_display_settings(Vector2i(1600,900),false)
	app._load_display_settings()
	check(root.content_scale_size==Vector2i(1280,720),"Saved display preferences restore on initialization")
	app.ui._close_all()
	app.start_new_game()
	check(await wait_phase(app,"world"),"Initialize map")
	app.ui._close_all()
	preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(app.session)
	var location: WorldMapLocation = app.world_map.get_location(&"bandits")
	location.state.discovered = true
	app.world_map.player.global_position = location.interaction_point()
	check(app.world_map.interaction.begin(location),"Open battle location")
	app.world_map.interaction.request_battle()
	check(await wait_phase(app,"battle"),"Deploy battle")
	if app.battle==null: quit(1); return
	check(app.battle.camera.get_node("CombatAudioListener").is_current(), "Battle listens near the viewed ground")
	for tick: int in 5: await process_frame
	var cursor: TerrainCursor3D = app.battle.cursor
	check(cursor.is_gameplay_cursor_active(),"Battle begins with terrain cursor captured")
	await key(KEY_Q)
	check(app.free_mouse_enabled and not paused and not cursor.is_gameplay_cursor_active(),"Q switches to the system mouse without stopping combat")
	await key(KEY_Q,true)
	check(app.free_mouse_enabled,"Key repeat does not repeatedly toggle mouse mode")
	await key(KEY_SPACE)
	check(paused and app.free_mouse_enabled,"Manual pause preserves the chosen system mouse mode")
	await key(KEY_SPACE)
	check(not paused and app.free_mouse_enabled and not cursor.is_gameplay_cursor_active(),"Resuming does not capture a deliberately released mouse")
	await key(KEY_Q)
	check(not app.free_mouse_enabled and cursor.is_gameplay_cursor_active(),"Second Q returns to terrain cursor")
	await key(KEY_SPACE)
	check(paused and app.is_battle_manually_paused() and app.ui.pause_hint.is_visible_in_tree(),"Space pauses battle and shows a visible hint")
	var body: RigidBody3D = app.battle.actors[0].get_combat_anchor()
	var position := body.global_position
	for tick: int in 5: await physics_frame
	check(body.global_position.is_equal_approx(position),"Manual pause stops real rigid-body simulation")
	await key(KEY_SPACE,true)
	check(paused,"Space repeat cannot resume combat")
	app.ui._settings()
	await process_frame
	root.gui_release_focus()
	await key(KEY_SPACE)
	await key(KEY_Q)
	check(app.is_battle_manually_paused() and not app.free_mouse_enabled,"Settings consumes shortcuts without changing manual pause or mouse choice")
	app.ui._close_all()
	await process_frame
	check(paused and app.ui.pause_hint.visible,"Closing settings preserves manual pause")
	app.set_pause_reason(&"test_owner",true)
	await key(KEY_SPACE)
	check(not app.is_battle_manually_paused() and paused,"Space only releases its own pause reason")
	app.set_pause_reason(&"test_owner",false)
	await process_frame
	check(not paused and not app.ui.pause_hint.visible,"Final pause release resumes combat and clears the hint")
	var console := root.get_node("RuntimeConsole")
	console.set_console_open(true)
	await key(KEY_SPACE)
	check(not app.is_battle_manually_paused(),"Console text entry cannot toggle combat pause")
	console.set_console_open(false)
	await key(KEY_SPACE)
	app.battle.finish("retreat")
	await process_frame
	check(app.phase=="settlement" and not app.is_battle_manually_paused() and not app.ui.pause_hint.visible,"Settlement clears battle shortcut state")
	app.return_to_world()
	check(await wait_phase(app,"world") and not paused,"Return to map has no leftover manual pause")
	check(get_nodes_in_group(&"player_controller_3d").is_empty(),"New shortcuts never recreate the old Controller or wheel")
	app.queue_free()
	await process_frame; await process_frame
	print("BATTLE_CONTROLS_DISPLAY_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
