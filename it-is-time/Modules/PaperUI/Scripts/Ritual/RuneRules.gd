extends RefCounted
## Independent summon experiment; legacy web rules remain untouched.
const CONTENT = preload("res://Scripts/Summoning/SummonContent.gd")
const RUNES = CONTENT.RUNES
const RELICS = CONTENT.RELICS
const PREVIOUS_RUNES = [
	{
		"id": "armor",
		"name": "甲片",
		"rank": 0,
		"threshold": 4,
		"effect": "护甲 +40%",
		"detail": "护甲数值增加40%，不是40%减伤。 所有效果数值均为试验参数。",
		"cells": [
			[
				0,
				0
			],
			[
				1,
				0
			]
		],
		"color": "9aaab6"
	},
	{
		"id": "health",
		"name": "血脉",
		"rank": 0,
		"threshold": 4,
		"effect": "生命与耐久 +15%",
		"detail": "总生命与部位耐久增加15%。 所有效果数值均为试验参数。",
		"cells": [
			[
				-1,
				0
			],
			[
				0,
				0
			],
			[
				1,
				0
			]
		],
		"color": "d98878"
	},
	{
		"id": "attack",
		"name": "锐牙",
		"rank": 0,
		"threshold": 4,
		"effect": "攻击 +12%",
		"detail": "普通攻击数值增加12%。 所有效果数值均为试验参数。",
		"cells": [
			[
				0,
				-1
			],
			[
				0,
				0
			],
			[
				1,
				-1
			]
		],
		"color": "d5ad65"
	},
	{
		"id": "iron",
		"name": "铁壁",
		"rank": 1,
		"threshold": 3,
		"effect": "护甲 +100%",
		"detail": "护甲数值增加100%。 所有效果数值均为试验参数。",
		"cells": [
			[
				0,
				0
			],
			[
				1,
				0
			],
			[
				1,
				-1
			],
			[
				0,
				-1
			]
		],
		"color": "8897ba"
	},
	{
		"id": "bloodblade",
		"name": "血刃",
		"rank": 1,
		"threshold": 3,
		"effect": "攻击 +35%，生命 -15%",
		"detail": "攻击增加35%；总生命与部位耐久降低15%。 所有效果数值均为试验参数。",
		"cells": [
			[
				0,
				0
			],
			[
				1,
				0
			],
			[
				2,
				0
			],
			[
				2,
				-1
			]
		],
		"color": "cb766c"
	},
	{
		"id": "cocoon",
		"name": "护茧",
		"rank": 1,
		"threshold": 3,
		"effect": "一次入场护盾",
		"detail": "战斗接口：最大生命20%的共享护盾，持续10秒，每场一次。当前只记录能力，未接入实战。 所有效果数值均为试验参数。",
		"cells": [
			[
				0,
				0
			],
			[
				1,
				0
			],
			[
				1,
				1
			],
			[
				2,
				1
			]
		],
		"color": "b6a3cb"
	},
	{
		"id": "vitality",
		"name": "厚生",
		"rank": 1,
		"threshold": 3,
		"effect": "生命与耐久 +35%",
		"detail": "总生命与部位耐久增加35%。 所有效果数值均为试验参数。",
		"cells": [
			[
				0,
				0
			],
			[
				1,
				0
			],
			[
				1,
				-1
			],
			[
				0,
				-1
			],
			[
				-1,
				0
			]
		],
		"color": "b0b87a"
	},
	{
		"id": "fang",
		"name": "开锋",
		"rank": 1,
		"threshold": 3,
		"effect": "攻击 +28%",
		"detail": "普通攻击数值增加28%。 所有效果数值均为试验参数。",
		"cells": [
			[
				0,
				0
			],
			[
				1,
				0
			],
			[
				2,
				0
			],
			[
				2,
				-1
			],
			[
				3,
				-1
			]
		],
		"color": "e0ba7a"
	},
	{
		"id": "burn",
		"name": "灼印",
		"rank": 1,
		"threshold": 3,
		"effect": "攻击附加灼烧",
		"detail": "战斗接口：每秒12%攻击的灼烧，3秒；同目标取最强并刷新。当前只记录能力，未接入实战。 所有效果数值均为试验参数。",
		"cells": [
			[
				0,
				0
			],
			[
				1,
				0
			],
			[
				2,
				0
			],
			[
				2,
				1
			],
			[
				1,
				2
			]
		],
		"color": "df9a66"
	},
	{
		"id": "haste",
		"name": "迅击",
		"rank": 1,
		"threshold": 3,
		"effect": "攻击周期 ×0.80",
		"detail": "普通攻击实际周期乘0.80；试验最低0.5秒。 所有效果数值均为试验参数。",
		"cells": [
			[
				0,
				0
			],
			[
				1,
				0
			],
			[
				1,
				-1
			],
			[
				2,
				-1
			],
			[
				2,
				-2
			],
			[
				3,
				-2
			]
		],
		"color": "88b6ad"
	},
	{
		"id": "feast",
		"name": "饕餮",
		"rank": 1,
		"threshold": 3,
		"effect": "击杀回血",
		"detail": "战斗接口：击杀非分身回复最大生命15%，每场最多3次，不修复断肢。当前只记录能力，未接入实战。 所有效果数值均为试验参数。",
		"cells": [
			[
				0,
				0
			],
			[
				1,
				0
			],
			[
				1,
				1
			],
			[
				0,
				2
			],
			[
				-1,
				2
			],
			[
				-1,
				1
			]
		],
		"color": "a8a477"
	},
	{
		"id": "giant",
		"name": "巨化",
		"rank": 2,
		"threshold": 2,
		"effect": "3只，每只2队位",
		"detail": "生命×1.8、攻甲×1.5。两枚进入超巨化：1只占5队位，试验失败率90%。 所有效果数值均为试验参数。",
		"cells": [
			[
				0,
				0
			],
			[
				1,
				0
			],
			[
				1,
				-1
			],
			[
				0,
				-1
			],
			[
				-1,
				0
			],
			[
				-1,
				1
			],
			[
				0,
				1
			]
		],
		"color": "c7a16f"
	},
	{
		"id": "multiply",
		"name": "增殖",
		"rank": 2,
		"threshold": 2,
		"effect": "5本体，入场分身接口",
		"detail": "本体攻防血×0.8；每本体入场产生1分身，属性50%，只继承普攻，不可回收。畸变试验：2分身，本体×0.64。当前无实战。 所有效果数值均为试验参数。",
		"cells": [
			[
				0,
				0
			],
			[
				1,
				0
			],
			[
				1,
				-1
			],
			[
				0,
				-1
			],
			[
				-1,
				0
			],
			[
				-1,
				1
			],
			[
				-1,
				2
			],
			[
				0,
				2
			]
		],
		"color": "89b48a"
	},
	{
		"id": "tiny",
		"name": "缩小",
		"rank": 2,
		"threshold": 2,
		"effect": "5只为1队位，不可回收",
		"detail": "生命护甲×0.2、攻击×0.3。同批整组安置；畸变试验：尺寸更小，攻防血为普通缩小体的2倍。 所有效果数值均为试验参数。",
		"cells": [
			[
				0,
				0
			],
			[
				1,
				0
			],
			[
				1,
				-1
			],
			[
				0,
				-1
			],
			[
				-1,
				0
			],
			[
				-1,
				1
			],
			[
				0,
				1
			],
			[
				1,
				1
			],
			[
				2,
				0
			]
		],
		"color": "c6b98e"
	}
]
const LEGACY_RUNES = [
	{"id":"ember", "name":"余烬", "effect":"攻击附加灼烧", "detail":"每次命中留下 3 秒余火。", "color":"ff8a55", "cells":[[0,0],[1,0],[1,-1],[2,-1]]},
	{"id":"tide", "name":"回潮", "effect":"施法时恢复少量生命", "detail":"成功召唤后恢复 8% 生命。", "color":"55cae8", "cells":[[0,0],[1,0],[1,1],[0,2],[-1,2]]},
	{"id":"ward", "name":"壁垒", "effect":"生成短暂护盾", "detail":"抵挡下一次受到的伤害。", "color":"bd93f9", "cells":[[0,0],[1,0],[1,1],[0,1],[-1,1],[-1,0]]},
	{"id":"gale", "name":"疾风", "effect":"提升行动速度", "detail":"移动与行动速度提高 18%。", "color":"a7dd64", "cells":[[0,0],[1,0],[2,0],[2,-1],[3,-1]]},
	{"id":"sky-nail", "name":"天钉", "effect":"首次攻击贯穿", "detail":"贯穿目标身后的一个敌人。", "color":"f2c25e", "cells":[[0,0],[1,0],[2,0],[1,1],[0,2],[-1,3],[-2,4]]},
	{"id":"cycle", "name":"回环", "effect":"缩短召唤技能冷却", "detail":"围绕空心蜂窝形成未闭合回路，冷却缩短 12%。", "color":"f0a85b", "cells":[[1,0],[1,-1],[0,-1],[-1,0],[-1,1],[0,1]]},
	{"id":"twin-peak", "name":"双峰", "effect":"强化两个相邻符文", "detail":"两侧最近的启用符文获得 15% 强度加成。", "color":"ef7bc0", "cells":[[-2,1],[-3,1],[-2,0],[-1,0],[-1,1],[0,1],[1,1],[2,0],[2,-1]]}
]
const PREVIOUS_RELICS = [
	{"id":"tide-pump", "name":"潮汐泵", "effect":"刻入符文时恢复 3% 生命", "color":"52d0c8", "cells":[[0,0],[1,0],[0,1]]},
	{"id":"prism-heart", "name":"棱镜心脏", "effect":"相邻符文强度提高 12%", "color":"e886ff", "cells":[[0,0],[1,0],[0,1],[-1,1]]},
	{"id":"bone-die", "name":"骨骰", "effect":"召唤完成时强化一种属性", "color":"e4d6b0", "cells":[[0,0],[1,0]]}
]
var stage: int = 1
var draft: Array = []
var placed: Array = []
var relics: Array = []
var serial: int = 0
var layout_version: int = CONTENT.VERSION

