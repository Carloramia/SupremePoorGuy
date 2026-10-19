extends SceneTree
const RULES = preload("res://Modules/PaperUI/Scripts/Ritual/RuneRules.gd")
const CONTENT = preload("res://Scripts/Summoning/SummonContent.gd")
const EXPERIMENT = preload("res://Modules/PaperUI/Scripts/SummonExperiment.gd")
const SESSION = preload("res://Scripts/Application/GameSession.gd")
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("FAIL: "+label)

func _initialize() -> void: call_deferred("run")

func equivalent(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int): return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for index: int in a.size():
			if not equivalent(a[index],b[index]): return false
		return true
	return a==b

func run() -> void:
	check(CONTENT.RUNES.size()==9 and CONTENT.RELICS.size()==8,"Current catalogue counts")
	var rules := RULES.new()
	rules.stage=4
	for rune: Dictionary in CONTENT.RUNES:
		for pattern: Array in CONTENT.patterns(rune):
			for mirrored: bool in [false,true]:
				for turn: int in 6:
					var path := RULES.transformed(pattern,turn,mirrored)
					check(rules.recognize(path).get("id")==rune.id,"Unambiguous shape "+rune.id+" "+str(path.size()))
	check(rules.recognize([[0,0],[1,0]]).is_empty(),"Old two-cell armor no longer active")
	var legacy := RULES.new()
	check(legacy.import_layout({"version":3,"stage":1,"placed":[{"runeId":"armor","cells":[[0,0],[1,0]],"enabled":true}],"placedRelics":[]}) and legacy.placed.size()==1,"Version 3 layout validates with old semantics")
	var session := SESSION.new()
	session.save_path="res://Tests/.runtime/integration/current_summon_%d.json" % Time.get_ticks_usec()
	check(session.data.known_runes==["health"] and session.data.known_relics.is_empty(),"New game only owns basic life")
	check(session.claim_content_reward("QST_SIDE_001_001","library:test",{"dialogue_completed":true}),"Library reward commits")
	check(session.data.known_runes.has("attack") and session.data.known_runes.has("armor"),"Library unlocks attack and defense")
	check(not session.claim_content_reward("QST_SIDE_001_001","library:test2",{"dialogue_completed":true}),"Library reward deduplicates")
	check(not session.claim_content_reward("QST_GRASS_008","unrelated",{"battle_id":"missing"}),"No fabricated battle rewards")
	session.data.known_runes=CONTENT.RUNES.map(func(r):return r.id)
	session.data.known_relics=CONTENT.RELICS.map(func(r):return r.id)
	session.data.array_stage=4
	rules.draft=CONTENT.RUNES[0].cells.duplicate(true)
	check(rules.commit(),"Life commits")
	check(rules.place_relic("spiral-idol",[-3,1]),"Spiral idol placement")
	check(rules.place_relic("crystal-eye",[2,-2]),"Crystal eye placement")
	check(EXPERIMENT.preview(rules).mutation_chance==0.0,"Spiral idol does not add mutation chance")
	var random := RandomNumberGenerator.new()
	random.seed=123456
	check(session.summon(rules,"test","world",random),"Real creatures with extra limbs and eye summon: "+session.last_error)
	check(session.data.pending.size()==5,"Five real bodies generated")
	var eyes := 0
	for record: Dictionary in session.data.monsters:
		if record.get("magic_eye",false): eyes+=1
		var original := FACTORY.template(record.definition_id)
		check(record.parts.size()>original.parts.size()+1 and record.poses.has("SummonExtraLimbs/ExtraLimb0") and record.poses.has("SummonExtraLimbs/ExtraLimb1") and not record.poses.has("SummonExtraLimbs/ExtraLimb2"),"One extra pair of complete limb branches")
		check(FACTORY.valid_record(record),"Modified anatomy survives strict record validation")
	check(eyes==1,"Exactly one guaranteed eye in first-pass batch")
	var restored := SESSION.new()
	restored.save_path=session.save_path
	check(restored.load_save(),"New anatomy save reloads: "+restored.last_error)
	check(equivalent(restored.data.monsters,session.data.monsters),"Reload does not reroll anatomy or magic eye (JSON numeric roundoff allowed)")
	var level := Node3D.new()
	root.add_child(level)
	if not session.data.monsters.is_empty():
		var record: Dictionary = session.data.monsters[0]
		var actor := FACTORY.spawn(record,level,Vector3(0,10,0),0)
		check(actor!=null,"Extra anatomy deploys")
		if actor!=null:
			check(actor.get_node_or_null("SummonExtraLimbs")!=null,"Extra limbs are actual scene bodies")
			var effects: Node = actor.get_meta(&"summon_effects",null)
			check(is_instance_valid(effects),"Battle-local effects attached")
			if is_instance_valid(effects):
				var part: PhysicalBodyPart3D = actor._get_physical_body_parts()[0]
				effects.shield=10.0; effects.shield_remaining=1.0
				check(is_zero_approx(effects.filter_damage(part,5.0)) and is_equal_approx(effects.shield,5.0),"Shared shield absorbs once")
	level.queue_free()
	await process_frame
	var swarm := RULES.new()
	swarm.stage=4
	swarm.draft=RULES.current_definition("multiply").cells.duplicate(true)
	check(swarm.commit(),"Swarm shape recognized")
	var preview := EXPERIMENT.preview(swarm)
	check(preview.mode=="swarm" and preview.count==5 and preview.total_slots==1,"Swarm is five small bodies / one slot")
	var generated := EXPERIMENT.generate(swarm,99,"test",random)
	for unit: Dictionary in generated.units:
		check(unit.clone_count==0 and unit.visual_scale<1.0,"Swarm shrinks and never creates clones")
	var before := session.data.duplicate(true)
	session.save_path+="/blocked.json"
	check(not session.claim_content_reward("QST_GRASS_007","donkey:test",{"dialogue_completed":true}),"Failed reward save propagates")
	check(session.data==before,"Failed reward save rolls back both relics and markers")
	validate_reward_bindings()
	validate_legacy_migration(restored.data)
	await validate_anatomy_physics()
	print("CURRENT_SUMMON_CHECKS=",checks," FAILURES=",failures)
	quit(0 if failures==0 else 1)

