extends SceneTree
var app: Node
var output := "D:/GameJamWorkspace/Reports/BattleControlsDisplay_2026-10-15"
func _initialize() -> void: call_deferred("run")
func key(code: Key) -> void:
	for pressed: bool in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code; event.physical_keycode = code; event.pressed = pressed
		root.push_input(event,true)
		for frame: int in 3: await process_frame
func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point; event.global_position = point; event.pressed = pressed
		root.push_input(event,true)
		for frame: int in 3: await process_frame
func capture(name: String) -> void:
	for frame: int in 5: await process_frame
	RenderingServer.force_draw()
	var picture := root.get_texture().get_image()
	assert(picture!=null and not picture.is_empty(),"Real rendering is required")
	assert(picture.save_png(output+"/"+name+".png")==OK)
	print("BATTLE_DISPLAY_CAPTURE ",name," render_size=",picture.get_size()," window_mode=",root.mode)
func run() -> void:
	root.size = Vector2i(1280,720)
	app = preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.use_delivery_map = false
	var path := "res://Tests/.runtime/integration/native_display_"+str(Time.get_ticks_usec())
	app.save_path = path+".json"
	app.display_settings_path = path+".cfg"
	root.add_child(app)
	app.ui.animate_panels = false; app.ui.board_motion.enabled = false
	app.ui._settings()
	await capture("01_settings_1280")
	var choices: OptionButton = app.ui.modal_box.find_child("Resolution",true,false)
	var fullscreen: CheckButton = app.ui.modal_box.find_child("Fullscreen",true,false)
	var apply: Button = app.ui.modal_box.find_child("ApplyDisplay",true,false)
	choices.select(app.DISPLAY_RESOLUTIONS.find(Vector2i(1280,720)))
	await click(fullscreen)
	assert(fullscreen.button_pressed)
	await click(apply)
	assert(root.mode==Window.MODE_FULLSCREEN and DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN)
	assert(root.content_scale_size==Vector2i(1280,720))
	var config := ConfigFile.new()
	assert(config.load(app.display_settings_path)==OK and config.get_value("display","fullscreen"))
	await capture("02_settings_fullscreen")
	fullscreen.button_pressed = false
	choices.select(app.DISPLAY_RESOLUTIONS.find(Vector2i(1120,680)))
	apply.pressed.emit()
	assert(root.mode==Window.MODE_WINDOWED and root.size==Vector2i(1120,680))
	root.position = Vector2i(-10000,-10000)
	await capture("03_settings_1120")
	assert(app.apply_display_settings(Vector2i(1280,720),false))
	root.position = Vector2i(-10000,-10000)
	app.ui._close_all()
	app.start_new_game()
	for tick: int in 600:
		if app.phase=="world": break
		await physics_frame
	assert(app.phase=="world")
	app.ui._close_all()
	preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(app.session)
	var location: WorldMapLocation = app.world_map.get_location(&"bandits")
	location.state.discovered = true
	app.world_map.player.global_position = location.interaction_point()
	app.world_map.interaction.begin(location)
	app.world_map.interaction.request_battle()
	for tick: int in 600:
		if app.phase=="deployment": app.start_battle()
		if app.phase=="battle": break
		await physics_frame
	assert(app.phase=="battle")
	for frame: int in 5: await process_frame
	assert(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED)
	await key(KEY_Q)
	assert(app.free_mouse_enabled and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE and not paused)
	await capture("04_battle_free_mouse")
	await click(app.ui.base.get_node("%Settings"))
	assert(app.ui.overlay.visible)
	app.ui._close_all()
	for frame: int in 3: await process_frame
	assert(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE and app.free_mouse_enabled)
	await key(KEY_Q)
	assert(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED)
	await key(KEY_SPACE)
	assert(paused and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE and app.ui.pause_hint.is_visible_in_tree())
	await capture("05_battle_paused")
	app.ui._settings()
	await capture("06_paused_settings")
	app.ui._close_all()
	await key(KEY_SPACE)
	assert(not paused and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED)
	await capture("07_battle_resumed")
	app.queue_free()
	await process_frame; await process_frame
	print("BATTLE_CONTROLS_DISPLAY_CAPTURE_PASSED")
	quit()
