extends SceneTree
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
const State = preload("res://Scripts/PrototypeState.gd")
const Experiment = preload("res://Scripts/SummonExperiment.gd")
const Scene = preload("res://Scenes/GameDemo.tscn")
var checks := 0
var failures := 0
var app

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAILED: "+description)

func rng(seed_value: int) -> RandomNumberGenerator:
	var result := RandomNumberGenerator.new()
	result.seed = seed_value
	return result

func model(stage: int = 4):
	var result = State.new()
	result.data.array_stage = stage
	result.data.layout.stage = stage
	result.save_path = ProjectSettings.globalize_path("res://Tests/.runtime")+"/summon_v2_%d_%d.json" % [Time.get_ticks_usec(),checks]
	return result

func construct(ids: Array, stage: int = 4):
	var result = Rules.new()
	result.stage = stage
	for id in ids:
		var found := false
		for anchor in Rules.cells(stage):
			for turn in 6:
				if found:
					break
				var path: Array = Rules.transformed(Rules.definition(id).cells,turn,false)
				path = Experiment._shift(path,[int(anchor[0])-int(path[0][0]),int(anchor[1])-int(path[0][1])])
				var valid := true
				for cell in path:
					valid = valid and result.can_use(cell)
				if valid:
					for cell in path:
						result.extend(cell)
					found = result.commit()
			if found:
				break
		check(found,"legal nonoverlapping fixture "+id)
	return result

func recipe(turn: int = 0, mirrored: bool = false):
	var result = Rules.new()
	result.stage = 4
	for item in Experiment.RECIPE.runes:
		for c in Rules.transformed(item.cells,turn,mirrored):
			result.extend(c)
		check(result.commit(),"recipe stroke "+item.id)
	# Transformed footprint is imported, so rotated relic validation remains exercised separately.
	if turn==0 and not mirrored:
		check(result.place_relic("bone-die",[1,0]),"recipe relic")
	else:
		result.relics.append({"uid":"o_recipe","relicId":"bone-die","cells":Rules.transformed(Experiment.RECIPE.anchor,turn,mirrored)})
	return result

func settle() -> void:
	for i in 8:
		await process_frame

func capture(name: String) -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://Tests/screenshots/"+name+".png")

