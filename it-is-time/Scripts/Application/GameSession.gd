extends "res://Modules/PaperUI/Scripts/PrototypeState.gd"
## One slot owns economy, creatures, map sessions and committed battle receipts.

signal changed
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const SUPPORTED_RUNES := ["health","armor","attack","iron","bloodblade","vitality","fang","haste"]
var integration_logging := false
var pending_result: Dictionary = {}
var _recovered_backup := false

func reset() -> void:
	super.reset()
	data.merge({"schema_version":1,"worlds":{},"battle":{},"battle_results":{},"transactions":[],"day":1},true)

func save() -> bool:
	var directory := ProjectSettings.globalize_path(save_path.get_base_dir())
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		last_error = "无法创建存档目录："+error_string(error)
		return false
	if not _valid_save(data):
		last_error = "状态校验失败，未覆盖存档。"
		return false
	# Do not overwrite the good backup with the corrupt main file we recovered from.
	if _recovered_backup and FileAccess.file_exists(save_path):
		var source := ProjectSettings.globalize_path(save_path)
		if DirAccess.rename_absolute(source,source+".corrupt_"+str(Time.get_ticks_usec()))!=OK:
			last_error = "无法保留损坏存档；备份未被覆盖。"
			return false
	var success := super.save()
	if success: _recovered_backup = false; changed.emit()
	return success

func load_save() -> bool:
	var success := super.load_save()
	_recovered_backup = success and last_error=="已从备份恢复"
	return success

func _valid_save(value: Variant) -> bool:
	if not super._valid_save(value) or int(value.get("schema_version",0)) != 1: return false
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
		if not map_id is String or not snapshot is Dictionary or not world_validator.validate_save_data(snapshot) or snapshot.map_id!=map_id: return false
	for id: Variant in value.battle_results:
		if not id is String or not _valid_result(value.battle_results[id]) or value.battle_results[id].battle_id!=id: return false
	var pending: Dictionary = value.battle
	if pending.is_empty(): return true
	if not pending.get("battle_id") is String or pending.battle_id.is_empty(): return false
	if pending.get("phase")=="settlement":
		return _valid_result(pending.get("result")) and pending.result.battle_id==pending.battle_id and value.battle_results.has(pending.battle_id)
	if pending.get("phase")!="loading" or not pending.get("party_ids") is Array or pending.party_ids.is_empty(): return false
	if not pending.get("map_id") is String or not pending.get("location_id") is String or not value.worlds.has(pending.map_id): return false
	if value.worlds[pending.map_id].pending_battle.get("location_id")!=pending.location_id: return false
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

func supported_layout(rules) -> String:
	var preview := Experiment.preview(rules)
	if preview.mode != "normal": return "当前接入仅开放普通结构；该结构的真实物理能力尚未接入。"
	for item: Dictionary in rules.placed:
		if item.enabled and item.runeId not in SUPPORTED_RUNES: return "符文“%s”的真实战斗效果尚未接入，不会扣费。" % Rules.definition(item.runeId).name
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
		var id: String = {"人形":"human","兽形":"wolf","蛇形":"snake"}[unit.form]
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

func save_world(snapshot: Dictionary) -> bool:
	var before := data.duplicate(true)
	if not snapshot.get("pending_battle",{}).is_empty() and data.battle.is_empty():
		data.battle = snapshot.pending_battle.duplicate(true)
		data.battle.merge({"battle_id":"battle_"+str(Time.get_unix_time_from_system())+"_"+str(randi()),"party_ids":monsters("team").map(func(unit):return unit.id),"phase":"loading"},true)
	data.worlds[str(snapshot.map_id)] = snapshot.duplicate(true)
	if snapshot.get("pending_battle",{}).is_empty() and data.battle.get("phase","")=="loading": data.battle = {}
	if save(): return true
	data = before
	return false

func unlock_next_stage(current_layout: Dictionary = {}) -> bool:
	var victories := 0
	for result: Dictionary in data.battle_results.values():
		if result.get("outcome")=="victory": victories+=1
	if victories < int(data.array_stage):
		last_error = "需要累计 %d 次胜利才能解锁下一阶。" % int(data.array_stage)
		return false
	return super.unlock_next_stage(current_layout)

func recycle_monster(id: String) -> bool:
	if id in data.battle.get("party_ids",[]):
		last_error = "已部署的生物在战斗结束前不能回收。"
		return false
	return super.recycle_monster(id)

func commit_battle(result: Dictionary, world_snapshot: Dictionary) -> bool:
	if not _valid_result(result): last_error = "无效战斗回执。"; return false
	var id: String = result.battle_id
	if data.battle_results.has(id): return true
	if data.battle.get("battle_id","") != id: last_error = "战斗回执与待处理战斗不匹配。"; return false
	var before := data.duplicate(true)
	data.magic += int(result.get("reward",0))
	data.battle_results[id] = result.duplicate(true)
	data.worlds[str(world_snapshot.map_id)] = world_snapshot.duplicate(true)
	data.battle = {"battle_id":id,"phase":"settlement","result":result.duplicate(true)}
	if not save(): data = before; return false
	trace("battle_commit",{"battle_id":id,"outcome":result.outcome})
	return true

func trace(event: String, detail: Dictionary = {}) -> void:
	if integration_logging: print("[integration] event=",event," data=",detail)

