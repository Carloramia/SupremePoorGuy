extends "res://Modules/PaperUI/Scripts/PrototypeState.gd"
## One slot owns economy, creatures, map sessions and committed battle receipts.

signal changed
signal quests_changed
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const QUEST_SERVICE = preload("res://Scripts/Quests/QuestService.gd")
const QUEST_DEFINITION = preload("res://Scripts/Quests/QuestDefinition.gd")
const SUPPORTED_RUNES := ["health","armor","attack","iron","bloodblade","vitality","fang","haste"]
const DELIVERY_RUNTIME = preload("res://Modules/FrontierDelivery/Scripts/Map/WorldMapRuntime.gd")
const DELIVERY_MAP := "frontier_layout"
var integration_logging := false
var pending_result: Dictionary = {}
var _recovered_backup := false
var _needs_schema_backup := false
var _needs_quest_backup := false
var _quest_service := QUEST_SERVICE.new()
var _saved_quests: Dictionary = {}

func reset() -> void:
	super.reset()
	data.merge({"schema_version":2,"worlds":{},"battle":{},"battle_results":{},"transactions":[],"day":1},true)
	data.quests = QUEST_SERVICE.empty_state()
	if _quest_service != null: _quest_service.synchronize(data.quests)

func save() -> bool:
	var directory := ProjectSettings.globalize_path(save_path.get_base_dir())
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		last_error = "无法创建存档目录："+error_string(error)
		return false
	if not _valid_save(data):
		last_error = "状态校验失败，未覆盖存档。"
		return false
	if _needs_schema_backup:
		var source_path := save_path+".bak" if _recovered_backup else save_path
		var backup_path := save_path+".pre_delivery_v2.bak"
		if FileAccess.file_exists(source_path) and not FileAccess.file_exists(backup_path) and DirAccess.copy_absolute(ProjectSettings.globalize_path(source_path),ProjectSettings.globalize_path(backup_path))!=OK:
			last_error = "无法备份地图升级前的存档。"
			return false
	if _needs_quest_backup:
		var source_path := save_path+".bak" if _recovered_backup else save_path
		var backup_path := save_path+".pre_quests_v1.bak"
		if FileAccess.file_exists(source_path) and not FileAccess.file_exists(backup_path) and DirAccess.copy_absolute(ProjectSettings.globalize_path(source_path),ProjectSettings.globalize_path(backup_path))!=OK:
			last_error = "无法备份任务升级前的存档。"
			return false
	# Do not overwrite the good backup with the corrupt main file we recovered from.
	if _recovered_backup and FileAccess.file_exists(save_path):
		var source := ProjectSettings.globalize_path(save_path)
		if DirAccess.rename_absolute(source,source+".corrupt_"+str(Time.get_ticks_usec()))!=OK:
			last_error = "无法保留损坏存档；备份未被覆盖。"
			return false
	var success := super.save()
	if success:
		_recovered_backup = false
		_needs_schema_backup = false
		_needs_quest_backup = false
		var quest_change: bool = _saved_quests != data.quests
		_saved_quests = data.quests.duplicate(true)
		changed.emit()
		if quest_change: quests_changed.emit()
	return success

func load_save() -> bool:
	var success := super.load_save()
	_recovered_backup = success and last_error=="已从备份恢复"
	if success and int(data.schema_version)==1:
		data.schema_version = 2
		for snapshot: Dictionary in data.worlds.values(): snapshot.backend = "legacy_frontier"
		_needs_schema_backup = true
	if success:
		_needs_quest_backup = not data.has("quests")
		if _needs_quest_backup: data.quests = QUEST_SERVICE.empty_state()
		_quest_service.synchronize(data.quests)
		_saved_quests = data.quests.duplicate(true)
	return success

