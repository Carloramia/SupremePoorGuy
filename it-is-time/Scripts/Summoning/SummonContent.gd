extends RefCounted
## Current design catalogue. IDs are persistent; old IDs are read only by RuneRules.
const VERSION := 4
const RUNES = [
	{"id":"health","name":"生命","rank":0,"threshold":4,"effect":"延长直线强化生命与耐久","detail":"180°等臂，3/5/7格分别+15%/+35%/+60%。同族合计重复。","cells":[[-1,0],[0,0],[1,0]],"family":true,"color":"d98878"},
	{"id":"attack","name":"攻击","rank":0,"threshold":4,"effect":"延长60°双臂强化攻击","detail":"3/5/7格分别+12%/+28%/+48%。同族合计重复。","cells":[[0,-1],[0,0],[1,-1]],"family":true,"color":"d5ad65"},
	{"id":"armor","name":"防御","rank":0,"threshold":4,"effect":"延长120°双臂强化护甲","detail":"3/5/7格分别+60%/+120%/+200%，不是百分比减伤。","cells":[[-1,0],[0,0],[1,-1]],"family":true,"color":"9aaab6"},
	{"id":"bloodblade","name":"撕咬诅咒","rank":1,"threshold":3,"effect":"攻击+35%，生命耐久-15%","detail":"畸变只放大攻击收益，不放大生命代价。数值为测试参数。","cells":[[0,0],[1,0],[2,0],[2,-1]],"color":"cb766c"},
	{"id":"haste","name":"好战","rank":1,"threshold":3,"effect":"普攻冷却×0.90","detail":"只缩短实际攻击冷却，不加速物理动作。最低0.5秒，测试参数。","cells":[[0,0],[1,0],[1,-1],[2,-1]],"color":"88b6ad"},
	{"id":"burn","name":"沸血","rank":1,"threshold":3,"effect":"普攻附加3秒灼烧","detail":"每秒12%攻击；同目标取最强并刷新，测试参数。不是自伤或狂暴。","cells":[[0,0],[1,0],[2,0],[2,1],[1,2]],"color":"df9a66"},
	{"id":"limb-fortitude","name":"血肉顽强","rank":1,"threshold":3,"effect":"非致命肢体耐久+40%","detail":"保护非致命肢体，不强化头和致命躯干；不再生断肢。测试参数。","cells":[[0,0],[1,0],[1,-1],[0,-1]],"color":"b0b87a"},
	{"id":"giant","name":"巨化","rank":2,"threshold":2,"effect":"3只，每只2队位","detail":"增大身体；重复两枚进入超巨化风险分支。测试参数可独立调整。","cells":[[0,0],[1,0],[1,-1],[0,-1],[-1,0],[-1,1],[0,1]],"color":"c7a16f"},
	{"id":"multiply","name":"大群","rank":2,"threshold":2,"effect":"5只小型本体，整组1队位","detail":"包含缩小效果，不产生分身；不再另设缩小符文。首轮沿用旧缩小数值。","cells":[[0,0],[1,0],[1,-1],[0,-1],[-1,0],[-1,1],[-1,2],[0,2]],"color":"89b48a"}
]
const RELICS = [
	{"id":"spiral-idol","name":"螺旋人像","effect":"适配怪物增加一对同类肢体","detail":"首轮测试每只适配怪物增加一对同类肢体，不提高变异率。","kind":"generation","color":"ae8cc0","cells":[[0,0],[1,0],[1,-1],[0,-1]]},
	{"id":"taunt-bell","name":"挑衅铃","effect":"周期性嘲讽附近敌人","detail":"只改变合法选敌，不打断正在进行的动作。","kind":"combat","color":"d7b66d","cells":[[0,0],[1,0],[1,-1],[0,-1]]},
	{"id":"propaganda-banner","name":"宣传旗帜","effect":"附近其他友军攻击+8%","detail":"自身不享受，同类不叠加，测试参数。","kind":"combat","color":"d78b73","cells":[[0,0],[1,0],[1,-1],[0,-1]]},
	{"id":"shell-carving","name":"壳雕","effect":"周期性获得共享护盾","detail":"护盾属于整只怪物，不按部位复制。","kind":"combat","color":"a6bec3","cells":[[0,0],[1,0],[1,-1],[0,-1]]},
	{"id":"crystal-eye","name":"结晶化眼球","effect":"本批保证1只获得射线魔眼","detail":"使用参与召唤时保证1只获得可发射射线的魔眼，不是提高概率。","kind":"generation","color":"cf83bc","cells":[[0,0],[1,0],[1,-1],[0,-1]]},
	{"id":"blood-crystal","name":"血红晶石","effect":"造成实际生命伤害时吸血","detail":"不计算溢出、护盾吸收、自伤及友伤；受每秒上限约束。","kind":"combat","color":"d77178","cells":[[0,0],[1,0],[1,-1],[0,-1]]},
	{"id":"moss-heart","name":"苔藓心脏","effect":"每4秒恢复4%生命","detail":"不储存溢出治疗，不再生断肢。测试参数。","kind":"combat","color":"89ab75","cells":[[0,0],[1,0],[1,-1],[0,-1]]},
	{"id":"clockwork-box","name":"发条盒","effect":"每场首次死亡后复起一次","detail":"等待2秒，以30%生命复起；不重置其他能力次数。测试参数。","kind":"combat","color":"b8a681","cells":[[0,0],[1,0],[1,-1],[0,-1]]}
]
const EVENT_REWARDS = {
	"QST_SIDE_001_001":{"runes":["attack","armor"],"relics":[]},
	"QST_SIDE_002_001":{"runes":[],"relics":["spiral-idol"]},
	"QST_GRASS_007":{"runes":[],"relics":["taunt-bell","propaganda-banner"]},
	"QST_GRASS_008":{"runes":["giant"],"relics":[]},
	"QST_GRASS_010":{"runes":[],"relics":["shell-carving"]},
	"QST_GRASS_011":{"runes":["multiply","bloodblade"],"relics":[]},
	"QST_GRASS_015":{"runes":["haste","limb-fortitude"],"relics":[]},
	"QST_GRASS_016":{"runes":[],"relics":["crystal-eye"]},
	"QST_SIDE_003_001:stage_2":{"runes":["burn"],"relics":[]},
	"QST_SIDE_003_001:stage_3":{"runes":[],"relics":["blood-crystal"]},
	"QST_GRASS_020:round_4":{"runes":[],"relics":["clockwork-box"]},
	"boss:earth-guardian":{"runes":[],"relics":["moss-heart"]}
}

static func patterns(rune: Dictionary) -> Array:
	if not rune.get("family",false): return [rune.cells]
	var result: Array = []
	for length: int in [1,2,3]:
		var path: Array = []
		if rune.id == "attack":
			for step: int in range(length,0,-1): path.append([0,-step])
		else:
			for step: int in range(-length,0): path.append([step,0])
		path.append([0,0])
		for step: int in range(1,length+1): path.append([step,0] if rune.id=="health" else [step,-step])
		result.append(path)
	return result

static func attribute_bonus(id: String, cells: int) -> float:
	var values: Dictionary = {"health":[0.15,0.35,0.60],"attack":[0.12,0.28,0.48],"armor":[0.60,1.20,2.00]}
	if not values.has(id) or cells not in [3,5,7]: return 0.0
	return values[id][(cells-3)/2]
