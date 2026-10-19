extends "res://Modules/PaperUI/Scripts/PrototypeState.gd"
## One slot owns economy, creatures, map sessions and committed battle receipts.

signal changed
signal new_player_tasks_completed(task_ids: Array)
signal story_events_changed
const STORY_EVENTS = preload("res://Scripts/Events/StoryEventService.gd")
const STORY_RESOURCES = preload("res://Scripts/Events/StoryEventResources.gd")
const HEX_PROGRESS = preload("res://Scripts/Events/HexMapProgress.gd")
const NEW_PLAYER_TASKS = preload("res://Scripts/Application/NewPlayerTasks.gd")
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const SUPPORTED_RUNES := ["health","armor","attack","iron","bloodblade","vitality","fang","haste"]
const DELIVERY_RUNTIME = preload("res://Modules/FrontierDelivery/Scripts/Map/WorldMapRuntime.gd")
const DELIVERY_MAP := "frontier_layout"
var integration_logging := false
var pending_result: Dictionary = {}
var _recovered_backup := false
var _needs_schema_backup := false
var task_definitions: Array = NEW_PLAYER_TASKS.DEFINITIONS.duplicate(true)
var story_events := STORY_EVENTS.new()
var _story_business_active := false

func reset() -> void:
	super.reset()
	data.merge({"schema_version":2,"worlds":{},"battle":{},"battle_results":{},"transactions":[],"day":1},true)
	data["known_relics"]=["tide-pump","prism-heart","bone-die"]

func save() -> bool:
	if _story_business_active:
		last_error = "事件资源适配器不得嵌套保存。"
		return false
	# Apply task completion and rewards inside the same transaction as business data.
	if not _valid_save(data):
		last_error = "状态校验失败，未覆盖存档。"
		return false
	var before := data.duplicate(true)
	var tasks: Dictionary = NEW_PLAYER_TASKS.reconcile(data,task_definitions)
	if not tasks.ok:
		data = before
		last_error = tasks.error
		return false
	story_events.reconcile(data)
	if not _save_session_file():
		data = before
		return false
	if not tasks.completed.is_empty(): new_player_tasks_completed.emit(tasks.completed)
	story_events_changed.emit()
	return true

func _save_session_file() -> bool:
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
	# Do not overwrite the good backup with the corrupt main file we recovered from.
	if _recovered_backup and FileAccess.file_exists(save_path):
		var source := ProjectSettings.globalize_path(save_path)
		if DirAccess.rename_absolute(source,source+".corrupt_"+str(Time.get_ticks_usec()))!=OK:
			last_error = "无法保留损坏存档；备份未被覆盖。"
			return false
	var success := super.save()
	if success: _recovered_backup = false; _needs_schema_backup = false; changed.emit()
	return success

func load_save() -> bool:
	var success := super.load_save()
	if success and not data.has("known_relics"): data["known_relics"]=["tide-pump","prism-heart","bone-die"]
	_recovered_backup = success and last_error=="已从备份恢复"
	if success and int(data.schema_version)==1:
		data.schema_version = 2
		for snapshot: Dictionary in data.worlds.values(): snapshot.backend = "legacy_frontier"
		_needs_schema_backup = true
	return success

func _valid_save(value: Variant) -> bool:
	if not super._valid_save(value) or int(value.get("schema_version",0)) not in [1,2]: return false
	if not NEW_PLAYER_TASKS.valid_progress(value): return false
	if not STORY_EVENTS.valid_progress(value): return false
	if not STORY_RESOURCES.valid_inventory(value): return false
	if value.has("hex_map") and not HEX_PROGRESS.valid(value.hex_map): return false
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

func enable_new_player_tasks() -> bool:
	var before := data.duplicate(true)
	NEW_PLAYER_TASKS.ensure_progress(data).enabled = true
	var probe := data.duplicate(true)
	var result: Dictionary = NEW_PLAYER_TASKS.reconcile(probe,task_definitions)
	if not result.ok:
		data = before
		last_error = result.error
		return false
	if probe==before: return true
	if save(): return true
	data = before
	return false

func record_task_arrival(map_id: String, location_id: String) -> bool:
	var before := data.duplicate(true)
	NEW_PLAYER_TASKS.record_location(data,map_id,location_id)
	if save(): return true
	data = before
	return false

func new_player_task_rows() -> Array:
	return NEW_PLAYER_TASKS.rows(data,task_definitions)

