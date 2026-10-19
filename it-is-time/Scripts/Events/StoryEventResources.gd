extends RefCounted
## Real mutations on the GameSession transaction dictionary. No file I/O here.
const TASKS = preload("res://Scripts/Application/NewPlayerTasks.gd")
const RULES = preload("res://Modules/PaperUI/Scripts/Ritual/RuneRules.gd")
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
var item_definitions: Dictionary = {}
var monster_presets: Dictionary = {}

static func valid_inventory(data: Dictionary) -> bool:
	if not data.has("story_items"): return true
	if not data.story_items is Dictionary: return false
	for id: Variant in data.story_items:
		if not id is String or id.is_empty() or not TASKS._integer(data.story_items[id],1): return false
	return true

func apply(data: Dictionary, request: Dictionary) -> String:
	if request.kind not in ["transaction","purchase","sacrifice","bet"]: return "此请求不属于资源事务。"
	var before := data.duplicate(true)
	var error := _apply(data,request)
	if not error.is_empty():
		data.clear()
		data.merge(before,true)
	return error

func _apply(data: Dictionary, request: Dictionary) -> String:
	if request.kind=="purchase":
		var cost: Variant = request.plan.get("cost")
		var target: Variant = request.plan.get("to_stage")
		if not TASKS._integer(cost,1) or data.array_stage!=request.plan.get("from_stage") or not TASKS._integer(target,2) or int(target)!=int(data.array_stage)+1 or int(target)>4: return "扩圈请求已失效。"
		if data.magic<int(cost): return "购买魔力不足。"
		var candidate: Dictionary = data.layout.duplicate(true)
		candidate.stage = int(target)
		var rules := RULES.new()
		if not rules.import_layout(candidate): return "扩圈后的法阵布局无效。"
		data.magic -= int(cost)
		data.array_stage = int(target)
		data.layout = candidate
		return ""
	if request.kind=="bet":
		var cost: Variant = request.plan.get("stake")
		if not TASKS._integer(cost,1) or data.magic<int(cost): return "下注魔力不足或本金无效。"
		data.magic -= int(cost)
		return ""
	if request.kind=="sacrifice":
		var ids: Variant = request.payload.get("monster_ids")
		if not TASKS._string_list(ids) or ids.is_empty() or request.payload.get("confirmed")!=true: return "献祭没有有效的确认实例。"
		var owned: Array = data.monsters.filter(func(m): return m.position in ["team","warehouse"])
		if owned.size()-ids.size()<1: return "献祭后必须至少保留一只怪物。"
		for id: String in ids:
			var matches: Array = owned.filter(func(m): return m.id==id)
			if matches.size()!=1: return "献祭实例已不存在。"
			var m: Dictionary = matches[0]
			for event: Dictionary in data.get("story_events",{}).get("entries",{}).values():
				if event.get("pending",{}).get("plan",{}).get("frozen_rosters",{}).get("left",[]).any(func(unit):return unit.id==id): return "献祭实例被未结算的事件战斗占用。"
			if not m.get("recoverable",true) or m.get("locked",false) or id in data.get("battle",{}).get("party_ids",[]): return "献祭实例不可回收或正在使用。"
		data.monsters = data.monsters.filter(func(m): return m.id not in ids)
	var reward: Variant = request.plan.get("reward")
	if not reward is Dictionary or not TASKS._valid_reward({"magic":reward.get("magic"),"runes":reward.get("runes",[]),"relics":reward.get("relics",[])}): return "真实奖励尚未配置。"
	for item: Dictionary in reward.get("items",[]):
		if not item_definitions.has(item.get("id")) or not TASKS._integer(item.get("count"),1): return "物品尚未注册或数量无效。"
	for item: Dictionary in reward.get("monsters",[]):
		if not monster_presets.has(item.get("id")) or not TASKS._integer(item.get("count"),1): return "奖励怪物预设尚未注册。"
	TASKS._apply_reward(data,{"magic":reward.magic,"runes":reward.get("runes",[]),"relics":reward.get("relics",[])})
	if not reward.get("items",[]).is_empty() and not data.has("story_items"): data["story_items"] = {}
	for item: Dictionary in reward.get("items",[]):
		data.story_items[item.id] = int(data.story_items.get(item.id,0))+int(item.count)
	var ordinal := 0
	for item: Dictionary in reward.get("monsters",[]):
		for index: int in int(item.count):
			var record: Variant = monster_presets[item.id]
			if not record is Dictionary or not FACTORY.valid_record(record): return "奖励怪物的实际物理预设无效。"
			var instance: Dictionary = record.duplicate(true)
			instance["id"] = request.request_id+"_monster_"+str(ordinal)
			instance["position"] = "warehouse"
			instance["traits"] = instance.get("traits",[])
			if data.monsters.any(func(m): return m.id==instance.id): return "奖励怪物实例ID重复。"
			data.monsters.append(instance)
			ordinal += 1
	if request.get("operation",{}).get("kind")=="sacrifice":
		var stage: String=request.branch
		var day: float=data.get("story_events",{}).get("clock",{}).get("day",1.0)
		var previous: Dictionary=data.get("story_weather",{})
		var permanent: bool=stage=="third" or previous.get("permanent",false)
		data["story_weather"]={"permanent":permanent,"expires_day":maxf(float(previous.get("expires_day",0)),day+(2 if stage=="first" else 4)),"radius_cells":2,"hp_multiplier":1.1,"source_request":request.request_id}
	return ""
