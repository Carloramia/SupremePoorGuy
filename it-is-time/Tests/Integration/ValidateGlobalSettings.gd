extends SceneTree
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
var failed := false
var output := "D:/GameJamWorkspace/Reports/GlobalSettings_2026-10-16"
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("SETTINGS_CHECK ",ok," ",message)
	if not ok: failed = true; push_error(message)
func wait_phase(app: Node, wanted: String) -> bool:
	for tick: int in 900:
		if app.phase == wanted: return true
		await physics_frame
	return false
func key(code: Key, echo: bool = false) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code; event.physical_keycode = code
		event.pressed = pressed; event.echo = echo if pressed else false
		root.push_input(event,true)
		await process_frame
func settings_open(app: Node) -> bool:
	return not app.ui.modal_stack.is_empty() and app.ui.modal_stack.back().kind == "settings"
func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point; motion.global_position = point
	root.push_input(motion,true)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		event.position = point; event.global_position = point
		root.push_input(event,true)
		await process_frame
func create_app(delivery: bool) -> Node:
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.use_hex_map_for_new_games = false # This fixture verifies the retained 20261015 map.
	app.use_delivery_map = delivery
	app.save_path = output+"/session_"+str(Time.get_ticks_usec())+".json"
	app.display_settings_path = output+"/display.cfg"
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	return app
func begin_battle(app: Node) -> void:
	if app.use_delivery_map:
		var catalog := preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
		for camp: Dictionary in catalog.world().objects:
			if camp.type == "camp" and "wolf" in str(camp.get("enemy_config_id","")):
				app.delivery_map.runtime.data.player = camp.position.duplicate()
				app.delivery_map.runtime.data.discovered.append(camp.id)
				app.delivery_map.begin_battle(camp.id,"clear")
				break
	else:
		var location: WorldMapLocation = app.world_map.get_location(&"bandits")
		location.state.discovered = true
		app.world_map.player.global_position = location.interaction_point()
		app.world_map.interaction.begin(location)
		app.world_map.interaction.request_battle()
