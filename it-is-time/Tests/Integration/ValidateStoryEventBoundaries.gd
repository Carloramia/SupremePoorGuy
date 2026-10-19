extends SceneTree
const SESSION = preload("res://Scripts/Application/GameSession.gd")
const SERVICE = preload("res://Scripts/Events/StoryService.gd")
const CATALOG = preload("res://Scripts/Events/StoryCatalog.gd")
const MAPS = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
const SCENE = preload("res://Scenes/Application/GameRoot.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(90).timeout.connect(func():push_error("STORY_BOUNDARY_TIMEOUT");quit(1))
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks+=1
	if not ok: failures+=1; push_error("STORY_BOUNDARY_FAIL: "+label)
	return ok

func press(app: Node, text: String) -> bool:
	for button: Node in app.ui.find_children("*","Button",true,false):
		if button.is_visible_in_tree() and button.text==text and not button.disabled:
			button.pressed.emit()
			return true
	return false

func read(app: Node, id: String) -> void:
	for step: int in 32:
		if CATALOG.definition(id).nodes[SERVICE.entry(app.session.data,id).node].type!="dialogue": return
		if not check(press(app,"继续") or press(app,"阅读完成"),"Current dialogue has a working button"): return

func wait_world(app: Node) -> void:
	for frame: int in 600:
		if app.phase=="world": return
		await process_frame
	check(false,"World startup timed out")

func configuration_checks() -> void:
	var parameters := CATALOG.parameters().duplicate(true)
	check(CATALOG.CONFIGURATION.error(parameters).is_empty(),"Production null placeholders are valid syntax")
	for bad: Variant in [null,[],12,"bad"]:
		var candidate := parameters.duplicate(true)
		candidate[SERVICE.BET].rounds=bad
		check(not CATALOG.CONFIGURATION.error(candidate).is_empty(),"Malformed rounds rejected without a runtime cast error")
	for bad: Variant in ["bad",{},[],true,-1,INF,NAN]:
		var candidate := parameters.duplicate(true)
		candidate[SERVICE.ENGINE].purchase_cost=bad
		check(not CATALOG.CONFIGURATION.error(candidate).is_empty(),"Invalid numeric parameter rejected")
	for bad: Variant in [null,[],"bad"]:
		var candidate := parameters.duplicate(true)
		candidate["QST_GRASS_008"].battles.battle=bad
		check(not CATALOG.CONFIGURATION.error(candidate).is_empty(),"Malformed branch rejected")
	var fields := ["nodes","paragraphs","options","action","label"]
	for field: String in fields:
		var flows := CATALOG.flows().duplicate(true)
		var flow: Dictionary = flows[SERVICE.OPENING]
		match field:
			"nodes": flow.nodes=[]
			"paragraphs": flow.nodes.intro.paragraphs=[999]
			"options": flow.nodes.intro.options={}
			"action": flow.nodes.sign.action=null
			"label": flow.nodes.sign.erase("label")
		check(not CATALOG.validate_assets(flows,CATALOG.texts(),parameters).is_empty(),"Malformed execution field rejected: "+field)
	var session := SESSION.new()
	SERVICE.prepare_new_game(session.data)
	for kind: String in ["cursor","completed","context","await","credential"]:
		var invalid := session.data.duplicate(true)
		var current: Dictionary = invalid.story_events.entries[SERVICE.OPENING]
		match kind:
			"cursor": current.cursor=999
			"completed": current.completed=true
			"context": current.context=null
			"await": current.flags.await_battle=true
			"credential": current.node="end"; current.cursor=0; current.completed=true
		check(not session._valid_save(invalid),"Corrupt story save rejected: "+kind)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	root.get_node("GameLocalization").set_locale("zh_CN",false)
	configuration_checks()
	var app := SCENE.instantiate()
	var save_path := "res://Tests/.runtime/story-boundaries/%d.json" % Time.get_ticks_usec()
	app.save_path=save_path
	app.display_settings_path=save_path+".display.cfg"
	root.add_child(app)
	app.ui.animate_panels=false
	app.ui.board_motion.enabled=false
	app.story_controller.set_process(false)
	app.start_new_game()
	await wait_world(app)
	app.story_controller._process(0.3)
	var opening_magic: float = app.session.data.magic
	var opening_clock: Dictionary = app.session.data.world_time.duplicate(true)
	check(app.ui.close_button.disabled and not app.delivery_map.input_enabled,"Opening prevents skip and map actions")
	app.ui._close_modal()
	check(app.ui.modal_stack.size()==1,"Ordinary close cannot skip opening")
	app.ui.toggle_settings()
	check(app.ui.modal_stack.size()==2 and app.ui.modal_stack.back().kind=="settings","Settings can overlay opening")
	app.ui.toggle_settings()
	check(app.ui.modal_stack.size()==1 and app.ui.close_button.disabled,"Restoring opening preserves mandatory-close guard")
	check(press(app,"继续"),"Opening next works after settings")
	check(app.return_to_main_menu(),"Unfinished opening can save and return to menu")
	app.ui.main_menu.get_node("%Continue").pressed.emit()
	await wait_world(app)
	app.story_controller._process(0.3)
	check(int(SERVICE.entry(app.session.data,SERVICE.OPENING).cursor)==1,"Continue resumes the same opening line")
	read(app,SERVICE.OPENING)
	var before: Dictionary = app.session.data.duplicate(true)
	app.session.save_path=save_path+"/blocked.json"
	check(press(app,"确认签收") and app.session.data==before,"Opening failed receipt save rolls back all progress and credential")
	app.session.save_path=save_path
	check(press(app,"确认签收") and app.session.data.event_items.king_special_order==1,"Same confirmation retries safely")
	check(app.session.data.magic==opening_magic and app.session.data.world_time==opening_clock,"Opening issues no startup money and charges no world time")
	check(app.ui.modal_stack.size()==1 and app.ui.modal_stack.back().kind=="tasks","Tutorial follows successful opening exactly once")
	app.ui._close_all()
	var site: Dictionary = MAPS.location("layout_sargate_city")
	app.delivery_map.runtime.data.player=site.position.duplicate()
	app.delivery_map.runtime._visible_origin=Vector2.INF
	app.delivery_map.runtime._update_hex_visibility()
	app.delivery_map._arrived(site.id,"location")
	check(press(app,"购买扩充引擎"),"City routes to actual engine UI")
	read(app,SERVICE.ENGINE)
	check(press(app,"我买了"),"Native engine purchase succeeds")
	read(app,SERVICE.ENGINE)
	app.session.data.world_time.total_minutes=SERVICE.entry(app.session.data,SERVICE.ENGINE).flags.ghost_due_minutes+1
	check(app.session.save(),"Due-time fixture saves")
	app.delivery_map.runtime.busy=true
	app.story_controller._process(0.3)
	check(app.ui.modal_stack.is_empty(),"Timed event never interrupts an active map action")
	app.delivery_map.runtime.busy=false
	var console: Node = root.get_node("RuntimeConsole")
	console.set_console_open(true)
	app.story_controller._process(0.3)
	check(app.ui.modal_stack.is_empty(),"Timed event never interrupts console")
	console.set_console_open(false)
	app.story_controller._process(0.3)
	check(app.ui.modal_stack.size()==1 and app.ui.modal_stack.back().get("event_id")==SERVICE.GHOST,"Due ghost opens at safe map time")
	app.ui._close_modal()
	app.story_controller._process(0.3)
	check(app.ui.modal_stack.is_empty() and not SERVICE.entry(app.session.data,SERVICE.GHOST).completed,"Dismissed ghost does not reopen every frame or complete itself")
	check(app.story_controller.location_events(site.id).any(func(row):return row.id==SERVICE.GHOST),"Dismissed ghost remains available from its city entry")
	check(app.return_to_main_menu(),"Pending ghost saves on return")
	app.queue_free()
	await process_frame
	app=SCENE.instantiate()
	app.save_path=save_path
	app.display_settings_path=save_path+".display.cfg"
	root.add_child(app)
	app.ui.animate_panels=false
	app.ui.board_motion.enabled=false
	app.story_controller.set_process(false)
	app.ui.main_menu.get_node("%Continue").pressed.emit()
	await wait_world(app)
	app.story_controller._process(0.3)
	check(app.ui.modal_stack.size()==1 and app.ui.modal_stack.back().get("event_id")==SERVICE.GHOST,"Fresh process resumes pending timed dialogue once")
	read(app,SERVICE.GHOST)
	check(press(app,"有点好笑"),"Ghost first reply works through UI")
	read(app,SERVICE.GHOST)
	check(press(app,"学习好战、血肉顽强"),"Ghost reward works through UI")
	app.story_controller._process(0.3)
	check(not SERVICE.due(app.session.data) and app.ui.modal_stack.is_empty(),"Completed timed event never repeats")
	app.queue_free()
	await process_frame
	print("STORY_BOUNDARY_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
