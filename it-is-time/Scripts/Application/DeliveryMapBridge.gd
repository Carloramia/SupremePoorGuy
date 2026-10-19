extends "res://Modules/FrontierDelivery/Scripts/Map/FrontierMapView.gd"
const L10N = preload("res://Scripts/Localization/GameText.gd")

var application: Node
var active_location_id := ""
var _last_saved := {}
var _save_elapsed := 0.0
var _map_diagnostic_logging := false
var _last_travel_feedback := ""
var _travel_pending := false
var _travel_target := Vector2.ZERO
var _destruction_serial := 0
var _breaking_obstacle := ""

func _ready() -> void:
	battle_preview_enabled = false
	runtime = Runtime.new(application.session.delivery_snapshot())
	runtime.diagnostic_event.connect(_map_diagnostic)
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	set_map_diagnostic_logging(console!=null and console.is_map_tracking_enabled())
	sync_party()
	distance_travelled.connect(application.session.advance_world_travel)
	super._ready()
	_last_saved = runtime.snapshot()
	interaction_requested.connect(_arrived)
	feedback.connect(func(message):
		_last_travel_feedback = message
		L10N.bind(application.ui.status,&"text",func(): return L10N.text(message))
		_map_diagnostic("map_feedback",{"reason":message}))
	progress_changed.connect(func():
		if _travel_pending and path.is_empty():
			_travel_pending = false
			_map_diagnostic("travel_completed",{"target":[_travel_target.x,_travel_target.y],"remaining_distance":runtime.player().distance_to(_travel_target),"location_id":pending_interaction})
		save_progress())
	location_hovered.connect(_hovered)
	_map_diagnostic("map_loaded",{"pending_setup":runtime.data.pending_battle_setup,"active_battle":runtime.data.active_battle.get("request_id",""),"discovered_count":runtime.data.discovered.size(),"destroyed_count":runtime.data.destroyed.size(),"cleared_count":runtime.data.cleared.size()})

func set_map_diagnostic_logging(value: bool) -> void:
	_map_diagnostic_logging = value
	runtime.diagnostic_logging = value

func _map_diagnostic(event: String, detail: Dictionary = {}) -> void:
	if Catalog.is_hex(): detail=detail.merged({"map_version":Catalog.version})
	if _map_diagnostic_logging: application.trace_map_event(event,detail)

func _gui_input(event: InputEvent) -> void:
	if _map_diagnostic_logging and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var point := screen_to_world(event.position)
		var object := pick(point)
		_map_diagnostic("map_click",{"screen":[event.position.x,event.position.y],"world":[point.x,point.y],"location_id":object.get("id",""),"object_type":object.get("type","ground"),"input_enabled":input_enabled,"busy":runtime.busy})
	super._gui_input(event)

func request_location(id: String) -> bool:
	_map_diagnostic("interaction_requested",{"location_id":id,"kind":"location"})
	_last_travel_feedback = ""
	var accepted := super.request_location(id)
	if not accepted: _map_diagnostic("interaction_rejected",{"location_id":id,"reason":_last_travel_feedback if not _last_travel_feedback.is_empty() else "无法规划抵达路线。"})
	return accepted

func request_obstacle(id: String) -> bool:
	_map_diagnostic("interaction_requested",{"location_id":id,"kind":"obstacle"})
	_last_travel_feedback = ""
	var accepted := super.request_obstacle(id)
	if not accepted: _map_diagnostic("interaction_rejected",{"location_id":id,"reason":_last_travel_feedback if not _last_travel_feedback.is_empty() else "无法靠近路障。"})
	return accepted

func request_move(point: Vector2, interaction_id: String = "") -> bool:
	_last_travel_feedback = ""
	var accepted := super.request_move(point,interaction_id)
	if accepted:
		_travel_pending = true
		_travel_target = point
	_map_diagnostic("travel_started" if accepted else "travel_rejected",{"location_id":interaction_id,"target":[point.x,point.y],"path_points":path.size(),"reason":_last_travel_feedback if not _last_travel_feedback.is_empty() else "" if accepted else "导航网格没有可用路线。"})
	return accepted

func stop_moving() -> void:
	if not path.is_empty(): _map_diagnostic("travel_stopped",{"location_id":pending_interaction,"remaining_path_points":path.size()})
	_travel_pending = false
	super.stop_moving()

func _process(delta: float) -> void:
	super._process(delta)
	if not path.is_empty() and input_enabled:
		_save_elapsed += delta
		if _save_elapsed>=1.0: save_progress()

