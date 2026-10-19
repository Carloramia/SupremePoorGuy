extends SceneTree
const ROOT_SCENE = preload("res://Scenes/Application/GameRoot.tscn")
var checks := 0
var failures := 0
var app: Node

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL: "+label)

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): push_error("Task UI test timed out"); quit(1))
	call_deferred("run")

func frames(count := 3) -> void:
	for _frame: int in count: await process_frame

func wait_world() -> bool:
	for _frame: int in 900:
		if app.phase=="world": return true
		await physics_frame
	return false

func task_row(id: String) -> Control:
	for row: Control in app.ui._task_page.get_node("%PendingRows").get_children():
		if row.get_meta("task_id","")==id: return row
	return null

func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await frames(5)
	RenderingServer.force_draw()
	var picture := root.get_texture().get_image()
	check(picture!=null and not picture.is_empty(),"Rendered task viewport is available")
	if picture==null or picture.is_empty(): return
	var folder := "res://Tests/.runtime/new_player_tasks_screenshots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	check(picture.save_png(folder+"/"+name+".png")==OK,"Task screenshot saved: "+name)

func run() -> void:
	root.size = Vector2i(1280,720)
	app = ROOT_SCENE.instantiate()
	app.save_path = "res://Tests/.runtime/integration/task_ui_%d.json" % Time.get_ticks_usec()
	app.display_settings_path = "res://Tests/.runtime/integration/task_ui_display_%d.cfg" % Time.get_ticks_usec()
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	await frames()
	var button: Button = app.ui.base.get_node("%Navigation").get_node("%Tasks")
	check(button.disabled,"Task entry is disabled at the main menu")
	app.ui._start_new()
	check(await wait_world(),"New game enters the real delivery map")
	await frames()
	check(app.session.data.new_player_tasks.enabled and app.ui.overlay.visible,"First new-game world entry activates tasks and opens the story")
	check(app.ui.modal_stack.size()==1 and app.ui.modal_stack.back().kind=="opening_event","New game opens the appointment instead of a task paper")
	check(app.session.data.new_player_tasks.completed.is_empty(),"Spawning and saving the map complete no task")
	preload("res://Tests/Integration/ApplicationFixtures.gd").complete_opening(app)
	await frames()
	check(app.ui.modal_stack.is_empty() and not button.disabled and app.delivery_map.input_enabled,"Closing the initial guide restores travel without reopening it")
	button.pressed.emit()
	await frames()
	check(app.ui.modal_stack.back().kind=="tasks" and app.ui._task_page.get_node("%PendingRows").get_child_count()==4,"Existing entry opens all four task rows")
	check(task_row("prepare_party").get_node("%Go").disabled and task_row("prepare_party").get_node("%Description").text.contains("完成召唤"),"Locked task displays its prerequisite and disables action")
	app.ui._task_action("prepare_party")
	check(app.ui.modal_stack.back().kind=="tasks","A direct locked task request cannot bypass the guard")
	await capture("01_initial_1280")
	for size: Vector2i in [Vector2i(1120,680),Vector2i(1920,1080)]:
		root.size = size
		await frames()
		check(app.ui._task_page.get_node("%PendingRows").get_child_count()==4,"Task rows survive resize: "+str(size.x))
		await capture("initial_"+str(size.x))
	root.size = Vector2i(1280,720)
	task_row("explore_frontier").get_node("%Go").pressed.emit()
	await frames()
	check(app.ui.modal_stack.is_empty() and app.ui.route=="world" and app.phase=="world","Exploration action closes the paper and returns to the map")
	app.ui._tasks()
	task_row("complete_summon").get_node("%Go").pressed.emit()
	await frames()
	check(not app.ui.modal_stack.is_empty() and app.ui.modal_stack.back().title.begins_with("六相召唤阵"),"Summon task reuses the existing ritual route")
	app.ui._close_all()
	await frames()
	# Click the actual summoning hut on the actual native map.
	var point: Vector2 = app.delivery_map.get_global_transform_with_canvas()*app.delivery_map.world_to_screen(app.delivery_map.runtime.player())
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point; event.global_position = point; event.pressed = pressed
		root.push_input(event,true)
		await process_frame
	for _frame: int in 180:
		if app.ui.overlay.visible: break
		await physics_frame
	check(app.session.data.new_player_tasks.completed.has("explore_frontier"),"Actual map click and hut arrival permanently complete exploration")
	app.ui._close_all()
	await frames()
	app.ui._tasks()
	check(task_row("explore_frontier").get_node("%Status").text.contains("已完成"),"Completed task remains visible with its checkmark")
	check(task_row("explore_frontier").get_node("%Go").disabled,"Completed action is disabled")
	await capture("02_explored_1280")
	app.ui._close_all()
	var rules = app.ui.Rules.new()
	rules.extend([0,0]); rules.extend([1,0]); rules.commit()
	var rng := RandomNumberGenerator.new(); rng.seed = 1234
	check(app.session.summon(rules,"frontier_layout","world",rng),"Actual session generates a supported batch")
	var id: String = app.session.data.pending[0]
	check(app.session.move_monster(id,"team") and app.session.store_pending(),"Actual batch is assigned and stored")
	app.ui._tasks()
	check(not task_row("win_battle").get_node("%Go").disabled,"Party completion unlocks victory task")
	await capture("03_ready_1280")
	task_row("win_battle").get_node("%Go").pressed.emit()
	await frames()
	check(app.phase=="world" and app.ui.modal_stack.is_empty() and not is_instance_valid(app.battle),"Victory task returns to map without automatically starting combat")
	# A valid persisted receipt is sufficient for the UI; combat itself is covered by delivery regression tests.
	app.session.data.battle_results["ui_victory"] = {"battle_id":"ui_victory","outcome":"victory","reward":0,"parts":{}}
	var saved: bool = app.session.save()
	check(saved,"Victory receipt and task result save together: "+app.session.last_error)
	if not saved: app.queue_free(); await frames(); quit(1); return
	app.ui._tasks()
	check(app.ui._task_page.get_node("%PendingRows").get_child_count()==4 and app.ui._task_page.get_node("%PendingEmpty").visible,"All completed rows and final summary are retained")
	check(app.ui._task_page.get_node("%PendingRows").get_children().all(func(row): return row.get_node("%Status").text.contains("已完成")),"All four statuses show completion")
	await capture("04_complete_1280")
	app.ui._close_all()
	for phase: String in ["loading_world","loading_battle","deployment","battle","settlement","returning","scenario","main"]:
		app.phase = phase
		app.ui._process(0.0)
		check(button.disabled,"Task entry remains disabled in phase: "+phase)
		app.ui._tasks()
		check(app.ui.modal_stack.is_empty(),"Direct task opening is rejected in phase: "+phase)
	app.phase = "world"
	app.ui._process(0.0)
	check(not button.disabled,"Returning to the map restores the task entry")
	check(app.return_to_main_menu(),"Existing return-to-menu flow saves successfully")
	app.ui.main_menu.get_node("%Continue").pressed.emit()
	check(await wait_world(),"Continue reenters the real map")
	await frames()
	check(app.ui.modal_stack.is_empty() and app.session.data.new_player_tasks.completed.size()==4,"Continue preserves progress without automatically reopening the guide")
	check(app.return_to_main_menu(),"Return to the menu before a second new game")
	app.start_new_game()
	check(await wait_world(),"A second new game returns to the real map")
	await frames()
	check(app.session.data.new_player_tasks.enabled and app.session.data.new_player_tasks.completed.is_empty(),"A new game clears the prior tutorial while enabling the new one")
	check(app.ui.modal_stack.size()==1 and app.ui.modal_stack.back().kind=="opening_event","Another new game opens its own appointment once")
	preload("res://Tests/Integration/ApplicationFixtures.gd").complete_opening(app)
	var saved_path: String = app.save_path
	var display_path: String = app.display_settings_path
	app.queue_free()
	await frames()
	app = ROOT_SCENE.instantiate()
	app.save_path = saved_path
	app.display_settings_path = display_path
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	app.ui.main_menu.get_node("%Continue").pressed.emit()
	check(await wait_world(),"Continue also restores a newly created save after restart")
	await frames()
	check(app.ui.modal_stack.is_empty(),"Restarting and continuing does not repeat the initial guide")
	app.queue_free()
	await frames()
	print("NEW_PLAYER_TASK_UI checks=",checks," failures=",failures)
	quit(1 if failures else 0)