func _valid_save(value: Variant) -> bool:
	if not super._valid_save(value) or int(value.get("schema_version",0)) not in [1,2]: return false
	if value.has("quests") and not QUEST_SERVICE.valid_state(value.quests): return false
	for key: String in ["worlds","battle","battle_results"]:
		if not value.get(key) is Dictionary: return false
	if not value.get("transactions") is Array: return false
	if not value.get("pending_location") is String or value.get("pending_return") not in ["world","battle"]: return false
	for entry: Variant in value.transactions:
		if not entry is String: return false
	for record: Dictionary in value.monsters:
		if not FACTORY.valid_record(record): return false
	var world_validator := WorldMapSaveService.new()
	for map_id: Variant in value.worlds:
		var snapshot: Variant = value.worlds[map_id]
		if not map_id is String or not snapshot is Dictionary or snapshot.get("map_id")!=map_id: return false
		var backend: String = snapshot.get("backend","legacy_frontier" if int(value.schema_version)==1 else "")
		if backend=="frontier_delivery_v1":
			if not DELIVERY_RUNTIME.valid_snapshot(snapshot) or not snapshot.get("active_battle",{}).is_empty() or not snapshot.get("battle_receipts",{}).is_empty(): return false
		elif backend!="legacy_frontier" or not world_validator.validate_save_data(snapshot): return false
	for id: Variant in value.battle_results:
		if not id is String or not _valid_result(value.battle_results[id]) or value.battle_results[id].battle_id!=id: return false
	var pending: Dictionary = value.battle
	if pending.is_empty(): return true
	if not pending.get("battle_id") is String or pending.battle_id.is_empty(): return false
	if pending.get("phase")=="settlement":
		return _valid_result(pending.get("result")) and pending.result.battle_id==pending.battle_id and value.battle_results.has(pending.battle_id)
	if pending.get("phase")!="loading" or not pending.get("party_ids") is Array or pending.party_ids.is_empty(): return false
	if not pending.get("map_id") is String or not pending.get("location_id") is String or not value.worlds.has(pending.map_id): return false
	if pending.map_id==DELIVERY_MAP:
		var probe: Dictionary = value.worlds[pending.map_id].duplicate(true)
		probe.active_battle = pending.duplicate(true)
		if pending.get("request_id")!=pending.battle_id or not DELIVERY_RUNTIME.valid_snapshot(probe): return false
	elif value.worlds[pending.map_id].pending_battle.get("location_id")!=pending.location_id: return false
	var seen := {}
	for id: Variant in pending.party_ids:
		if not id is String or seen.has(id): return false
		seen[id] = true
		var found := false
		for creature: Dictionary in value.monsters:
			if creature.id==id: found=true
		if not found: return false
	return true

func _valid_result(value: Variant) -> bool:
	if not value is Dictionary or not value.get("battle_id") is String or value.battle_id.is_empty(): return false
	if value.get("outcome") not in ["victory","defeat","retreat"] or not value.get("parts") is Dictionary: return false
	var reward: Variant = value.get("reward")
	return (reward is int or reward is float) and is_finite(float(reward)) and float(reward)>=0

## Configure before loading/creating a slot. This does not write to disk.
func configure_quests(definitions: Array) -> bool:
	var candidate := QUEST_SERVICE.new()
	last_error = candidate.configure(definitions)
	if not last_error.is_empty(): return false
	for quest: QUEST_DEFINITION in candidate.definitions.values():
		for pair: Array in [[quest.reward_rune_ids, false], [quest.reward_relic_ids, true]]:
			for reference_id: StringName in pair[0]:
				if Rules.definition(str(reference_id),pair[1]).is_empty():
					last_error = "任务 %s 引用了不存在的奖励 %s。" % [quest.id,reference_id]
					return false
	_quest_service = candidate
	_quest_service.synchronize(data.quests)
	return true

func get_quest(id: StringName) -> Dictionary:
	return _quest_service.view(data.quests,str(id))

