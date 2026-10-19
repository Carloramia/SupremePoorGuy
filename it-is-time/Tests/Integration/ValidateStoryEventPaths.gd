extends SceneTree
## Whole-flow fixtures. Enemy rosters, payouts and flying traits below are NOT production defaults.
const SESSION = preload("res://Scripts/Application/GameSession.gd")
const SERVICE = preload("res://Scripts/Events/StoryService.gd")
const CATALOG = preload("res://Scripts/Events/StoryCatalog.gd")
const MAPS = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
const RUNTIME = preload("res://Modules/FrontierDelivery/Scripts/Map/WorldMapRuntime.gd")
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
var checks := 0
var failures := 0
var paths: Array = []
var visited := {}
var preset_path := ""

func _initialize() -> void:
	create_timer(180).timeout.connect(func():push_error("STORY_PATH_TIMEOUT");quit(1))
	call_deferred("run")

func check(ok: bool, text: String) -> bool:
	checks+=1
	if not ok: failures+=1; push_error("STORY_PATH_FAIL: "+text)
	return ok

func context(id: String, role: String = "", configured: Dictionary = {}) -> Dictionary:
	for value: Dictionary in CATALOG.bindings(id,"20261019",configured):
		if role.is_empty() or value.entry_role==role: return value.duplicate(true)
	check(false,"Missing context "+id+":"+role)
	return {}

func unit(id: String, species := "wolf", position := "warehouse", facts: Dictionary = {}) -> Dictionary:
	var value := FACTORY.template(species)
	value.merge({"id":id,"position":position,"traits":[],"event_traits":facts},true)
	return value

func fresh(id: String):
	var s := SESSION.new()
	s.save_path="res://Tests/.runtime/story-paths/%s_%d.json" % [id,Time.get_ticks_usec()]
	s.data.delivery_map_version="20261019"
	s.data.serial=1
	s.data.monsters=[unit("player","wolf","team"),unit("fur")]
	s.data.monsters[0].attack=100
	if id==SERVICE.ALTAR:
		s.data.monsters.append_array([unit("fly1","wolf","warehouse",{"can_fly":true,"fur":false}),unit("fly2","wolf","warehouse",{"can_fly":true,"fur":false}),unit("snake1","snake"),unit("snake2","snake"),unit("snake3","snake"),unit("keeper","human")])
	s.story_parameters=CATALOG.parameters().duplicate(true)
	for event_id: String in s.story_parameters:
		var p: Dictionary = s.story_parameters[event_id]
		for key: String in ["private_money_magic","magic_reward","first_magic_reward","direct_magic_reward","enchanter_magic_reward","fight_magic_reward","wood_magic_reward","watch_magic_reward"]:
			if p.has(key): p[key]=17
		if p.has("attack_threshold"): p.attack_threshold=25
		if p.has("pickup_item_id"): p.pickup_item_id="fixture_item"
		for branch: String in p.get("battles",{}):
			p.battles[branch]={"battle_map_id":"battle_bandit_camp","enemy_config_id":"bandit_clear_team"}
			if branch=="watch": p.battles[branch]={"battle_map_id":"battle_bandit_camp","side_a_roster":"bandit_clear_team","side_b_roster":"bandit_clear_team"}
		if event_id=="QST_SIDE_002_001": p.battles.clear.source_id="layout_camp_001"
		if event_id=="QST_GRASS_019": p.reward_presets={"wolf":preset_path,"beast":preset_path}
		if event_id==SERVICE.BET:
			p.loss_policy="lose_stake"
			for index: int in 4: p.rounds[index]={"battle_map_id":"battle_bandit_camp","side_a_roster":"bandit_clear_team","side_b_roster":"bandit_clear_team"}
	MAPS.select_version("20261019")
	check(s.save_delivery_world(RUNTIME.new().snapshot()),"Fixture save "+id)
	return s

func advance(s, id: String, choice: String, selected: Array = []) -> bool:
	return check(s.advance_story_event(id,choice,int(SERVICE.entry(s.data,id).revision),selected),id+"/"+str(SERVICE.entry(s.data,id).node)+"/"+choice+" "+s.last_error)