func sync_party() -> void:
	runtime.party_count = application.session.monsters().size()

func save_progress(action: String = "") -> bool:
	_save_elapsed = 0.0
	if not action.is_empty(): application.session.spend_world_action(action)
	if application.session.save_delivery_world(runtime.snapshot()):
		_last_saved = runtime.snapshot()
		return true
	_map_diagnostic("map_save_failed",{"reason":application.session.last_error})
	runtime.restore_snapshot(_last_saved)
	application.session.restore_saved_world_time()
	stop_moving()
	reset_runtime(runtime)
	application.ui._notice(func(): return L10N.text(application.session.last_error))
	return false

func set_enabled(value: bool) -> void:
	var was_enabled := input_enabled
	input_enabled = value
	# Commit the last partial second before a menu starts its own save transaction.
	if was_enabled and not value and runtime.snapshot() != _last_saved: save_progress()
	world_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	if not value:
		if not _breaking_obstacle.is_empty():
			_destruction_serial+=1
			runtime.busy=false
			_map_diagnostic("obstacle_break_cancelled",{"location_id":_breaking_obstacle})
			_breaking_obstacle=""
			feedback.emit("石障破坏已取消。")
		dragging = false
		application.ui.view.hide_location_hint()

func location_name() -> String:
	return str(Catalog.location(active_location_id).get("name","边境旅途"))

func _hovered(id: String, point: Vector2) -> void:
	var ui = application.ui
	ui.view.hide_location_hint()
	var object := Catalog.location(id)
	if object.is_empty() or object.type!="camp" or not input_enabled: return
	var card: Control = ui.view.get_node("LocationHint")
	L10N.bind(card.get_node("%Title"),&"text",func(): return L10N.text(L10N.text(object.name)))
	L10N.bind(card.get_node("%Summary"),&"text",func(): return L10N.text(L10N.text("ui.c8827e970138") % application.session.occupied_slots()))
	card.show()
	card.reset_size()
	card.position = (point+Vector2(24,0)).clamp(Vector2.ZERO,(size-card.size).max(Vector2.ZERO))

func _arrived(id: String, kind: String) -> void:
	_map_diagnostic("interaction_arrived",{"location_id":id,"kind":kind})
	if application.phase!="world":
		_map_diagnostic("interaction_rejected",{"location_id":id,"reason":"当前不在地图探索阶段。"})
		return
	stop_moving()
	sync_party()
	active_location_id = id
	application.ui.location = id
	var object := Catalog.location(id)
	if object.is_empty(): _map_diagnostic("interaction_rejected",{"location_id":id,"reason":"地点不存在。"}); return
	if kind=="obstacle":
		if runtime.hex!=null:
			await _destroy_hex_obstacle(object)
			return
		var before: Dictionary = runtime.snapshot()
		if not runtime.destroy_obstacle(id):
			var reason: String = runtime.interaction_error(object)
			_map_diagnostic("interaction_rejected",{"location_id":id,"reason":reason if not reason.is_empty() else "路障不可破坏或超出有效范围。","owned_count":runtime.party_count})
			application.ui._notice("ui.cb9081b24ad0")
			return
		if not save_progress("clear_obstacle"): runtime.restore_snapshot(before)
		else: _map_diagnostic("obstacle_destroyed",{"location_id":id})
		_refresh_objects()
		return
	if kind=="encounter":
		var error := roster_error(id,kind)
		if not error.is_empty(): _map_diagnostic("battle_rejected",{"location_id":id,"kind":kind,"reason":error}); application.ui._notice(func(): return L10N.text(error)); return
		if application.session.monsters("team").is_empty():
			runtime.data.pending_battle_setup = {"location_id":id,"kind":kind}
			if save_progress():
				_map_diagnostic("party_setup_required",{"location_id":id,"kind":kind,"reason":"出战队列为空。"})
				open_setup()
		else: begin_battle(id,kind)
		return
	if kind=="clear":
		open_location(object)
		return
	var error: String = runtime.interaction_error(object)
	if not error.is_empty(): _map_diagnostic("interaction_rejected",{"location_id":id,"reason":error}); application.ui._notice(func(): return L10N.text(error)); return
	if id not in runtime.data.visited: runtime.data.visited.append(id)
	if not save_progress("visit"): return
	if object.get("location_id","")=="summoning_hut":
		_map_diagnostic("event_routed",{"location_id":id,"event_id":"summon","source":"summoning_hut"})
		application.ui._open_ritual()
	else:
		_map_diagnostic("event_unavailable",{"location_id":id,"reason":"此地点暂无已接入的事件。"})
		application.ui._modal(str(object.name),func(body):
			var pending: Array=[]
			if Catalog.is_hex():
				for event: Dictionary in Catalog.world().events:
					if event.id==object.get("event_id","") or object.get("event_links",[]).any(func(link): return link.get("event_id")==event.id): pending.append(event)
			var message := "此地点的事件尚未配置执行流程，暂不开放。" if Catalog.is_hex() else "ui.a7b6d7d13745"
			var page: Control = application.ui._text_screen(body,message)
			for event: Dictionary in pending:
				var button: Button=application.ui._btn(page.get_node("%Commands"),str(event.name)+" · 待接入",func(): pass)
				button.disabled=true
				button.tooltip_text=str(event.id)+"：执行图、条件和奖励尚未绑定。"
			application.ui._btn(page.get_node("%Commands"),"ui.a56e8056bd25",func(): application.ui._close_modal()))

