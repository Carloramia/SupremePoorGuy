extends SceneTree
## Transaction/state integration. Battle outcomes here are explicit test receipts;
## real physics deployment and abilities are covered in separate battle tests.
const SESSION=preload("res://Scripts/Application/GameSession.gd")
const RESOURCES=preload("res://Scripts/Events/StoryEventResources.gd")
const PROFILES=preload("res://Scripts/Events/StoryCreatureProfiles.gd")
const HEX=preload("res://Scripts/Events/HexMapProgress.gd")
var s: RefCounted
var resources:=RESOURCES.new()
var profiles:=PROFILES.new()
var checks:=0
var failed:=false
var id:=""
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failed=true; push_error(id+": "+label)
func fresh(event_id: String) -> void:
	id=event_id; s=SESSION.new()
	s.save_path="res://Tests/.runtime/approved_lifecycle_%s_%d.json"%[id,Time.get_ticks_usec()]
	s.data.magic=1000
	s.data.hex_map=HEX.initial()
	s.data.monsters=[]
	for species in ["wolf","bird","bird","snake","snake","snake","human"]:
		var unit: Dictionary=s.FACTORY.template(species)
		unit.merge({"id":species+str(s.data.monsters.size()),"position":"team" if s.data.monsters.is_empty() else "warehouse","traits":[]},true)
		s.data.monsters.append(unit)
	s.data.monsters[0].attack=140
	s.data.last_summon={"succeeded":1}; s.data.serial=1
	check(s.set_story_game_day(1),"Authoritative clock initialized")
func open(entrance: String) -> void:
	var result: Dictionary=s.open_story_event(id,entrance,true)
	check(result.ok,"Open "+entrance+" "+result.get("error",""))
func choose(branch: String,payload: Dictionary={}) -> Dictionary:
	var result: Dictionary=s.story_event_action(id,branch,s.story_event_view(id).conversation,payload)
	check(result.ok,"Choose "+branch+" "+result.get("error",""))
	return result.get("request",{})
func finish(outcome: String="success",winner: String="one") -> void:
	var r: Dictionary=s.pending_story_request(id)
	check(not r.is_empty(),"Pending request exists")
	if r.is_empty(): return
	var receipt:={"request_id":r.request_id,"event_id":id,"stage":r.stage,"branch":r.branch,"kind":r.kind,"outcome":outcome,"committed":true}
	var ok: bool
	if r.has("battle_id"):
		receipt.battle_id=r.battle_id; receipt.winner=winner
		ok=s.commit_story_battle(receipt,{"battle_id":r.battle_id,"outcome":outcome,"parts":{},"reward":0,"duration":1},r.plan.get("source_site_id",""))
	else: ok=s.commit_story_receipt(receipt,resources.apply)
	check(ok,"Commit "+outcome+" "+s.last_error)
	if not ok: return
	var before: Dictionary=s.data.duplicate(true)
	check(s.commit_story_battle(receipt,{"battle_id":r.get("battle_id",""),"outcome":outcome},"") if r.has("battle_id") else s.commit_story_receipt(receipt,resources.apply),"Duplicate receipt accepted")
	check(s.data==before,"Duplicate receipt changes no resources")
func complete() -> void:
	check(s.story_event_view(id).get("completed",false),"Complete")
	var restored:=SESSION.new(); restored.save_path=s.save_path
	var loaded: bool=restored.load_save()
	if not loaded: print("RELOAD ERROR ",restored.last_error)
	check(loaded and difference(restored.data,s.data).is_empty(),"Full state survives reload")