func new_player_task_action(task_id: String) -> String:
	for row: Dictionary in new_player_task_rows():
		if row.id==task_id and not row.done and not row.locked: return row.action
	return ""

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
		if relic.relicId not in ["bone-die","prism-heart","giant-tusk","crystal-carapace","crystal-eye"]: return "该奇物的实际效果尚未接入，不会扣费。"
		if relic.relicId not in known_references(true): return "该奇物尚未解锁。"
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
		if HEX_PROGRESS.rain_active(data): hp_ratio*=1.1; unit.traits.append("血雨祝福")
		var armor_ratio: float=unit.get("physical_stat_ratios",{}).get("armor",float(unit.armor)/maxf(float(unit.base_stats.armor),1.0))
		var attack_ratio: float=unit.get("physical_stat_ratios",{}).get("attack",float(unit.attack)/maxf(float(unit.base_stats.attack),1.0))
		var interval_ratio := float(unit.interval)/1.5
		var speed_ratio := float(unit.speed)/3.0
		unit.merge(real,true)
		if rules.relics.any(func(relic):return relic.relicId=="crystal-eye") and rng.randf()<0.1:
			unit.magic_eye=true; unit.traits.append("魔眼")
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
	data.worlds[str(snapshot.map_id)] = tagged_world(snapshot,"legacy_frontier")
	if snapshot.get("pending_battle",{}).is_empty() and data.battle.get("phase","")=="loading": data.battle = {}
	if save(): return true
	data = before
	return false

func save_hex_world(snapshot: Dictionary) -> bool:
	if not HEX_PROGRESS.valid(snapshot): last_error="新地图快照无效，未覆盖进度。"; return false
	var before:=data.duplicate(true)
	var previous: Dictionary=data.get("hex_map",{})
	var distance:=maxf(0.0,float(snapshot.travel_distance)-float(previous.get("travel_distance",snapshot.travel_distance)))
	var day: float=STORY_EVENTS.ensure(data).clock.day if STORY_EVENTS.ensure(data).clock.ready else 1.0
	day+=distance/2400.0
	data["hex_map"]=snapshot.duplicate(true)
	for key: String in ["discovered","visited","cleared","destroyed"]:
		for id: String in previous.get(key,[]):
			if id not in data.hex_map[key]: data.hex_map[key].append(id)
	data.hex_map.game_day=day
	var error:=story_events.set_game_day(data,day)
	if not error.is_empty(): data=before; last_error=error; return false
	if save(): return true
	data=before
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
	for event: Dictionary in data.get("story_events",{}).get("entries",{}).values():
		for record: Dictionary in event.get("pending",{}).get("plan",{}).get("frozen_rosters",{}).get("left",[]):
			if record.id==id: last_error="事件战斗尚未结算，该怪物不能回收。"; return false
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
	data.battle_results[id].map_id = world_snapshot.map_id
	var backend := "frontier_delivery_v1" if world_snapshot.map_id==DELIVERY_MAP else "legacy_frontier"
	data.worlds[str(world_snapshot.map_id)] = tagged_world(world_snapshot,backend)
	data.battle = {"battle_id":id,"map_id":world_snapshot.map_id,"phase":"settlement","result":result.duplicate(true)}
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

func save_delivery_world(snapshot: Dictionary, request: Dictionary = {}) -> bool:
	var before := data.duplicate(true)
	data.worlds[DELIVERY_MAP] = tagged_world(snapshot,"frontier_delivery_v1")
	if not request.is_empty():
		if not data.battle.is_empty(): last_error = "已有待处理战斗。"; data = before; return false
		data.battle = request.duplicate(true)
		data.battle.merge({"battle_id":request.request_id,"map_id":DELIVERY_MAP,"phase":"loading"},true)
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

func _save_story_change(before: Dictionary, result: Dictionary) -> Dictionary:
	if not result.get("ok",false):
		data = before
		last_error = result.get("error","事件操作失败。")
		return result
	if data==before: return result
	if save():
		return result
	data = before
	return {"ok":false,"error":last_error}

func story_world_entered() -> bool:
	var before := data.duplicate(true)
	story_events.reconcile(data,true)
	return _save_story_change(before,{"ok":true}).ok

func set_story_game_day(day: float) -> bool:
	var before := data.duplicate(true)
	var error := story_events.set_game_day(data,day)
	return _save_story_change(before,{"ok":error.is_empty(),"error":error}).ok

func open_story_event(id: String, entrance: String, safe: bool) -> Dictionary:
	var before := data.duplicate(true)
	return _save_story_change(before,story_events.open(data,id,entrance,safe))

