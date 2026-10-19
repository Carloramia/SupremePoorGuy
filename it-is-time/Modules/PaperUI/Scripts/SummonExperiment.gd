extends RefCounted
## Current summon construction. Trial values are separated from persistent catalogue IDs.
const Rules = preload("res://Modules/PaperUI/Scripts/Ritual/RuneRules.gd")
const CONTENT = preload("res://Scripts/Summoning/SummonContent.gd")
const SETTINGS = preload("res://Resources/Application/DefaultSummonGameplay.tres")
const TEAM_LIMIT = 6
const TIER_COSTS = [2,8,20,38]
const BASES = [[200,30,5],[280,42,7],[392,59,10],[549,82,14]]
const MUTATION_CHANCE = [0.20,0.35,0.50]
const MUTATION_FAILURE = 0.50
const MUTATION_AMPLIFIER = 4.0
const ULTRA_FAILURE = 0.90
# Historical recipe kept as a reference, never dispatched through the current catalogue.
const RECIPE = {"id":"trial-iron-wolf","name":"旧铁甲灵狼配方（停用）","form":"兽形","runes":[{"id":"armor","cells":[[-2,0],[-1,0]]},{"id":"health","cells":[[-1,1],[0,1],[1,1]]},{"id":"attack","cells":[[0,-1],[0,0],[1,-1]]}],"relic":"bone-die","anchor":[[1,0],[2,0]]}

static func recipe_matches(_rules) -> bool:
	return false

static func _shift(path: Array, offset: Array) -> Array:
	var result: Array = []
	for cell: Array in path: result.append([int(cell[0])+int(offset[0]),int(cell[1])+int(offset[1])])
	return result

static func preview(rules) -> Dictionary:
	var cost := 0
	var active_cost := 0
	var counts := {}
	var attribute_bonuses := {"health":0.0,"attack":0.0,"armor":0.0}
	var error := ""
	for item: Dictionary in rules.placed:
		cost += item.cells.size()
		if not item.enabled: continue
		active_cost += item.cells.size()
		var d: Dictionary = Rules.current_definition(item.runeId)
		if d.is_empty(): error = "布局含已停用符文，请使用当前9类符文。"; continue
		counts[item.runeId] = int(counts.get(item.runeId,0))+1
		if attribute_bonuses.has(item.runeId):
			attribute_bonuses[item.runeId] += CONTENT.attribute_bonus(item.runeId,item.cells.size())
	var combat_relics := 0
	var has_eye := false
	for item: Dictionary in rules.relics:
		cost += item.cells.size()
		active_cost += item.cells.size()
		var d: Dictionary = Rules.current_definition(item.relicId,true)
		if d.is_empty(): error = "布局含旧奇物，请从当前目录重新选择。"; continue
		if d.kind=="combat": combat_relics+=1
		if d.id=="crystal-eye": has_eye=true
	if combat_relics>1: error="首轮每次召唤最多使用1件战斗定位奇物。"
	var tier := 1
	for i: int in TIER_COSTS.size():
		if active_cost>=TIER_COSTS[i]: tier=mini(i+1,rules.stage)
	var sources: Array = []
	var normal_probability := 1.0
	for id: String in counts:
		var d: Dictionary = Rules.current_definition(id)
		if counts[id]>=d.threshold:
			var chance := minf(0.90,MUTATION_CHANCE[d.rank]+0.05*(int(counts[id])-int(d.threshold)))
			sources.append({"id":id,"name":d.name,"count":counts[id],"threshold":d.threshold,"chance":chance})
			normal_probability *= 1.0-chance
	var mode := "normal"
	var count := 5
	var slots := 1
	if counts.has("giant") and counts.has("multiply"): error="首轮巨化和大群分别测试，不混用。"
	if counts.has("giant"):
		mode = "ultra" if counts.giant>=2 else "giant"
		count = 1 if mode=="ultra" else 3
		slots = 5 if mode=="ultra" else 2
	elif counts.has("multiply"):
		mode="swarm"
		count=SETTINGS.swarm_count
	var probability := 1.0-normal_probability
	var failure := probability*MUTATION_FAILURE
	if mode=="ultra":
		probability=1.0
		failure=ULTRA_FAILURE
		for source: Dictionary in sources:
			if source.id=="giant": source.chance=1.0
	# No paid attempt may violate the promised eye guarantee. The all-failed policy is unapproved.
	if has_eye and failure>0.0: error="魔眼保底的全失败处理尚未定案；首轮请使用无失败风险的构筑。"
	return {"cost":cost,"effective_cost":active_cost,"counts":counts,"attribute_bonuses":attribute_bonuses,"tier":tier,"mode":mode,"count":count,"slots_each":slots,"total_slots":1 if mode=="swarm" else count*slots,"sources":sources,"mutation_chance":probability,"failure_chance":failure,"error":error}