func difference(a: Variant,b: Variant,path: String="root") -> String:
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return path+" key count"
		for key in a:
			if not b.has(key): return path+" missing "+str(key)
			var issue:=difference(a[key],b[key],path+"/"+str(key))
			if not issue.is_empty(): return issue
		return ""
	if a is Array and b is Array:
		if a.size()!=b.size(): return path+" length"
		for i in a.size():
			var issue:=difference(a[i],b[i],path+"/"+str(i))
			if not issue.is_empty(): return issue
		return ""
	if (a is int or a is float) and (b is int or b is float): return "" if is_equal_approx(float(a),float(b)) else path
	return "" if a==b else path
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	resources.item_definitions=profiles.definitions.items
	for key in ["reward_two_head_wolf","reward_magic_eye_beast"]: resources.monster_presets[key]=profiles.make(key,key)
	for case: Array in [["QST_MAIN_001_001","opening","read"],["QST_SIDE_001_001","library","talk"],["QST_GRASS_009","cart","read"],["QST_GRASS_010","temple","break"],["QST_GRASS_013","well","record"],["QST_GRASS_017","bridge","wood"]]:
		fresh(case[0]); open(case[1]); choose(case[2]); finish(); complete()
	fresh("QST_GRASS_005"); open("shepherd"); choose("talk"); complete()
	for case: Array in [["QST_GRASS_002","tree","battle"],["QST_GRASS_008","giant","battle"],["QST_GRASS_011","mine","enter"],["QST_GRASS_012","farm","direct"],["QST_GRASS_016","circus","help"],["QST_GRASS_017","bridge","fight"],["QST_GRASS_019","clash","wolf"],["QST_GRASS_019","clash","beast"],["QST_GRASS_019","clash","watch"]]:
		fresh(case[0]); open(case[1]); choose(case[2]); finish("victory"); finish(); complete()
	fresh("QST_SIDE_002_001"); open("center"); choose("accept")
	open("defense_target"); choose("battle"); finish("victory")
	check(s.story_event_view(id).defense_won,"Defense awaits city hand-in")
	open("center"); choose("submit"); finish(); complete()
	fresh("QST_SIDE_002_001"); open("center"); choose("accept")
	s.data.battle_results["historical"]={"battle_id":"historical","outcome":"victory","parts":{},"reward":0,"site_id":"other_site","map_id":"hex_frontier_20261019"}
	check(s.save() and not s.story_event_view(id).defense_won,"Other historical victory cannot fulfill defense")
	s.data.battle_results.historical.site_id="hex_camp_mv9za92d_38"
	check(s.save() and s.story_event_view(id).defense_won,"Reliable historical victory at exact site is credited")
	fresh("QST_GRASS_006"); open("tower"); choose("pickup"); finish()
	choose("battle"); finish("defeat")
	check(s.story_event_view(id).stage=="picked_up","Defeat retains pickup and retry")
	choose("battle"); finish("victory"); finish(); complete()
	fresh("QST_GRASS_007"); open("donkey")
	open("merchant"); choose("from_merchant"); choose("return_dialogue"); finish(); complete()
	fresh("QST_GRASS_012"); open("farm"); choose("ask"); open("enchanter"); choose("enchanter"); finish(); complete()
	fresh("QST_GRASS_014"); open("engine"); choose("buy"); finish(); complete()
	check(s.data.magic==900 and s.data.array_stage==2,"Purchase charged 100 for one actual expansion")
	check(s.set_story_game_day(4.99) and "QST_GRASS_015" not in s.ready_story_events(true),"Ghost not early")
	check(s.set_story_game_day(5) and "QST_GRASS_015" in s.ready_story_events(true),"Ghost due after four days")
	id="QST_GRASS_015"; open("ghost"); choose("kind"); choose("teach"); finish(); complete()
	fresh("QST_GRASS_016"); open("circus"); choose("away")
	check(s.story_event_view(id).stage=="available","Leaving circus allows revisit")
	fresh("QST_SIDE_003_001"); open("altar")
	for case: Array in [["first",["wolf0"]],["second",["bird1","bird2"]],["third",["snake3","snake4","snake5"]]]:
		choose(case[0],{"monster_ids":case[1],"confirmed":true}); finish()
	check(s.data.monsters.size()==1 and s.data.story_weather.permanent,"Three real sacrifices retain last monster and permanent rain")
	complete()
	fresh("QST_GRASS_020"); open("knight")
	choose("one"); finish(); check(s.data.magic==990,"Stake deducted before spectator")
	finish("draw"); finish()
	check(s.data.magic==1000 and s.story_event_view(id).rounds==0,"Draw refunds and preserves round")
	for round_index in 4:
		choose("one"); finish(); finish("victory","one"); finish()
		check(s.story_event_view(id).rounds==round_index+1,"Effective round settles once")
	check(s.data.magic==1180,"All wins pay 2B total, net B")
	complete()
	print("APPROVED_LIFECYCLE_","FAILED" if failed else "PASSED"," checks=",checks)
	quit(1 if failed else 0)
