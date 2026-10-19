extends SceneTree
const SESSION = preload("res://Scripts/Application/GameSession.gd")
const ROOT_SCENE = preload("res://Scenes/Application/GameRoot.tscn")
var failures: Array[String] = []
var checks := 0
var app: Node

func _initialize() -> void:
	create_timer(120).timeout.connect(func(): push_error("OPENING_EVENT_TIMEOUT"); quit(1))
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks+=1
	print("OPENING_CHECK ",ok," ",message)
	if not ok: failures.append(message); push_error(message)

func frames(count := 3) -> void:
	for frame: int in count: await process_frame

func next_button() -> Button:
	return app.ui.modal_box.find_child("OpeningNext",true,false) as Button

func wait_world() -> void:
	for frame: int in 600:
		if app.phase=="world": return
		await process_frame
	check(false,"world entered before timeout")

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await create_timer(0.6).timeout
	await frames(5)
	await RenderingServer.frame_post_draw
	var folder := "res://Tests/.runtime/opening_appointment"
	DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder+"/"+label+".png")==OK,"capture "+label)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	root.size=Vector2i(1280,720)
	var fixture := SESSION.new()
	check(not fixture.opening_event_pending(),"reset and legacy saves are not forced into the event")
	fixture.prepare_opening_event()
	check(fixture._valid_save(fixture.data),"pending opening state is valid")
	var malformed := fixture.data.duplicate(true)
	malformed.opening_event.line=null
	check(not fixture._valid_save(malformed),"Nil reading index rejected")
	malformed=fixture.data.duplicate(true); malformed.opening_event.completed=true
	check(not fixture._valid_save(malformed),"completion without a credential rejected")
	malformed=fixture.data.duplicate(true); malformed.opening_event.credential={"id":"king_special_order","quantity":1}
	check(not fixture._valid_save(malformed),"pending event cannot already issue a credential")
	app=ROOT_SCENE.instantiate()
	app.save_path="res://Tests/.runtime/integration/opening_"+str(Time.get_ticks_usec())+".json"
	app.display_settings_path=app.save_path+".display.cfg"
	root.add_child(app)
	app.ui.animate_panels=false
	app.ui.board_motion.enabled=false
	app.start_new_game()
	await wait_world()
	check(app.ui.modal_stack.size()==1 and app.ui.modal_stack.back().kind=="opening_event","new game replaces the task popup with the appointment")
	check(app.session.data.new_player_tasks.enabled and app.session.data.new_player_tasks.completed.is_empty(),"task tracking is enabled without fabricating achievements")
	check(app.session.opening_event_definition().lines.size()==8,"all eight original envoy lines are available")
	check(app.ui.close_button.disabled and not app.delivery_map.input_enabled,"reading blocks close shortcut and map input")
	app.ui._close_modal()
	check(app.ui.modal_stack.size()==1,"regular close cannot skip confirmation")
	var time_before: Dictionary=app.session.data.world_time.duplicate()
	var magic_before: int=app.session.data.magic
	app.ui.toggle_settings()
	check(app.ui.modal_stack.size()==2 and app.ui.modal_stack.back().kind=="settings","ESC settings can overlay the opening")
	app.ui.toggle_settings()
	check(app.ui.modal_stack.size()==1 and app.ui.modal_stack.back().kind=="opening_event","closing settings restores the same dialogue")
	await frames()
	check(app.ui.overlay.get_global_rect().has_point(next_button().get_global_rect().get_center()) and app.ui.overlay.get_global_rect().has_point(app.ui.modal_box.find_child("Description",true,false).get_global_rect().get_center()),"dialogue text and next button remain onscreen after settings")
	await capture("01_opening_1280")
	next_button().pressed.emit()
	check(app.session.data.opening_event.line==1 and app.session.opening_event_pending(),"next line persists progress without completing")
	var loaded := SESSION.new(); loaded.save_path=app.save_path
	check(loaded.load_save() and loaded.data.opening_event.line==1,"line progress is written to the real save")
	check(app.return_to_main_menu(),"unfinished dialogue can exit through settings/menu")
	app.ui.main_menu.get_node("%Continue").pressed.emit()
	await wait_world()
	check(app.ui.modal_stack.back().kind=="opening_event" and app.session.data.opening_event.line==1,"continue resumes unfinished reading instead of restarting")
	for line: int in range(2,8): next_button().pressed.emit()
	check(app.session.data.opening_event.line==7 and app.session.opening_event_pending(),"last line still requires explicit acknowledgement")
	await capture("02_confirmation_1280")
	var path: String=app.session.save_path
	var before: Dictionary = app.session.data.duplicate(true)
	app.session.save_path=path+"/blocked.json"
	next_button().pressed.emit()
	check(app.session.data==before and app.session.opening_event_pending(),"failed completion save rolls back both receipt and progress")
	check(app.ui.modal_stack.back().kind=="opening_event" and not next_button().disabled,"failed save leaves the confirmation open and retryable")
	app.session.save_path=path
	next_button().pressed.emit()
	check(app.ui.modal_stack.is_empty() and app.delivery_map.input_enabled,"successful acknowledgement restores free exploration")
	check(not app.session.opening_event_pending() and app.session.data.opening_event.credential.quantity==1,"one story credential is committed")
	check(app.session.data.magic==magic_before and app.session.data.world_time==time_before,"opening grants no extra funds and costs no world time")
	check(not app.session.advance_opening_event() and app.session.data.opening_event.credential.quantity==1,"completed event cannot issue duplicate credentials")
	app.ui.base.get_node("%Navigation").get_node("%Tasks").pressed.emit()
	check(app.ui.modal_stack.back().kind=="tasks" and app.ui._task_page.get_node("%PendingRows").get_child_count()==4,"manual task button retains all four tasks")
	app.ui._close_all()
	check(app.return_to_main_menu(),"completed save returns to menu")
	var save_path: String=app.save_path
	app.free()
	await frames()
	app=ROOT_SCENE.instantiate(); app.save_path=save_path; app.display_settings_path=save_path+".display.cfg"
	root.add_child(app); app.ui.animate_panels=false; app.ui.board_motion.enabled=false
	app.ui.main_menu.get_node("%Continue").pressed.emit()
	await wait_world()
	check(app.ui.modal_stack.is_empty() and app.session.data.opening_event.credential.quantity==1,"restart and continue never replay a completed opening")
	app.session.data.erase("opening_event")
	check(app.session.save() and app.return_to_main_menu(),"legacy save without opening state remains writable")
	app.ui.main_menu.get_node("%Continue").pressed.emit()
	await wait_world()
	check(app.ui.modal_stack.is_empty() and not app.session.data.has("opening_event"),"old saves are not retroactively forced into the opening")
	check(app.return_to_main_menu(),"return before a second new game")
	app.start_new_game()
	await wait_world()
	check(app.session.data.opening_event.line==0 and not app.session.data.opening_event.has("credential") and app.ui.modal_stack.back().kind=="opening_event","new game resets the event and credential")
	for dimensions: Vector2i in [Vector2i(1120,680),Vector2i(1920,1080)]:
		root.size=dimensions
		await frames()
		check(is_instance_valid(next_button()) and not next_button().disabled,"dialogue survives resize "+str(dimensions))
		await capture("opening_"+str(dimensions.x))
	TranslationServer.set_locale("en")
	preload("res://Scripts/Localization/GameText.gd").refresh_bindings()
	check(next_button().text=="Continue" and app.ui.modal_box.find_child("Description",true,false).text.begins_with("Hello."),"English locale updates both dialogue and controls")
	await capture("opening_en")
	TranslationServer.set_locale("zh_CN")
	preload("res://Scripts/Localization/GameText.gd").refresh_bindings()
	app.queue_free()
	await frames()
	print("OPENING_APPOINTMENT_","PASSED" if failures.is_empty() else "FAILED"," checks=",checks)
	quit(0 if failures.is_empty() else 1)