func validate_reward_bindings() -> void:
	var bindings = preload("res://Scripts/Summoning/SummonRewardBindings.gd")
	var data: Dictionary = SESSION.new().data
	check(not bindings.apply(data,"QST_SIDE_003_001:stage_3","early",{"stage":"stage_3","sacrifice_committed":true}).is_empty(),"Third sacrifice cannot skip second reward")
	for key: String in CONTENT.EVENT_REWARDS:
		var id := "fixture:"+key
		var source := "QST_GRASS_020" if key=="QST_GRASS_020:round_4" else key
		data.battle_results[id]={"battle_id":id,"content_source":source,"combat_mode":"spectator" if key=="QST_GRASS_020:round_4" else "party","outcome":"victory","parts":{},"reward":0}
		var facts := {"battle_id":id,"dialogue_completed":true,"returned_to_giver":true,"single_owned_attack_check_passed":true,"sacrifice_committed":true,"stage":key.get_slice(":",1),"settled_rounds":4}
		check(bindings.apply(data,key,id,facts).is_empty(),"Current reward binding "+key)
		check(not bindings.apply(data,key,id,facts).is_empty(),"Reward deduplicates "+key)
	check(data.known_runes.size()==9 and data.known_relics.size()==8,"Event bindings cover exactly nine runes and eight relics")
	for outcome: String in ["victory","defeat"]:
		var game: Dictionary = SESSION.new().data
		game.battle_results.test={"battle_id":"test","content_source":"QST_GRASS_020","combat_mode":"spectator","outcome":outcome,"parts":{},"reward":0}
		check(not bindings.apply(game,"QST_GRASS_020:round_4","test",{"battle_id":"test","settled_rounds":3}).is_empty(),"Clockwork never paid before fourth settlement")
		check(bindings.apply(game,"QST_GRASS_020:round_4","test",{"battle_id":"test","settled_rounds":4}).is_empty() and "clockwork-box" in game.known_relics,"Fourth-round gift on "+outcome)

func validate_legacy_migration(records: Dictionary) -> void:
	var legacy := SESSION.new()
	legacy.save_path="res://Tests/.runtime/integration/summon_v3_migration_%d.json" % Time.get_ticks_usec()
	legacy.data=records.duplicate(true)
	legacy.data.known_runes=["health","vitality","iron","fang","tiny"]
	legacy.data.known_relics=["bone-die"]
	legacy.data.layout={"version":3,"stage":4,"placed":[{"runeId":"health","cells":[[-1,0],[0,0],[1,0]],"enabled":true}],"placedRelics":[]}
	check(legacy.save(),"Write isolated old-layout fixture")
	var old_hash := FileAccess.get_sha256(legacy.save_path)
	var loaded := SESSION.new()
	loaded.save_path=legacy.save_path
	check(loaded.load_save(),"Load and migrate legacy knowledge/layout")
	check(loaded.data.layout.version==4 and loaded.data.layout.placed.is_empty() and loaded.data.has("legacy_rune_layout_v3"),"Old incompatible layout archived, not reinterpreted")
	check(equivalent(loaded.data.monsters,legacy.data.monsters),"Migration never rerolls existing creatures")
	check(loaded.data.known_runes==["health","armor","attack","multiply"] and loaded.data.known_relics==["bone-die"],"Merge legacy knowledge without granting new fortitude or relics")
	check(loaded.save() and FileAccess.get_sha256(loaded.save_path+".pre_summon_v4.bak")==old_hash,"Save migration preserves byte-identical pre-upgrade backup")
	var invalid: Dictionary = loaded.data.monsters[0].duplicate(true)
	invalid.magic_eye="yes"
	check(not FACTORY.valid_record(invalid),"Invalid effect metadata cannot pass record validation")

func validate_anatomy_physics() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var actors: Array[Node3D] = []
	for species: String in FACTORY.SUMMON_POOL:
		var template := FACTORY.template(species,{"scale":1.0,"extra_limb_pairs":1})
		if species=="snake":
			check(template.is_empty(),"Limb-less snake is explicitly excluded from the extra-limb pool")
			continue
		check(not template.is_empty(),"Extra limb branch supported on "+species)
		template.id="anatomy_"+species
		var actor := FACTORY.spawn(template,level,Vector3(actors.size()*40,15,0),0)
		check(actor!=null,"Deploy additional limb branch on "+species)
		if actor!=null: actors.append(actor); FACTORY.activate(actor)
	for frame: int in 30: await physics_frame
	for actor: Node3D in actors:
		check(actor.is_combat_alive(),"Initial integrity accepts augmented limb connections "+actor.name)
		check(actor._get_physical_body_parts().all(func(part):return part.global_position.is_finite() and part.linear_velocity.is_finite()),"Augmented physics remains finite "+actor.name)
	level.queue_free()
	await process_frame
