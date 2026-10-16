extends RefCounted
## Explicit sandbox configuration. All numbers below are trial values, not final balance.
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
const TEAM_LIMIT = 6 # Trial capacity, measured in slots rather than creature count.
const TIER_COSTS = [2, 8, 20, 38] # Trial only: tier is bounded by unlocked array stage.
const BASES = [[200,30,5], [280,42,7], [392,59,10], [549,82,14]]
const MUTATION_CHANCE = [0.20, 0.35, 0.50]
const MUTATION_FAILURE = 0.50
const MUTATION_AMPLIFIER = 4.0
const ULTRA_FAILURE = 0.90
const RECIPE = {"id":"trial-iron-wolf", "name":"铁甲灵狼（试验配方）", "form":"兽形",
	"runes":[{"id":"armor", "cells":[[-2,0],[-1,0]]},
		{"id":"health", "cells":[[-1,1],[0,1],[1,1]]},
		{"id":"attack", "cells":[[0,-1],[0,0],[1,-1]]}],
	"relic":"bone-die", "anchor":[[1,0],[2,0]]}

static func recipe_matches(rules) -> bool:
	# Exact layout up to translation / rotation / mirror; no extra strokes or relics.
	if rules.placed.size() != 3 or rules.relics.size() != 1:
		return false
	if rules.relics[0].relicId != RECIPE.relic:
		return false
	for mirrored in [false, true]:
		for turn in 6:
			var pattern: Array = Rules.transformed(RECIPE.anchor, turn, mirrored)
			for origin in rules.relics[0].cells:
				var offset := [int(origin[0])-int(pattern[0][0]), int(origin[1])-int(pattern[0][1])]
				if not _same_cells(rules.relics[0].cells, _shift(pattern, offset)):
					continue
				var matched := true
				for requirement in RECIPE.runes:
					var wanted := _shift(Rules.transformed(requirement.cells, turn, mirrored), offset)
					var found := false
					for item in rules.placed:
						if item.enabled and item.runeId == requirement.id and _same_cells(item.cells, wanted):
							found = true
					matched = matched and found
				if matched:
					return true
	return false

static func _shift(path: Array, offset: Array) -> Array:
	var result: Array = []
	for c in path:
		result.append([int(c[0])+int(offset[0]),int(c[1])+int(offset[1])])
	return result

