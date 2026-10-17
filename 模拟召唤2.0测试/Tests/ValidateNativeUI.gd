extends SceneTree
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
const State = preload("res://Scripts/PrototypeState.gd")
const Scene = preload("res://Scenes/GameDemo.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAILED: "+description)

func _run() -> void:
	var rules = Rules.new()
	rules.stage = 4
	check(Rules.cells().size()==61,"61 cells")
	for rune in Rules.RUNES:
		for mirror in [false,true]:
			for rotation in 6:
				var shape: Array = Rules.transformed(rune.cells,rotation,mirror)
				for c in shape:
					c[0] += 2
					c[1] -= 1
				var expected: String = rune.id
				check(rules.recognize(shape).get("id","")==expected,"matches source transforms "+rune.id)
				shape.reverse()
				check(rules.recognize(shape).get("id","")==expected,"matches source reverse "+rune.id)
	check(rules.extend([0,0]),"begin")
	for rune in Rules.RUNES:
		for i in range(1,rune.cells.size()):
			check(Rules.distance(rune.cells[i-1],rune.cells[i])==1,"every stroke adjacent "+rune.id)
	check(not rules.extend([0,0]),"no repeat")
	check(not rules.extend([3,0]),"must be adjacent")
	check(not rules.commit() and rules.draft.size()==1,"failed stroke preserved")
	rules.draft.clear()
	for c in Rules.RUNES[0].cells:
		check(rules.extend(c),"valid armor stroke")
	check(rules.commit(),"commit armor")
	rules.placed[0].enabled = false
	check(not rules.can_use([0,0]),"disabled still occupies")
	check(not rules.place_relic("bone-die",[0,0]),"reject overlap")
	check(rules.place_relic("bone-die",[-3,0]),"place relic")
	check(not rules.place_relic("bone-die",[0,3]),"unique relic")
	check(not rules.place_relic("tide-pump",[4,4]),"bounds")
	var restored = Rules.new()
	restored.stage = 4
	check(restored.import_layout(rules.export_layout()),"layout import")
	check(restored.relics.size()==1 and restored.placed.size()==1,"layout roundtrip")
	check(not restored.placed[0].enabled,"enabled roundtrip")
	rules.placed[0].enabled = true
	var state = State.new()
	state.data.array_stage = 4
	state.save_path = "user://native_ui_test_%d.json" % Time.get_ticks_usec()
	check(state.summon(rules,"forest","world"),"summon succeeds")
	check(state.data.magic==296 and state.data.pending.size()==5,"cost and count")
	check(not state.summon(rules,"forest","world"),"pending blocks duplicate summon")
	var loaded = State.new()
	loaded.save_path = state.save_path
	check(loaded.load_save(),"reload")
	for i in 5:
		var a: Dictionary = loaded.data.monsters[i]
		var b: Dictionary = state.data.monsters[i]
		check(a.id==b.id and a.name==b.name and int(a.hp)==int(b.hp) and int(a.attack)==int(b.attack) and is_equal_approx(float(a.speed),float(b.speed)) and a.traits==b.traits,"outcome stable across load")
	check(state.store_pending(),"store pending")
	for batch in 2:
		check(state.summon(rules,"forest","world"),"next batch")
		check(state.store_pending(),"store next batch")
	for i in 6:
		check(state.move_monster(state.data.monsters[i].id,"team"),"team slot")
	check(not state.move_monster(state.data.monsters[6].id,"team"),"team limit")
	check(state.move_monster(state.data.monsters[0].id,"warehouse"),"withdraw")
	check(state.move_monster(state.data.monsters[6].id,"team"),"replace")
	check(state.rename_monster(state.data.monsters[0].id,"命名试样"),"rename")
	var money: int = state.data.magic
	check(state.claim_once("battle_test",20),"claim")
	check(not state.claim_once("battle_test",20) and state.data.magic==money+20,"reward exactly once")
	var failed = State.new()
	failed.data.array_stage = 4
	failed.save_path = "user://missing_test_directory/session.json"
	check(not failed.summon(rules,"grassland","world"),"save failure rejects summon")
	check(failed.data.magic==300 and failed.data.monsters.is_empty(),"save failure rolls back")
	var app = Scene.instantiate()
	app.animate_panels = false
	app.state.save_path = "user://native_ui_scene_test_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	await process_frame
	check(app.route=="main","native entry")
	app._show("world")
	app._open_ritual()
	await process_frame
	check(app.overlay.visible and app.board != null,"native ritual window")
	for c in Rules.RUNES[0].cells:
		app.rules.extend(c)
	app.rules.commit()
	app._refresh_ritual()
	check(not app.summon_button.disabled,"summon enabled")
	app._summon()
	check(app.route=="eruption" and app.state.data.pending.size()==5,"world summon uses scene")
	app.view.skip_eruption()
	await process_frame
	check(app.route=="world" and app.overlay.visible,"eruption returns to map with results")
	app._close_modal()
	check(app.state.data.pending.is_empty() and app.state.monsters("warehouse").size()==5,"closing results stores all")
	app.state.move_monster(app.state.data.monsters[0].id,"team")
	app._warehouse("team")
	app._detail(app.state.data.monsters[0].id)
	app._term("攻击","说明")
	check(app.modal_stack.size()==3,"nested tooltips")
	app._close_modal()
	check(app.modal_stack.size()==2,"tooltip returns to detail")
	app._close_all()
	app._show("battle")
	app._skip_battle()
	check(app.modal_stack.back().title=="战斗胜利","skip shows settlement")
	app._close_all()
	app._open_event("traveler")
	check(app.route=="battle","event does not load exploration scene")
	app._close_all()
	app.queue_free()
	await process_frame
	print("NATIVE_UI_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
