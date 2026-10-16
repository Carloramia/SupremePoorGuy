extends SceneTree
const Scene = preload("res://Scenes/GameDemo.tscn")
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
const State = preload("res://Scripts/PrototypeState.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SKETCH FAILED: "+label)
func settle() -> void:
	for i in 8:
		await process_frame
func _run() -> void:
	root.size = Vector2i(1280,720)
	var app = Scene.instantiate()
	app.animate_panels = false
	app.state.save_path = ProjectSettings.globalize_path("res://Tests/.runtime") + "/native_sketch_test_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	await settle()
	check(app.main_menu.visible,"menu follows supplied sketch")
	app._show("world")
	check(app.actions.get_child_count()==0 and not app.actions.visible,"duplicate location footer removed")
	check(app.status.visible and app.header.text.contains("荒原兽群"),"location in A1 with one footer hint retained")
	check(not app.view.summon_book.visible,"duplicate map corner summon entry removed")
	app._show("battle")
	check(app.actions.get_child_count()==0 and not app.actions.visible,"battle bottom toolbar removed")
	check(app.base.get_node("%Party").visible and app.base.get_node("%ReturnMap").visible,"battle actions moved to left bookmarks")
	check(app.status.visible,"battle hint remains below map")
	app._show("world")
	check(app.header.text.contains("天") and app.header.text.contains("下次事件"),"A1 information")
	check(app.base.get_node("%Tasks").visible,"A2 tasks bookmark")
	app._open_ritual()
	await settle()
	var page: Control = app.modal_box.get_child(0)
	for leaf in ["C1","C2","C3"]:
		check(page.get_node("Columns/"+leaf).scene_file_path.ends_with("LooseLeafPage.tscn"),"independent paper "+leaf)
	check(page.has_node("Columns/C1/CopperLinks") and page.has_node("Columns/C2/CopperLinks"),"two copper bindings join three sheets")
	check(app.ritual_left_scroll.global_position.x < app.board.global_position.x,"C1 left of C2")
	check(app.board.global_position.x < app.ritual_right_scroll.global_position.x,"C3 right of C2")
	check(not page.get_node("%Relics").visible,"relic paper folded initially")
	page.get_node("%RelicTab").pressed.emit()
	check(page.get_node("%Relics").visible,"relic paper opens")
	check(not app.base.get_node("%Settings").disabled,"persistent A1 settings available")
	for cell in Rules.RUNES[0].cells:
		app.rules.extend(cell)
	app.rules.commit()
	app._refresh_ritual()
	app._summon()
	if app.state.data.pending.is_empty():
		quit(1)
		return
	check(app.state.data.pending.size()==3,"single summon preserves batch")
	app.view.skip_eruption()
	await settle()
	check(app.modal_box.get_child(0).get_node("%Cards").get_child_count()==3,"same three results shown")
	app._close_all()
	app.state.store_pending()
	app._warehouse()
	await settle()
	page = app.warehouse_page
	check(page.get_node("D1").scene_file_path.ends_with("LooseLeafPage.tscn") and page.get_node("D2").scene_file_path.ends_with("LooseLeafPage.tscn"),"D1 and D2 are individual sheets")
	check(page.has_node("D1/CopperLinks"),"copper binding joins D sheets")
	check(page.get_node("%DetailBody").get_child_count()>0,"D1 selected detail")
	check(page.get_node("%ListScroll") is ScrollContainer,"D2 scroll list")
	check(page.get_node("%Human").toggle_mode,"right-side form filters")
	var id: String = app.state.data.monsters[0].id
	var count: int = app.state.data.monsters.size()
	app._confirm("回收怪物？","测试",func(): app._recycle_monster(id))
	app._recycle_monster(id)
	check(app.state.data.monsters.size()==count-1,"recycle removes exactly one ID")
	var loaded = State.new()
	loaded.save_path = app.state.save_path
	loaded.load_save()
	check(loaded.monster_by_id(id).is_empty(),"recycle survives reload")
	var bad = State.new()
	bad.data = app.state.data.duplicate(true)
	bad.save_path = ProjectSettings.globalize_path("res://Tests/.runtime") + "/missing_sketch_folder/save.json"
	var survivor: String = bad.data.monsters[0].id
	check(not bad.recycle_monster(survivor) and not bad.monster_by_id(survivor).is_empty(),"failed recycle rolls back")
	app.state.data.known_runes = ["ember"]
	app.state.data.known_relics = []
	check(app.state.claim_once("sketch_unlock",0,["tide"],["bone-die"]),"event reference reward saves")
	app._close_all()
	app._open_ritual()
	page = app.modal_box.get_child(0)
	check(page.get_node("%References").get_child_count()==2,"event rune appears automatically")
	check(page.get_node("%Relics").get_child_count()==1,"event relic appears automatically")
	app.queue_free()
	await process_frame
	print("SKETCH_UI_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)