func _run() -> void:
	root.content_scale_size = Vector2i(1280,720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	for stage in range(1,5):
		check(Rules.cells(stage).size()==[7,19,37,61][stage-1],"array ring count")
		var board_rules = Rules.new()
		board_rules.stage = stage
		check(board_rules.can_use([stage,0]) and not board_rules.can_use([stage+1,0]),"unlock boundary")
	var progress = model(1)
	for stage in range(2,5):
		check(progress.unlock_next_stage(),"story event unlock")
		check(progress.data.magic==300 and progress.data.array_stage==stage,"unlock costs no mana")
	var progress_reload = model(1)
	progress_reload.save_path = progress.save_path
	check(progress_reload.load_save() and progress_reload.data.array_stage==4,"unlock persists")
	check(not progress.unlock_next_stage(),"no fourth upgrade")
	var failed_unlock = model(1)
	failed_unlock.save_path = ProjectSettings.globalize_path("res://Tests/.runtime")+"/missing_v06_directory/unlock.json"
	var unlock_before: Dictionary = failed_unlock.data.duplicate(true)
	check(not failed_unlock.unlock_next_stage() and failed_unlock.data==unlock_before,"unlock save failure is atomic")
	var cost_rules = construct(["armor"],1)
	check(cost_rules.place_relic("bone-die",[0,-1]),"same-price relic fits")
	var p := Experiment.preview(cost_rules)
	check(p.cost==4 and p.effective_cost==4 and p.tier==1,"rune and relic cost, stage caps tier")
	cost_rules.placed[0].enabled = false
	check(Experiment.preview(cost_rules).cost==4 and Experiment.preview(cost_rules).counts.is_empty(),"disabled billed but inactive")
	check(not model(1).summon(cost_rules,"forest","world",rng(1)),"inactive cannot summon")
	cost_rules.placed[0].enabled = true
	var original = model(1)
	check(original.summon(cost_rules,"forest","world",rng(3)),"base summon")
	check(original.data.pending.size()==5 and original.data.magic==296,"five stable originals and exact charge")
	var reload = model(1)
	reload.save_path = original.save_path
	check(reload.load_save(),"valid expanded schema reload")
	# JSON parses integer literals as floating point; compare the serialized data contract.
	check(reload.data.monsters==JSON.parse_string(JSON.stringify(original.data.monsters)),"no reroll on reopen")
	var saved_snapshot: Dictionary = original.data.duplicate(true)
	check(not original.summon(cost_rules,"forest","world",rng(4)) and original.data==saved_snapshot,"pending prevents duplicate debit")
	check(original.store_pending(),"store base batch")
	var first_id: String = original.data.monsters[0].id
	var attributes: Dictionary = original.monster_by_id(first_id).duplicate(true)
	check(original.rename_monster(first_id,"同名") and original.move_monster(first_id,"team"),"name and transfer")
	check(original.monster_by_id(first_id).hp==attributes.hp and original.monster_by_id(first_id).attack==attributes.attack and original.monster_by_id(first_id).tier==attributes.tier,"no permanent growth on UI operation")
	var failed = model(1)
	failed.save_path = ProjectSettings.globalize_path("res://Tests/.runtime")+"/missing_v06_directory/session.json"
	var before: Dictionary = failed.data.duplicate(true)
	check(not failed.summon(cost_rules,"forest","world",rng(3)) and failed.data==before,"save failure rolls back debit, IDs and pending")
	var poor = model(1)
	poor.data.magic = 3
	check(not poor.summon(cost_rules,"forest","world",rng(3)) and poor.data.monsters.is_empty() and poor.data.magic==3,"insufficient mana does not generate")
	var forged = construct(["armor"],1)
	forged.placed.append(forged.placed[0].duplicate(true))
	check(not model(1).summon(forged,"forest","world",rng(3)),"overlapping layout rejected at commit")
	for rune in Rules.RUNES:
		var below: Array = []
		for n in rune.threshold-1:
			below.append(rune.id)
		var below_rules = construct(below)
		check(Experiment.preview(below_rules).sources.is_empty(),"below mutation boundary "+rune.id)
		below.append(rune.id)
		var at_rules = construct(below)
		check(Experiment.preview(at_rules).sources.size()==1,"at mutation boundary "+rune.id)
		at_rules.placed.back().enabled = false
		check(Experiment.preview(at_rules).sources.is_empty(),"disabled does not contribute risk "+rune.id)
	var mutation_rules = construct(["armor","armor","armor","armor"])
	var saw_normal := false
	var saw_mutated := false
	var saw_failure := false
	var saw_partial := false
	for seed_value in range(30):
		var result := Experiment.generate(mutation_rules,1,"forest",rng(seed_value))
		check(result.units.size()+result.report.failed==5,"per-creature accounting")
		saw_failure = saw_failure or result.report.failed>0
		saw_partial = saw_partial or (result.units.size()>0 and result.units.size()<5)
		for unit in result.units:
			if unit.mutation_sources.is_empty():
				saw_normal = true
				check(unit.armor==int(round(7.0*2.6)),"ordinary repeat benefit")
			else:
				saw_mutated = true
				check(unit.armor==int(round(7.0*7.4)) and unit.mutation_sources==["armor"],"mutation amplifies triggering armor")
			check(unit.hp==unit.base_stats.hp and unit.attack==unit.base_stats.attack,"armor mutation does not amplify unrelated stats")
	check(saw_normal and saw_mutated and saw_failure and saw_partial,"independent normal, mutated, failed and partial outcomes observed")
	var giant_rules = construct(["giant"],1)
	var giants = model(1)
	check(giants.summon(giant_rules,"forest","world",rng(9)) and giants.data.pending.size()==3,"giant count")
	for id in giants.data.pending.duplicate():
		check(giants.monster_by_id(id).slots==2 and giants.move_monster(id,"team"),"giant occupies two slots")
	check(giants.occupied_slots()==6,"three giants fill six slots")
	var ultra_rules = construct(["giant","giant"],3)
	check(Experiment.preview(ultra_rules).count==1 and Experiment.preview(ultra_rules).total_slots==5,"ultra changes batch before generation")
	var ultra_success := false
	var ultra_failure := false
	for seed_value in range(80):
		var result := Experiment.generate(ultra_rules,1,"forest",rng(seed_value))
		check(result.report.attempted==1,"ultra only one attempt")
		ultra_failure = ultra_failure or result.units.is_empty()
		if not result.units.is_empty():
			ultra_success = true
			check(result.units[0].slots==5 and result.units[0].mode=="ultra" and result.units[0].hp>1500,"ultra success strength and slots")
	check(ultra_success and ultra_failure,"ultra success and failure both exercised")
	var failure_commit = model(3)
	var all_fail_seed := 0
	while not Experiment.generate(ultra_rules,1,"forest",rng(all_fail_seed)).units.is_empty():
		all_fail_seed += 1
	check(failure_commit.summon(ultra_rules,"forest","world",rng(all_fail_seed)),"failed attempt is committed")
	check(failure_commit.data.pending.is_empty() and failure_commit.data.magic==286 and failure_commit.data.last_summon.failed==1,"all-failed debits once and persists report")
	var clone_rules = construct(["multiply"],2)
	var clones: Array = Experiment.generate(clone_rules,2,"forest",rng(8)).units
	check(clones.size()==5 and clones[0].clone_count==1 and clones[0].recoverable,"clone capability attached to recoverable original only")
	var tiny_rules = construct(["tiny"],2)
	var tiny = model(2)
	check(tiny.summon(tiny_rules,"forest","world",rng(8)),"tiny batch")
	check(tiny.move_monster(tiny.data.pending[0],"team") and tiny.monsters("team").size()==5 and tiny.occupied_slots()==1,"tiny transfer is atomic group")
	check(not tiny.data.monsters[0].recoverable,"tiny recovery disabled")
	check(tiny.move_monster(tiny.data.monsters[2].id,"warehouse") and tiny.monsters("team").is_empty(),"tiny withdrawal moves whole group")
	tiny.move_monster(tiny.data.monsters[0].id,"team")
	tiny.save_path = ProjectSettings.globalize_path("res://Tests/.runtime")+"/missing_v06_directory/tiny.json"
	before = tiny.data.duplicate(true)
	check(not tiny.move_monster(tiny.data.monsters[0].id,"warehouse") and tiny.data==before,"group transfer save failure rolls back")
	var combination = construct(["giant","tiny"])
	check(not model().summon(combination,"forest","world",rng(3)),"undefined structural combination reports blocking reason")
	for mirrored in [false,true]:
		for turn in 6:
			check(Experiment.recipe_matches(recipe(turn,mirrored)),"exact spatial recipe allows whole transformations")
	var recipe_rules = recipe()
	var special = model()
	check(special.summon(recipe_rules,"forest","world",rng(8)) and special.data.pending.size()==1,"targeted one-creature summon")
	check(special.data.monsters[0].recipe_id==Experiment.RECIPE.id and special.data.monsters[0].form=="兽形","targeted category persisted")
	recipe_rules.placed[0].cells = [[-3,0],[-2,0]]
	check(not Experiment.recipe_matches(recipe_rules),"same counts in wrong pattern do not match")
	for mirrored in [false,true]:
		for turn in 6:
			var rotated_recipe = recipe(turn,mirrored)
			var restored_recipe = Rules.new()
			check(restored_recipe.import_layout(rotated_recipe.export_layout()) and Experiment.recipe_matches(restored_recipe),"transformed recipe survives layout restore")
	var backup_fixture = model(1)
	backup_fixture.summon(cost_rules,"forest","world",rng(14))
	backup_fixture.store_pending()
	var expected_id: String = backup_fixture.data.monsters[0].id
	var damaged_file := FileAccess.open(backup_fixture.save_path,FileAccess.WRITE)
	damaged_file.store_string("not valid json")
	damaged_file.close()
	var backup_reload = model(1)
	backup_reload.save_path = backup_fixture.save_path
	check(backup_reload.load_save() and backup_reload.data.monsters[0].id==expected_id and not backup_reload.data.pending.is_empty(),"backup restores identical pending batch without reroll")
	# A real old-schema snapshot keeps inventory/rewards, archives incompatible strokes.
	var legacy = model(1)
	legacy.data.erase("array_stage")
	legacy.data.erase("last_summon")
	legacy.data.magic = 320
	legacy.data.completed = ["event_traveler"]
	legacy.data.layout = {"version":2,"placed":[{"uid":"r1","runeId":"ember","enabled":true,"cells":[[0,0],[1,0],[1,-1],[2,-1]]}],"placedRelics":[]}
	legacy.data.monsters = [{"id":"summon_1_0","name":"旧妖兽","form":"人形","hp":100,"attack":20,"armor":5,"speed":3.0,"traits":["余烬"],"position":"warehouse","color":"839b78"}]
	legacy.data.serial = 1
	check(legacy.save(),"legacy fixture persisted")
	var restored = model(1)
	restored.save_path = legacy.save_path
	check(restored.load_save(),"old save opens")
	check(restored.data.monsters==JSON.parse_string(JSON.stringify(legacy.data.monsters)) and restored.data.magic==320 and restored.data.completed==["event_traveler"],"legacy inventory, currency and event ledger retained")
	check(restored.data.legacy_summon_layout==JSON.parse_string(JSON.stringify(legacy.data.layout)) and restored.data.array_stage==1 and restored.data.layout.placed.is_empty(),"old layout archived separately from new seven-cell board")
	check(restored.save(),"migrated save commits")
	check(FileAccess.file_exists(restored.save_path+".pre_summon_v2.bak") and JSON.parse_string(FileAccess.get_file_as_string(restored.save_path+".pre_summon_v2.bak"))==JSON.parse_string(JSON.stringify(legacy.data)),"immutable pre-upgrade backup retains original full save")
	var next_reload = model(1)
	next_reload.save_path = restored.save_path
	check(next_reload.load_save() and next_reload.data.monsters.size()==1,"legacy creatures survive subsequent reload")
	check(next_reload.move_monster("summon_1_0","team") and next_reload.occupied_slots()==1,"legacy unit keeps ordinary placement")
	await _ui_checks()
	print("SUMMON_V2_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)

func _ui_checks() -> void:
	app = Scene.instantiate()
	app.animate_panels = false
	app.state.save_path = ProjectSettings.globalize_path("res://Tests/.runtime")+"/summon_v2_scene_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app._show("world")
	app._open_ritual()
	await settle()
	check(not app.ritual_page.get_node("%Risk").visible,"risk UI hidden before threshold")
	check(app.ritual_page.get_node("Columns/C1/CopperLinks") != null,"original copper-linked leaves retained")
	for resolution in [Vector2i(1120,680),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		await settle()
		check(app.modal_scroll.get_global_rect().encloses(app.summon_button.get_global_rect()),"summon action visible "+str(resolution))
		check(app.ritual_columns.size.x <= app.modal_scroll.size.x+1,"book fits width "+str(resolution))
		await capture("summon_v2_book_%d" % resolution.x)
	check(app.board.cell_at(app.board.point([2,0])).is_empty(),"locked cell has no input hit")
	for c in Rules.definition("armor").cells:
		var input := InputEventMouseButton.new()
		input.button_index = MOUSE_BUTTON_LEFT
		input.pressed = true
		input.position = app.board.point(c)
		app.board._gui_input(input)
		input.pressed = false
		app.board._gui_input(input)
	app.ritual_page.get_node("%Commit").pressed.emit()
	check(app.rules.placed.size()==1 and not app.summon_button.disabled,"real board/button interaction")
	app.summon_button.pressed.emit()
	app.view.skip_eruption()
	await settle()
	check(app.state.data.pending.size()==5,"five result instances")
	for resolution in [Vector2i(1120,680),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		await settle()
		var page = app.modal_box.get_child(0)
		check(app.modal_scroll.get_global_rect().encloses(page.get_node("%StoreAll").get_global_rect()),"result action visible "+str(resolution))
		check(page.get_node("%Cards").size.x <= page.size.x+1,"five results never overflow horizontally "+str(resolution))
		await capture("summon_v2_results_%d" % resolution.x)
	var result_page = app.modal_box.get_child(0)
	result_page.get_node("%Cards").get_child(0).get_node("%Detail").pressed.emit()
	await settle()
	check("攻击周期" in app.modal_box.get_child(0).get_node("%Stats").text,"summon detail exposes expanded generated attributes")
	app._close_modal()
	app._close_modal()
	check(app.state.monsters("warehouse").size()==5,"close results stores all")
	app._open_ritual()
	app.ritual_page.get_node("%Upgrade").pressed.emit()
	await settle()
	check(app.rules.stage==2 and app.state.data.magic==298,"upgrade via UI no extra mana")
	app._load_example(2)
	app.modal_box.get_child(0).get_node("%Commands").get_child(0).pressed.emit()
	await settle()
	check(app.ritual_page.get_node("%Risk").visible,"risk UI appears at four basic copies")
	root.size = Vector2i(1280,720)
	await settle()
	await capture("summon_v2_risk")
	app.summon_button.pressed.emit()
	check(app.modal_stack.back().title=="确认风险召唤" and app.state.data.magic==298,"risk confirmation before debit")
	app._close_modal()
	check(app.state.data.magic==298,"cancel risk confirmation is free")
	app._close_all()
	app.state = model(3)
	var ultra_rules = construct(["giant","giant"],3)
	var failure_seed := 0
	while not Experiment.generate(ultra_rules,1,"forest",rng(failure_seed)).units.is_empty():
		failure_seed += 1
	app.state.summon(ultra_rules,"forest","world",rng(failure_seed))
	app._results()
	await settle()
	check(app.modal_box.get_child(0).get_node("%Empty").visible and "失败 1 只" in app.modal_box.get_child(0).get_node("%Hint").text,"all-failed UI retains outcome with no fabricated creature")
	app._close_modal()
	check(app.state.data.monsters.is_empty(),"closing all-failed result never creates inventory")
	app.queue_free()
	await settle()