static func _same_cells(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for c in a:
		if c not in b:
			return false
	return true

static func preview(rules) -> Dictionary:
	var cost := 0
	var active_cost := 0
	var counts := {}
	for item in rules.placed:
		cost += item.cells.size()
		if item.enabled:
			active_cost += item.cells.size()
			counts[item.runeId] = int(counts.get(item.runeId,0))+1
	for item in rules.relics:
		cost += item.cells.size()
		active_cost += item.cells.size()
	var tier := 1
	for i in TIER_COSTS.size():
		if active_cost >= TIER_COSTS[i]:
			tier = mini(i+1, rules.stage)
	var sources: Array = []
	var normal_probability := 1.0
	for id in counts:
		var d: Dictionary = Rules.definition(id)
		var threshold: int = d.threshold
		if counts[id] >= threshold:
			var chance := minf(0.90, MUTATION_CHANCE[int(d.rank)]+0.05*(int(counts[id])-threshold))
			sources.append({"id":id,"name":d.name,"count":counts[id],"threshold":threshold,"chance":chance})
			normal_probability *= 1.0-chance
	var mode := "normal"
	var count := 5
	var slots := 1
	var conflict := ""
	var structures := 0
	for id in ["giant","multiply","tiny"]:
		if counts.has(id):
			structures += 1
	if structures > 1:
		conflict = "结构符文组合尚未定案：本试验请分别测试巨化、增殖、缩小。"
	if counts.has("giant"):
		mode = "ultra" if counts.giant >= 2 else "giant"
		count = 1 if mode == "ultra" else 3
		slots = 5 if mode == "ultra" else 2
	elif counts.has("multiply"):
		mode = "multiply"
	elif counts.has("tiny"):
		mode = "tiny"
	if recipe_matches(rules):
		mode = "special"
		count = 1
	var probability := 1.0-normal_probability
	var failure := probability*MUTATION_FAILURE
	if mode == "ultra":
		probability = 1.0
		failure = ULTRA_FAILURE
		for source in sources:
			if source.id == "giant":
				source.chance = 1.0
	return {"cost":cost,"effective_cost":active_cost,"counts":counts,"tier":tier,"mode":mode,
		"count":count,"slots_each":slots,"total_slots":1 if mode=="tiny" else count*slots,
		"sources":sources,"mutation_chance":probability,"failure_chance":failure,"error":conflict}

static func generate(rules, serial: int, location: String, rng: RandomNumberGenerator) -> Dictionary:
	var p := preview(rules)
	var units: Array = []
	var failures := 0
	for index in p.count:
		var mutated: Array = []
		if p.mode == "ultra":
			mutated.append("giant")
			if rng.randf() < ULTRA_FAILURE:
				failures += 1
				continue
			for source in p.sources:
				if source.id != "giant" and rng.randf() < source.chance:
					mutated.append(source.id)
		else:
			for source in p.sources:
				if rng.randf() < source.chance:
					mutated.append(source.id)
			if not mutated.is_empty() and rng.randf() < MUTATION_FAILURE:
				failures += 1
				continue
		units.append(_monster(rules,p,mutated,serial,index,location,rng))
	return {"units":units,"report":{"serial":serial,"attempted":p.count,"succeeded":units.size(),
		"failed":failures,"cost":p.cost,"tier":p.tier,"mode":p.mode,"sources":p.sources}}

static func _monster(rules, p: Dictionary, mutated: Array, serial: int, index: int, location: String, rng: RandomNumberGenerator) -> Dictionary:
	var base: Array = BASES[p.tier-1]
	var hp := float(base[0])*rng.randf_range(0.92,1.08)
	var attack := float(base[1])*rng.randf_range(0.92,1.08)
	var armor := float(base[2])
	var hp_bonus := 0.0
	var attack_bonus := 0.0
	var armor_bonus := 0.0
	var interval := 1.5
	var abilities: Array = []
	var traits: Array = []
	var bonuses := {"shield_ratio":0.0,"burn_ratio":0.0,"heal_ratio":0.0}
	for id in p.counts:
		var d := Rules.definition(id)
		var n: int = p.counts[id]
		var amplification := MUTATION_AMPLIFIER if id in mutated else 1.0
		traits.append(d.name)
		match id:
			"armor": armor_bonus += 0.40*n*amplification
			"health": hp_bonus += 0.15*n*amplification
			"attack": attack_bonus += 0.12*n*amplification
			"iron": armor_bonus += 1.00*n*amplification
			"bloodblade":
				attack_bonus += 0.35*n*amplification
				hp_bonus -= 0.15*n # Trial: amplify the benefit, retain the original cost.
			"vitality": hp_bonus += 0.35*n*amplification
			"fang": attack_bonus += 0.28*n*amplification
			"cocoon": bonuses.shield_ratio += 0.20*n*amplification
			"burn": bonuses.burn_ratio += 0.12*n*amplification
			"haste": interval *= pow(0.80,n*amplification)
			"feast": bonuses.heal_ratio += 0.15*n*amplification
		abilities.append({"rune_id":id,"name":d.name,"copies":n,"amplification":amplification,
			"description":d.detail,"mutated":id in mutated})
	var basic := {"hp":int(round(hp)),"attack":int(round(attack)),"armor":int(armor)}
	hp *= maxf(0.10,1.0+hp_bonus)
	attack *= 1.0+attack_bonus
	armor *= 1.0+armor_bonus
	var visual_scale := 1.0
	var speed := 3.0
	match p.mode:
		"giant":
			hp *= 1.8; attack *= 1.5; armor *= 1.5; visual_scale = 1.5
		"ultra":
			hp *= 8.0; attack *= 5.0; armor *= 5.0; visual_scale = 2.5
		"multiply":
			var f := 0.80*0.80 if "multiply" in mutated else 0.80
			hp *= f; attack *= f; armor *= f
		"tiny":
			var f := 2.0 if "tiny" in mutated else 1.0
			hp *= 0.20*f; attack *= 0.30*f; armor *= 0.20*f
			visual_scale = 0.25 if "tiny" in mutated else 0.35
	for relic in rules.relics:
		if relic.relicId == "bone-die":
			match rng.randi_range(0,2):
				0: hp *= 1.1
				1: attack *= 1.1
				2: speed *= 1.1 # Preserve the old bone-die HP / attack / speed selection.
	var form: String = ["人形","兽形","蛇形"][rng.randi_range(0,2)]
	var name_text := "%s·%s %02d" % [traits[0],form,index+1]
	if p.mode == "special":
		form = RECIPE.form
		name_text = RECIPE.name
	if not mutated.is_empty():
		name_text = "畸变·"+name_text
	var final_hp := maxi(1,int(round(hp)))
	var part_hp := {"头部":maxi(1,int(round(hp*0.75))),"核心":final_hp,"肢体":maxi(1,int(round(hp*0.30)))}
	return {"id":"summon_%d_%d" % [serial,index],"batch_id":"batch_%d" % serial,
		"name":name_text,"form":form,"tier":p.tier,"hp":final_hp,"attack":maxi(1,int(round(attack))),
		"armor":maxi(0,int(round(armor))),"speed":speed,"interval":maxf(0.50,interval),"traits":traits,
		"abilities":abilities,"effects":bonuses,"mode":p.mode,"mutation_sources":mutated,
		"slots":p.slots_each,"recoverable":p.mode != "tiny","clone_count":(2 if "multiply" in mutated else 1) if p.mode=="multiply" else 0,
		"clone_ratio":0.50,"visual_scale":visual_scale,"position":"pending",
		"color":["839b78","8caaa3","bb9272"][index%3],"base_stats":basic,"part_hp":part_hp,
		"source_location":location,"source_layout":rules.export_layout(),"source_cost":p.cost,
		"created_at":Time.get_datetime_string_from_system(),"recipe_id":RECIPE.id if p.mode=="special" else ""}

static func trial_notes() -> String:
	return "试验参数：等段门槛2/8/20/38格，上限由法阵决定；停用仍收费但不提段、不计重复；队位上限6。\n畸变各源基础概率20%/35%/50%，超额每枚+5%；触发后失败50%，成功放大对应符文4倍。超巨化固定失败90%，其余风险源在成功后分别判断强化。失败不返费。\n结构畸变单独配表：超巨化生命×8、攻甲×5；增殖2分身、本体×0.64；缩小尺寸更小、攻防血为普通缩小体的2倍。\n缩小同批整组安置，不足5只仍占1队位；结构混用暂阻止。全部为可调整试验口径。"
