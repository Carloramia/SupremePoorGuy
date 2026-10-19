extends SceneTree

const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const HOST = preload("res://Scripts/Application/BattleHost.gd")
const SETTINGS = preload("res://Scripts/Application/BattleCapacitySettings.gd")
const SESSION = preload("res://Scripts/Application/GameSession.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(150,true,false,true).timeout.connect(func(): push_error("REINFORCEMENTS_TIMEOUT"); quit(1))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	print("REINFORCEMENT_CHECK ",ok," ",message)
	if not ok: failures.append(message)

func frames(count: int = 3) -> void:
	for frame: int in count: await process_frame

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("D:/GameJamWorkspace/RuntimeChecks/BattleReinforcements_20261019/"+name+".png")

func creature(species: String, id: String, position: String = "team") -> Dictionary:
	var record := FACTORY.template(species)
	record.merge({"id":id,"position":position,"traits":[]},true)
	return record

func freeze_actors(host: Node3D) -> void:
	for actor: Node3D in host.actors:
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		for body: RigidBody3D in actor.find_children("*","RigidBody3D",true,false):
			body.freeze = true
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO

func kill(actor: Node3D) -> void:
	for part: PhysicalBodyPart3D in actor.find_children("*","PhysicalBodyPart3D",true,false):
		if 3 in part.tags and not part.is_broken: part.apply_damage(part.current_hp+1.0)
	await frames(2)
	check(not actor.is_combat_alive(),"Real head destruction marks the creature dead")

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	root.size = Vector2i(1280,720)
	var settings := SETTINGS.new()
	var roster: Array = []
	for index: int in 6: roster.append(creature("horned_beast","horn_"+str(index)))
	var initial: Dictionary = settings.initial_roster(roster)
	check(initial.error.is_empty() and initial.records.size()==3 and settings.evaluate(initial.records).used==30,"Initial roster caps each side at 30 and leaves excess in reserve")
	check(not settings.initial_roster([{"definition_id":"unknown"}]).error.is_empty(),"Unknown capacity fails closed")
	await _enemy_reserves()
	await _player_flow()
	await _hex_flow()
	FACTORY._release_presentation_parts()
	for message: String in failures: push_error(message)
	print("BATTLE_REINFORCEMENTS_CHECKS ",checks," failures=",failures.size())
	call_deferred("quit",0 if failures.is_empty() else 1)

func _enemy_reserves() -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	root.add_child(viewport)
	var host := HOST.new()
	host.capacity_settings = SETTINGS.new()
	host.capacity_settings.total_capacity = 12
	host.enemy_definitions.assign(["human","human","human","human"])
	viewport.add_child(host)
	check(await host.deploy([creature("wolf","ally_wolf")],"enemy_reserve_test"),"Battle with over-cap enemy roster loads")
	check(host.capacity_status(1).used==12 and host.reserve_records(1).size()==1 and host.actors.size()==4,"Only affordable enemies are physically instantiated")
	check(host.start_combat(),"Enemy reserve fixture starts")
	host.set_physics_process(false)
	freeze_actors(host)
	await physics_frame
	var victim: Node3D = host.actors[1]
	await kill(victim)
	host._physics_process(3.1)
	check(not host.ended and host.reserve_records(1).is_empty() and host.actors.size()==5,"Enemy death releases capacity and automatic reinforcement enters")
	check(host.capacity_status(1).used==12,"Enemy replacement never exceeds its independent budget")
	freeze_actors(host)
	var outcome: Array = []
	host.finished.connect(func(result): outcome.append(result.outcome))
	for actor: Node3D in host.actors:
		if actor.get_faction_id()==1 and actor.is_combat_alive(): await kill(actor)
	host._physics_process(0.1)
	check(outcome==["victory"],"Victory waits until enemies and their reserves are exhausted")
	viewport.queue_free()
	await frames()

func _player_flow() -> void:
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.use_delivery_map = false
	app.use_hex_map_for_new_games = false
	app.save_path = "res://Tests/.runtime/integration/reinforcement_"+str(Time.get_ticks_usec())+".json"
	app.display_settings_path = "res://Tests/.runtime/integration/reinforcement_display.cfg"
	app.battle_capacity_settings = SETTINGS.new()
	app.battle_capacity_settings.total_capacity = 10
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	app.start_new_game()
	for tick: int in 600:
		if app.phase=="world": break
		await physics_frame
	check(app.phase=="world","Real application starts on the world map")
	if app.phase!="world": app.queue_free(); return
	app.ui._close_all()
	app.session.data.monsters.assign([creature("human","first"),creature("wolf","warehouse_wolf","warehouse"),creature("human","warehouse_human","warehouse")])
	check(app.session.save(),"Isolated party and warehouse save succeeds")
	var location: WorldMapLocation = app.world_map.get_location(&"bandits")
	location.state.discovered = true
	app.world_map.player.global_position = location.interaction_point()
	check(app.world_map.interaction.begin(location),"Real battle entrance opens")
	app.world_map.interaction.request_battle()
	for tick: int in 600:
		if app.phase=="deployment": break
		await physics_frame
	check(app.phase=="deployment","Initial deployment loads")
	if app.phase!="deployment": app.queue_free(); return
	app.start_battle()
	var host: Node3D = app.battle
	host.set_physics_process(false)
	freeze_actors(host)
	await frames()
	check(app.ui.reinforcement_button.visible and host.reserve_records().size()==2,"Extra button offers undeployed warehouse creatures")
	app.ui.reinforcement_button.pressed.emit()
	check(paused and app.ui.overlay.visible,"Opening reserves pauses combat")
	await frames()
	await capture("reserves")
	var pick := app.ui.modal_box.find_child("Reserve_warehouse_wolf",true,false) as Button
	check(pick!=null and not pick.disabled,"Warehouse creature within remaining budget is selectable")
	if pick==null: app.free(); return
	pick.pressed.emit()
	await frames()
	check(app.phase=="reinforcement" and paused and host.reinforcing and not app.ui.overlay.visible,"Selection enters paused placement with active terrain cursor")
	check(host.cursor.can_process() and host.camera.can_process() and host.deployment.can_process(),"Placement cursor, camera and placement controller work while combat is paused")
	check(not host.deployment.pick_up(host.actors[0]),"Reinforcements cannot reposition existing combatants")
	check(host.capacity_status().used==4,"Unconfirmed preview does not consume capacity")
	check(host.deployment.place_dragged(),"Reinforcement can be placed at a legal ground point: "+host.deployment.placement_error)
	await frames()
	await capture("placement")
	app.ui.confirm_reinforcement_button.pressed.emit()
	check(app.phase=="battle" and not paused and host.capacity_status().used==10,"Confirm resumes combat and charges deployed capacity exactly once")
	if app.phase!="battle": app.free(); return
	check(host.reserve_records().size()==1 and host.reserve_records()[0].id=="warehouse_human","An already deployed warehouse creature cannot be called twice")
	check("warehouse_wolf" in app.session.data.battle.party_ids,"Warehouse deployment is saved as a battle participant")
	check(not host.begin_reinforcement("warehouse_human") and not host.reinforcing,"Player cannot bypass the live capacity cap")
	freeze_actors(host)
	await frames()
	var warehouse_actor: Node3D = host.actors.back()
	warehouse_actor.set_temporary_ragdoll(app,true)
	host.elapsed = 1.0
	host._physics_process(0.1)
	check(host.capacity_status().used==10 and not app.session.monster_by_id("warehouse_wolf").is_empty(),"Temporary ragdoll does not release capacity or permanently remove a living unit")
	warehouse_actor.set_temporary_ragdoll(app,false)
	# A failed death save must stop the battle without mutating inventory or losing the retry.
	var good_path: String = app.session.save_path
	var blocked: String = "res://Tests/.runtime/integration/death_write_blocked_"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked+".tmp"))
	app.session.save_path = blocked
	await kill(host.actors[0])
	host.elapsed = 1.0
	host._physics_process(0.1)
	check(paused and app._pause_reasons.has(&"battle_save") and not app.session.monster_by_id("first").is_empty(),"Failed permanent-death save rolls back inventory and pauses combat")
	app.ui._close_modal()
	check(app.ui.overlay.visible,"Mandatory death-save retry cannot be dismissed")
	app.session.save_path = good_path
	var retry := app.ui.modal_box.find_child("RetryBattleDeathSave",true,false) as Button
	check(retry!=null,"Death-save error provides an actual retry button")
	if retry!=null: retry.pressed.emit()
	check(not paused and app.session.monster_by_id("first").is_empty() and host.capacity_status().used==6,"Retry permanently removes the dead team member and releases capacity")
	var loaded := SESSION.new()
	loaded.save_path = good_path
	check(loaded.load_save() and loaded.monster_by_id("first").is_empty() and "first" in loaded.data.battle.casualties,"Reloading a mid-battle save preserves permanent death")
	var after_death: Dictionary = app.session.data.duplicate(true)
	check(app.session.record_battle_deaths(host.battle_id,["first"]) and app.session.data==after_death,"Repeated death notification is idempotent")
	check(not app.session.record_battle_deaths(host.battle_id,["warehouse_human"]) and app.session.data==after_death,"Undeployed warehouse creatures cannot be removed by a death receipt")
	app.set_pause_reason(&"manual",true)
	app.open_reinforcements()
	app.begin_reinforcement("warehouse_human")
	await frames()
	check(app.phase=="reinforcement","Freed capacity permits another warehouse preview")
	app.ui.cancel_reinforcement_button.pressed.emit()
	await frames()
	check(app.phase=="battle" and paused and app.is_battle_manually_paused() and host.capacity_status().used==6 and not app.session.monster_by_id("warehouse_human").is_empty(),"Cancelling a preview preserves inventory, capacity and the original manual pause")
	app.set_pause_reason(&"manual",false)
	var wolf: Node3D
	for actor: Node3D in host.actors:
		if actor.get_meta(&"creature_instance_id","")=="warehouse_wolf": wolf=actor
	await kill(wolf)
	host._physics_process(0.1)
	await frames()
	check(not host.ended and app.ui.overlay.visible and paused,"All deployed allies dead automatically opens reserves instead of ending the battle")
	check(app.session.monster_by_id("warehouse_wolf").is_empty(),"Death also permanently removes a deployed warehouse creature")
	check(host.reserve_records().size()==1,"Untouched warehouse creatures remain available")
	check(not app.session.recycle_monster("first"),"Dead creature cannot be recycled back into resources")
	app.request_retreat()
	check(app.phase=="settlement" and app.session.data.battle.result.casualties.size()==2,"Settlement records both permanent losses")
	check(loaded.load_save() and loaded.monsters().size()==1,"Settlement save keeps only the surviving warehouse creature")
	app.queue_free()
	await frames()

