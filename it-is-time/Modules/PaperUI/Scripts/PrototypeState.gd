extends RefCounted
const L10N = preload("res://Scripts/Localization/GameText.gd")
const Rules = preload("res://Modules/PaperUI/Scripts/Ritual/RuneRules.gd")
const Experiment = preload("res://Modules/PaperUI/Scripts/SummonExperiment.gd")
const TEAM_LIMIT = 6
const BATCH_SIZE = 5
const SAVE_VERSION = 1
var save_path: String = "user://prototype_session.json"
var data: Dictionary = {}
var last_error: String = ""
var last_recycled_name := ""

func _init() -> void:
	reset()

func reset() -> void:
	data = {"version":SAVE_VERSION, "magic":300, "serial":0, "monsters":[], "pending":[], "pending_location":"grassland", "pending_return":"world", "completed":[], "array_stage":1,"last_summon":{},"layout":{"version":3,"stage":1,"placed":[],"placedRelics":[]}}

func save() -> bool:
	last_error = ""
	# Preserve the first pre-upgrade file separately from the rotating .bak.
	if data.has("legacy_summon_layout") and FileAccess.file_exists(save_path) and not FileAccess.file_exists(save_path+".pre_summon_v2.bak"):
		var original := JSON.new()
		if original.parse(FileAccess.get_file_as_string(save_path)) == OK and original.data is Dictionary and original.data.get("layout") is Dictionary and int(original.data.layout.get("version",0)) < 3:
			var old_path := ProjectSettings.globalize_path(save_path)
			if DirAccess.copy_absolute(old_path,old_path+".pre_summon_v2.bak") != OK:
				last_error = "无法保留召唤升级前的存档"
				return false
	var f := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if f == null:
		last_error = L10N.text("ui.af3b38a8fcd5") % error_string(FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(data,"",true,true))
	f.flush()
	var write_error := f.get_error()
	f.close()
	if write_error != OK:
		last_error = "存档写入失败"
		return false
	var path := ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path):
		if DirAccess.copy_absolute(path, path + ".bak") != OK:
			last_error = "无法保留旧存档备份"
			return false
	var error := DirAccess.rename_absolute(path + ".tmp", path)
	if error != OK:
		last_error = L10N.text("ui.ae2a11140767") % error_string(error)
	return error == OK

func load_save() -> bool:
	for path in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(path):
			continue
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(path)) != OK:
			continue
		var parsed = parser.data
		if _valid_save(parsed):
			data = parsed
			_prepare_summon_save()
			last_error = "已从备份恢复" if path.ends_with(".bak") else ""
			return true
	last_error = "存档不存在或损坏，未覆盖原文件"
	return false

func _valid_save(value: Variant) -> bool:
	if not value is Dictionary or int(value.get("version",0)) != SAVE_VERSION:
		return false
	for key in ["monsters", "pending", "completed"]:
		if not value.get(key) is Array:
			return false
	if not value.get("layout") is Dictionary or not value.get("magic") is float and not value.get("magic") is int:
		return false
	if value.magic < 0 or not is_finite(float(value.magic)):
		return false
	if not value.has("serial") or not value.has("pending_location") or not value.has("pending_return"):
		return false
	if int(value.layout.get("version",0)) >= 3:
		var candidate = Rules.new()
		if int(value.get("array_stage",0)) != int(value.layout.get("stage",0)) or not candidate.import_layout(value.layout) or candidate.placed.size() != value.layout.placed.size() or candidate.relics.size() != value.layout.get("placedRelics",[]).size():
			return false
		if not value.get("last_summon") is Dictionary:
			return false
	var ids: Array = []
	var pending_ids: Array = []
	for monster in value.monsters:
		if not monster is Dictionary:
			return false
		for key in ["id","name","form","hp","attack","armor","speed","traits","position","color"]:
			if not monster.has(key):
				return false
		if not monster.traits is Array or monster.id in ids or monster.position not in ["warehouse","team","pending"]:
			return false
		for key in ["id","name","form","color"]:
			if not monster[key] is String or str(monster[key]).is_empty():
				return false
		if monster.form not in ["人形","兽形","蛇形"] or not Color.html_is_valid(monster.color):
			return false
		for key in ["hp","attack","armor","speed"]:
			if not (monster[key] is int or monster[key] is float) or not is_finite(float(monster[key])) or float(monster[key])<0:
				return false
		for ability_name in monster.traits:
			if not ability_name is String:
				return false
		if monster.has("mode") and not _valid_summon_unit(monster):
			return false
		ids.append(monster.id)
		if monster.position == "pending":
			pending_ids.append(monster.id)
	var seen_pending: Array = []
	for id in value.pending:
		if id in seen_pending or id not in pending_ids:
			return false
		seen_pending.append(id)
		if id not in ids:
			return false
		for m in value.monsters:
			if m.id == id and m.position != "pending":
				return false
	return team_slots(value.monsters) <= TEAM_LIMIT and value.pending.size() <= BATCH_SIZE and pending_ids.size() == value.pending.size()