func reload(s) -> bool:
	var before: Dictionary = s.data.duplicate(true)
	var restored := SESSION.new()
	restored.save_path=s.save_path
	if not check(restored.load_save(),"Load at current checkpoint: "+restored.last_error): return false
	if not check(JSON.stringify(restored.data.story_events)==JSON.stringify(JSON.parse_string(JSON.stringify(before.story_events))),"No story state rerolled by load"): return false
	s.data=restored.data
	return true

func settle(s, outcome: String) -> bool:
	var request: Dictionary = s.data.battle.duplicate(true)
	if not reload(s): return false
	if not check(s.data.battle.battle_id==request.battle_id and s.data.battle.enemy_definitions_snapshot==request.enemy_definitions_snapshot,"Pending battle and roster survive restart"): return false
	var runtime := RUNTIME.new(s.delivery_snapshot())
	var result := {"battle_id":request.battle_id,"request_id":request.battle_id,"outcome":outcome,"reward":0,"parts":{},"combat_mode":request.combat_mode}
	if not check(runtime.complete_battle(result) and s.commit_battle(result,runtime.snapshot()),"Commit "+str(request.event_id)+" "+outcome+": "+s.last_error): return false
	var after: Dictionary = s.data.duplicate(true)
	if not check(s.commit_battle(result,runtime.snapshot()) and s.data==after,"Repeated battle receipt changes nothing"): return false
	s.data.battle={}
	return check(s.save(),"Settlement return saves")

