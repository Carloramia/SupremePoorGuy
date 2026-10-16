extends RefCounted
## Port of 模拟召唤/js/{hex-grid,rune-engine,rune-definitions,relic-definitions}.js.
const RUNES = [
	{"id":"ember", "name":"余烬", "effect":"攻击附加灼烧", "detail":"每次命中留下 3 秒余火。", "color":"ff8a55", "cells":[[0,0],[1,0],[1,-1],[2,-1]]},
	{"id":"tide", "name":"回潮", "effect":"施法时恢复少量生命", "detail":"成功召唤后恢复 8% 生命。", "color":"55cae8", "cells":[[0,0],[1,0],[1,1],[0,2],[-1,2]]},
	{"id":"ward", "name":"壁垒", "effect":"生成短暂护盾", "detail":"抵挡下一次受到的伤害。", "color":"bd93f9", "cells":[[0,0],[1,0],[1,1],[0,1],[-1,1],[-1,0]]},
	{"id":"gale", "name":"疾风", "effect":"提升行动速度", "detail":"移动与行动速度提高 18%。", "color":"a7dd64", "cells":[[0,0],[1,0],[2,0],[2,-1],[3,-1]]},
	{"id":"sky-nail", "name":"天钉", "effect":"首次攻击贯穿", "detail":"贯穿目标身后的一个敌人。", "color":"f2c25e", "cells":[[0,0],[1,0],[2,0],[1,1],[0,2],[-1,3],[-2,4]]},
	{"id":"cycle", "name":"回环", "effect":"缩短召唤技能冷却", "detail":"围绕空心蜂窝形成未闭合回路，冷却缩短 12%。", "color":"f0a85b", "cells":[[1,0],[1,-1],[0,-1],[-1,0],[-1,1],[0,1]]},
	{"id":"twin-peak", "name":"双峰", "effect":"强化两个相邻符文", "detail":"两侧最近的启用符文获得 15% 强度加成。", "color":"ef7bc0", "cells":[[-2,1],[-3,1],[-2,0],[-1,0],[-1,1],[0,1],[1,1],[2,0],[2,-1]]}
]
const RELICS = [
	{"id":"tide-pump", "name":"潮汐泵", "effect":"刻入符文时恢复 3% 生命", "color":"52d0c8", "cells":[[0,0],[1,0],[0,1]]},
	{"id":"prism-heart", "name":"棱镜心脏", "effect":"相邻符文强度提高 12%", "color":"e886ff", "cells":[[0,0],[1,0],[0,1],[-1,1]]},
	{"id":"bone-die", "name":"骨骰", "effect":"召唤完成时强化一种属性", "color":"e4d6b0", "cells":[[0,0],[1,0]]}
]
var draft: Array = []
var placed: Array = []
var relics: Array = []
var serial: int = 0

static func cell_key(cell: Array) -> String:
	return "%d,%d" % [cell[0], cell[1]]

static func distance(a: Array, b: Array) -> int:
	return maxi(maxi(absi(int(a[0])-int(b[0])), absi(int(a[1])-int(b[1]))), absi(int(a[0])+int(a[1])-int(b[0])-int(b[1])))

static func cells() -> Array:
	var result: Array = []
	for q in range(-4, 5):
		for r in range(maxi(-4, -q-4), mini(4, -q+4)+1):
			result.append([q,r])
	return result

static func definition(id: String, is_relic: bool = false) -> Dictionary:
	for item in RELICS if is_relic else RUNES:
		if item.id == id:
			return item
	return {}

static func transformed(path: Array, rotations: int, mirror: bool) -> Array:
	var result: Array = []
	for cell in path:
		var q: int = cell[0]
		var r: int = cell[1]
		if mirror:
			q = -q-r
		for turn in rotations:
			var old_q := q
			q = -r
			r = old_q+r
		result.append([q,r])
	return result

static func same_shape(path: Array, pattern: Array) -> bool:
	if path.is_empty() or path.size() != pattern.size():
		return false
	var dq: int = int(path[0][0])-int(pattern[0][0])
	var dr: int = int(path[0][1])-int(pattern[0][1])
	for i in path.size():
		if int(path[i][0]) != int(pattern[i][0])+dq or int(path[i][1]) != int(pattern[i][1])+dr:
			return false
	return true