func _hex_flow() -> void:
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.save_path = "res://Tests/.runtime/integration/hex_reinforcement_"+str(Time.get_ticks_usec())+".json"
	app.display_settings_path = "res://Tests/.runtime/integration/reinforcement_display.cfg"
	app.battle_capacity_settings = SETTINGS.new()
	app.battle_capacity_settings.total_capacity = 10
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	app.start_new_game()
	for tick: int in 600:
		if app.phase=="world": break
		await physics_frame
	preload("res://Tests/Integration/ApplicationFixtures.gd").complete_opening(app)
	app.session.data.monsters.assign([creature("human","hex_first"),creature("wolf","hex_warehouse","warehouse")])
	check(app.session.save(),"Hex-map party and warehouse fixture saved")
	var catalog = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
	for camp: Dictionary in catalog.world().objects:
		if camp.type=="camp" and "wolf" in str(camp.get("enemy_config_id","")) and app.get_delivery_battle_settings().availability_error(camp.enemy_config_id).is_empty():
			app.delivery_map.runtime.data.player = camp.position.duplicate()
			app.delivery_map.runtime.data.discovered.append(camp.id)
			check(app.delivery_map.begin_battle(camp.id,"clear"),"Production hex-map battle entry accepts capacity-limited enemies")
			break
	for tick: int in 900:
		if app.phase=="deployment": break
		await physics_frame
	check(app.phase=="deployment","Production map reaches deployment")
	if app.phase!="deployment": app.queue_free(); await frames(); return
	app.start_battle()
	var host: Node3D = app.battle
	host.set_physics_process(false)
	freeze_actors(host)
	app.open_reinforcements()
	app.begin_reinforcement("hex_warehouse")
	await frames()
	check(app.phase=="reinforcement" and host.deployment.place_dragged(),"Warehouse reinforcement fits the production map and hazard checks")
	app.confirm_reinforcement()
	check(app.phase=="battle" and host.capacity_status().used==10,"Production-map reinforcement commits and respects capacity")
	if app.phase=="battle":
		freeze_actors(host)
		await kill(host.actors.back())
		check(host.flush_deaths(),"Permanent death saves against the hex-map battle snapshot")
		var loaded := SESSION.new()
		loaded.save_path = app.save_path
		check(loaded.load_save() and loaded.monster_by_id("hex_warehouse").is_empty() and loaded.data.delivery_map_version=="20261019","Production-map reload preserves the warehouse casualty")
	host.ended = true
	app.queue_free()
	await frames()