func get_quests(states: PackedStringArray = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _quest_service.definitions:
		var quest := get_quest(StringName(id))
		if states.is_empty() or quest.state in states: result.append(quest)
	return result

func accept_quest(id: StringName) -> bool:
	var before := data.duplicate(true)
	last_error = _quest_service.accept(data.quests,str(id))
	if not last_error.is_empty(): return false
	if save(): return true
	data = before
	return false

## Stable event_id identifies a business receipt, never a frame or button click.
func record_quest_event(event_key: StringName, event_id: String, target_id: StringName = &"", amount: int = 1, historical: bool = false) -> bool:
	return record_quest_events([{"event_key":str(event_key), "event_id":event_id,
		"target_id":str(target_id), "amount":amount, "historical":historical}])

func record_quest_events(events: Array) -> bool:
	last_error = ""
	if not QUEST_SERVICE.valid_events(events): last_error = "任务事件格式无效。"; return false
	var before := data.duplicate(true)
	if not _quest_service.apply_events(data.quests,events): return true
	if save(): return true
	data = before
	return false

func claim_quest_reward(id: StringName) -> bool:
	var quest := get_quest(id)
	if quest.is_empty() or quest.state != "completed": last_error = "任务尚未完成或奖励已经领取。"; return false
	var before := data.duplicate(true)
	data.quests.entries[str(id)].state = "claimed"
	# The existing reward transaction saves both the claim marker and the reward.
	if super.claim_once("quest:"+str(id),quest.reward_magic,quest.reward_rune_ids,quest.reward_relic_ids): return true
	data = before
	return false

func supported_layout(rules) -> String:
	var preview := Experiment.preview(rules)
	if preview.mode != "normal": return "当前接入仅开放普通结构；该结构的真实物理能力尚未接入。"
	for item: Dictionary in rules.placed:
		if item.enabled and item.runeId not in SUPPORTED_RUNES: return L10N.text("ui.5ba1eb826c67") % Rules.definition(item.runeId).name
	for relic: Dictionary in rules.relics:
		if relic.relicId!="bone-die": return "该奇物的实际效果尚未接入，不会扣费。"
	return ""

func summon(rules, at: String, back: String, test_rng: RandomNumberGenerator = null) -> bool:
	last_error = supported_layout(rules)
	if not last_error.is_empty(): return false
	if not data.pending.is_empty() or not rules.draft.is_empty():
		last_error = "请先安置已有结果，并刻入或取消当前笔画。"
		return false
	var checked = Rules.new()
	var layout: Dictionary = rules.export_layout()
	if rules.stage != int(data.array_stage) or not checked.import_layout(layout) or checked.placed.size()!=rules.placed.size() or checked.relics.size()!=rules.relics.size():
		last_error = "法阵布局无效。"
		return false
	var preview := Experiment.preview(rules)
	if preview.counts.is_empty() or not preview.error.is_empty() or data.magic < preview.cost:
		last_error = preview.error if not preview.error.is_empty() else "有效符文不足或魔力不足。"
		return false
	var before := data.duplicate(true)
	var rng := test_rng if test_rng != null else RandomNumberGenerator.new()
	if test_rng == null: rng.randomize()
	var seed_value := rng.seed
	var generated := Experiment.generate(rules,int(data.serial)+1,at,rng)
	for unit: Dictionary in generated.units:
		var id: String = FACTORY.SUMMON_POOL[rng.randi_range(0,FACTORY.SUMMON_POOL.size()-1)]
		var real := FACTORY.template(id)
		if real.is_empty(): last_error = "物种模板无法加载。"; return false
		var hp_ratio := float(unit.hp)/maxf(float(unit.base_stats.hp),1.0)
		var armor_ratio := float(unit.armor)/maxf(float(unit.base_stats.armor),1.0)
		var attack_ratio := float(unit.attack)/maxf(float(unit.base_stats.attack),1.0)
		var interval_ratio := float(unit.interval)/1.5
		var speed_ratio := float(unit.speed)/3.0
		unit.merge(real,true)
		unit.hp = 0.0
		for part: Dictionary in unit.parts.values():
			part.hp *= hp_ratio
			part.armor *= armor_ratio
			unit.hp += part.hp
		unit.armor *= armor_ratio
		unit.attack *= attack_ratio
		unit.damage_multiplier = attack_ratio
		unit.interval_multiplier = interval_ratio
		unit.interval = 1.5*interval_ratio
		unit.speed_multiplier = speed_ratio
		unit.speed *= speed_ratio
		unit.generator_seed = str(seed_value)
		unit.position = "pending"
		unit.erase("part_hp")
		data.monsters.append(unit)
		data.pending.append(unit.id)
	data.serial += 1
	data.magic -= preview.cost
	data.pending_location = at
	data.pending_return = back
	data.layout = layout
	data.last_summon = generated.report
	data.transactions.append("summon_"+str(data.serial))
	if not save(): data = before; trace("summon_rollback",{"reason":last_error}); return false
	trace("summon_commit",{"batch":data.serial,"count":data.pending.size(),"cost":preview.cost})
	return true

func save_world(snapshot: Dictionary, quest_events: Array = []) -> bool:
	if not QUEST_SERVICE.valid_events(quest_events): last_error = "任务事件格式无效。"; return false
	var before := data.duplicate(true)
	if not snapshot.get("pending_battle",{}).is_empty() and data.battle.is_empty():
		data.battle = snapshot.pending_battle.duplicate(true)
		data.battle.merge({"battle_id":"battle_"+str(Time.get_unix_time_from_system())+"_"+str(randi()),"party_ids":monsters("team").map(func(unit):return unit.id),"phase":"loading"},true)
	data.worlds[str(snapshot.map_id)] = tagged_world(snapshot,"legacy_frontier")
	if snapshot.get("pending_battle",{}).is_empty() and data.battle.get("phase","")=="loading": data.battle = {}
	_quest_service.apply_events(data.quests,quest_events)
	if save(): return true
	data = before
	return false

func unlock_next_stage(current_layout: Dictionary = {}) -> bool:
	var victories := 0
	for result: Dictionary in data.battle_results.values():
		if result.get("outcome")=="victory": victories+=1
	if victories < int(data.array_stage):
		last_error = L10N.text("ui.b48fe8be685e") % int(data.array_stage)
		return false
	return super.unlock_next_stage(current_layout)

func recycle_monster(id: String) -> bool:
	if id in data.battle.get("party_ids",[]):
		last_error = "已部署的生物在战斗结束前不能回收。"
		return false
	return super.recycle_monster(id)

func commit_battle(result: Dictionary, world_snapshot: Dictionary, quest_events: Array = []) -> bool:
	if not QUEST_SERVICE.valid_events(quest_events): last_error = "任务事件格式无效。"; return false
	if not _valid_result(result): last_error = "无效战斗回执。"; return false
	var id: String = result.battle_id
	if data.battle_results.has(id): return true
	if data.battle.get("battle_id","") != id: last_error = "战斗回执与待处理战斗不匹配。"; return false
	var before := data.duplicate(true)
	data.magic += int(result.get("reward",0))
	data.battle_results[id] = result.duplicate(true)
	data.battle_results[id].map_id = world_snapshot.map_id
	var backend := "frontier_delivery_v1" if world_snapshot.map_id==DELIVERY_MAP else "legacy_frontier"
	data.worlds[str(world_snapshot.map_id)] = tagged_world(world_snapshot,backend)
	data.battle = {"battle_id":id,"map_id":world_snapshot.map_id,"phase":"settlement","result":result.duplicate(true)}
	_quest_service.apply_events(data.quests,quest_events)
	if not save(): data = before; return false
	trace("battle_commit",{"battle_id":id,"outcome":result.outcome})
	return true

func tagged_world(snapshot: Dictionary, backend: String) -> Dictionary:
	var result := snapshot.duplicate(true)
	result.backend = backend
	if backend=="frontier_delivery_v1":
		result.active_battle = {}
		result.battle_receipts = {}
	return result

func save_delivery_world(snapshot: Dictionary, request: Dictionary = {}, quest_events: Array = []) -> bool:
	if not QUEST_SERVICE.valid_events(quest_events): last_error = "任务事件格式无效。"; return false
	var before := data.duplicate(true)
	data.worlds[DELIVERY_MAP] = tagged_world(snapshot,"frontier_delivery_v1")
	if not request.is_empty():
		if not data.battle.is_empty(): last_error = "已有待处理战斗。"; data = before; return false
		data.battle = request.duplicate(true)
		data.battle.merge({"battle_id":request.request_id,"map_id":DELIVERY_MAP,"phase":"loading"},true)
	_quest_service.apply_events(data.quests,quest_events)
	if save(): return true
	data = before
	return false

func delivery_snapshot() -> Dictionary:
	var snapshot: Dictionary = data.worlds.get(DELIVERY_MAP,{}).duplicate(true)
	if snapshot.is_empty(): snapshot = DELIVERY_RUNTIME.new().snapshot()
	if not data.battle.is_empty() and data.battle.get("map_id")==DELIVERY_MAP and data.battle.get("phase")=="loading": snapshot.active_battle = data.battle.duplicate(true)
	for id: String in data.battle_results:
		var result: Dictionary = data.battle_results[id]
		if result.get("map_id")==DELIVERY_MAP: snapshot.battle_receipts[id] = {"request_id":id,"outcome":result.outcome}
	return snapshot

func trace(event: String, detail: Dictionary = {}) -> void:
	if integration_logging: print("[integration] event=",event," data=",detail)

