extends RefCounted
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
const Experiment = preload("res://Scripts/SummonExperiment.gd")
const TEAM_LIMIT = Experiment.TEAM_LIMIT
const BATCH_SIZE = 5
const SAVE_VERSION = 2
var save_path: String = "user://prototype_session.json"
var data: Dictionary = {}
var last_error: String = ""

func _init() -> void:
	reset()

func reset() -> void:
	data = {"version":SAVE_VERSION, "magic":300, "serial":0, "monsters":[], "pending":[], "pending_location":"grassland", "pending_return":"world", "completed":[], "array_stage":1,"last_summon":{}, "layout":{"version":3,"stage":1,"placed":[],"placedRelics":[]}}

func save() -> bool:
	last_error = ""
	var f := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if f == null:
		last_error = "无法写入存档：%s" % error_string(FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(data))
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
		last_error = "无法替换存档：%s" % error_string(error)
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
	if not value.get("layout") is Dictionary or not value.get("last_summon") is Dictionary:
		return false
	if not (value.get("magic") is int or value.get("magic") is float) or not is_finite(float(value.magic)) or value.magic < 0:
		return false
	if int(value.get("array_stage",0)) not in [1,2,3,4] or int(value.layout.get("stage",0)) != int(value.array_stage):
		return false
	if not value.has("serial") or not value.has("pending_location") or not value.has("pending_return"):
		return false
	if not _valid_layout(value.layout):
		return false
	var ids: Array = []
	var pending_ids: Array = []
	for monster in value.monsters:
		if not monster is Dictionary:
			return false
		for key in ["id","name","form","hp","attack","armor","speed","interval","traits","position","color","tier","mode","slots","batch_id","abilities","mutation_sources","part_hp","base_stats","recoverable","clone_count","source_layout","source_cost","source_location","effects","created_at","visual_scale"]:
			if not monster.has(key):
				return false
		if not monster.traits is Array or not monster.abilities is Array or not monster.mutation_sources is Array or not monster.part_hp is Dictionary or not monster.base_stats is Dictionary:
			return false
		if monster.id in ids or monster.position not in ["warehouse","team","pending"]:
			return false
		for key in ["id","name","form","color","batch_id"]:
			if not monster[key] is String or str(monster[key]).is_empty():
				return false
		if monster.form not in ["人形","兽形","蛇形"] or not Color.html_is_valid(monster.color):
			return false
		if int(monster.tier) not in [1,2,3,4] or monster.mode not in ["normal","giant","ultra","multiply","tiny","special"]:
			return false
		if int(monster.slots) != (5 if monster.mode=="ultra" else 2 if monster.mode=="giant" else 1):
			return false
		if not monster.recoverable is bool or (monster.mode=="tiny" and monster.recoverable) or not monster.effects is Dictionary or not _valid_layout(monster.source_layout):
			return false
		for key in ["shield_ratio","burn_ratio","heal_ratio"]:
			if not _finite_nonnegative(monster.effects.get(key)):
				return false
		for key in ["hp","attack","armor"]:
			if not _finite_nonnegative(monster.base_stats.get(key)):
				return false
		for key in ["头部","核心","肢体"]:
			if not _finite_nonnegative(monster.part_hp.get(key)):
				return false
		for ability in monster.abilities:
			if not ability is Dictionary:
				return false
			for key in ["rune_id","name","description","copies","amplification","mutated"]:
				if not ability.has(key):
					return false
			if Rules.definition(str(ability.rune_id)).is_empty() or not ability.name is String or not ability.description is String or not ability.mutated is bool or not _finite_nonnegative(ability.copies) or not _finite_nonnegative(ability.amplification):
				return false
		for source_id in monster.mutation_sources:
			if not source_id is String or Rules.definition(source_id).is_empty():
				return false
		for key in ["hp","attack","armor","speed","interval"]:
			if not (monster[key] is int or monster[key] is float) or not is_finite(float(monster[key])) or float(monster[key])<0:
				return false
		for ability_name in monster.traits:
			if not ability_name is String:
				return false
		ids.append(monster.id)
		if monster.position == "pending":
			pending_ids.append(monster.id)
	var unique_pending: Array = []
	for id in value.pending:
		if id not in pending_ids or id in unique_pending:
			return false
		unique_pending.append(id)
	return pending_ids.size()==value.pending.size() and value.pending.size() <= BATCH_SIZE and team_slots(value.monsters) <= TEAM_LIMIT

static func _finite_nonnegative(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value)>=0

static func _valid_layout(layout: Variant) -> bool:
	if not layout is Dictionary or not layout.get("placed") is Array or not layout.get("placedRelics") is Array or int(layout.get("stage",0)) not in [1,2,3,4]:
		return false
	var candidate = Rules.new()
	return candidate.import_layout(layout) and candidate.placed.size()==layout.placed.size() and candidate.relics.size()==layout.placedRelics.size()

static func team_slots(units: Array) -> int:
	var total := 0
	var tiny_batches := {}
	for unit in units:
		if unit.position != "team":
			continue
		if unit.mode == "tiny":
			tiny_batches[unit.batch_id] = int(tiny_batches.get(unit.batch_id,0))+1
		else:
			total += int(unit.slots)
	for count in tiny_batches.values():
		total += int(ceil(float(count)/5.0))
	return total

func occupied_slots() -> int:
	return team_slots(data.monsters)

func transfer_ids(id: String) -> Array:
	var unit := monster_by_id(id)
	if unit.is_empty():
		return []
	var ids: Array = [id]
	if unit.mode == "tiny":
		ids.clear()
		for other in data.monsters:
			if other.mode=="tiny" and other.batch_id==unit.batch_id:
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
		last_error = "队位不足：加入后 %d / %d；缩小单位按同批整组操作" % [slots_after_join(id),TEAM_LIMIT]
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
		last_error = "魔力不足，还需 %d" % (preview.cost-data.magic)
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

func apply_battle_receipt(receipt: Dictionary) -> bool:
	# Testable integration interface. The "skip battle" UI never invents deaths or calls this.
	var receipt_id := str(receipt.get("id",""))
	if receipt_id.is_empty() or not receipt.get("victory") is bool or not receipt.get("dead_original_ids") is Array:
		last_error = "战斗回执格式无效"
		return false
	var ledger_id := "receipt_"+receipt_id
	if ledger_id in data.completed:
		last_error = "该战斗回执已结算"
		return false
	var dead_ids: Array = []
	var recovery := 0
	for id in receipt.dead_original_ids:
		var unit := monster_by_id(str(id))
		if unit.is_empty() or unit.position != "team" or id in dead_ids:
			last_error = "回执包含非己方出战本体或重复编号"
			return false
		dead_ids.append(id)
		if receipt.victory and unit.recoverable and unit.mode != "tiny":
			recovery += int(unit.tier)-1
	var before := data.duplicate(true)
	for index in range(data.monsters.size()-1,-1,-1):
		if data.monsters[index].id in dead_ids:
			data.monsters.remove_at(index)
	data.magic += recovery
	data.completed.append(ledger_id)
	data.last_battle = {"id":receipt_id,"victory":receipt.victory,"dead_ids":dead_ids,"recovery":recovery,
		"clone_deaths":maxi(0,int(receipt.get("clone_deaths",0)))}
	if not save():
		data = before
		return false
	return true

func claim_once(id: String, reward: int) -> bool:
	if id in data.completed:
		last_error = "此奖励已经领取"
		return false
	var before := data.duplicate(true)
	data.magic += maxi(0,reward)
	data.completed.append(id)
	if not save():
		data = before
		return false
	return true
