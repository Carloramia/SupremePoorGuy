extends RefCounted
## Reviewed dialogue sequences and authored entry aliases; no gameplay mutation.
const PATH := "res://Content/Events/MapPatch20261019/EventMapCatalog.json"
var catalog: Dictionary = {}
var events: Dictionary = {}
var runtime: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://Content/Events/GrasslandEvents.json"))
var profiles: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://Content/Events/ApprovedStoryProfiles.json"))

func _init() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	for event: Dictionary in catalog.events: events[event.id] = event

func bindings_for_site(site_id: String, mode: String = "interact") -> Array:
	return catalog.bindings.filter(func(b): return b.source_id==site_id and b.event_trigger.get("enabled",false) and b.event_trigger.mode==mode).duplicate(true)

func dialogue(id: String, state: Dictionary, sequence: String = "") -> Array:
	if not events.has(id): return []
	var event: Dictionary = events[id]
	if sequence.is_empty():
		sequence = "intro"
		match int(event.number):
			1: sequence = "opening"
			4:
				if state.get("stage")=="active": sequence = "submit" if state.get("defense_won",false) else "revisit"
			7: sequence = "return_dialogue" if state.get("stage")=="return_dialogue" else state.get("entry","donkey")
			12:
				if state.get("stage")=="await_enchanter" and state.get("entry")=="enchanter": sequence = "enchanter"
			15:
				if state.get("stage")=="teach": sequence = state.get("route","")
			18:
				var requirement: String = {"available":"first","stage_2":"second","stage_3":"third"}.get(state.get("stage","available"),"")
				return (event.dialogues.get("intro",[])+event.dialogues.get(requirement,[])).duplicate(true)
	var pages: Array=event.dialogues.get(sequence,[]).duplicate(true)
	if id=="QST_GRASS_020":
		var round_index:=mini(3,int(state.get("rounds",0)))
		var round_data: Dictionary=runtime.bindings.bet_rounds[round_index]
		for page: Dictionary in pages:
			page.text=page.text.replace("（怪物1组）",roster_name(round_data.one)).replace("（怪物2组）",roster_name(round_data.two)).replace("打赌10魔力","打赌%d魔力"%int(round_data.stake))
	return pages

func roster_name(config: Dictionary) -> String:
	var counts: Dictionary={}
	for key: String in config.get("profiles",[]):
		var species: String=profiles.profiles.get(key,{}).get("species","")
		var title: String=preload("res://Scripts/Application/CreatureFactory.gd").DEFINITIONS.get(species,{}).get("name",species)
		counts[title]=int(counts.get(title,0))+1
	var names: PackedStringArray=[]
	for title: String in counts: names.append("%s×%d"%[title,counts[title]])
	return "、".join(names)

func branch_label(id: String, branch: String, state: Dictionary={}) -> String:
	if id=="QST_GRASS_020" and branch in ["one","two"]:
		var round_data: Dictionary=runtime.bindings.bet_rounds[mini(3,int(state.get("rounds",0)))]
		return "押注 %d 魔力：%s"%[int(round_data.stake),roster_name(round_data[branch])]
	if id=="QST_GRASS_002" and branch=="battle": return "确认开战"
	if branch=="teach": return "学习符文"
	if branch=="return_dialogue": return "确认归还"
	if events.has(id):
		for item: Dictionary in events[id].branches:
			if item.key==branch: return item.label
	return {"battle":"进入战斗","leave":"离开","close":"关闭","revisit":"交谈","teach":"接受符文","return_dialogue":"完成归还","record":"记录星图"}.get(branch,branch)