static func cell_key(cell: Array) -> String:
	return "%d,%d" % [cell[0], cell[1]]

static func distance(a: Array, b: Array) -> int:
	return maxi(maxi(absi(int(a[0])-int(b[0])), absi(int(a[1])-int(b[1]))), absi(int(a[0])+int(a[1])-int(b[0])-int(b[1])))

static func cells(array_stage: int = 4) -> Array:
	var result: Array = []
	var radius := clampi(array_stage,1,4)
	for q in range(-radius, radius+1):
		for r in range(maxi(-radius, -q-radius), mini(radius, -q+radius)+1):
			result.append([q,r])
	return result

static func definition(id: String, is_relic: bool = false) -> Dictionary:
	for item in RELICS if is_relic else RUNES:
		if item.id == id:
			return item
	# Compatibility only: old creatures and layouts are not relabelled or reinterpreted.
	for item in PREVIOUS_RELICS if is_relic else PREVIOUS_RUNES + LEGACY_RUNES:
		if item.id == id: return item
	return {}

static func current_definition(id: String, is_relic: bool = false) -> Dictionary:
	for item in RELICS if is_relic else RUNES:
		if item.id == id: return item
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

func recognize(path: Array, legacy: bool = false) -> Dictionary:
	for rune: Dictionary in PREVIOUS_RUNES if legacy else RUNES:
		for pattern: Array in [rune.cells] if legacy else CONTENT.patterns(rune):
			for mirror in [false, true]:
				for turn in 6:
					var shape := transformed(pattern, turn, mirror)
					if same_shape(path, shape): return rune
					shape.reverse()
					if same_shape(path, shape): return rune
	return {}