func recognize(path: Array) -> Dictionary:
	for rune in RUNES:
		for mirror in [false, true]:
			for turn in 6:
				var shape := transformed(rune.cells, turn, mirror)
				if same_shape(path, shape):
					return rune
				shape.reverse()
				if same_shape(path, shape):
					return rune
	return {}

func owner_at(cell: Array) -> Dictionary:
	for item in placed + relics:
		for c in item.cells:
			if cell_key(c) == cell_key(cell):
				return item
	return {}

func can_use(cell: Array) -> bool:
	return distance(cell, [0,0]) <= 4 and owner_at(cell).is_empty()

func extend(cell: Array) -> bool:
	if not can_use(cell):
		return false
	for c in draft:
		if cell_key(c) == cell_key(cell):
			return false
	if not draft.is_empty() and distance(draft.back(), cell) != 1:
		return false
	draft.append(cell.duplicate())
	return true

func commit() -> bool:
	var rune := recognize(draft)
	if rune.is_empty():
		return false
	serial += 1
	placed.append({"uid":"r%d" % serial, "runeId":rune.id, "cells":draft.duplicate(true), "enabled":true})
	draft.clear()
	return true

func preview_relic(id: String, anchor: Array) -> Dictionary:
	var d := definition(id, true)
	if d.is_empty():
		return {"valid":false, "cells":[]}
	var shape: Array = []
	var valid := true
	for item in relics:
		if item.relicId == id:
			valid = false
	for c in d.cells:
		var cell := [int(c[0])+int(anchor[0]), int(c[1])+int(anchor[1])]
		shape.append(cell)
		if not can_use(cell) or cell in draft:
			valid = false
	return {"valid":valid, "cells":shape}

func place_relic(id: String, anchor: Array) -> bool:
	var preview := preview_relic(id, anchor)
	if not preview.valid:
		return false
	serial += 1
	relics.append({"uid":"o%d" % serial, "relicId":id, "cells":preview.cells})
	return true

func remove(uid: String) -> void:
	for list in [placed, relics]:
		for i in range(list.size()-1, -1, -1):
			if list[i].uid == uid:
				list.remove_at(i)

func export_layout() -> Dictionary:
	return {"version":2, "placed":placed.duplicate(true), "placedRelics":relics.duplicate(true)}

func import_layout(data: Dictionary) -> bool:
	if int(data.get("version", 0)) not in [1,2] or not data.get("placed") is Array:
		return false
	draft.clear()
	placed.clear()
	relics.clear()
	serial = 0
	for item in data.placed:
		if not item is Dictionary or not item.get("cells") is Array:
			continue
		var shape: Array = item.cells
		var safe := _valid_shape(shape)
		if not safe:
			continue
		var identified := recognize(shape)
		if identified.get("id", "") != item.get("runeId", ""):
			continue
		serial += 1
		placed.append({"uid":"r%d" % serial, "runeId":identified.id, "cells":shape.duplicate(true), "enabled":item.get("enabled",true)})
	for item in data.get("placedRelics", []):
		if not item is Dictionary or not item.get("cells") is Array:
			continue
		var d := definition(str(item.get("relicId","")), true)
		if d.is_empty() or not _valid_shape(item.cells) or not same_shape(item.cells, d.cells):
			continue
		var anchor := [int(item.cells[0][0])-int(d.cells[0][0]), int(item.cells[0][1])-int(d.cells[0][1])]
		place_relic(d.id, anchor)
	return true

func _valid_shape(shape: Array) -> bool:
	var seen: Array = []
	for c in shape:
		if not c is Array or c.size() != 2:
			return false
		for n in c:
			if not (n is int or n is float) or not is_finite(float(n)) or float(n) != floor(float(n)):
				return false
		if not can_use(c) or cell_key(c) in seen:
			return false
		seen.append(cell_key(c))
	return not shape.is_empty()