func walk(s, id: String, decisions: Dictionary = {}, outcome := "victory", reopen := true, label := "") -> bool:
	var initial_failures := failures
	if id==SERVICE.OPENING: SERVICE.prepare_new_game(s.data)
	if id==SERVICE.GHOST:
		if not walk(s,SERVICE.ENGINE,{},"victory",false,"ghost prerequisite"): return false
		s.data.world_time.total_minutes=SERVICE.entry(s.data,SERVICE.ENGINE).flags.ghost_due_minutes
	if id=="QST_GRASS_007":
		var first: String = decisions.get("first_role","donkey")
		if not check(s.open_story_event(id,context(id,first)),"First discovery"): return false
	var role: String = "merchant" if id=="QST_GRASS_007" and decisions.get("first_role","donkey")=="donkey" else "donkey" if id=="QST_GRASS_007" else ""
	var ctx := context(id,role,s.story_parameters)
	if not check(s.open_story_event(id,ctx),"Open "+id+" "+label+": "+s.last_error): return false
	for step: int in 160:
		var current := SERVICE.entry(s.data,id)
		visited[id+":"+str(current.node)]=true
		if current.node==decisions.get("stop_at",""):
			check(not current.completed and not s.data.completed.has("content_reward:"+id),"Failed condition preserves the event and grants no victory reward")
			paths.append({"event":id,"path":label,"outcome":"condition_failed","completed":false,"passed":failures==initial_failures})
			return failures==initial_failures
		if current.completed:
			var after: Dictionary = s.data.duplicate(true)
			check(not s.advance_story_event(id,"confirm",int(current.revision)) and s.data==after,"Completed flow never rewards twice "+id)
			paths.append({"event":id,"path":label,"outcome":outcome,"completed":true,"passed":failures==initial_failures})
			return failures==initial_failures
		if id=="QST_SIDE_002_001" and current.node in ["progress","return"]:
			ctx=context(id,"clear_target" if current.node=="progress" else "city_center",s.story_parameters)
		if id=="QST_GRASS_012" and current.node=="waiting": ctx=context(id,"return_city_enchanter",s.story_parameters)
		if reopen:
			var cursor: int = current.cursor
			var node_name: String = current.node
			if not reload(s) or not check(s.open_story_event(id,ctx),"Re-enter "+id+": "+s.last_error): return false
			current=SERVICE.entry(s.data,id)
			visited[id+":"+str(current.node)]=true
			if current.node==node_name and not check(int(current.cursor)==cursor,"Close/reopen preserves dialogue index "+id): return false
		var node: Dictionary = CATALOG.definition(id).nodes[current.node]
		if node.type=="blocked":
			paths.append({"event":id,"path":label,"outcome":outcome,"completed":false,"blocked":true,"passed":failures==initial_failures})
			return failures==initial_failures
		var choice: String = "next" if node.type=="dialogue" else "confirm"
		var command: Dictionary = node.get("action",{})
		if node.type=="choice":
			choice=str(decisions.get(current.node,node.options[0].id))
			for option: Dictionary in node.options:
				if option.id==choice: command=option.get("action",{}); break
		if command.get("op")=="close":
			var before: Dictionary = s.data.duplicate(true)
			check(advance(s,id,choice) and s.data==before,"Closing choice has no completion, payment or reward side effects "+id)
			paths.append({"event":id,"path":label,"outcome":outcome,"completed":false,"cancelled":true,"passed":failures==initial_failures})
			return failures==initial_failures
		var selected: Array = []
		if command.get("op")=="sacrifice":
			var eligible: Array = SERVICE.candidates(s.data,int(command.stage))
			for index: int in int(command.stage): selected.append(eligible[index].id)
		if not advance(s,id,choice,selected): return false
		if not s.data.battle.is_empty():
			if not settle(s,outcome): return false
			if outcome!="victory" and id!=SERVICE.BET and command.get("mode","party")=="party":
				check(not SERVICE.entry(s.data,id).completed and not s.data.completed.has("content_reward:"+id),"Failure/retreat grants no victory reward "+id)
				paths.append({"event":id,"path":label,"outcome":outcome,"completed":false,"passed":failures==initial_failures})
				return failures==initial_failures
	check(false,"Nonterminating event path "+id+" "+label)
	return false

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Tests/.runtime/story-paths"))
	preset_path="res://Tests/.runtime/story-paths/reward_fixture.json"
	var file := FileAccess.open(preset_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(unit("fixture_reward")))
	file.close()
	for id: String in CATALOG.flows():
		if id.begins_with("AUX_"): continue
		walk(fresh(id),id,{},"victory",true,"primary+reentry+reload")
	for id: String in ["QST_GRASS_002","QST_SIDE_002_001","QST_GRASS_006","QST_GRASS_008","QST_GRASS_011","QST_GRASS_012","QST_GRASS_016","QST_GRASS_017","QST_GRASS_019"]:
		for outcome: String in ["defeat","retreat"]: walk(fresh(id),id,{},outcome,true,"failed battle")
	for row: Array in [["QST_GRASS_007",{"first_role":"merchant"}], ["QST_GRASS_012",{"decision":"ask"}], ["QST_GRASS_015",{"decision":"kind"}], ["QST_GRASS_017",{"decision":"wood"}], ["QST_GRASS_019",{"decision":"beast"}], ["QST_GRASS_019",{"decision":"watch"}], [SERVICE.BET,{"decision":"two"}]]:
		walk(fresh(row[0]),row[0],row[1],"victory",true,"alternate branch")
	for outcome: String in ["defeat","draw","retreat"]: walk(fresh(SERVICE.BET),SERVICE.BET,{},outcome,true,"observer result")
	for row: Array in [["QST_GRASS_016","away"],["QST_GRASS_019","leave"],[SERVICE.BET,"leave"],["QST_SIDE_001_001","leave"]]:
		walk(fresh(row[0]),row[0],{"decision":row[1],"aid":row[1]},"victory",true,"leave without claim")
	var low_attack = fresh("QST_GRASS_010")
	for monster: Dictionary in low_attack.data.monsters: monster.attack=25
	walk(low_attack,"QST_GRASS_010",{"stop_at":"failure"},"victory",true,"single attack equals threshold")
	var rova = fresh(SERVICE.LIBRARY)
	walk(rova,SERVICE.LIBRARY,{},"victory",true,"library prerequisite for resident Rova")
	walk(rova,"AUX_GRASS_ROVA",{},"victory",true,"repeatable resident dialogue")
	for id: String in ["AUX_GRASS_FOSTER","AUX_GRASS_SALGERT"]:
		check(not rova.open_story_event(id,context(id)),"Town container cannot be mistaken for an executable reward event")
	var report := {"checks":checks,"failures":failures,"fixture_only":true,"paths":paths,"visited_nodes":visited.keys()}
	file=FileAccess.open("res://Tests/.runtime/story-paths/coverage.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("STORY_PATH_CHECKS=",checks," FAILURES=",failures," PATHS=",paths.size())
	quit(1 if failures else 0)