func owner_at(cell: Array) -> Dictionary:
	for item in placed + relics:
		for c in item.cells:
			if cell_key(c) == cell_key(cell):
				return item
	return {}

func can_use(cell: Array) -> bool:
	return distance(cell, [0,0]) <= stage and owner_at(cell).is_empty()

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
	return {"version":layout_version, "stage":stage, "placed":placed.duplicate(true), "placedRelics":relics.duplicate(true)}

func import_layout(data: Dictionary) -> bool:
	if int(data.get("version", 0)) not in [1,2,3,4] or not data.get("placed") is Array:
		return false
	layout_version = int(data.version)
	var loaded_stage := int(data.get("stage",stage))
	if loaded_stage < 1 or loaded_stage > 4:
		return false
	stage = loaded_stage
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
		var identified := recognize(shape,layout_version<CONTENT.VERSION)
		if identified.get("id", "") != item.get("runeId", ""):
			continue
		serial += 1
		placed.append({"uid":"r%d" % serial, "runeId":identified.id, "cells":shape.duplicate(true), "enabled":item.get("enabled",true)})
	for item in data.get("placedRelics", []):
		if not item is Dictionary or not item.get("cells") is Array:
			continue
		var relic_id := str(item.get("relicId",""))
		var d := current_definition(relic_id,true) if layout_version>=CONTENT.VERSION else {}
		if layout_version<CONTENT.VERSION:
			for old: Dictionary in PREVIOUS_RELICS:
				if old.id==relic_id: d=old
		if d.is_empty() or not _valid_shape(item.cells) or not _relic_shape_matches(item.cells, d.cells):
			continue
		var duplicate_relic := false
		for existing in relics:
			duplicate_relic = duplicate_relic or existing.relicId==d.id
		if duplicate_relic:
			continue
		serial += 1
		relics.append({"uid":"o%d" % serial,"relicId":d.id,"cells":item.cells.duplicate(true)})
	return true

static func _relic_shape_matches(shape: Array, pattern: Array) -> bool:
	for mirrored in [false,true]:
		for turn in 6:
			var candidate := transformed(pattern,turn,mirrored)
			if same_shape(shape,candidate):
				return true
			candidate.reverse()
			if same_shape(shape,candidate):
				return true
	return false

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
