extends SceneTree
const SESSION = preload("res://Scripts/Application/GameSession.gd")
const SERVICE = preload("res://Scripts/Events/StoryService.gd")
const CATALOG = preload("res://Scripts/Events/StoryCatalog.gd")
const ROOT_SCENE = preload("res://Scenes/Application/GameRoot.tscn")
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const MAPS = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
const RUNTIME = preload("res://Modules/FrontierDelivery/Scripts/Map/WorldMapRuntime.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(90).timeout.connect(func():push_error("STORY_TIMEOUT");quit(1))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("STORY_FAIL: "+label)

func fresh():
	var session := SESSION.new()
	session.save_path="res://Tests/.runtime/story/session_%d.json" % Time.get_ticks_usec()
	session.data.delivery_map_version="20261019"
	MAPS.select_version("20261019")
	check(session.save_delivery_world(RUNTIME.new().snapshot()),"Isolated session saves")
	return session

func binding(id: String, role: String = "") -> Dictionary:
	for row: Dictionary in CATALOG.bindings(id):
		if role.is_empty() or row.entry_role==role: return row
	check(false,"Missing binding "+id+":"+role)
	return {}

func read_dialogue(session, id: String) -> void:
	for step: int in 40:
		var current := SERVICE.entry(session.data,id)
		if CATALOG.definition(id).nodes[current.node].type!="dialogue": return
		if not session.advance_story_event(id,"next",int(current.revision)):
			check(false,"Read dialogue "+id+": "+session.last_error)
			return
	check(false,"Dialogue loop "+id)

func act(session, id: String, choice: String, selected: Array = []) -> bool:
	return session.advance_story_event(id,choice,int(SERVICE.entry(session.data,id).revision),selected)

func unit(id: String, species: String = "wolf", position: String = "warehouse", facts: Dictionary = {}) -> Dictionary:
	var record := FACTORY.template(species)
	record.merge({"id":id,"position":position,"traits":[],"event_traits":facts},true)
	return record

func press(ui: Node, label: String) -> bool:
	for button: Node in ui.find_children("*","Button",true,false):
		if button.is_visible_in_tree() and button.text==label and not button.disabled:
			button.pressed.emit()
			return true
	return false

func finish_dialogue_ui(app: Node, id: String) -> void:
	for step: int in 40:
		var current := SERVICE.entry(app.session.data,id)
		if CATALOG.definition(id).nodes[current.node].type!="dialogue": return
		if not press(app.ui,"继续") and not press(app.ui,"阅读完成"): check(false,"Visible dialogue button "+id); return

func settle(session, outcome: String) -> bool:
	var runtime := RUNTIME.new(session.delivery_snapshot())
	var request: Dictionary = session.data.battle
	var result := {"battle_id":request.battle_id,"request_id":request.battle_id,"outcome":outcome,"reward":0,"parts":{},"combat_mode":request.get("combat_mode","party")}
	if not runtime.complete_battle(result): return false
	if not session.commit_battle(result,runtime.snapshot()): return false
	session.data.battle={}
	return session.save()

func session_checks() -> void:
	var s = fresh()
	check(SERVICE.entry(s.data,SERVICE.OPENING).is_empty(),"Existing/ordinary sessions do not invent opening progress")
	check(s.open_story_event(SERVICE.LIBRARY,binding(SERVICE.LIBRARY)),"Library opens from registered city binding")
	read_dialogue(s,SERVICE.LIBRARY)
	var revision: int = SERVICE.entry(s.data,SERVICE.LIBRARY).revision
	var before: Dictionary = s.data.duplicate(true)
	var path: String = s.save_path
	s.save_path=path+"/blocked.json"
	check(not act(s,SERVICE.LIBRARY,"confirm") and s.data==before,"Failed library save rolls reward and progress back atomically")
	s.save_path=path
	check(act(s,SERVICE.LIBRARY,"confirm") and s.data.known_runes==["health","attack","armor"],"Library uses current two-rune reward; life stays initial")
	check(not s.advance_story_event(SERVICE.LIBRARY,"confirm",revision),"Stale reward click rejected")
	s.story_parameters=CATALOG.parameters().duplicate(true)
	s.story_parameters[SERVICE.LIBRARY].private_money_magic=null
	check(not act(s,SERVICE.LIBRARY,"aid"),"Deliberately unconfigured aid fixture blocks only its own action")
	var loaded := SESSION.new()
	loaded.save_path=path
	check(loaded.load_save() and SERVICE.entry(loaded.data,SERVICE.LIBRARY).node=="aid" and loaded.data.known_runes.has("armor"),"Load resumes after committed rune grant without reroll")
	for roles: Array in [["donkey","merchant"],["merchant","donkey"]]:
		s=fresh()
		var id := "QST_GRASS_007"
		check(s.open_story_event(id,binding(id,roles[0])),"First donkey/merchant visit")
		check(SERVICE.entry(s.data,id).node==roles[0],"First entry shows the correct merchant/donkey paragraph")
		read_dialogue(s,id)
		check(not act(s,id,"from_"+str(roles[0])),"Cannot return until both seen")
		check(s.open_story_event(id,binding(id,roles[1])),"Second donkey/merchant visit")
		read_dialogue(s,id)
		check(act(s,id,"from_"+str(roles[1])),"Either discovery order reaches same return dialogue")
		read_dialogue(s,id)
		check(act(s,id,"confirm") and s.data.known_relics==["taunt-bell","propaganda-banner"],"Return gifts once without escort")
		check(not s.open_story_event(id,binding(id,roles[0])),"Completed shared event cannot regrant")
	s=fresh()
	check(s.open_story_event(SERVICE.ENGINE,binding(SERVICE.ENGINE)),"Engine merchant opens")
	read_dialogue(s,SERVICE.ENGINE)
	s.data.magic=99
	check(not act(s,SERVICE.ENGINE,"buy") and s.data.array_stage==1 and s.data.magic==99,"99 magic cannot buy engine")
	s.data.magic=100
	before=s.data.duplicate(true)
	path=s.save_path
	s.save_path=path+"/blocked.json"
	check(not act(s,SERVICE.ENGINE,"buy") and s.data==before,"Engine save failure rolls clock, ownership, upgrade and payment together")
	s.save_path=path
	check(act(s,SERVICE.ENGINE,"buy") and s.data.magic==0 and s.data.array_stage==2,"100 magic buys exactly one ring")
	check(not SERVICE.due(s.data),"Ghost not immediately due")
	var due_time: float = SERVICE.entry(s.data,SERVICE.ENGINE).flags.ghost_due_minutes
	s.data.world_time.total_minutes=due_time-1
	check(not SERVICE.due(s.data),"Ghost not due one minute before four days")
	s.data.world_time.total_minutes=due_time+1440
	check(SERVICE.due(s.data),"Skipping beyond four days still triggers ghost")
	check(s.open_story_event(SERVICE.GHOST,binding(SERVICE.GHOST)),"Due ghost opens")
	read_dialogue(s,SERVICE.GHOST)
	check(act(s,SERVICE.GHOST,"kind"),"Ghost kind branch accepted")
	read_dialogue(s,SERVICE.GHOST)
	check(act(s,SERVICE.GHOST,"confirm") and s.data.known_runes.has("haste") and s.data.known_runes.has("limb-fortitude"),"Ghost gives good-war and tenacious-flesh runes")
	check(not SERVICE.due(s.data),"Completed ghost never retriggers")
	s=fresh()
	s.data.array_stage=4
	s.data.layout.stage=4
	check(s.open_story_event(SERVICE.ENGINE,binding(SERVICE.ENGINE)),"Max-level merchant still has readable dialogue")
	read_dialogue(s,SERVICE.ENGINE)
	check(not act(s,SERVICE.ENGINE,"buy") and s.data.magic==300,"Max-level purchase never charges")
	s=fresh()
	var shell := "QST_GRASS_010"
	s.story_parameters=CATALOG.parameters().duplicate(true)
	s.story_parameters[shell].attack_threshold=100
	s.story_parameters[shell].magic_reward=7
	s.data.monsters=[unit("owned_warehouse")]
	s.data.monsters[0].attack=100
	check(s.open_story_event(shell,binding(shell)),"Shell shrine opens")
	read_dialogue(s,shell)
	check(act(s,shell,"break") and SERVICE.entry(s.data,shell).node=="failure","Equal single attack fails strictly-greater check")
	read_dialogue(s,shell)
	s.data.monsters[0].attack=101
	check(act(s,shell,"break"),"Warehouse unit qualifies without joining team")
	read_dialogue(s,shell)
	s.data.monsters[0].attack=99
	check(not act(s,shell,"confirm"),"Reward rechecks current ownership/stats")
	s.data.monsters[0].attack=101
	check(act(s,shell,"confirm") and s.data.magic==307 and s.data.known_relics==["shell-carving"],"Shell and configured money commit together")
	s=fresh()
	var farm := "QST_GRASS_012"
	check(s.open_story_event(farm,binding(farm,"farm")),"Farm opens")
	read_dialogue(s,farm)
	check(act(s,farm,"ask"),"Farm accepts return-to-city route")
	check(s.open_story_event(farm,binding(farm,"farm")) and SERVICE.entry(s.data,farm).node=="waiting","Revisit preserves locked city route")
	check(s.open_story_event(farm,binding(farm,"return_city_enchanter")) and SERVICE.entry(s.data,farm).node=="enchanter","Registered city stage continues same farm progress")
	read_dialogue(s,farm)
	var magic_before: float = s.data.magic
	check(act(s,farm,"confirm") and SERVICE.entry(s.data,farm).completed and s.data.magic==magic_before+20,"Production enchanter route now pays confirmed twenty and completes")
	sacrifice_checks()
	battle_checks()

func sacrifice_checks() -> void:
	var s = fresh()
	s.story_parameters=CATALOG.parameters().duplicate(true)
	s.story_parameters[SERVICE.ALTAR].first_magic_reward=9
	s.data.monsters=[unit("fur"),unit("fly_a","wolf","warehouse",{"fur":false,"can_fly":true}),unit("fly_b","wolf","warehouse",{"fur":false,"can_fly":true}),unit("snake_a","snake"),unit("snake_b","snake"),unit("snake_c","snake"),unit("keep","human")]
	check(s.open_story_event(SERVICE.ALTAR,binding(SERVICE.ALTAR)),"Altar opens")
	read_dialogue(s,SERVICE.ALTAR)
	var path: String = s.save_path
	var before: Dictionary = s.data.duplicate(true)
	s.save_path=path+"/blocked.json"
	check(not act(s,SERVICE.ALTAR,"first",["fur"]) and s.data==before,"Sacrifice save failure consumes no monster and reveals no next stage")
	s.save_path=path
	check(act(s,SERVICE.ALTAR,"first",["fur"]) and SERVICE.entry(s.data,SERVICE.ALTAR).node=="stage_2" and s.data.magic==309,"First sacrifice consumes one fur and only then reveals second requirement")
	check(not act(s,SERVICE.ALTAR,"second",["fly_a","fly_a"]),"Duplicate sacrifice IDs rejected")
	check(act(s,SERVICE.ALTAR,"second",["fly_a","fly_b"]) and s.data.known_runes.has("burn") and SERVICE.entry(s.data,SERVICE.ALTAR).node=="stage_3","Second sacrifice grants boiling blood before third requirement")
	check(act(s,SERVICE.ALTAR,"third",["snake_a","snake_b","snake_c"]) and s.data.monsters.size()==1 and s.data.known_relics==["blood-crystal"],"Third sacrifice grants blood-red crystal and retains one monster")
	check(not act(s,SERVICE.ALTAR,"third",["snake_a","snake_b","snake_c"]),"Completed sacrifice cannot consume or regrant")

func battle_checks() -> void:
	var s = fresh()
	var id := "QST_GRASS_008"
	s.data.monsters=[unit("party","wolf","team")]
	check(s.open_story_event(id,binding(id)),"Battle event opens")
	read_dialogue(s,id)
	check(not act(s,id,"battle") and s.data.battle.is_empty(),"Missing real enemy config blocks battle, not dialogue")
	s.story_parameters=CATALOG.parameters().duplicate(true)
	s.story_parameters[id].battles.battle={"battle_map_id":"battle_bandit_camp","enemy_config_id":"bandit_clear_team"}
	check(act(s,id,"battle") and s.data.battle.kind=="story","Explicit isolated fixture creates persisted story battle request")
	check(settle(s,"victory"),"Battle receipt routes through runtime and session transaction")
	check(act(s,id,"confirm") and s.data.known_runes.has("giant"),"Only matching victorious story receipt grants giant")
	s=fresh()
	s.story_parameters=CATALOG.parameters().duplicate(true)
	s.story_parameters[SERVICE.BET].rounds=[{"battle_map_id":"battle_bandit_camp","side_a_roster":"bandit_clear_team","side_b_roster":"bandit_clear_team"}].duplicate(true)
	for index: int in 3: s.story_parameters[SERVICE.BET].rounds.append(s.story_parameters[SERVICE.BET].rounds[0].duplicate(true))
	check(s.open_story_event(SERVICE.BET,binding(SERVICE.BET)),"Knight opens")
	read_dialogue(s,SERVICE.BET)
	check(not act(s,SERVICE.BET,"one") and s.data.magic==300,"Unconfirmed loss policy blocks real payment even with filled rosters")
	s.story_parameters[SERVICE.BET].loss_policy="lose_stake" # Test fixture, not production decision.
	for index: int in 4:
		var before_money: float = s.data.magic
		check(act(s,SERVICE.BET,"one") and s.data.battle.party_ids.is_empty(),"Round %d locks two AI rosters with no player inventory" % (index+1))
		check(s.data.magic==before_money-[10,20,50,100][index],"Stake deducted once")
		check(not act(s,SERVICE.BET,"two"),"Outstanding bet cannot switch side or charge twice")
		check(settle(s,"victory" if index<3 else "defeat"),"Actual matching result settles round")
		check(int(SERVICE.entry(s.data,SERVICE.BET).flags.settled_rounds)==index+1,"Only settled result advances round")
		if index<3: check(s.data.magic==before_money+[10,20,50,100][index],"Win returns 2B total, not 3B")
		read_dialogue(s,SERVICE.BET)
	check(act(s,SERVICE.BET,"confirm") and s.data.known_relics==["clockwork-box"],"Fourth-round loss still receives clockwork box")
	check(not s.open_story_event(SERVICE.BET,binding(SERVICE.BET)),"Knight disappears after gift commits")
	# Production missing values remain null; all values below belong only to this fixture.
	s=fresh()
	var budget := "QST_SIDE_002_001"
	s.data.monsters=[unit("guard_party","wolf","team")]
	s.story_parameters=CATALOG.parameters().duplicate(true)
	s.story_parameters[budget].battles.clear={"source_id":"layout_camp_001","battle_map_id":"battle_bandit_camp","enemy_config_id":"bandit_clear_team"}
	var target: Dictionary = CATALOG.bindings(budget,"20261019",s.story_parameters).back()
	check(not s.open_story_event(budget,target),"Budget cannot start at target before accepting commission")
	check(s.open_story_event(budget,binding(budget,"city_center")),"Budget opens at city giver")
	read_dialogue(s,budget)
	check(act(s,budget,"accept") and not act(s,budget,"battle"),"Budget accepts but rejects remote launch from city")
	check(s.open_story_event(budget,target) and act(s,budget,"battle"),"Configured target receives same accepted commission")
	check(settle(s,"victory") and "layout_camp_001" in s.data.worlds.frontier_layout.cleared,"Story clear victory updates real map clear state")
	check(not act(s,budget,"submit"),"Budget reward cannot be taken at battle target")
	check(s.open_story_event(budget,binding(budget,"city_center")) and act(s,budget,"submit"),"Budget requires actual city-stage hand-in")
	read_dialogue(s,budget)
	check(act(s,budget,"confirm") and s.data.known_relics.has("spiral-idol"),"Budget hand-in grants spiral idol from matching victory")
	s=fresh()
	var pickup := "QST_GRASS_006"
	s.data.monsters=[unit("pick_party","wolf","team")]
	s.story_parameters=CATALOG.parameters().duplicate(true)
	s.story_parameters[pickup].pickup_item_id="fixture_item_only"
	s.story_parameters[pickup].battles.battle={"battle_map_id":"battle_bandit_camp","enemy_config_id":"bandit_clear_team"}
	check(s.open_story_event(pickup,binding(pickup)),"Pickup event opens")
	read_dialogue(s,pickup)
	check(act(s,pickup,"confirm") and s.data.event_items.fixture_item_only==1,"Pickup commits before any battle request")
	read_dialogue(s,pickup)
	check(act(s,pickup,"battle") and settle(s,"defeat") and s.data.event_items.fixture_item_only==1,"Defeat never revokes or duplicates previously obtained item")
	check(act(s,pickup,"battle"),"Failed pickup battle can retry without repeating pickup")
	SERVICE.cancel_battle(s.data,s.data.battle)
	s.data.battle={}
	check(s.save() and s.data.event_items.fixture_item_only==1,"Loading failure also preserves committed pickup")
	s=fresh()
	var duel := "QST_GRASS_019"
	s.data.monsters=[unit("duel_player","wolf","team")]
	var reward_path := "res://Tests/.runtime/story/reward_fixture_%d.json" % Time.get_ticks_usec()
	var reward_file := FileAccess.open(reward_path,FileAccess.WRITE)
	reward_file.store_string(JSON.stringify(unit("fixture_preset","wolf")))
	reward_file.close()
	s.story_parameters=CATALOG.parameters().duplicate(true)
	s.story_parameters[duel].battles.wolf={"battle_map_id":"battle_bandit_camp","enemy_config_id":"bandit_clear_team"}
	s.story_parameters[duel].reward_presets.wolf=reward_path
	check(s.open_story_event(duel,binding(duel)),"Duel help branch opens")
	read_dialogue(s,duel)
	check(act(s,duel,"wolf") and s.data.battle.party_ids==["duel_player"],"Help branch deploys only player party, not the helped creature")
	check(settle(s,"victory"),"Duel victory stores its exact reward record")
	s.story_parameters[duel].reward_presets.wolf=null
	check(act(s,duel,"confirm") and s.data.monsters.size()==2 and s.monster_by_id("story_reward_"+duel).position=="warehouse","Frozen reward survives later config edits and enters warehouse without reroll")
	s=fresh()
	s.story_parameters=CATALOG.parameters().duplicate(true)
	s.story_parameters[duel].battles.watch={"battle_map_id":"battle_bandit_camp","side_a_roster":"bandit_clear_team","side_b_roster":"bandit_clear_team"}
	s.story_parameters[duel].watch_magic_reward=17
	check(s.open_story_event(duel,binding(duel)),"Duel observer branch opens")
	read_dialogue(s,duel)
	check(act(s,duel,"watch") and s.data.battle.party_ids.is_empty(),"Duel observer accepts an empty player roster")
	check(settle(s,"defeat") and act(s,duel,"confirm") and s.data.magic==317 and s.data.monsters.is_empty(),"Either actual observer winner settles only configured money, not a monster")

func spectator_ui_check(app: Node) -> void:
	app.ui._close_all()
	app.session.story_parameters=CATALOG.parameters().duplicate(true)
	var fixture := {"battle_map_id":"battle_bandit_camp","side_a_roster":"bandit_clear_team","side_b_roster":"bandit_clear_team"}
	app.session.story_parameters[SERVICE.BET].rounds=[fixture.duplicate(true),fixture.duplicate(true),fixture.duplicate(true),fixture.duplicate(true)]
	app.session.story_parameters[SERVICE.BET].loss_policy="lose_stake"
	var site: Dictionary = MAPS.location(binding(SERVICE.BET).source_id)
	app.delivery_map.runtime.data.player=site.position.duplicate()
	app.delivery_map.runtime._visible_origin=Vector2.INF
	app.delivery_map.runtime._update_hex_visibility()
	check(app.delivery_map.save_progress(),"Spectator fixture position saves")
	app.delivery_map._arrived(site.id,"location")
	check(press(app.ui,CATALOG.title(SERVICE.BET)),"Knight opens through actual location menu")
	finish_dialogue_ui(app,SERVICE.BET)
	check(press(app.ui,"赌就赌，我选怪物1组"),"Native UI submits one bet")
	for frame: int in 900:
		if app.phase in ["battle","world"]: break
		await physics_frame
	check(app.phase=="battle" and is_instance_valid(app.battle),"Two AI rosters auto-start real BattleHost without player deployment")
	if app.phase!="battle" or not is_instance_valid(app.battle): return
	var sides := {0:0,1:0}
	for actor: Node3D in app.battle.actors: sides[actor.get_faction_id()]+=1
	check(sides[0]>0 and sides[1]>0 and app.session.data.monsters.is_empty(),"Both factions have real actors; no player creature is created or deployed")
	check(app.session.data.battle.party_ids.is_empty() and not app.session.data.battle.side_a_definitions_snapshot.is_empty(),"Persisted observer request freezes actual roster definitions")
	for frame: int in 5: await physics_frame
	app.battle.finish("retreat")
	check(app.phase=="settlement" and app.session.data.magic==290,"Interrupted observer fight does not invent a winner or payout")
	app.return_to_world()
	for frame: int in 600:
		if app.phase=="world": break
		await process_frame
	check(app.phase=="world" and SERVICE.entry(app.session.data,SERVICE.BET).node=="unresolved" and int(SERVICE.entry(app.session.data,SERVICE.BET).flags.get("settled_rounds",0))==0,"Interrupted paid bet stays unresolved and never increments round")

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	check(CATALOG.validate().is_empty(),"Native catalogue validates: "+CATALOG.validate())
	var app := ROOT_SCENE.instantiate()
	app.save_path="res://Tests/.runtime/story/app_%d.json" % Time.get_ticks_usec()
	app.display_settings_path=app.save_path+".display.cfg"
	root.add_child(app)
	app.ui.animate_panels=false
	app.start_new_game()
	for frame: int in 600:
		if app.phase=="world" and not app.ui.modal_stack.is_empty(): break
		await process_frame
	check(app.phase=="world" and not app.ui.modal_stack.is_empty() and app.ui.modal_stack.back().kind=="story","Real new-game host opens native opening")
	check(SERVICE.entry(app.session.data,SERVICE.OPENING).node=="intro","Opening starts at authored dialogue")
	var retired_button: Button
	for button: Node in app.ui.find_children("*","Button",true,false):
		if button.is_visible_in_tree() and button.text=="继续": retired_button=button; break
	if is_instance_valid(retired_button):
		retired_button.pressed.emit()
		var after_first: int = SERVICE.entry(app.session.data,SERVICE.OPENING).cursor
		retired_button.pressed.emit()
		check(int(SERVICE.entry(app.session.data,SERVICE.OPENING).cursor)==after_first,"Retired page callback cannot advance a fresh dialogue step")
	else: check(false,"Opening has a live continue button")
	finish_dialogue_ui(app,SERVICE.OPENING)
	check(press(app.ui,"确认签收") and app.session.data.get("event_items",{}).get("king_special_order")==1 and SERVICE.entry(app.session.data,SERVICE.OPENING).completed,"Real opening UI confirms credential without extra reward: "+app.session.last_error)
	app.story_controller.set_process(false)
	var site: Dictionary = MAPS.location("layout_foster_town")
	app.delivery_map.runtime.data.player=site.position.duplicate()
	app.delivery_map.runtime.data.opening_unlocked=true
	app.delivery_map.runtime._visible_origin=Vector2.INF
	app.delivery_map.runtime._update_hex_visibility()
	app.delivery_map._arrived(site.id,"location")
	check(press(app.ui,"图书馆"),"Real map arrival routes city menu into library")
	finish_dialogue_ui(app,SERVICE.LIBRARY)
	check(press(app.ui,"收下攻击、防御符文") and app.session.data.known_runes.has("armor"),"Existing paper UI invokes native reward and saves")
	await spectator_ui_check(app)
	app.queue_free()
	await process_frame
	session_checks()
	print("STORY_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
