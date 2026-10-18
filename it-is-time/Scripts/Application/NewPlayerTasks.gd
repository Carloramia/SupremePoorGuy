extends RefCounted
## Task data and reconciliation only. GameSession owns the atomic save and signals.
const RULES = preload("res://Modules/PaperUI/Scripts/Ritual/RuneRules.gd")
const SAVE_KEY := "new_player_tasks"
const VERSION := 1
const DEFINITIONS: Array = [
	{
		"id":"explore_frontier", "title":"探索边境",
		"description":"实际抵达任意一个可交互地点。",
		"prerequisites":[], "condition":{"type":"location_arrived", "count":1},
		"action":"world", "reward":{"magic":0, "runes":[], "relics":[]}
	},
	{
		"id":"complete_summon", "title":"完成召唤",
		"description":"成功召唤至少一只妖兽，并将该批结果全部加入出战或存入仓库。",
		"prerequisites":[], "condition":{"type":"summon_settled", "count":1},
		"action":"summon", "reward":{"magic":0, "runes":[], "relics":[]}
	},
	{
		"id":"prepare_party", "title":"准备出战",
		"description":"将至少一只妖兽加入出战队伍。",
		"prerequisites":["complete_summon"], "condition":{"type":"party_members", "count":1},
		"action":"party", "reward":{"magic":0, "runes":[], "relics":[]}
	},
	{
		"id":"win_battle", "title":"赢得一次战斗",
		"description":"赢得一次真实战斗，并成功保存战斗结算。",
		"prerequisites":["prepare_party"], "condition":{"type":"battle_victories", "count":1},
		"action":"world", "reward":{"magic":0, "runes":[], "relics":[]}
	}
]
const CONDITION_TYPES := ["location_arrived", "summon_settled", "party_members", "battle_victories"]
const ACTIONS := ["world", "summon", "party"]

static func initial_progress() -> Dictionary:
	return {"version":VERSION, "enabled":false, "completed":{},
		"facts":{"locations":[], "summon_batches":[], "party_size":0, "victories":[]}}

static func ensure_progress(data: Dictionary) -> Dictionary:
	if not data.has(SAVE_KEY): data[SAVE_KEY] = initial_progress()
	return data[SAVE_KEY]