func monsters(position: String = "") -> Array:
	var result: Array = []
	for monster in data.monsters:
		if position == "" or monster.position == position:
			result.append(monster)
	return result

func monster_by_id(id: String) -> Dictionary:
	for monster in data.monsters:
		if monster.id == id:
			return monster
	return {}

func move_monster(id: String, position: String) -> bool:
	var monster := monster_by_id(id)
	if monster.is_empty() or position not in ["warehouse","team"]:
		last_error = "妖兽或目标位置无效"
		return false
	if position == "team" and not can_join(id):
		last_error = L10N.text("ui.aaa1643bd504") % [slots_after_join(id),TEAM_LIMIT]
		return false
	var before := data.duplicate(true)
	for unit_id in transfer_ids(id):
		monster_by_id(unit_id).position = position
		data.pending.erase(unit_id)
	if not save():
		data = before
		return false
	return true

func rename_monster(id: String, new_name: String) -> bool:
	var monster := monster_by_id(id)
	new_name = new_name.strip_edges().left(24)
	if monster.is_empty() or new_name.is_empty():
		return false
	var before := data.duplicate(true)
	monster.name = new_name
	monster.custom_name = true
	if not save():
		data = before
		return false
	return true

func store_pending() -> bool:
	var before := data.duplicate(true)
	for id in data.pending:
		monster_by_id(id).position = "warehouse"
	data.pending.clear()
	if not save():
		data = before
		return false
	return true

func save_layout(layout: Dictionary) -> bool:
	if int(layout.get("stage",0)) != int(data.array_stage):
		last_error = "法阵解锁状态不一致"
		return false
	var before: Dictionary = data.layout.duplicate(true)
	data.layout = layout.duplicate(true)
	if not save():
		data.layout = before
		return false
	return true

func summon(rules, location: String, return_route: String, test_rng: RandomNumberGenerator = null) -> bool:
	if not data.pending.is_empty():
		last_error = "请先安置上次召唤的妖兽"
		return false
	if not rules.draft.is_empty():
		last_error = "请先刻入或取消当前笔画"
		return false
	var validated = Rules.new()
	var layout: Dictionary = rules.export_layout()
	if rules.stage != int(data.array_stage) or not validated.import_layout(layout) or validated.placed.size()!=rules.placed.size() or validated.relics.size()!=rules.relics.size():
		last_error = "盘面有越界、重叠或解锁状态错误"
		return false
	var preview := Experiment.preview(rules)
	if preview.counts.is_empty():
		last_error = "请至少刻入并启用一枚符文"
		return false
	if not preview.error.is_empty():
		last_error = preview.error
		return false
	if data.magic < preview.cost:
		last_error = L10N.text("ui.1fd297d92c86") % (preview.cost-data.magic)
		return false
	var before := data.duplicate(true)
	data.magic -= preview.cost
	data.serial += 1
	data.pending_location = location
	data.pending_return = return_route
	data.layout = layout
	var rng := test_rng if test_rng != null else RandomNumberGenerator.new()
	if test_rng == null:
		rng.randomize()
	var generated := Experiment.generate(rules,data.serial,location,rng)
	data.last_summon = generated.report
	for unit in generated.units:
		data.monsters.append(unit)
		data.pending.append(unit.id)
	if not save():
		data = before
		return false
	return true # Commit also succeeds when all attempts fail; outcome is in last_summon.

func claim_once(id: String, reward: int, rune_ids: Array = [], relic_ids: Array = []) -> bool:
	if id in data.completed:
		last_error = "此奖励已经领取"
		return false
	var before := data.duplicate(true)
	data.magic += maxi(0,reward)
	data.completed.append(id)
	for pair in [["known_runes",rune_ids],["known_relics",relic_ids]]:
		if not data.has(pair[0]):
			data[pair[0]] = known_references(pair[0] == "known_relics")
		for reference_id in pair[1]:
			if not Rules.definition(reference_id,pair[0] == "known_relics").is_empty() and reference_id not in data[pair[0]]:
				data[pair[0]].append(reference_id)
	if not save():
		data = before
		return false
	return true