func _destroy_hex_obstacle(object: Dictionary) -> void:
	if runtime.busy or object.id in runtime.data.destroyed: return
	runtime.hex.sync(runtime.data,runtime.party_count)
	if runtime.hex.axial(runtime.player()) not in runtime.hex.obstacle_neighbors(object):
		feedback.emit("需要先抵达石障相邻的可通行格。")
		return
	if not runtime.condition(str(object.get("condition_ref",""))):
		feedback.emit("需要持有妖兽才能破坏石障。")
		return
	_destruction_serial+=1
	_breaking_obstacle=str(object.id)
	var serial := _destruction_serial
	var distance := sqrt(3.0)*float(Catalog.world().hex_grid.cell_width)*0.5*float(object.destruction.get("walk_steps",3))
	var seconds := distance/float(Catalog.world().travel_animation_speed)
	runtime.busy=true
	feedback.emit("正在破坏石障…")
	_map_diagnostic("obstacle_break_started",{"location_id":object.id,"seconds":seconds,"travel_distance_cost":distance})
	await get_tree().create_timer(seconds,false).timeout
	if serial!=_destruction_serial: return
	runtime.busy=false
	_breaking_obstacle=""
	if application.phase!="world" or not input_enabled:
		_map_diagnostic("obstacle_break_cancelled",{"location_id":object.id})
		return
	var before: Dictionary=runtime.snapshot()
	sync_party()
	if not runtime.destroy_obstacle(object.id): return
	application.session.advance_world_travel(distance)
	if not save_progress(): runtime.restore_snapshot(before)
	else: _map_diagnostic("obstacle_break_committed",{"location_id":object.id,"game_minutes":distance/float(application.session.data.world_time.travel_speed)*60.0})
	_refresh_objects()

func roster_error(id: String, kind: String) -> String:
	var object := Catalog.location(id)
	var config: Dictionary = object.get("encounter",{}) if kind=="encounter" else object
	var settings: DeliveryBattleSettings = application.get_delivery_battle_settings()
	var roster_id := str(config.get("enemy_config_id",object.get("enemy_config_id","")))
	var error := settings.availability_error(roster_id)
	return error if not error.is_empty() else capacity_status(id,kind).error

func capacity_status(_id: String, _kind: String) -> Dictionary:
	return application.session.initial_party_capacity()

func open_location(object: Dictionary) -> void:
	if runtime.interaction_error(object).is_empty() and not application.session.record_task_arrival(str(runtime.data.map_id),str(object.id)):
		application.ui._notice(application.session.last_error)
	_map_diagnostic("location_panel_opened",{"location_id":object.id,"roster_error":roster_error(object.id,"clear"),"can_enter_battle":not application.session.monsters("team").is_empty() and roster_error(object.id,"clear").is_empty()})
	application.ui._modal(str(object.name),func(body):
		var message := "ui.aaef0121bd42"
		if Catalog.is_hex():
			message="敌方数量：%d\n%s" % [int(object.get("enemy_count",0)),roster_error(object.id,"clear")]
		message = L10N.text(message)+"\n"+application.battle_capacity_settings.summary(capacity_status(object.id,"clear"))
		var page: Control = application.ui._text_screen(body,message)
		var button: Button = application.ui._btn(page.get_node("%Commands"),"ui.e62745dce172",func(): begin_battle(object.id,"clear"))
		button.name = "EnterBattle"
		var error := roster_error(object.id,"clear")
		button.disabled = application.session.monsters("team").is_empty() or not error.is_empty()
		L10N.bind(button,&"tooltip_text",func(): return L10N.text(error if not error.is_empty() else L10N.text("ui.d16f235099df") if button.disabled else L10N.text("ui.b368f63f4b31")))
		application.ui._btn(page.get_node("%Commands"),"ui.a56e8056bd25",func(): application.ui._close_modal()),"delivery_location")

