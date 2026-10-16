extends SceneTree
const FIXTURE = preload("res://Tests/Integration/ApplicationFixtures.gd")
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("DELIVERY_CHECK ",ok," ",message)
	if not ok: failed=true; push_error(message)
func wait_phase(app: Node, wanted: String) -> bool:
	for frame: int in 900:
		if wanted=="battle" and app.phase=="deployment": app.start_battle()
		if app.phase==wanted: return true
		await physics_frame
	return false
func run() -> void:
	root.size = Vector2i(1280,720)
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.save_path = "res://Tests/.runtime/integration/delivery_"+str(Time.get_ticks_usec())+".json"
	app.display_settings_path = "res://Tests/.runtime/integration/delivery_display.cfg"
	app.integration_logging = true
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	app.start_new_game()
	check(await wait_phase(app,"world"),"Delivery world initializes")
	check(app.delivery_map!=null and app.world_map==null,"Only the delivery map backend is active")
	check(app.session.data.monsters.is_empty() and app.session.data.magic==300,"New game keeps empty inventory and 300 magic")
	check(app.delivery_map.runtime.player()==Vector2(700,2368),"New game starts at summoning hut")
	check(app.delivery_map.battle_viewport==null,"No duplicate preview battle viewport")
	check(not app.map_container.visible,"Inactive legacy viewport cannot cover the delivery map or its mouse input")
	for frame: int in 5: await process_frame
	var point: Vector2 = app.delivery_map.get_global_transform_with_canvas()*app.delivery_map.world_to_screen(app.delivery_map.runtime.player())
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point; event.global_position = point; event.pressed = pressed
		root.push_input(event,true)
		await process_frame
	for tick: int in 180:
		if app.ui.overlay.visible: break
		await physics_frame
	check(app.ui.overlay.visible,"Actual mouse click on native summoning hut opens existing ritual UI")
	var pool_text: String = app.ui.ritual_page.get_node("%Context").text
	check("树桩兽" in pool_text and "角兽" in pool_text and "蜘蛛" in pool_text and "人形" not in pool_text,"Ritual UI lists the active summon pool")
	app.ui._close_all()
	app.ui._warehouse()
	check(not app.delivery_map.input_enabled,"Paper blocks map input")
	app.ui._close_all()
	check(app.delivery_map.input_enabled,"Closing paper restores map input")
	var camp := {}
	for object: Dictionary in CATALOG.world().objects:
		if object.type=="camp" and "wolf" in str(object.get("enemy_config_id","")): camp=object; break
	check(not camp.is_empty(),"Wolf camp resolves")
	app.delivery_map.runtime.data.player = camp.position.duplicate()
	app.delivery_map.runtime.data.discovered.append(camp.id)
	app.delivery_map._arrived(camp.id,"encounter")
	check(not app.delivery_map.runtime.data.pending_battle_setup.is_empty() and app.ui.find_child("ConfirmBattleSetup",true,false).disabled,"Empty automatic encounter opens explicit party preparation")
	app.ui._close_modal()
	check(app.delivery_map.runtime.data.pending_battle_setup.is_empty() and app.delivery_map.input_enabled,"Cancel preparation saves and restores exploration")
	app.delivery_map.open_location(camp)
	check(app.ui.find_child("EnterBattle",true,false).disabled,"Empty party cannot manually enter battle")
	app.ui._close_all()
	FIXTURE.add_human(app.session)
	var real_path: String = app.session.save_path
	app.session.save_path = real_path+"/blocked.json"
	check(not app.delivery_map.begin_battle(camp.id,"clear") and app.session.data.battle.is_empty(),"Failed save cannot start combat")
	app.session.save_path = real_path
	app.ui._close_all()
	app.delivery_map.open_location(camp)
	check(app.delivery_map.begin_battle(camp.id,"clear"),"Battle request is committed")
	check(await wait_phase(app,"battle"),"Native delivery battlefield deploys physical NPCs")
	if app.battle==null or app.phase!="battle": app.queue_free(); await process_frame; quit(1); return
	check(not app.ui.overlay.visible and not paused,"Location paper closes when entering actual battle")
	check(app.battle.actors.size()==2,"Party and configured wolf roster deploy")
	check(app.battle.actors[0].faction_id==0 and app.battle.actors[0].position.x<0.0 and is_zero_approx(app.battle.actors[0].rotation.y),"Actual allied actor deploys on the left facing right")
	check(app.battle.actors[1].faction_id==1 and app.battle.actors[1].position.x>0.0 and is_equal_approx(app.battle.actors[1].rotation.y,PI),"Actual enemy actor deploys on the right facing left")
	check(app.battle.cursor.free_cursor_mode and app.get_active_controller()==null,"Battle uses free cursor without Controller")
	check(app.battle.get_world_3d()!=root.find_world_3d(),"Battle physics is isolated")
	check(app.battle._geometry.has_node("PhysicalGround") and not app.battle._geometry.has_node("Ground"),"Only real adapted ground is active")
	for action: String in ["Space","Space","QPressed","QPressed"]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = true
		root.push_input(event,true)
		await process_frame
		if action=="Space": check(paused==app.is_battle_manually_paused(),"Space pause synchronizes actual physics")
		else: check(app.battle.camera.input_enabled!=app.free_mouse_enabled,"Q toggles system mouse and camera input")
		event = InputEventAction.new(); event.action=action; event.pressed=false
		root.push_input(event,true)
		await process_frame
	var battle_id: String = app.battle.battle_id
	var magic: int = app.session.data.magic
	app.session.save_path = real_path+"/blocked.json"
	app.battle.finish("victory")
	await process_frame
	check(app.session.data.magic==magic and not app.session.data.battle_results.has(battle_id),"Failed settlement leaves rewards untouched")
	app.session.save_path = real_path
	app._finalize_battle()
	check(app.session.data.magic==magic+20 and camp.id in app.delivery_map.runtime.data.cleared,"Clear victory commits reward and camp clear together")
	check(app.delivery_map.commit_result(app._pending_result) and app.session.data.magic==magic+20,"Duplicate result never duplicates reward")
	var recovered = preload("res://Scripts/Application/GameSession.gd").new()
	recovered.save_path = real_path
	check(recovered.load_save() and recovered.data.battle.phase=="settlement","Settlement survives restart")
	check(recovered.delivery_snapshot().battle_receipts.has(battle_id),"Runtime receipts derive from the one session ledger")
	app.return_to_world()
	check(await wait_phase(app,"world"),"Settlement returns to existing delivery map")
	check(app.session.data.battle.is_empty() and app.delivery_map.runtime.data.active_battle.is_empty(),"Return clears the active request")
	app.ui._close_all()
	app.delivery_battle_settings = app.delivery_battle_settings.duplicate(true)
	app.delivery_battle_settings.unit_scale = 0.0
	check(app.delivery_map.begin_battle(camp.id,"clear") and app.phase=="world" and app.session.data.battle.is_empty() and app.battle==null,"Deployment failure cancels the committed request and returns to the map")
	app.ui._close_all()
	var request: Dictionary = app.delivery_map.runtime.begin_battle(camp.id,"encounter",["test_human"])
	check(app.session.save_delivery_world(app.delivery_map.runtime.snapshot(),request),"Persist loading fixture for cancellation recovery")
	app.phase = "loading_battle"
	app.session.save_path = real_path+"/blocked.json"
	app._cancel_failed_delivery_battle("fixture")
	check(app.ui.close_button.disabled and app.session.data.battle.battle_id==request.request_id,"Cancellation save failure keeps request and a concrete retry action")
	app.ui._close_modal()
	check(app.ui.overlay.visible,"Escape cannot dismiss the only cancellation retry action")
	app.session.save_path = real_path
	app._cancel_failed_delivery_battle("fixture")
	check(app.phase=="world" and app.session.data.battle.is_empty(),"Cancellation retry recovers the map")
	app.ui._close_all()
	request = app.delivery_map.runtime.begin_battle(camp.id,"encounter",["test_human"])
	check(app.session.save_delivery_world(app.delivery_map.runtime.snapshot(),request),"Persist interrupted loading battle")
	app.queue_free()
	await process_frame
	await process_frame
	app = preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.save_path = real_path
	app.display_settings_path = "res://Tests/.runtime/integration/delivery_display.cfg"
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	app.enter_world()
	check(await wait_phase(app,"battle") and app.battle.battle_id==request.request_id,"Application restart resumes the same saved battle with real actors")
	app.request_retreat()
	await process_frame
	await app.return_to_world()
	app.queue_free()
	await process_frame
	await process_frame
	await _check_summoned_species()
	print("DELIVERY_APPLICATION_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func _check_summoned_species() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var host := preload("res://Scripts/Application/BattleHost.gd").new()
	host.delivery_settings = preload("res://Resources/Application/FrontierDeliveryBattle.tres")
	host.delivery_request = {"battle_map_id":"battle_wolf_savanna","enemy_config_id":"wolf_clear_team","deployment_id":""}
	viewport.add_child(host)
	var records: Array = []
	var factory = preload("res://Scripts/Application/CreatureFactory.gd")
	for species: String in factory.SUMMON_POOL:
		var record: Dictionary = factory.template(species)
		record.merge({"id":"pool_"+species,"position":"team","traits":[]},true)
		records.append(record)
	check(await host.deploy(records,"summon_pool"),"All five summoned species deploy into a real battlefield")
	check(host.start_combat(),"Explicitly finish deployment before testing combat")
	check(host.actors.size()==6,"Five allies and configured enemy spawn")
	host.ended = true
	for actor: Node3D in host.actors:
		check(not actor.generate_on_ready and not actor.get_node("NPCStateMachine3D")._available_attacks().is_empty(),"Saved creature has usable AI attack modules: "+str(actor.name))
	for tick: int in 60: await physics_frame
	for actor: Node3D in host.actors:
		if actor.get_meta(&"creature_instance_id")=="pool_spider":
			var support: Dictionary = actor.get_node("GeneratedLegStepMovementController3D").get_stance_support_diagnostics().spider_independent_support
			check(support.enabled and not support.torsos.is_empty(),"Spider support resolves the isolated battle physics world")
		for body: Node in actor.find_children("*","RigidBody3D",true,false):
			check(body.global_position.is_finite() and body.linear_velocity.is_finite(),"Activated summoned physics remains finite")
	host.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	viewport.queue_free()
	await process_frame
	await process_frame