func recycle_monster(id: String) -> bool:
	var monster := monster_by_id(id)
	if monster.is_empty() or monster.position == "pending" or not monster.get("recoverable",true):
		last_error = "待安置、不存在或不可回收的怪物不能回收"
		return false
	var before := data.duplicate(true)
	last_recycled_name = monster.name
	data.monsters.erase(monster)
	if not save():
		data = before
		return false
	return true

func known_references(relics: bool = false) -> Array:
	var key := "known_relics" if relics else "known_runes"
	# Older prototype saves had every test reference open; preserve that compatibility.
	return data.get(key,(Rules.RELICS if relics else Rules.RUNES).map(func(item): return item.id)).duplicate()

func has_save() -> bool:
	return FileAccess.file_exists(save_path)

func unlock_next_stage(current_layout: Dictionary = {}) -> bool:
	# Debug surrogate for a story/Boss event. No mana purchase API exists.
	if data.array_stage >= 4:
		last_error = "法阵已完成三次扩圈"
		return false
	var before := data.duplicate(true)
	if not current_layout.is_empty():
		data.layout = current_layout.duplicate(true)
	data.array_stage += 1
	data.layout.stage = data.array_stage
	if not save():
		data = before
		return false
	return true


func occupied_slots() -> int:
	return team_slots(data.monsters)


func transfer_ids(id: String) -> Array:
	var unit := monster_by_id(id)
	if unit.is_empty():
		return []
	var ids: Array = [id]
	if unit.get("mode", "normal") == "tiny":
		ids.clear()
		for other in data.monsters:
			if other.get("mode", "normal")=="tiny" and other.batch_id==unit.batch_id:
				ids.append(other.id)
	return ids


func can_join(id: String) -> bool:
	var test_units: Array = data.monsters.duplicate(true)
	var ids := transfer_ids(id)
	if ids.is_empty():
		return false
	for unit in test_units:
		if unit.id in ids:
			unit.position = "team"
	return team_slots(test_units) <= TEAM_LIMIT


func slots_after_join(id: String) -> int:
	var test_units: Array = data.monsters.duplicate(true)
	var ids := transfer_ids(id)
	for unit in test_units:
		if unit.id in ids:
			unit.position = "team"
	return team_slots(test_units)


static func team_slots(units: Array) -> int:
	var total := 0
	var tiny_batches := {}
	for unit in units:
		if unit.position != "team":
			continue
		if unit.get("mode", "normal") == "tiny":
			tiny_batches[unit.batch_id] = int(tiny_batches.get(unit.batch_id,0))+1
		else:
			total += int(unit.get("slots",1))
	for count in tiny_batches.values():
		total += int(ceil(float(count)/5.0))
	return total


func _prepare_summon_save() -> void:
	# Keep legacy creatures, progression and rewards. Only incompatible rune layouts
	# move to an archive; the old file remains untouched until a successful save.
	if int(data.layout.get("version", 0)) < 3:
		data.legacy_summon_layout = data.layout.duplicate(true)
		data.layout = {"version":3,"stage":1,"placed":[],"placedRelics":[]}
		data.array_stage = 1
		if data.has("known_runes"):
			data.known_runes = Rules.RUNES.map(func(item): return item.id)
	data.array_stage = int(data.get("array_stage",data.layout.get("stage",1)))
	if not data.has("last_summon"):
		data.last_summon = {}

func _valid_summon_unit(unit: Dictionary) -> bool:
	if unit.get("mode") not in ["normal","giant","ultra","multiply","tiny","special"] or int(unit.get("tier",0)) not in [1,2,3,4]:
		return false
	if not unit.get("batch_id") is String or str(unit.batch_id).is_empty():
		return false
	if int(unit.get("slots",0)) != (5 if unit.mode=="ultra" else 2 if unit.mode=="giant" else 1):
		return false
	if not unit.get("mutation_sources") is Array or not unit.get("abilities") is Array or not unit.get("recoverable") is bool:
		return false
	if unit.mode=="tiny" and unit.recoverable:
		return false
	for source in unit.mutation_sources:
		if not source is String or Rules.definition(source).is_empty():
			return false
	for ability in unit.abilities:
		if not ability is Dictionary or not ability.get("name") is String or not ability.get("description") is String or not ability.get("mutated") is bool or Rules.definition(str(ability.get("rune_id",""))).is_empty():
			return false
	return true
