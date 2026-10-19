extends SceneTree
const APP = preload("res://Scenes/Application/GameRoot.tscn")
const SESSION = preload("res://Scripts/Application/GameSession.gd")
const SERVICE = preload("res://Scripts/Events/StoryService.gd")
const CATALOG = preload("res://Scripts/Events/StoryCatalog.gd")
const OUTPUT := "res://Tests/.runtime/story-dialogue-log/"
var checks := 0
var failures := 0
var app: Node

func _initialize() -> void:
	create_timer(90).timeout.connect(func():push_error("STORY_LOG_TIMEOUT");quit(1))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("STORY_LOG_FAIL: "+label)

func frames(count := 7) -> void:
	for index: int in count: await process_frame

func text_control() -> Label:
	return app.ui.modal_box.find_child("Description",true,false)

func press(caption: String) -> bool:
	for button: Node in app.ui.find_children("*","Button",true,false):
		if button.is_visible_in_tree() and button.text==caption and not button.disabled:
			button.pressed.emit()
			return true
	return false

func expected(id: String, node_id: String, count: int) -> String:
	var lines: Array[String] = []
	for index: int in count: lines.append(CATALOG.paragraph(id,CATALOG.definition(id).nodes[node_id].paragraphs[index]))
	return "\n\n".join(lines)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	root.get_node("GameLocalization").set_locale("zh_CN",false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	app=APP.instantiate()
	app.save_path=OUTPUT+"isolated_%d.json" % Time.get_ticks_usec()
	app.display_settings_path=OUTPUT+"display.cfg"
	root.add_child(app)
	root.size=Vector2i(1120,680)
	root.content_scale_size=Vector2i(1120,680)
	app.ui.animate_panels=false
	app.ui.board_motion.enabled=false
	app.story_controller.set_process(false)
	app.start_new_game()
	for frame: int in 600:
		if app.phase=="world": break
		await process_frame
	app.story_controller._process(0.3)
	await frames()
	var label := text_control()
	var label_id: int = label.get_instance_id()
	var panel_id: int = label.get_parent().get_parent().get_instance_id()
	var scroll_id: int = label.get_parent().get_instance_id()
	check(label.text==expected(SERVICE.OPENING,"intro",1),"Only first revealed sentence is shown initially")
	check(press("继续"),"Continue button works")
	await frames()
	check(text_control().text==expected(SERVICE.OPENING,"intro",2),"Next sentence appears below the first, without replacement")
	check(text_control().get_instance_id()==label_id and text_control().get_parent().get_instance_id()==scroll_id and text_control().get_parent().get_parent().get_instance_id()==panel_id,"Continuing keeps the same paper, Label and scroll container")
	var before: Dictionary = app.session.data.duplicate(true)
	# A retired callback must not duplicate prose or advance a fresh step.
	app.story_controller._choose(SERVICE.OPENING,"next",int(SERVICE.entry(app.session.data,SERVICE.OPENING).revision)-1)
	check(app.session.data==before and text_control().text==expected(SERVICE.OPENING,"intro",2),"Stale click changes neither progress nor prose")
	var real_path: String = app.session.save_path
	app.session.save_path=real_path+"/blocked.json"
	check(press("继续") and app.session.data==before,"Failed save rolls back both cursor and dialogue history")
	check(text_control().text==expected(SERVICE.OPENING,"intro",2),"Failed save never displays uncommitted next sentence")
	app.session.save_path=real_path
	check(press("继续"),"Retry succeeds")
	await frames()
	check(text_control().text==expected(SERVICE.OPENING,"intro",3),"Retry appends once, without repeated previous sentences")
	check(app.ui.modal_feedback.text.is_empty(),"Successful retry clears the previous failure feedback on the reused sheet")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OUTPUT+"opening_three_lines.png")==OK,"Actual first-three-lines capture saved")
	app.ui._settings()
	await frames()
	app.ui._close_modal()
	await frames()
	check(text_control().text==expected(SERVICE.OPENING,"intro",3),"Returning from settings rebuilds exactly the same transcript")
	check(app.ui.close_button.disabled,"Mandatory opening guard survives cumulative display and settings")
	var restored := SESSION.new()
	restored.save_path=real_path
	check(restored.load_save() and SERVICE.prose(restored.data,SERVICE.OPENING)==text_control().text,"Read history survives an actual save reload")
	var legacy: Dictionary = restored.data.duplicate(true)
	legacy.story_events.entries[SERVICE.OPENING].erase("dialogue_history")
	check(restored._valid_save(legacy) and SERVICE.prose(legacy,SERVICE.OPENING)==expected(SERVICE.OPENING,"intro",3),"Old save reconstructs only the proven prefix of its current dialogue")
	for bad: Variant in [null,"bad",[false],[{"node":"missing","paragraph":0}],[{"node":"intro","paragraph":999}]]:
		var corrupt: Dictionary = restored.data.duplicate(true)
		corrupt.story_events.entries[SERVICE.OPENING].dialogue_history=bad
		check(not restored._valid_save(corrupt),"Malformed history is rejected without runtime failure")
	var count: int = CATALOG.definition(SERVICE.OPENING).nodes.intro.paragraphs.size()
	while int(SERVICE.entry(app.session.data,SERVICE.OPENING).cursor)+1<count:
		check(press("继续"),"Append next opening sentence")
		await frames()
		check(text_control().text==expected(SERVICE.OPENING,"intro",int(SERVICE.entry(app.session.data,SERVICE.OPENING).cursor)+1),"Transcript order matches revealed authoring paragraphs")
	var scroll: ScrollContainer = text_control().get_parent()
	check(text_control().text==expected(SERVICE.OPENING,"intro",count),"Entire opening remains readable on the same sheet")
	check(scroll.get_v_scroll_bar().max_value>scroll.get_v_scroll_bar().page and scroll.scroll_vertical>0,"Long accumulated dialogue automatically scrolls downward")
	check(is_equal_approx(float(scroll.scroll_vertical)+scroll.get_v_scroll_bar().page,scroll.get_v_scroll_bar().max_value),"Automatic scroll reaches latest sentence")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OUTPUT+"opening_accumulated.png")==OK,"Actual cumulative dialogue capture saved")
	check(press("阅读完成"),"Opening advances to signature")
	await frames()
	check(text_control().text==expected(SERVICE.OPENING,"intro",count),"Signature step retains prior conversation")
	check(press("确认签收") and SERVICE.entry(app.session.data,SERVICE.OPENING).completed,"Unchanged signature and reward path completes")
	app.ui._close_all()
	var id: String = SERVICE.LIBRARY
	check(app.session.open_story_event(id,CATALOG.bindings(id)[0]),"Different event opens")
	app.story_controller._present(id)
	await frames()
	check(text_control().text==expected(id,"intro",1) and not text_control().text.contains("王国特使"),"Different event has an independent transcript")
	var ghost := SERVICE.GHOST
	var data: Dictionary = SESSION.new().data
	var context := {"source_id":"fixture","entry_role":"engine_ghost","trigger_mode":"on_game_time"}
	var row := SERVICE.new_entry(ghost,context)
	row.node="decision"
	SERVICE.ensure(data).entries[ghost]=row
	check(SERVICE.advance(data,CATALOG.parameters(),ghost,"kind",0).is_empty(),"Selected response enters only its own branch")
	check(row.dialogue_history.size()==1 and row.dialogue_history[0].node=="kind","Unchosen branch never enters saved reading history")
	var merchant := SESSION.new()
	var donkey_id := "QST_GRASS_007"
	for binding: Dictionary in CATALOG.bindings(donkey_id):
		if binding.entry_role!="merchant": continue
		check(merchant.open_story_event(donkey_id,binding),"Merchant-first event entry works")
		check(SERVICE.entry(merchant.data,donkey_id).dialogue_history.size()==1 and SERVICE.entry(merchant.data,donkey_id).dialogue_history[0].node=="merchant","Merchant-first log does not leak unvisited donkey dialogue")
		break
	app.queue_free()
	await frames(4)
	print("STORY_LOG_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
