extends SceneTree
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failed=true; push_error(message)
func wait_phase(app: Node, wanted: String) -> bool:
	for frame: int in 600:
		if wanted=="battle" and app.phase=="deployment": app.start_battle()
		if app.phase==wanted: return true
		await physics_frame
	return false
func run() -> void:
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.use_delivery_map = false
	app.save_path = "res://Tests/.runtime/integration/root_"+str(Time.get_ticks_usec())+".json"
	app.integration_logging = true
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	check(app.phase=="main" and app.session.data.monsters.is_empty(),"Application begins without a gifted creature")
	app.start_new_game()
	check(await wait_phase(app,"world"),"World initializes in its own viewport")
	if app.world_map==null: quit(1); return
	check(app.ui.modal_stack.size()==1 and app.ui.modal_stack.back().kind=="tasks" and app.world_map.paused,"New game opens the guide after the legacy map is ready")
	app.ui._close_all()
	check(app.session.data.monsters.is_empty(),"Starting a new game keeps warehouse and party empty")
	preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(app.session)
	check(app.world_map.is_initialized and app.world_map.save_service.session==app.session,"Map uses the unified save service")
	check(not app.world_map.has_node("FakeBattleAdapter") and not app.world_map.has_node("ScenarioOverlay"),"No duplicate demo battle or routing adapters")
	app.ui._warehouse()
	await process_frame
	check(app.world_map.paused and not paused,"Paper pauses map module without pausing entire tree")
	app.ui._close_all()
	await process_frame
	check(not app.world_map.paused,"Closing final paper restores world travel")
	var location: WorldMapLocation = app.world_map.get_location(&"bandits")
	location.state.discovered = true
	app.world_map.player.global_position = location.interaction_point()
	check(app.world_map.interaction.begin(location),"Arrived map location opens real paper interaction")
	app.ui._close_modal()
	check(app.world_map.interaction.active_location==null and not app.world_map.paused,"Closing a location paper cancels the visit without softlocking travel")
	check(app.world_map.interaction.begin(location),"Location can be visited again after leaving")
	var visits_before: int = location.state.visits
	var real_path: String = app.session.save_path
	app.session.save_path = real_path+"/blocked.json"
	app.world_map.interaction.request_battle()
	check(app.phase=="world" and app.world_map.runtime_state.pending_battle.is_empty() and app.session.data.battle.is_empty(),"Save failure must not launch or retain an uncommitted battle")
	app.session.save_path = real_path
	app.world_map.interaction.request_battle()
	check(await wait_phase(app,"battle"),"Map request deploys real physical actors and waits for navigation")
	if app.battle==null: quit(1); return
	check(app.battle.actors.size()==2 and app.battle.actors[0].get_meta(&"creature_instance_id")=="test_human","Party deployment preserves roster identity")
	check(app.get_active_controller()==null and get_nodes_in_group(&"player_controller_3d").is_empty(),"Battle never generates a player Controller")
	check(app.battle.cursor.free_cursor_mode and not app.is_gameplay_blocked(),"Permanent HUD permits the free terrain cursor")
	check(app.battle.actors[0].get_world_3d()==app.battle_viewport.find_world_3d() and app.battle.get_world_3d()!=root.find_world_3d(),"Actor physics belongs to an isolated combat SubViewport")
	app.set_pause_reason(&"test_workshop",true)
	app.ui._warehouse()
	await process_frame
	check(paused,"Paper pauses actual battle physics")
	var body: RigidBody3D = app.battle.actors[0].get_combat_anchor()
	var frozen_position := body.global_position
	for tick: int in 5: await physics_frame
	check(body.global_position.is_equal_approx(frozen_position),"Paused battle rigid bodies actually stop, despite the UI processing always")
	app.ui._close_all()
	await process_frame
	check(paused,"Closing paper must not release another owner's pause")
	app.set_pause_reason(&"test_workshop",false)
	await process_frame
	check(not paused and not app.is_gameplay_blocked(),"Last pause release resumes the free cursor")
	var magic: float = app.session.data.magic
	app.session.save_path = real_path+"/blocked.json"
	app.battle.finish("victory")
	await process_frame
	check(app.phase=="settlement" and app.session.data.magic==magic and app.world_map.interaction.active_location==location and location.state.visits==visits_before,"Failed result commit keeps location, pending battle and reward unchanged")
	app.session.save_path = real_path
	app._finalize_battle()
	await process_frame
	check(app.phase=="settlement" and app.session.data.magic==magic+20,"Real result commits one reward and opens settlement")
	app.ui._settings()
	check(app.ui.modal_stack.size()==2,"Settings may open above committed settlement")
	app.ui._close_modal()
	check(app.ui.modal_stack.size()==1 and paused,"Closing nested settings preserves settlement and its physics pause")
	app.return_to_world()
	check(await wait_phase(app,"world"),"Settlement returns to existing world")
	await process_frame
	check(app.battle==null and not paused and not app.world_map.paused,"Return releases combat and restores map interaction")
	check(app.session.data.battle.is_empty() and app.session.data.battle_results.size()==1,"Pending battle clears but receipt remains")
	check(location.state.visits==visits_before+1 and location.state.lifecycle==LocationRuntimeState.Lifecycle.COMPLETED,"Battle applies one additional visit and completes the location")
	var console := root.get_node("RuntimeConsole")
	check("true" in console.execute_command("trackintegration on"),"Console can enable integration logs")
	app.queue_free()
	await process_frame
	await process_frame
	print("APPLICATION_ROOT_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