static func generate(rules, serial: int, location: String, rng: RandomNumberGenerator) -> Dictionary:
	var p := preview(rules)
	var units: Array = []
	var failures := 0
	if not p.error.is_empty(): return {"units":[],"report":{"error":p.error}}
	for index: int in p.count:
		var mutated: Array = []
		if p.mode=="ultra":
			mutated.append("giant")
			if rng.randf()<ULTRA_FAILURE: failures+=1; continue
		else:
			for source: Dictionary in p.sources:
				if rng.randf()<source.chance: mutated.append(source.id)
			if not mutated.is_empty() and rng.randf()<MUTATION_FAILURE: failures+=1; continue
		units.append(_monster(rules,p,mutated,serial,index,location,rng))
	for relic: Dictionary in rules.relics:
		if relic.relicId=="crystal-eye" and not units.is_empty():
			var chosen: Dictionary = units[rng.randi_range(0,units.size()-1)]
			chosen.magic_eye=true
			if "结晶化眼球" not in chosen.traits: chosen.traits.append("结晶化眼球")
	return {"units":units,"report":{"serial":serial,"attempted":p.count,"succeeded":units.size(),"failed":failures,"cost":p.cost,"tier":p.tier,"mode":p.mode,"sources":p.sources}}

static func _monster(rules, p: Dictionary, mutated: Array, serial: int, index: int, location: String, rng: RandomNumberGenerator) -> Dictionary:
	var base: Array = BASES[p.tier-1]
	var hp := float(base[0])*rng.randf_range(0.92,1.08)
	var attack := float(base[1])*rng.randf_range(0.92,1.08)
	var armor := float(base[2])
	var basic := {"hp":hp,"attack":attack,"armor":armor}
	var hp_bonus := 0.0
	var attack_bonus := 0.0
	var armor_bonus := 0.0
	var interval := 1.5
	var durability := 0.0
	var burn := 0.0
	var traits: Array = []
	var abilities: Array = []
	for id: String in p.counts:
		var d: Dictionary = Rules.current_definition(id)
		var n: int = p.counts[id]
		var amp := MUTATION_AMPLIFIER if id in mutated else 1.0
		traits.append(d.name)
		match id:
			"health": hp_bonus+=p.attribute_bonuses.health*amp
			"attack": attack_bonus+=p.attribute_bonuses.attack*amp
			"armor": armor_bonus+=p.attribute_bonuses.armor*amp
			"bloodblade": attack_bonus+=0.35*n*amp; hp_bonus-=0.15*n
			"haste": interval*=pow(0.90,n*amp)
			"burn": burn+=0.12*n*amp
			"limb-fortitude": durability+=0.40*n*amp
		abilities.append({"rune_id":id,"name":d.name,"copies":n,"amplification":amp,"description":d.detail,"mutated":id in mutated})
	hp*=maxf(0.10,1.0+hp_bonus)
	attack*=1.0+attack_bonus
	armor*=1.0+armor_bonus
	var size := 1.0
	match p.mode:
		"giant": hp*=1.8; attack*=1.5; armor*=1.5; size=1.5
		"ultra": hp*=8.0; attack*=5.0; armor*=5.0; size=2.5
		"swarm":
			var amp := 2.0 if "multiply" in mutated else 1.0
			hp*=0.20*amp; attack*=0.30*amp; armor*=0.20*amp
			size=0.25 if "multiply" in mutated else SETTINGS.swarm_scale
	var relic_ids: Array = []
	var pairs := 0
	for item: Dictionary in rules.relics:
		relic_ids.append(item.relicId)
		var d: Dictionary = Rules.current_definition(item.relicId,true)
		if d.id!="crystal-eye": traits.append(d.name)
		if d.id=="spiral-idol": pairs=SETTINGS.extra_limb_pairs
	var form: String = ["人形","兽形","蛇形"][rng.randi_range(0,2)]
	return {"id":"summon_%d_%d" % [serial,index],"batch_id":"batch_%d" % serial,"name":("畸变·" if not mutated.is_empty() else "")+str(traits[0])+"·"+form+" %02d" % (index+1),"form":form,"tier":p.tier,"hp":hp,"attack":attack,"armor":armor,"speed":3.0,"interval":maxf(0.50,interval),"traits":traits,"abilities":abilities,"effects":{"burn_ratio":burn},"mode":p.mode,"mutation_sources":mutated,"slots":p.slots_each,"recoverable":p.mode!="swarm","clone_count":0,"clone_ratio":0.0,"visual_scale":size,"anatomy":{"scale":size,"extra_limb_pairs":pairs},"magic_eye":false,"limb_durability_bonus":durability,"relic_ids":relic_ids,"position":"pending","color":["839b78","8caaa3","bb9272"][index%3],"base_stats":basic,"source_location":location,"source_layout":rules.export_layout(),"source_cost":p.cost,"created_at":Time.get_datetime_string_from_system(),"recipe_id":""}

static func trial_notes() -> String:
	return "当前9类符文、8件奇物。属性族3/5/7格按同族计重复。大群5只小型本体、整组1队位、不产生分身；螺旋人像每只适配怪物加一对同类肢体，不提高变异率。魔眼保证1只，本轮不支持可能全失败的魔眼构筑。所有数值与占格均为首轮测试参数。"