func back_to_menu(app: Node) -> void:
	if not settings_open(app): await key(KEY_ESCAPE)
	check(settings_open(app),"Settings reachable before returning: "+app.phase)
	var button: Button = app.ui.modal_box.find_child("ReturnToMainMenu",true,false)
	check(button != null and not button.disabled,"Return to Main Menu button available")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/settings.png")
	await click(button)
	check(await wait_phase(app,"main"),"Return finishes at main menu")
	check(app.world_map == null and app.delivery_map == null and app.battle == null and app.scenario == null,"Gameplay scenes are released")
	check(not paused and app._pause_reasons.is_empty() and not app.free_mouse_enabled,"Pause and free-mouse state are cleared")
	check(app.ui.main_menu.visible and not app.ui.overlay.visible and not app.ui.main_menu.get_node("%Continue").disabled,"Main menu shows an enabled Continue button")
	check(not app.ui.view.running,"No summon animation can reopen a page after returning")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,720)
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	for delivery: bool in [false,true]:
		var app := create_app(delivery)
		await key(KEY_ESCAPE)
		check(settings_open(app),"ESC also opens settings at main menu")
		await key(KEY_ESCAPE,true)
		check(settings_open(app),"Key repeat does not close settings")
		await key(KEY_ESCAPE)
		check(not app.ui.overlay.visible,"Second ESC closes settings")
		app.start_new_game()
		check(await wait_phase(app,"world"),"Initialize world: "+str(delivery))
		app.ui._close_all()
		preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(app.session)
		# ESC has priority even during animated warehouse entry and text editing.
		app.ui.animate_panels = true; app.ui.board_motion.enabled = true
		app.ui._warehouse()
		check(app.ui.board_motion.busy,"Warehouse entry animation is active")
		await key(KEY_ESCAPE)
		check(settings_open(app) and app.ui.modal_stack.size() == 2,"ESC interrupts animation and overlays settings without discarding the warehouse")
		await key(KEY_ESCAPE)
		check(app.ui.modal_stack.size() == 1 and app.ui.modal_stack.back().title.begins_with("妖兽仓库"),"Closing settings restores the warehouse")
		app.ui.animate_panels = false; app.ui.board_motion.enabled = false
		app.ui._detail("test_human")
		var field := app.ui.modal_box.find_child("NameInput",true,false) as LineEdit
		field.grab_focus()
		await key(KEY_ESCAPE)
		check(settings_open(app),"ESC opens settings while a LineEdit has focus")
		await key(KEY_ESCAPE)
		check(app.ui.modal_stack.back().title == "妖兽详情","Closing settings restores the nested detail page")
		app.ui._close_all()
		await key(KEY_ESCAPE)
		var real_path: String = app.session.save_path
		app.session.save_path = real_path+"/blocked.json"
		check(not app.return_to_main_menu() and app.phase == "world" and settings_open(app),"Save failure keeps the current world and settings open")
		app.session.save_path = real_path
		await back_to_menu(app)
		app.ui.main_menu.get_node("%Continue").pressed.emit()
		check(await wait_phase(app,"world") and app.session.monsters("team").size() == 1,"Continue rebuilds one world and preserves party")
		begin_battle(app)
		check(await wait_phase(app,"deployment"),"Enter real deployment")
		var host: Node3D = app.battle
		await key(KEY_ESCAPE)
		check(settings_open(app) and paused and not host.cursor.is_gameplay_cursor_active(),"Deployment settings pause and release the cursor")
		await key(KEY_ESCAPE)
		check(not paused and host.cursor.is_gameplay_cursor_active(),"Closing settings resumes deployment")
		app.start_battle()
		await key(KEY_SPACE)
		await key(KEY_ESCAPE)
		check(settings_open(app) and app.is_battle_manually_paused(),"ESC works while battle is manually paused")
		await key(KEY_ESCAPE)
		check(paused and app.is_battle_manually_paused(),"Closing settings preserves manual pause")
		var console := root.get_node("RuntimeConsole")
		console.set_console_open(true)
		await key(KEY_ESCAPE)
		check(not console.is_console_open() and settings_open(app),"ESC replaces the console with settings")
		await back_to_menu(app)
		var saved_battle: String = app.session.data.battle.battle_id
		app.ui.main_menu.get_node("%Continue").pressed.emit()
		check(await wait_phase(app,"deployment") and app.battle.battle_id == saved_battle,"Continue restarts the same pending battle at deployment")
		app.start_battle()
		app.request_retreat()
		check(app.phase == "settlement","Enter settlement")
		await key(KEY_ESCAPE)
		check(settings_open(app) and not app.ui.close_button.disabled,"ESC settings remain closable above mandatory settlement")
		await key(KEY_ESCAPE)
		check(app.ui.modal_stack.back().title == "战斗结算" and app.ui.close_button.disabled,"Closing settings restores mandatory settlement")
		await back_to_menu(app)
		app.ui.main_menu.get_node("%Continue").pressed.emit()
		check(await wait_phase(app,"settlement"),"Continue restores saved settlement without replaying rewards")
		app.return_to_world()
		check(app.phase == "returning","World return is awaiting its transition")
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE; escape.pressed = true
		root.push_input(escape,true)
		check(settings_open(app),"ESC works during return transition")
		check(not app.return_to_main_menu() and app.returning_to_main_menu,"Menu return waits for the current transition")
		check(await wait_phase(app,"main"),"Return transition safely finishes at main menu")
		app.ui.main_menu.get_node("%Continue").pressed.emit()
		check(await wait_phase(app,"world"),"Continue restores world after returning transition")
		# A pending summon must survive leaving during its visual animation.
		var unit := FACTORY.template("wolf")
		unit.merge({"id":"pending_wolf","position":"pending","traits":[]},true)
		app.session.data.monsters.append(unit)
		app.session.data.pending.append(unit.id)
		app.session.data.pending_location = "grassland"
		app.session.data.pending_return = "world"
		check(app.session.save(),"Save pending summon fixture")
		app.ui._resume_pending()
		await key(KEY_ESCAPE)
		var elapsed: float = app.ui.view.elapsed
		for tick: int in 30: await process_frame
		check(settings_open(app) and is_equal_approx(app.ui.view.elapsed,elapsed),"Summon presentation cannot finish behind settings")
		await back_to_menu(app)
		for tick: int in 190: await process_frame
		check(app.ui.route == "main" and "pending_wolf" in app.session.data.pending,"Returning during summon preserves pending creatures and prevents late UI callbacks")
		app.queue_free()
		await process_frame; await process_frame
	await _loading_and_scenario()
	print("GLOBAL_SETTINGS_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func _loading_and_scenario() -> void:
	var app := create_app(false)
	app.start_new_game()
	app.enter_world()
	check(app.phase == "loading_world","World initialization is awaiting navigation")
	var loading_escape := InputEventKey.new()
	loading_escape.keycode = KEY_ESCAPE; loading_escape.pressed = true
	root.push_input(loading_escape,true)
	check(settings_open(app),"ESC works during world initialization")
	check(not app.return_to_main_menu() and app.returning_to_main_menu,"Menu return waits for world initialization")
	check(await wait_phase(app,"main"),"World loader releases its nodes before returning to menu")
	app.ui.main_menu.get_node("%Continue").pressed.emit()
	check(await wait_phase(app,"world"),"Create scenario fixture after loading cancellation")
	preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(app.session)
	var town: WorldMapLocation = app.world_map.get_location(&"town")
	app.world_map.player.global_position = town.interaction_point()
	app.world_map.interaction.begin(town)
	app.world_map.interaction.request_scenario()
	await process_frame
	check(app.phase == "scenario","Embedded scenario opens")
	await key(KEY_ESCAPE)
	check(settings_open(app) and paused and not app.scenario.can_process(),"ESC pauses embedded scenario")
	await back_to_menu(app)
	app.ui.main_menu.get_node("%Continue").pressed.emit()
	check(await wait_phase(app,"world"),"Continue after leaving scenario")
	begin_battle(app)
	check(app.phase == "loading_battle","Battle loader is waiting on physics frames")
	# Dispatch synchronously, before either awaited physics frame completes.
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE; event.pressed = true
	root.push_input(event,true)
	check(settings_open(app),"ESC works during battle loading")
	check(not app.return_to_main_menu() and app.returning_to_main_menu,"Return is deferred while the loader owns its nodes")
	check(await wait_phase(app,"main") and app.battle == null,"Deferred return completes without late loader callbacks")
	app.queue_free()
	await process_frame; await process_frame
