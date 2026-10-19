extends SceneTree
var checks:=0
var failed:=false
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failed=true; push_error(label)
func frames(count: int=4) -> void:
	for frame in count: await process_frame
func click(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new(); motion.position=point; motion.global_position=point
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT
		event.position=point; event.global_position=point; event.pressed=pressed
		root.push_input(event,true); await process_frame
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	var path: String="res://Tests/.runtime/hex_modal_"+name+".png"
	check(root.get_texture().get_image().save_png(path)==OK,"Capture "+name)
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	root.size=Vector2i(1280,720)
	var app:=preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.save_path="res://Tests/.runtime/hex_modal_%d.json"%Time.get_ticks_usec()
	app.display_settings_path=app.save_path+".cfg"
	root.add_child(app); app.ui.animate_panels=false; app.ui.board_motion.enabled=false
	app.start_new_game()
	for frame in 600:
		if app.phase=="world": break
		await process_frame
	await frames()
	check(app.phase=="world" and is_instance_valid(app.hex_map),"New game enters hex map")
	check(app.hex_map.get_viewport()==app.map_viewport,"Map layers are isolated inside map viewport")
	check(app.hex_map.get_viewport()!=app.ui.overlay.get_viewport(),"Fog and high-z scenery cannot draw above modal canvas")
	check(app.ui.overlay.visible and app.ui.modal_stack.back().kind=="tasks","Initial guide is visible")
	check(not app.hex_map.input_enabled,"Initial guide blocks map input")
	await capture("guide")
	app.ui._close_all(); await frames()
	check(app.hex_map.input_enabled,"Closing guide restores map input")
	check(app.map_container.visible,"World route displays map container")
	check(app.hex_map.size.is_equal_approx(Vector2(app.map_viewport.size)),"Map fills only its embedded viewport")
	await capture("world")
	app.hex_map.route.clear()
	var player_before: Vector2=app.hex_map.player
	app.ui._settings(); await frames()
	check(app.ui.modal_stack.back().kind=="settings" and app.ui.overlay.visible,"Settings open above world")
	var point: Vector2=app.map_container.get_global_rect().get_center()+Vector2(70,40)
	await click(point); await frames()
	check(app.hex_map.route.is_empty() and app.hex_map.player==player_before,"Clicking settings cannot leak into map movement")
	await capture("settings")
	var close: Control=app.ui.close_button
	await click(close.get_global_rect().get_center()); await frames()
	check(not app.ui.overlay.visible and app.hex_map.input_enabled,"Actual mouse click closes settings and restores travel")
	await click(point); await frames()
	check(not app.hex_map.route.is_empty() or app.hex_map.player!=player_before,"Mouse input reaches map after modal closes")
	app.hex_map.route.clear()
	app.ui._open_ritual(); await frames()
	check(app.ui.overlay.visible and not app.hex_map.input_enabled,"Summoning paper blocks map")
	await capture("ritual")
	app.ui._close_all(); await frames()
	check(app.hex_map.input_enabled,"Closing summoning paper restores map")
	app.ui._tasks(); app.ui._settings(); await frames()
	check(app.ui.modal_stack.size()==2 and not app.hex_map.input_enabled,"Nested settings preserve tutorial and map gate")
	app.ui._close_modal(); await frames()
	check(app.ui.modal_stack.size()==1 and app.ui.modal_stack.back().kind=="tasks" and not app.hex_map.input_enabled,"Closing nested settings reveals guide without releasing map")
	app.ui._close_all(); await frames()
	check(app.return_to_main_menu(),"Save and return to menu")
	await frames(); check(not app.map_container.visible,"Main menu hides map viewport")
	app.enter_world(); await frames()
	check(app.phase=="world" and app.map_container.visible and app.hex_map.get_viewport()==app.map_viewport,"Continue recreates map in isolated viewport")
	app.queue_free(); await process_frame
	print("HEX_MAP_MODAL_LAYERS_","FAILED" if failed else "PASSED"," checks=",checks)
	quit(1 if failed else 0)
