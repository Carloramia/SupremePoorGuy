extends RefCounted
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
const TEAM_LIMIT = 6
const BATCH_SIZE = 3
const SAVE_VERSION = 1
var save_path: String = "user://prototype_session.json"
var data: Dictionary = {}
var last_error: String = ""

func _init() -> void:
	reset()

func reset() -> void:
	data = {"version":SAVE_VERSION, "magic":300, "serial":0, "monsters":[], "pending":[], "pending_location":"grassland", "pending_return":"world", "completed":[], "layout":{"version":2,"placed":[],"placedRelics":[]}}

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
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
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
	if not value.get("layout") is Dictionary or not value.get("magic") is float and not value.get("magic") is int:
		return false
	if value.magic < 0 or not is_finite(float(value.magic)):
		return false
	if not value.has("serial") or not value.has("pending_location") or not value.has("pending_return"):
		return false
	var ids: Array = []
	var team := 0
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
		ids.append(monster.id)
		if monster.position == "team":
			team += 1
	for id in value.pending:
		if id not in ids:
			return false
		for m in value.monsters:
			if m.id == id and m.position != "pending":
				return false
	return team <= TEAM_LIMIT and value.pending.size() <= BATCH_SIZE

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
		return false
	if position == "team" and monster.position != "team" and monsters("team").size() >= TEAM_LIMIT:
		last_error = "出战队列已满（6 / 6），请先撤回一只怪物"
		return false
	var before := data.duplicate(true)
	monster.position = position
	data.pending.erase(id)
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
	var before: Dictionary = data.layout.duplicate(true)
	data.layout = layout.duplicate(true)
	if not save():
		data.layout = before
		return false
	return true

func summon(rules, location: String, return_route: String) -> bool:
	if not data.pending.is_empty():
		last_error = "请先安置上次召唤的怪物"
		return false
	if not rules.draft.is_empty():
		last_error = "请先刻入或取消当前笔画"
		return false
	var active: Array = []
	var cost := 0
	for item in rules.placed:
		cost += item.cells.size()
		if item.enabled:
			active.append(item.runeId)
	if active.is_empty():
		last_error = "请至少刻入并启用一枚符文"
		return false
	if data.magic < cost:
		last_error = "魔力不足，还需 %d" % (cost - data.magic)
		return false
	var before := data.duplicate(true)
	data.magic -= cost
	data.serial += 1
	data.pending_location = location
	data.pending_return = return_route
	data.layout = rules.export_layout()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in BATCH_SIZE:
		var form: String = ["人形","兽形","蛇形"][rng.randi_range(0,2)]
		var traits: Array = []
		for id in active:
			var d := Rules.definition(id)
			if not d.name in traits:
				traits.append(d.name)
		var monster := {"id":"summon_%d_%d" % [data.serial,i], "name":"%s·%s %02d" % [traits[0],form,i+1], "form":form, "hp":rng.randi_range(80,150), "attack":rng.randi_range(12,28), "armor":rng.randi_range(1,8), "speed":snappedf(rng.randf_range(2.0,4.5),0.1), "traits":traits, "position":"pending", "color":["839b78","8caaa3","bb9272"][i], "source_location":location, "source_layout":rules.export_layout()}
		if "gale" in active:
			monster.speed = snappedf(monster.speed * 1.18,0.1)
		for relic in rules.relics:
			if relic.relicId == "bone-die":
				var attribute: String = ["hp","attack","speed"][rng.randi_range(0,2)]
				monster[attribute] = snappedf(float(monster[attribute])*1.1,0.1) if attribute == "speed" else int(monster[attribute]*1.1)
		data.monsters.append(monster)
		data.pending.append(monster.id)
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
