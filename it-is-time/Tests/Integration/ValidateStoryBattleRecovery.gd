extends SceneTree
var checks:=0
var failed:=false
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failed=true; push_error(label)
func wait_phase(app: Node, wanted: String) -> bool:
	for frame in 600:
		if app.phase==wanted: return true
		if app.phase=="settlement" and wanted=="battle": return false
		await physics_frame
	return false
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	var app:=preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.save_path="res://Tests/.runtime/story_recovery_%d.json"%Time.get_ticks_usec(); app.display_settings_path=app.save_path+".cfg"
	root.add_child(app); app.ui.animate_panels=false; app.ui.board_motion.enabled=false
	app.start_new_game(); await wait_phase(app,"world"); app.ui._close_all()
	var opened: Dictionary=app.open_story_event("QST_GRASS_020","knight")
	check(opened.ok,"Actual UI host opens wager")
	var chosen: Dictionary=app.session.story_event_action("QST_GRASS_020","one",opened.event.conversation)
	check(chosen.ok,"Create approved wager")
	app.story_controller.execute(chosen.request)
	var ready: bool=await wait_phase(app,"battle")
	check(ready,"Actual wager enters autonomous combat")
	if not ready: app.queue_free(); await process_frame; quit(1); return
	check(app.session.data.magic==290,"Debit exactly one stake")
	for frame in 25: await physics_frame
	var wounded: Node=app.battle.actors[0].find_children("*","PhysicalBodyPart3D",true,false)[0]
	wounded.apply_damage(7)
	var wounded_path: NodePath=app.battle.actors[0].get_path_to(wounded)
	var saved_hp: float=wounded.current_hp
	check(app.save_session(),"Save actual physics checkpoint")
	var request: Dictionary=app.session.pending_story_request("QST_GRASS_020")
	check(request.plan.has("frozen_rosters") and request.plan.checkpoint.actors.size()==4,"Saved both real teams and each physical actor")
	var elapsed: float=request.plan.checkpoint.elapsed
	check(app.return_to_main_menu(),"Return to menu without aborting wager")
	await process_frame
	check(app.session.load_save(),"Reload pending wager from disk")
	app.enter_world(); await wait_phase(app,"world")
	app.ui._close_all()
	app.story_controller.execute(app.session.pending_story_request("QST_GRASS_020"))
	check(await wait_phase(app,"battle"),"Recreate real battlefield from frozen teams")
	check(app.battle.elapsed>=elapsed and app.session.data.magic==290,"Elapsed resumes; stake never charged twice")
	check(is_equal_approx(app.battle.actors[0].get_node(wounded_path).current_hp,saved_hp),"Actual damaged body HP resumes from checkpoint")
	app.request_retreat(); await process_frame
	check(app.phase=="settlement","Spectator abort opens settlement")
	app.finish_story_battle()
	var refund: Dictionary=app.session.pending_story_request("QST_GRASS_020")
	check(refund.plan.get("refund",false),"Abort has durable refund request")
	app.story_controller.execute(refund)
	check(app.session.data.magic==300 and app.session.story_event_view("QST_GRASS_020").rounds==0,"Actual host refunds stake and retains first round")
	app.ui._close_all()
	preload("res://Tests/Integration/ApplicationFixtures.gd").add_human(app.session)
	opened=app.open_story_event("QST_GRASS_008","giant")
	chosen=app.session.story_event_action("QST_GRASS_008","battle",opened.event.conversation)
	app.story_controller.execute(chosen.request)
	check(await wait_phase(app,"deployment"),"Player battle stops at manual deployment")
	check(app.save_session() and app.return_to_main_menu(),"Save manual deployment without starting combat")
	await process_frame
	app.enter_world(); await wait_phase(app,"world"); app.ui._close_all()
	app.story_controller.execute(app.session.pending_story_request("QST_GRASS_008"))
	check(await wait_phase(app,"deployment"),"Resume preserves deployment phase")
	check(not app.battle.ready_for_combat,"Resume never starts player combat without confirmation")
	app.queue_free(); await process_frame
	print("STORY_BATTLE_RECOVERY_","FAILED" if failed else "PASSED"," checks=",checks)
	quit(1 if failed else 0)
