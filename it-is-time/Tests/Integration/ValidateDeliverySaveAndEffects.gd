extends SceneTree
const SESSION = preload("res://Scripts/Application/GameSession.gd")
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const RUNTIME = preload("res://Modules/FrontierDelivery/Scripts/Map/WorldMapRuntime.gd")
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
var failed := false
class FlightStub extends Node:
	func is_airborne() -> bool: return true
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("SAVE_EFFECT_CHECK ",ok," ",message)
	if not ok: failed=true; push_error(message)
func run() -> void:
	var session := SESSION.new()
	session.save_path = "res://Tests/.runtime/integration/migration_"+str(Time.get_ticks_usec())+".json"
	preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(session)
	session.data.schema_version = 1
	var old := WorldMapRuntimeState.new()
	old.map_id = &"frontier"
	session.data.worlds["frontier"] = old.to_dict()
	check(session.save(),"Write a real v1 fixture: "+session.last_error)
	var old_text := FileAccess.get_file_as_string(session.save_path)
	var migrated := SESSION.new()
	migrated.save_path = session.save_path
	check(migrated.load_save() and migrated.data.schema_version==2,"v1 migrates to v2")
	check(migrated.data.monsters==JSON.parse_string(old_text).monsters and migrated.data.magic==session.data.magic,"Migration preserves identity, physics poses and economy")
	check(migrated.data.worlds.frontier.backend=="legacy_frontier","Legacy map retained with backend tag")
	check(migrated.save() and FileAccess.get_file_as_string(session.save_path+".pre_delivery_v2.bak")==old_text,"First v2 save keeps exact original backup")
	var runtime := RUNTIME.new()
	check(runtime.opening_locked(),"Empty inventory remains inside the opening area")
	check(not runtime.object_visible(CATALOG.location("layout_wolf_den_001")),"Undiscovered wolf den stays hidden")
	check(runtime.object_visible(CATALOG.location("layout_sargate_city")) and not runtime.interaction_error(CATALOG.location("layout_sargate_city")).is_empty(),"Known city remains visible but cannot be visited remotely")
	var gate := CATALOG.location("wizard_wolf_gate_rock")
	var near := CATALOG.v(gate.position)+Vector2(0,40)
	runtime.data.player = [near.x,near.y]
	runtime._record(near,near)
	check(not runtime.destroy_obstacle(gate.id),"Breaking gate requires an owned creature")
	runtime.party_count = 1
	check(runtime.destroy_obstacle(gate.id) and runtime.entry_unblocked(CATALOG.location("layout_forest_wolf_den_002")),"Breaking gate unlocks the linked wolf entrance")
	check(migrated.save_delivery_world(runtime.snapshot()) and migrated.data.worlds.size()==2,"New exploration coexists with legacy progress")
	var gate_reload := SESSION.new()
	gate_reload.save_path = migrated.save_path
	check(gate_reload.load_save() and gate.id in gate_reload.delivery_snapshot().destroyed,"Destroyed gate survives restart")
	var camp := {}
	for object: Dictionary in CATALOG.world().objects:
		if object.type=="camp" and "wolf" in str(object.get("enemy_config_id","")): camp=object; break
	runtime.data.player = camp.position.duplicate()
	var request := runtime.begin_battle(camp.id,"encounter",["test_human"])
	check(migrated.save_delivery_world(runtime.snapshot(),request),"Request and party persist together")
	var restart := SESSION.new()
	restart.save_path = migrated.save_path
	check(restart.load_save() and restart.delivery_snapshot().active_battle.request_id==request.request_id,"Restart retains the same pending request ID")
	var result := {"battle_id":request.request_id,"request_id":request.request_id,"outcome":"victory","reward":20,"parts":{}}
	check(runtime.complete_battle(result) and migrated.commit_battle(result,runtime.snapshot()),"Encounter receipt commits")
	check(camp.id not in migrated.delivery_snapshot().cleared,"Encounter victory does not permanently clear camp")
	var invalid := migrated.data.duplicate(true)
	invalid.worlds.frontier_layout.active_battle = request
	check(not migrated._valid_save(invalid),"Second persistent battle ledger is rejected")
	var settings = preload("res://Resources/Application/FrontierDeliveryBattle.tres")
	for id: String in settings.enemy_rosters:
		if "rat_" in id: check(not settings.availability_error(id).is_empty(),"Rat combat blocked: "+id)
	var host := preload("res://Scripts/Application/BattleHost.gd").new()
	host.delivery_settings = settings
	host.delivery_request = {"battle_map_id":"battle_bandit_camp","enemy_config_id":"bandit_clear_team","deployment_id":""}
	root.add_child(host)
	var adapter := preload("res://Scripts/Application/DeliveryBattleEnvironmentAdapter.gd").new()
	check(adapter.build(host,[FACTORY.template("human")]),"Effect test environment builds")
	host.add_child(host._geometry)
	var record := FACTORY.template("human")
	record.id = "effects_human"
	var actor := FACTORY.spawn(record,host,Vector3(-64,1,50),0)
	host.actors.append(actor)
	var effects := preload("res://Scripts/Application/BattleEnvironmentEffects3D.gd").new()
	effects.configure(host,adapter.layout,adapter.scale)
	host.add_child(effects)
	var bodies := actor.find_children("*","PhysicalBodyPart3D",true,false)
	var slow := {}
	var hazard := {}
	for zone: Dictionary in effects.zones:
		if zone.object.type=="thorns": slow=zone
		if zone.object.type=="collision_damage": hazard=zone
	check(not slow.is_empty() and not hazard.is_empty(),"Slow and collision regions bind")
	effects._entered(slow,bodies[0])
	effects._entered(slow,bodies[1])
	effects._physics_process(0.1)
	check(is_equal_approx(effects.multipliers[actor],0.7),"Multiple body contacts apply one 30% slow")
	for resource: Resource in effects.speeds[actor]: check(is_equal_approx(resource.target_speed,effects.speeds[actor][resource]*0.7),"Per-instance motion resource receives slow")
	effects._exited(slow,bodies[0])
	effects._physics_process(0.1)
	check(is_equal_approx(effects.multipliers[actor],0.7),"One part leaving does not clear another part's slow")
	effects._exited(slow,bodies[1])
	effects._physics_process(0.1)
	check(is_equal_approx(effects.multipliers[actor],1.0),"Final exit restores original movement speed")
	var part: PhysicalBodyPart3D = bodies[0]
	var hp := part.current_hp
	effects._entered(hazard,part)
	hazard.next_tick = 0.0
	effects._physics_process(0.1)
	check(is_equal_approx(part.current_hp,hp),"Source zero-damage obstacle does not invent HP loss")
	effects._apply_impact(part,20.0,(part.armor+0.1)/float(root.get_node("DamageService").calculate_raw_damage(20.0)))
	check(part.current_hp<hp,"Configured environment damage uses HP and armor entry points")
	var flight := FlightStub.new()
	flight.name = "BirdFlightController3D"
	actor.add_child(flight)
	check(effects.flying(actor),"Flying targeting reads actual flight state")
	check(not effects._eligible(actor,{"type":"mud","targets":"ground"}),"Ground slow excludes flying creatures")
	check(effects._eligible(actor,{"type":"web","targets":"flying","min_height":0.0,"max_height":100.0}),"Web accepts flying creatures within configured height")
	check(not effects._eligible(actor,{"type":"web","targets":"flying","min_height":100.0,"max_height":101.0}),"Web rejects creatures outside height interval")
	host.queue_free()
	await process_frame
	await process_frame
	print("DELIVERY_SAVE_EFFECTS_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
