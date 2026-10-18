extends RefCounted
## Pure progression logic. GameSession owns persistence and reward transactions.
const DEFINITION = preload("res://Scripts/Quests/QuestDefinition.gd")
const OBJECTIVE = preload("res://Scripts/Quests/QuestObjectiveData.gd")
const STATES := ["locked", "available", "active", "completed", "claimed"]
var definitions: Dictionary = {}

static func empty_state() -> Dictionary:
	return {"version":1, "entries":{}, "receipts":{}}

func configure(resources: Array) -> String:
	var candidate := {}
	for quest in resources:
		if not quest is DEFINITION or quest.id.is_empty() or candidate.has(str(quest.id)):
			return "任务资源为空、ID 为空或重复。"
		if quest.objectives.is_empty() or quest.reward_magic < 0:
			return "任务 %s 的目标或奖励无效。" % quest.id
		var objective_ids := {}
		for goal in quest.objectives:
			if goal == null or goal.id.is_empty() or objective_ids.has(str(goal.id)) or goal.event_key.is_empty() or goal.required_count < 1 or goal.required_count > 1000000 or goal.count_mode not in [OBJECTIVE.CountMode.COUNT, OBJECTIVE.CountMode.MAXIMUM]:
				return "任务 %s 的目标 ID、事件或计数设置无效。" % quest.id
			objective_ids[str(goal.id)] = true
		candidate[str(quest.id)] = quest.duplicate(true)
	for id: String in candidate:
		for prerequisite: StringName in candidate[id].prerequisite_ids:
			if not candidate.has(str(prerequisite)):
				return "任务 %s 引用了不存在的前置任务 %s。" % [id, prerequisite]
	# Topological removal also catches self references without recursive traversal.
	var remaining := candidate.keys()
	while not remaining.is_empty():
		var removed := false
		for id: String in remaining.duplicate():
			var blocked := false
			for prerequisite: StringName in candidate[id].prerequisite_ids:
				if str(prerequisite) in remaining: blocked = true
			if not blocked: remaining.erase(id); removed = true
		if not removed: return "任务前置条件存在循环。"
	definitions = candidate
	return ""

func synchronize(state: Dictionary) -> void:
	for id: String in definitions:
		var quest: DEFINITION = definitions[id]
		if not state.entries.has(id):
			state.entries[id] = {"state":"locked", "objectives":{}}
		var entry: Dictionary = state.entries[id]
		for goal in quest.objectives:
			if not entry.objectives.has(str(goal.id)):
				entry.objectives[str(goal.id)] = {"count":0}
	_refresh(state)

func _refresh(state: Dictionary) -> void:
	var changed := true
	while changed:
		changed = false
		for id: String in definitions:
			var quest: DEFINITION = definitions[id]
			var entry: Dictionary = state.entries[id]
			if entry.state == "locked":
				var unlocked := true
				for prerequisite: StringName in quest.prerequisite_ids:
					if state.entries[str(prerequisite)].state not in ["completed", "claimed"]: unlocked = false
				if unlocked:
					entry.state = "active" if quest.auto_accept else "available"
					changed = true
			if entry.state != "active": continue
			var complete := true
			for goal in quest.objectives:
				if int(entry.objectives[str(goal.id)].count) < goal.required_count: complete = false
			if complete: entry.state = "completed"; changed = true

func accept(state: Dictionary, id: String) -> String:
	if not definitions.has(id): return "任务不存在。"
	var entry: Dictionary = state.entries[id]
	if entry.state != "available": return "该任务当前不能接取。"
	entry.state = "active"
	return ""

static func valid_events(events: Array) -> bool:
	for event in events:
		if not event is Dictionary: return false
		for key: String in ["event_key", "event_id"]:
			if not event.get(key) is String or str(event[key]).is_empty(): return false
		if not event.get("target_id", "") is String or not event.get("historical", false) is bool: return false
		if not _nonnegative_integer(event.get("amount", 1)): return false
	return true

func apply_events(state: Dictionary, events: Array) -> bool:
	var changed := false
	for event in events:
		if event.event_id in state.receipts.get(event.event_key, []): continue
		var event_changed := false
		for id: String in definitions:
			var entry: Dictionary = state.entries[id]
			if entry.state != "active": continue
			for goal in definitions[id].objectives:
				if str(goal.event_key) != event.event_key: continue
				if not goal.target_id.is_empty() and str(goal.target_id) != event.get("target_id", ""): continue
				if event.get("historical", false) and not goal.count_history: continue
				var progress: Dictionary = entry.objectives[str(goal.id)]
				if int(progress.count) >= goal.required_count: continue
				var amount := int(event.get("amount", 1))
				var total := int(progress.count) + amount if goal.count_mode == OBJECTIVE.CountMode.COUNT else maxi(int(progress.count), amount)
				if total == int(progress.count): continue
				progress.count = mini(total, goal.required_count)
				event_changed = true
		if event_changed:
			if not state.receipts.has(event.event_key): state.receipts[event.event_key] = []
			state.receipts[event.event_key].append(event.event_id)
			changed = true
		# A newly unlocked quest starts with the next event, not this same receipt.
		_refresh(state)
	return changed

func view(state: Dictionary, id: String) -> Dictionary:
	if not definitions.has(id): return {}
	var quest: DEFINITION = definitions[id]
	var entry: Dictionary = state.entries[id]
	var goals: Array[Dictionary] = []
	for goal in quest.objectives:
		goals.append({"id":str(goal.id), "description_key":goal.description_key,
			"count":int(entry.objectives[str(goal.id)].count), "required_count":goal.required_count})
	return {"id":id, "title_key":quest.title_key, "description_key":quest.description_key,
		"state":entry.state, "objectives":goals, "prerequisite_ids":quest.prerequisite_ids.duplicate(),
		"reward_magic":quest.reward_magic, "reward_rune_ids":quest.reward_rune_ids.duplicate(),
		"reward_relic_ids":quest.reward_relic_ids.duplicate()}

static func valid_state(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not value.get("entries") is Dictionary or not value.get("receipts") is Dictionary: return false
	for event_key: Variant in value.receipts:
		if not event_key is String or event_key.is_empty() or not value.receipts[event_key] is Array: return false
		var seen := {}
		for receipt: Variant in value.receipts[event_key]:
			if not receipt is String or receipt.is_empty() or seen.has(receipt): return false
			seen[receipt] = true
	for id: Variant in value.entries:
		var entry: Variant = value.entries[id]
		if not id is String or id.is_empty() or not entry is Dictionary or entry.get("state") not in STATES or not entry.get("objectives") is Dictionary: return false
		for goal_id: Variant in entry.objectives:
			var progress: Variant = entry.objectives[goal_id]
			if not goal_id is String or goal_id.is_empty() or not progress is Dictionary or not _nonnegative_integer(progress.get("count")): return false
	return true

static func _nonnegative_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) <= 1000000000 and float(value) == floor(float(value))