func story_event_action(id: String, branch: String, conversation: String, payload: Dictionary = {}) -> Dictionary:
	var before := data.duplicate(true)
	return _save_story_change(before,story_events.act(data,id,branch,conversation,payload))

func commit_story_receipt(receipt: Dictionary, apply_business: Callable = Callable()) -> bool:
	# Trusted host interface. UI must never fabricate receipts. Business callback
	# mutates only this save dictionary and returns an error string; no nested save.
	var before := data.duplicate(true)
	var error := story_events.check_receipt(data,receipt)
	if not error.is_empty(): data = before; last_error = error; return false
	if STORY_EVENTS.ensure(data).receipts.has(receipt.request_id): return true
	var request := story_events.pending_request(data,receipt.event_id)
	error = story_events.revalidate_operation(data,request)
	if not error.is_empty(): data = before; last_error = error; return false
	if request.kind in ["transaction","purchase","sacrifice","bet"]:
		if not apply_business.is_valid(): data = before; last_error = "缺少正式资源事务适配器，未推进事件。"; return false
		_story_business_active = true
		var result: Variant = apply_business.call(data,request.duplicate(true))
		_story_business_active = false
		if not result is String or not result.is_empty():
			data = before
			last_error = result if result is String else "资源事务必须返回错误字符串。"
			return false
	error = story_events.commit_receipt(data,receipt)
	return _save_story_change(before,{"ok":error.is_empty(),"error":error}).ok

func story_event_view(id: String) -> Dictionary:
	return story_events.view(data,id)

func record_story_arrival(id: String, entrance: String, map_id: String = "", location_id: String = "") -> bool:
	if not story_events.definitions.has(id) or entrance not in story_events.definitions[id].entries:
		last_error = "地编绑定的事件ID或入口键不存在。"
		return false
	var before := data.duplicate(true)
	var e := story_events.entry(data,id)
	if entrance not in e.seen: e.seen.append(entrance)
	if not location_id.is_empty(): e["source_site_id"]=location_id
	NEW_PLAYER_TASKS.record_location(data,map_id,location_id)
	return _save_story_change(before,{"ok":true}).ok

func pending_story_request(id: String) -> Dictionary:
	return story_events.pending_request(data,id)

func commit_story_battle(receipt: Dictionary, result: Dictionary, site_id: String) -> bool:
	var before:=data.duplicate(true)
	var error:=story_events.check_receipt(data,receipt)
	if not error.is_empty(): data=before; last_error=error; return false
	if STORY_EVENTS.ensure(data).receipts.has(receipt.request_id): return true
	var request:=pending_story_request(receipt.event_id)
	error=story_events.commit_receipt(data,receipt)
	if not error.is_empty(): data=before; last_error=error; return false
	if request.kind=="battle" and _valid_result(result):
		data.battle_results[str(result.battle_id)]=result.duplicate(true)
		data.battle_results[str(result.battle_id)]["site_id"]=site_id
		data.battle_results[str(result.battle_id)]["map_id"]="hex_frontier_20261019"
	if request.kind=="battle" and result.outcome=="victory" and data.has("hex_map") and not site_id.is_empty() and site_id not in data.hex_map.cleared: data.hex_map.cleared.append(site_id)
	return _save_story_change(before,{"ok":true}).ok

func save_story_checkpoint(request: Dictionary, checkpoint: Dictionary) -> bool:
	var current:=pending_story_request(request.event_id)
	if current.get("request_id")!=request.get("request_id"): last_error="战斗快照与待处理请求不匹配。"; return false
	var before:=data.duplicate(true)
	story_events.entry(data,request.event_id).pending.plan["checkpoint"]=checkpoint.duplicate(true)
	return _save_story_change(before,{"ok":true}).ok

func freeze_story_rosters(request: Dictionary, left: Array, right: Array) -> bool:
	var current:=pending_story_request(request.event_id)
	if current.get("request_id")!=request.get("request_id"): last_error="战斗请求失效。"; return false
	if current.plan.has("frozen_rosters"): return true
	for record: Dictionary in left+right:
		if not FACTORY.valid_record(record): last_error="事件阵容包含无效怪物。"; return false
	var before:=data.duplicate(true)
	story_events.entry(data,request.event_id).pending.plan["frozen_rosters"]={"left":left.duplicate(true),"right":right.duplicate(true)}
	return _save_story_change(before,{"ok":true}).ok

func ready_story_events(safe: bool) -> Array:
	return story_events.ready_events(data,safe)

