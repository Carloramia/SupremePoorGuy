extends SceneTree
const SETTINGS = preload("res://Scripts/Application/BattleCapacitySettings.gd")
const SESSION = preload("res://Scripts/Application/GameSession.gd")
const HOST = preload("res://Scripts/Application/BattleHost.gd")
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
var failed := false

func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("BATTLE_CAPACITY_TIMEOUT"); quit(1))
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("CAPACITY_CHECK ",ok," ",message)
	if not ok: failed = true; push_error(message)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	root.size = Vector2i(1280,720)
	var settings := SETTINGS.new()
	check(settings.total_capacity == 30 and load("res://Resources/Application/DefaultBattleCapacity.tres").total_capacity == 30,"Both faction budgets default to 30 in script and preset")
	check(settings.creature_cost({"definition_id":"snake"}) == 12 and load("res://Resources/Application/DefaultBattleCapacity.tres").creature_cost({"definition_id":"snake"}) == 12,"Snake costs 12 in script and preset")
	check(settings.evaluate(["horned_beast","horned_beast","horned_beast"]).error.is_empty(),"Three horned beasts exactly fit the default 30")
	check(not settings.evaluate(["horned_beast","horned_beast","horned_beast","horned_beast"]).error.is_empty(),"Four horned beasts exceed 30 despite fitting party slots")
	check(settings.initial_roster([{"definition_id":"snake"},{"definition_id":"snake"},{"definition_id":"wolf"},{"definition_id":"wolf"}]).records.size() == 3,"Two Snakes and one Wolf use 30; excess units remain in reserve")
	settings.total_capacity = 12
	var wolf := {"definition_id":"wolf"}
	var status := settings.evaluate([wolf,wolf])
	check(status.used == 12 and status.remaining == 0 and status.error.is_empty(),"Friendly party at exact limit allowed")
	check(settings.evaluate([wolf,wolf,wolf,wolf,wolf]).used == 30,"Each friendly individual consumes capacity, including grouped summons")
	settings.total_capacity = 11
	check(not settings.evaluate([wolf,wolf]).error.is_empty(),"One point over friendly limit rejected")
	check(not settings.evaluate([{"definition_id":"unknown"}]).error.is_empty(),"Unconfigured friendly creature fails closed")
	settings.creature_costs.wolf = 0
	check(not settings.evaluate([wolf]).error.is_empty(),"Zero friendly cost rejected")
	settings.creature_costs.wolf = -1
	check(not settings.evaluate([wolf]).error.is_empty(),"Negative friendly cost rejected")
	settings.creature_costs.wolf = 6
	settings.total_capacity = 0
	check(not settings.evaluate([]).error.is_empty(),"Invalid limit rejected")
	check("友方" in settings.summary({"used":12,"limit":12,"allies":12,"remaining":0}),"Capacity messages describe allies only")
	settings.total_capacity = 5
	var host := HOST.new()
	host.capacity_settings = settings
	host.enemy_definitions.assign(["wolf"])
	check(not await host.deploy([wolf],"over_budget"),"Direct deployment cannot bypass cap")
	check(host.actors.is_empty() and host.get_child_count() == 0,"Rejected deployment creates no physical actors or navigation")
	host.definition = SceneDefinition.new()
	check(not await host.deploy([wolf],"authored_over_budget") and host.get_child_count() == 0,"Authored battle also rejects overbudget allies before loading geometry")
	host.free()
	var session := SESSION.new()
	session.reset()
	session.save_path = "res://Tests/.runtime/integration/capacity_"+str(Time.get_ticks_usec())+".json"
	session.battle_capacity_settings = settings
	var unit := FACTORY.template("human")
	unit.merge({"id":"capacity_human","position":"warehouse","traits":[]},true)
	session.data.monsters.append(unit)
	settings.total_capacity = 3
	check(session.can_join(unit.id) and session.move_monster(unit.id,"team"),"Preparing a party is independent of deployed capacity")
	check(not session.initial_party_capacity().error.is_empty(),"A battle still requires at least one affordable initial unit")
	settings.total_capacity = 4
	check(session.move_monster(unit.id,"team"),"Exact-cap party transfer succeeds")
	var loaded := SESSION.new()
	loaded.save_path = session.save_path
	loaded.battle_capacity_settings = settings
	check(loaded.load_save() and loaded.party_capacity().used == 4,"Existing record format loads without migration or new saved fields")
	settings.total_capacity = 1
	check(loaded.load_save() and not loaded.party_capacity().error.is_empty(),"Reducing cap preserves an existing overbudget save")
	check(loaded.move_monster(unit.id,"warehouse"),"Overbudget party can always remove creatures")
	await _application_flow()
	print("BATTLE_CAPACITY_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func _application_flow() -> void:
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.use_hex_map_for_new_games = false
	app.save_path = "res://Tests/.runtime/integration/capacity_app_"+str(Time.get_ticks_usec())+".json"
	app.display_settings_path = "res://Tests/.runtime/integration/capacity_display.cfg"
	app.battle_capacity_settings = load("res://Resources/Application/DefaultBattleCapacity.tres").duplicate(true)
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	app.start_new_game()
	for tick: int in 600:
		if app.phase == "world": break
		await physics_frame
	check(app.phase == "world","World initialized")
	if app.phase != "world": app.free(); return
	app.ui._close_all()
	preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(app.session)
	app.ui._warehouse("team")
	check(app.ui.warehouse_page.get_node("%DetailBody").has_node("CreatureCapacity"),"Warehouse creature detail displays capacity cost")
	if DisplayServer.get_name() != "headless":
		for tick: int in 3: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/GameJamWorkspace/RuntimeChecks/BattleCapacity_20261019/warehouse.png")
	app.ui._close_all()
	var catalog = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
	var selected := {}
	for location: Dictionary in catalog.world().objects:
		if location.type == "camp" and "wolf" in str(location.get("enemy_config_id","")):
			selected = location; break
	check(not selected.is_empty(),"Battle fixture available")
	if selected.is_empty(): app.free(); return
	var map = app.delivery_map
	map.runtime.data.player = selected.position.duplicate()
	map.runtime.data.discovered.append(selected.id)
	var budget: Dictionary = map.capacity_status(selected.id,"clear")
	app.battle_capacity_settings.total_capacity = budget.used - 1
	var snapshot: Dictionary = map.runtime.snapshot().duplicate(true)
	check(not map.begin_battle(selected.id,"clear"),"Map rejects an overbudget friendly party")
	check(map.runtime.snapshot() == snapshot and app.session.data.battle.is_empty() and app.battle == null,"Rejected entry leaves map, pending battle and actors unchanged")
	app.ui._close_all()
	app.battle_capacity_settings.total_capacity = 30
	check(map.begin_battle(selected.id,"clear"),"Normal capacity enters battle with independent enemy validation")
	for tick: int in 900:
		if app.phase == "deployment": break
		await physics_frame
	check(app.phase == "deployment","Deployment completed")
	if app.phase == "deployment":
		var actual: Dictionary = app.battle.capacity_status()
		check(actual.used == budget.used and actual.remaining == actual.limit-budget.used,"Spawned roster matches entry budget")
		check(app.battle.capacity_status(1).used <= actual.limit,"Enemy deployed roster also respects capacity")
		check(app.battle.reserve_records(1).size()+app.battle._enemy_initial.size()==app.battle.enemy_definitions.size(),"All unplaced enemies remain in reserve")
		app.refresh_input_gate()
		check(app.ui.capacity_hint.visible and "友方" in app.ui.capacity_hint.text and "敌方" in app.ui.capacity_hint.text,"Deployment displays both faction budgets")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/GameJamWorkspace/RuntimeChecks/BattleCapacity_20261019/deployment.png")
		app.battle_capacity_settings.total_capacity = budget.used-1
		app.refresh_input_gate()
		check(app.ui.start_battle_button.disabled and not app.battle.start_combat(),"Combat start revalidates capacity")
		app.battle_capacity_settings.total_capacity = budget.used
		app.refresh_input_gate()
		check(app.battle.capacity_status().error.is_empty() and app.ui.start_battle_button.disabled and not app.battle.start_combat(),"Enemy over-cap deployment also blocks combat start")
		app.battle_capacity_settings.total_capacity = 30
		app.start_battle()
		check(app.phase == "battle","Valid deployment starts combat")
	app.queue_free()
	await process_frame
	await process_frame