func open_setup() -> void:
	application.ui._warehouse("warehouse")

func confirm_setup() -> void:
	var setup: Dictionary = runtime.data.pending_battle_setup
	if not setup.is_empty(): begin_battle(setup.location_id,setup.kind)

func cancel_setup() -> bool:
	if runtime.data.pending_battle_setup.is_empty(): return true
	var before: Dictionary = runtime.snapshot()
	runtime.data.pending_battle_setup = {}
	if save_progress(): _map_diagnostic("party_setup_cancelled",before.pending_battle_setup); return true
	runtime.restore_snapshot(before)
	return false

func begin_battle(id: String, kind: String) -> bool:
	_map_diagnostic("battle_requested",{"location_id":id,"kind":kind})
	if application.phase!="world" or application.session.monsters("team").is_empty():
		_map_diagnostic("battle_rejected",{"location_id":id,"kind":kind,"reason":"当前阶段不能开战或出战队列为空。"})
		return false
	var error := roster_error(id,kind)
	if not error.is_empty(): _map_diagnostic("battle_rejected",{"location_id":id,"kind":kind,"reason":error}); application.ui._notice(func(): return L10N.text(error)); return false
	var before: Dictionary = runtime.snapshot()
	runtime.data.pending_battle_setup = {}
	var ids: Array = application.session.monsters("team").map(func(unit):return unit.id)
	var request: Dictionary = runtime.begin_battle(id,kind,ids)
	if request.is_empty():
		runtime.restore_snapshot(before)
		var reason: String = runtime.interaction_error(Catalog.location(id))
		_map_diagnostic("battle_rejected",{"location_id":id,"kind":kind,"reason":reason if not reason.is_empty() else "运行时拒绝：检查入口路障和战场配置。"})
		application.ui._notice("ui.afe977112fa3")
		return false
	if not application.session.save_delivery_world(runtime.snapshot(),request):
		runtime.restore_snapshot(before)
		runtime.busy = false
		_map_diagnostic("battle_request_save_failed",{"location_id":id,"reason":application.session.last_error})
		application.ui._notice(func(): return L10N.text(application.session.last_error))
		return false
	_last_saved = runtime.snapshot()
	_map_diagnostic("battle_request_committed",request)
	application._delivery_battle_requested(request)
	return true

func cancel_battle() -> bool:
	var session = application.session
	var before: Dictionary = session.data.duplicate(true)
	var snapshot: Dictionary = runtime.snapshot()
	runtime.cancel_battle()
	session.data.battle = {}
	if session.save_delivery_world(runtime.snapshot()):
		_last_saved = runtime.snapshot()
		_map_diagnostic("battle_cancelled",{"request_id":snapshot.active_battle.get("request_id",""),"location_id":snapshot.active_battle.get("location_id",active_location_id)})
		return true
	session.data = before
	runtime.restore_snapshot(snapshot)
	runtime.busy = true
	_map_diagnostic("battle_cancel_save_failed",{"reason":session.last_error})
	return false

func commit_result(result: Dictionary) -> bool:
	var session = application.session
	if session.data.battle_results.has(result.battle_id): _map_diagnostic("battle_result_duplicate",{"battle_id":result.battle_id}); return true
	var before: Dictionary = runtime.snapshot()
	var mapped := result.duplicate(true)
	mapped.request_id = result.battle_id
	if not runtime.complete_battle(mapped): _map_diagnostic("battle_result_rejected",{"battle_id":result.battle_id}); return false
	if not session.commit_battle(result,runtime.snapshot()):
		runtime.restore_snapshot(before)
		_map_diagnostic("battle_result_save_failed",{"battle_id":result.battle_id,"reason":session.last_error})
		return false
	_last_saved = runtime.snapshot()
	_map_diagnostic("battle_result_committed",{"battle_id":result.battle_id,"outcome":result.outcome,"reward":result.reward,"cleared":runtime.data.cleared.duplicate()})
	return true

func returned() -> void:
	runtime.cancel_battle()
	_last_saved = runtime.snapshot()
	show()
	_refresh_objects()
	_layout()
	_map_diagnostic("map_returned")
