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
	result.save_path = "user://native_v06_%d_%d.json" % [Time.get_ticks_usec(),checks]
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
	failed_unlock.save_path = "user://missing_v06_directory/unlock.json"
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
	failed.save_path = "user://missing_v06_directory/session.json"
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
	tiny.save_path = "user://missing_v06_directory/tiny.json"
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
	# Battle interface: controlled fixtures, no invented combat scene or timing claim.
	var battle = model()
	var battle_rules = construct(["armor"])
	check(battle.summon(battle_rules,"forest","world",rng(12)) and battle.store_pending(),"battle fixture")
	for i in 3:
		battle.data.monsters[i].tier = i+1
		battle.move_monster(battle.data.monsters[i].id,"team")
	var survivor_id: String = battle.data.monsters[2].id
	var dead_ids: Array = [battle.data.monsters[0].id,battle.data.monsters[1].id]
	var survivor_hp: int = battle.monster_by_id(survivor_id).hp
	var initial_magic: int = battle.data.magic
	var receipt := {"id":"test_win","victory":true,"dead_original_ids":dead_ids,"clone_deaths":50}
	check(battle.apply_battle_receipt(receipt) and battle.data.magic==initial_magic+1,"victory only recovers dead tier1=0 tier2=1; clones ignored")
	check(battle.monster_by_id(dead_ids[0]).is_empty() and battle.monster_by_id(survivor_id).hp==survivor_hp,"permanent removal and unchanged survivor")
	check(not battle.apply_battle_receipt(receipt) and battle.data.magic==initial_magic+1,"receipt idempotence")
	var battle_reload = model()
	battle_reload.save_path = battle.save_path
	check(battle_reload.load_save() and battle_reload.monster_by_id(dead_ids[1]).is_empty(),"deaths remain removed after reload")
	check(battle.apply_battle_receipt({"id":"test_loss","victory":false,"dead_original_ids":[survivor_id]}) and battle.data.magic==initial_magic+1,"defeat permanently removes without recovery")
	check(not battle.apply_battle_receipt({"id":"forged","victory":true,"dead_original_ids":["clone_1"]}),"unknown clone ID cannot collect recovery")
	var tiny_battle = model(2)
	tiny_battle.summon(tiny_rules,"forest","world",rng(8))
	tiny_battle.move_monster(tiny_battle.data.pending[0],"team")
	var tiny_dead: Array = []
	for unit in tiny_battle.data.monsters:
		tiny_dead.append(unit.id)
	initial_magic = tiny_battle.data.magic
	check(tiny_battle.apply_battle_receipt({"id":"tiny_win","victory":true,"dead_original_ids":tiny_dead}) and tiny_battle.data.magic==initial_magic,"victory tiny group never recovers")
	var corrupt: Dictionary = original.data.duplicate(true)
	corrupt.pending = [first_id,first_id]
	check(not original._valid_save(corrupt),"duplicate pending references rejected")
	corrupt = original.data.duplicate(true)
	corrupt.monsters[0].abilities[0].erase("description")
	check(not original._valid_save(corrupt),"malformed ability data rejected before rendering")
	var rollback_battle = model()
	rollback_battle.summon(construct(["armor"]),"forest","world",rng(10))
	rollback_battle.move_monster(rollback_battle.data.pending[0],"team")
	rollback_battle.save_path = "user://missing_v06_directory/receipt.json"
	before = rollback_battle.data.duplicate(true)
	check(not rollback_battle.apply_battle_receipt({"id":"save_fail","victory":true,"dead_original_ids":[rollback_battle.monsters("team")[0].id]}) and rollback_battle.data==before,"death, recovery and receipt ledger all roll back on save failure")
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
	await _ui_checks()
	print("SUMMON_WAREHOUSE_V06_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)

func _ui_checks() -> void:
	app = Scene.instantiate()
	app.animate_panels = false
	app.state.save_path = "user://native_v06_scene_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app._show("world")
	app._open_ritual()
	await settle()
	check(not app.ritual_page.get_node("%Risk").visible,"risk UI hidden before threshold")
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
	app.summon_button.pressed.emit()
	check(app.modal_stack.back().title=="确认风险召唤" and app.state.data.magic==298,"risk confirmation before debit")
	app._close_modal()
	check(app.state.data.magic==298,"cancel risk confirmation is free")
	app._close_all()
	app._warehouse("")
	await settle()
	var page = app.warehouse_page
	check(page.shown_ids.size()==5 and not page.selected_id.is_empty(),"book defaults to first real instance")
	var target_id: String = app.state.data.monsters[0].id
	page.selected_id = target_id
	page.refresh()
	page.get_node("%NameInput").text = "书页改名测试"
	page.get_node("%SaveName").pressed.emit()
	check(app.state.monster_by_id(target_id).name=="书页改名测试" and page.selected_id==target_id,"book rename preserves selection")
	page.get_node("%Move").pressed.emit()
	check(app.state.monster_by_id(target_id).position=="team" and page.selected_id==target_id and app.state.occupied_slots()==1,"book transfer preserves selection and totals")
	page.get_node("%Search").text = "书页改名测试"
	page.get_node("%Search").text_changed.emit("书页改名测试")
	check(page.shown_ids==[target_id],"search targets unique actual instance")
	page.get_node("%Search").text = "无此妖兽"
	page.get_node("%Search").text_changed.emit("无此妖兽")
	check(page.shown_ids.is_empty() and page.get_node("%NoSelection").visible,"empty filter does not show stale details")
	page.get_node("%ClearFilters").pressed.emit()
	check(page.shown_ids.size()==5,"clear filter restores list")
	page.selected_id = target_id
	page.refresh()
	page.get_node("%Search").text = "书页"
	page.get_node("%Search").text_changed.emit("书页")
	page.get_node("%Advanced").button_pressed = true
	await settle()
	page.get_node("%RightScroll").scroll_vertical = 160
	await settle()
	var book_scroll: int = page.get_node("%RightScroll").scroll_vertical
	page.get_node("%Detail").get_node("%Traits").get_child(0).pressed.emit()
	check(app.modal_stack.size()==2,"ability explanation sits above book")
	app._close_modal()
	await settle()
	page = app.warehouse_page
	check(page.selected_id==target_id and page.get_node("%Search").text=="书页","return restores selected instance and filters")
	check(page.get_node("%Advanced").button_pressed and page.get_node("%RightScroll").scroll_vertical==book_scroll,"return restores expanded controls and reading position")
	page.get_node("%ClearFilters").pressed.emit()
	for resolution in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(1024,768),Vector2i(1920,800)]:
		root.size = resolution
		await settle()
		check(app.modal_scroll.get_global_rect().encloses(page.get_node("%LeftScroll").get_global_rect()),"left book page contained "+str(resolution))
		check(app.modal_scroll.get_global_rect().encloses(page.get_node("%RightScroll").get_global_rect()),"right book page contained "+str(resolution))
		check(app.overlay.get_global_rect().encloses(page.get_node("%Move").get_global_rect()),"primary book action visible "+str(resolution))
		check(page.get_node("%LeftScroll").get_global_rect().end.x<page.get_node("%RightScroll").get_global_rect().position.x,"two distinct book halves "+str(resolution))
	var rollback_id: String = page.selected_id
	var old_name: String = app.state.monster_by_id(rollback_id).name
	app.state.save_path = "user://missing_v06_directory/ui.json"
	page.get_node("%NameInput").text = "不应保存"
	page.get_node("%SaveName").pressed.emit()
	check(app.state.monster_by_id(rollback_id).name==old_name and not app.modal_feedback.text.is_empty(),"UI saving failure leaves unchanged model and shows error")
	app._close_all()
	app.state = model(3)
	var ultra_rules = construct(["giant","giant"],3)
	var failure_seed := 0
	while not Experiment.generate(ultra_rules,1,"forest",rng(failure_seed)).units.is_empty():
		failure_seed += 1
	app.state.summon(ultra_rules,"forest","world",rng(failure_seed))
	app._results()
	await settle()
	check(app.modal_box.get_child(0).get_node("%Empty").visible and "失败1只" in app.modal_box.get_child(0).get_node("%Hint").text,"all-failed UI retains outcome with no fabricated creature")
	app._close_modal()
	check(app.state.data.monsters.is_empty(),"closing all-failed result never creates inventory")
	app.queue_free()
	await settle()