static func _integer(value: Variant, minimum: int = 0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and float(value)>=minimum and float(value)<=2147483647.0

static func _string_list(value: Variant) -> bool:
	if not value is Array: return false
	var seen := {}
	for item: Variant in value:
		if not item is String or item.is_empty() or seen.has(item): return false
		seen[item] = true
	return true

static func _valid_reward(reward: Variant) -> bool:
	if not reward is Dictionary or not _integer(reward.get("magic",0)): return false
	for key: Variant in reward:
		if key not in ["magic", "runes", "relics"]: return false
	for pair: Array in [["runes",false], ["relics",true]]:
		var ids: Variant = reward.get(pair[0],[])
		if not _string_list(ids): return false
		for id: String in ids:
			if RULES.definition(id,pair[1]).is_empty(): return false
	return true

static func valid_progress(data: Dictionary) -> bool:
	if not data.has(SAVE_KEY): return true # Additive migration; legacy saves stay readable.
	var progress: Variant = data[SAVE_KEY]
	if not progress is Dictionary or progress.get("version")!=VERSION or not progress.get("enabled") is bool: return false
	if not progress.get("completed") is Dictionary or not progress.get("facts") is Dictionary: return false
	for id: Variant in progress.completed:
		var receipt: Variant = progress.completed[id]
		if not id is String or id.is_empty() or not receipt is Dictionary or not _valid_reward(receipt.get("reward")): return false
	var facts: Dictionary = progress.facts
	return _string_list(facts.get("locations")) and _string_list(facts.get("summon_batches")) and _string_list(facts.get("victories")) and _integer(facts.get("party_size"))

static func validate_definitions(definitions: Array) -> String:
	var by_id := {}
	for task: Variant in definitions:
		if not task is Dictionary: return "任务配置必须是字典。"
		var id: Variant = task.get("id")
		if not id is String or id.is_empty() or by_id.has(id): return "任务 ID 缺失或重复。"
		for key: String in ["title", "description"]:
			if not task.get(key) is String or task[key].is_empty(): return "任务 %s 缺少%s。" % [id,key]
		if not _string_list(task.get("prerequisites",[])): return "任务 %s 的前置列表无效。" % id
		if task.get("action") not in ACTIONS: return "任务 %s 的跳转类型无效。" % id
		var condition: Variant = task.get("condition")
		if not condition is Dictionary or condition.get("type") not in CONDITION_TYPES or not _integer(condition.get("count",1),1): return "任务 %s 的完成条件无效。" % id
		if not _valid_reward(task.get("reward",{})): return "任务 %s 的奖励配置无效。" % id
		by_id[id] = task
	for task: Dictionary in definitions:
		for prerequisite: String in task.get("prerequisites",[]):
			if not by_id.has(prerequisite): return "任务 %s 引用了不存在的前置任务 %s。" % [task.id,prerequisite]
	# Topological elimination also detects self-dependencies and cycles.
	var resolved := {}
	for _pass: int in definitions.size():
		for task: Dictionary in definitions:
			if task.get("prerequisites",[]).all(func(id): return resolved.has(id)): resolved[task.id] = true
	if resolved.size()!=definitions.size(): return "任务前置关系存在循环。"
	return ""

static func _append_unique(list: Array, value: String) -> void:
	if not value.is_empty() and value not in list: list.append(value)

static func record_location(data: Dictionary, map_id: String, location_id: String) -> void:
	if not map_id.is_empty() and not location_id.is_empty():
		_append_unique(ensure_progress(data).facts.locations,map_id+":"+location_id)

static func _capture_reliable_facts(data: Dictionary, facts: Dictionary) -> void:
	# A stored map alone, discovered markers, or a spawn position prove no arrival.
	for map_id: String in data.get("worlds",{}):
		var world: Dictionary = data.worlds[map_id]
		if world.get("backend","")=="frontier_delivery_v1":
			for location_id: String in world.get("visited",[]):
				_append_unique(facts.locations,map_id+":"+location_id)
		else:
			for location_id: String in world.get("location_runtime_states",{}):
				var location: Dictionary = world.location_runtime_states[location_id]
				if _integer(location.get("visits",0),1): _append_unique(facts.locations,map_id+":"+location_id)
	var report: Dictionary = data.get("last_summon",{})
	if _integer(data.get("serial",0),1) and _integer(report.get("succeeded",0),1) and data.get("pending",[]).is_empty():
		_append_unique(facts.summon_batches,"batch_%d" % int(data.serial))
	var team_count := 0
	var batches := {}
	for monster: Dictionary in data.get("monsters",[]):
		if monster.get("position")=="team": team_count += 1
		var batch_id: String = str(monster.get("batch_id",""))
		if batch_id.begins_with("batch_") and str(monster.get("id","")).begins_with("summon_") and monster.get("source_layout") is Dictionary:
			batches[batch_id] = batches.get(batch_id,false) or monster.get("position")=="pending"
	for batch_id: String in batches:
		if not batches[batch_id]: _append_unique(facts.summon_batches,batch_id)
	facts.party_size = maxi(int(facts.party_size),team_count)
	for id: String in data.get("battle_results",{}):
		if data.battle_results[id].get("outcome")=="victory": _append_unique(facts.victories,id)

static func _condition_met(condition: Dictionary, facts: Dictionary) -> bool:
	var count := int(condition.get("count",1))
	match condition.type:
		"location_arrived": return facts.locations.size()>=count
		"summon_settled": return facts.summon_batches.size()>=count
		"party_members": return int(facts.party_size)>=count
		"battle_victories": return facts.victories.size()>=count
	return false

static func _apply_reward(data: Dictionary, reward: Dictionary) -> void:
	data.magic += int(reward.get("magic",0))
	for pair: Array in [["runes","known_runes",RULES.RUNES], ["relics","known_relics",RULES.RELICS]]:
		var additions: Array = reward.get(pair[0],[])
		if additions.is_empty(): continue
		# Missing lists mean all references were already unlocked; preserve that policy.
		if not data.has(pair[1]): data[pair[1]] = pair[2].map(func(item): return item.id)
		for id: String in additions: _append_unique(data[pair[1]],id)

static func reconcile(data: Dictionary, definitions: Array = DEFINITIONS) -> Dictionary:
	var error := validate_definitions(definitions)
	if not error.is_empty(): return {"ok":false, "error":error, "completed":[]}
	if not valid_progress(data): return {"ok":false, "error":"新手任务存档无效。", "completed":[]}
	var progress := ensure_progress(data)
	_capture_reliable_facts(data,progress.facts)
	var newly_completed: Array = []
	if not progress.enabled: return {"ok":true, "completed":newly_completed}
	# Repeat to allow out-of-order configuration and retroactive dependency chains.
	for _pass: int in definitions.size():
		var advanced := false
		for task: Dictionary in definitions:
			if progress.completed.has(task.id): continue
			if not task.get("prerequisites",[]).all(func(id): return progress.completed.has(id)): continue
			if not _condition_met(task.condition,progress.facts): continue
			var reward: Dictionary = task.get("reward",{}).duplicate(true)
			_apply_reward(data,reward)
			progress.completed[task.id] = {"reward":reward}
			newly_completed.append(task.id)
			advanced = true
		if not advanced: break
	return {"ok":true, "completed":newly_completed}

static func reward_text(reward: Dictionary) -> String:
	var parts := PackedStringArray()
	if int(reward.get("magic",0))>0: parts.append("魔力 +%d" % int(reward.magic))
	for pair: Array in [["runes",false], ["relics",true]]:
		for id: String in reward.get(pair[0],[]):
			parts.append("解锁"+str(RULES.definition(id,pair[1]).get("name",id)))
	return "、".join(parts)

static func rows(data: Dictionary, definitions: Array = DEFINITIONS) -> Array:
	var progress: Dictionary = data.get(SAVE_KEY,initial_progress())
	var titles := {}
	for task: Dictionary in definitions: titles[task.id] = task.title
	var result: Array = []
	for task: Dictionary in definitions:
		var done: bool = progress.completed.has(task.id)
		var missing := PackedStringArray()
		for id: String in task.get("prerequisites",[]):
			if not progress.completed.has(id): missing.append(str(titles.get(id,id)))
		result.append({"id":task.id, "title":task.title, "description":task.description,
			"action":task.action, "done":done, "locked":not progress.enabled or not missing.is_empty(),
			"prerequisite_text":"前置："+"、".join(missing) if not missing.is_empty() else "",
			"reward_text":reward_text(progress.completed[task.id].reward if done else task.get("reward",{}))})
	return result
