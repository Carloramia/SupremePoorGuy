extends SceneTree
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failed=true; push_error(message)
func key(code: Key, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	root.push_input(event,true)
	await process_frame
func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	print("INPUT_CLICK rect=",control.get_global_rect()," window=",root.size," scale=",root.content_scale_factor," target=",control.get_path())
	await click_at(point)
func click_at(point: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = point; move.global_position = point
	root.push_input(move,true)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point; event.global_position = point; event.pressed = pressed
		root.push_input(event,true)
		await process_frame
func run() -> void:
	root.size = Vector2i(1280,720)
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.use_delivery_map = false
	app.save_path = "res://Tests/.runtime/integration/input_"+str(Time.get_ticks_usec())+".json"
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	for tick: int in 5: await process_frame
	await click(app.ui.main_menu.get_node("%Start"))
	check(app.ui.overlay.visible,"Actual mouse click opens the new-game confirmation")
	app.ui._close_all()
	app.start_new_game()
	for tick: int in 600:
		if app.phase=="world": break
		await physics_frame
	app.ui._close_all()
	var town: WorldMapLocation = app.world_map.get_location(&"town")
	app.world_map.camera.focus_on_player()
	for tick: int in 5: await process_frame
	var local_point: Vector2 = app.map_viewport.get_canvas_transform()*town.global_position
	await click_at(app.map_container.get_global_transform_with_canvas()*local_point)
	check(app.world_map.current_interaction_target==&"town" or app.world_map.interaction.active_location==town,"Mouse coordinates route from paper shell to the actual 2D map")
	app.world_map.cancel_movement("test")
	app.world_map.clear_interaction_target()
	var location: WorldMapLocation = app.world_map.get_location(&"bandits")
	location.state.discovered = true
	app.world_map.player.global_position = location.interaction_point()
	check(app.world_map.interaction.begin(location),"Location paper")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE,false)
	check(app.ui.modal_stack.back().kind=="settings" and app.world_map.interaction.active_location==location,"Esc opens settings above the location paper")
	await key(KEY_ESCAPE)
	await key(KEY_ESCAPE,false)
	check(app.world_map.interaction.active_location==location,"Second Esc returns to the location paper")
	app.ui._close_modal()
	check(app.world_map.interaction.active_location==null and not app.ui.overlay.visible,"Closing the location paper exits the actual visit")
	app.world_map.interaction.begin(location)
	var enter: Button = app.ui.modal_box.find_child("EnterBattle",true,false)
	check(enter.disabled and not enter.tooltip_text.is_empty(),"Empty party disables the battle button with an explanation")
	await click(enter)
	app._battle_requested({})
	check(app.phase=="world" and app.battle==null and app.session.data.battle.is_empty() and app.world_map.runtime_state.pending_battle.is_empty(),"Clicking a disabled battle button or calling the host cannot deploy an empty party")
	app.ui._warehouse("team")
	preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(app.session)
	app.ui._close_modal()
	enter = app.ui.modal_box.find_child("EnterBattle",true,false)
	check(not enter.disabled,"Returning from the party page enables battle once a creature is assigned")
	app.ui._warehouse("team")
	check(app.session.move_monster("test_human","warehouse"),"Remove the last creature from the party")
	app.ui._close_modal()
	enter = app.ui.modal_box.find_child("EnterBattle",true,false)
	check(enter.disabled,"Returning with an empty party disables battle again")
	app.ui._warehouse()
	check(app.session.move_monster("test_human","team"),"Restore the test creature to the party")
	app.ui._close_modal()
	app.world_map.interaction.request_battle()
	for tick: int in 600:
		if app.phase=="deployment": app.start_battle()
		if app.phase=="battle": break
		await physics_frame
	check(app.phase=="battle","Battle input fixture")
	if app.battle==null: quit(1); return
	for tick: int in 10: await physics_frame
	root.gui_release_focus()
	check(get_nodes_in_group(&"player_controller_3d").is_empty(),"No player controller is instantiated")
	check(app.get_active_controller()==null and app.battle.cursor.free_cursor_mode,"Battle starts in free cursor mode")
	var cursor: TerrainCursor3D = app.battle.cursor
	check(cursor.movement_anchor==null and cursor.controlled_character==null and cursor.has_valid_ground_position(),"Free cursor starts on terrain without a character anchor")
	await key(KEY_Q)
	await key(KEY_Q,false)
	check(app.free_mouse_enabled and not paused,"Q releases the system mouse without pausing battle")
	await key(KEY_Q)
	await key(KEY_Q,false)
	check(not app.free_mouse_enabled,"Second Q restores the terrain cursor")
	var workshop := root.get_node("WorkshopUIController")
	await key(KEY_B)
	await key(KEY_B,false)
	for tick: int in 5: await process_frame
	check(not is_instance_valid(workshop._workshop) and not paused,"B does not open Workshop or pause combat")
	check(app.battle.find_child("ControllerRadialMenu",true,false)==null,"Q cannot create a wheel or detach any character")
	var point: Vector3 = cursor.get_mouse_ground_position()
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40,-20)
	app.battle_viewport.push_input(motion,true)
	for tick: int in 5: await physics_frame
	check(cursor.get_mouse_ground_position().distance_to(point)>0.1,"Unbound terrain cursor responds to mouse motion")
	check(app.battle.camera.global_position.is_equal_approx(cursor.get_mouse_ground_position()),"Camera follows the actual free cursor position")
	Input.action_press(&"MouseLeft")
	Input.action_press(&"Right")
	var context := preload("res://Scripts/Player/PlayerControlContext.gd")
	for actor: Node3D in app.battle.actors:
		check(not context.input_allowed(actor) and not context.action_pressed(actor,&"MouseLeft"),"Keyboard and attack inputs cannot fall back to controlling an NPC")
	check(not cursor._charge_input_pressed(),"MouseLeft cannot engage character charging or target-follow dragging")
	Input.action_release(&"MouseLeft")
	Input.action_release(&"Right")
	app.ui._warehouse("team")
	await process_frame
	check(paused,"Paper still pauses combat in observer mode")
	await key(KEY_Q)
	await key(KEY_Q,false)
	await key(KEY_B)
	await key(KEY_B,false)
	check(not is_instance_valid(workshop._workshop),"B remains inactive while a paper is open")
	app.ui._close_all()
	await process_frame
	app.queue_free()
	await process_frame; await process_frame
	print("APPLICATION_INPUT_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
