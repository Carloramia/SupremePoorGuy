extends Node

const SESSION = preload("res://Scripts/Application/GameSession.gd")
const UI = preload("res://Scripts/Application/GameUIController.gd")
const VIEW = preload("res://Scripts/Application/GameWorldView.gd")
const WORLD_SAVE = preload("res://Scripts/Application/WorldMapSessionSave.gd")
const BATTLE = preload("res://Scripts/Application/BattleHost.gd")
@export var save_path := "user://saves/slot_01.json"
@export var display_settings_path := "user://settings/display.cfg"
@export var world_scene: PackedScene = preload("res://Modules/Frontier/world_map/demo/WorldMapDemo.tscn")
@export var integration_logging := false
@export var battle_definitions: Dictionary = {}
@export var default_battle_definition: SceneDefinition
@export var monster_config_definitions: Dictionary = {"demo_guard":"human","human":"human","wolf":"wolf","snake":"snake"}
var session := SESSION.new()
var ui: Control
var world_map: WorldMapController
var battle: Node3D
var scenario: ScenarioController
var phase := "main"
var map_container: SubViewportContainer
var map_viewport: SubViewport
var battle_container: SubViewportContainer
var battle_viewport: SubViewport
var _pause_reasons := {}
var _owned_pause := false
var _previous_pause := false
var _last_blocked := false
var _pending_result := {}
var _transition: Tween
var _previous_minimum: Vector2i
var _previous_auto_quit := true
var _last_ui_route := ""
var _load_failed := false
var free_mouse_enabled := false
var display_error := ""
const DISPLAY_RESOLUTIONS := [Vector2i(1120,680),Vector2i(1280,720),Vector2i(1366,768),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160)]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"application_host")
	_previous_minimum = get_window().min_size
	get_window().min_size = _previous_minimum.max(Vector2i(1120,680))
	get_window().content_scale_size = get_window().size.max(get_window().min_size)
	_load_display_settings()
	_previous_auto_quit = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false
	get_window().close_requested.connect(_window_close_requested)
	session.save_path = save_path
	session.integration_logging = integration_logging
	if session.has_save() and not session.load_save(): _load_failed = true; push_warning(session.last_error)
	var layer := CanvasLayer.new()
	layer.name = "GameUI"
	layer.layer = 10
	ui = preload("res://Modules/PaperUI/Scenes/GameDemo.tscn").instantiate()
	ui.set_script(UI)
	ui.state = session
	ui.application = self
	ui.get_node("AppShell/Layout/MainContent/Center/WorldView").set_script(VIEW)
	add_child(layer)
	layer.add_child(ui)
	if _load_failed: ui.main_menu.get_node("%Continue").disabled = true
	map_container = _content_view("WorldMapView",false)
	map_viewport = map_container.get_child(0)
	battle_container = _content_view("ScenarioView",true)
	battle_viewport = battle_container.get_child(0)
	session.changed.connect(_session_changed)
	refresh_input_gate()

func _input(event: InputEvent) -> void:
	if phase!="battle" or event.is_echo() or not is_instance_valid(battle): return
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	if ui.overlay.visible or ui.route!="battle" or (console!=null and console.is_console_open()): return
	if event.is_action_pressed(&"QPressed"):
		free_mouse_enabled = not free_mouse_enabled
		refresh_input_gate()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"Space"):
		set_pause_reason(&"manual",not is_battle_manually_paused())
		refresh_input_gate()
		get_viewport().set_input_as_handled()

func is_battle_manually_paused() -> bool:
	return _pause_reasons.has(&"manual")

func get_display_settings() -> Dictionary:
	var window := get_window()
	var resolution := window.content_scale_size if window.content_scale_size!=Vector2i.ZERO else window.size
	return {"resolution":resolution,"fullscreen":window.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN]}

func _valid_display_resolution(resolution: Vector2i) -> bool:
	return resolution.x>=1120 and resolution.y>=680 and resolution.x<=7680 and resolution.y<=4320

func apply_display_settings(resolution: Vector2i, fullscreen: bool) -> bool:
	display_error = ""
	if not _valid_display_resolution(resolution): display_error = "分辨率超出支持范围。"; return false
	var usable := DisplayServer.screen_get_usable_rect(get_window().current_screen)
	if not fullscreen and usable.has_area() and (resolution.x>usable.size.x or resolution.y>usable.size.y):
		display_error = "当前屏幕无法容纳该窗口尺寸，请选择较小分辨率或启用全屏。"
		return false
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(display_settings_path.get_base_dir()))
	if error!=OK: display_error = "显示设置保存失败："+error_string(error); return false
	var config := ConfigFile.new()
	config.set_value("display","resolution",resolution)
	config.set_value("display","fullscreen",fullscreen)
	error = config.save(display_settings_path)
	if error!=OK: display_error = "显示设置保存失败："+error_string(error); return false
	_apply_display_settings(resolution,fullscreen)
	return true

func _apply_display_settings(resolution: Vector2i, fullscreen: bool) -> void:
	var window := get_window()
	# Keep a real render resolution even when the fullscreen window uses the desktop size.
	window.content_scale_size = resolution
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	if not fullscreen:
		window.size = resolution
		var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
		if usable.has_area(): window.position = usable.position+(usable.size-resolution)/2

func _load_display_settings() -> void:
	var config := ConfigFile.new()
	if config.load(display_settings_path)!=OK: return
	var resolution: Variant = config.get_value("display","resolution")
	var fullscreen: Variant = config.get_value("display","fullscreen",false)
	if not resolution is Vector2i or not fullscreen is bool or not _valid_display_resolution(resolution): return
	var usable := DisplayServer.screen_get_usable_rect(get_window().current_screen)
	if not fullscreen and usable.has_area():
		resolution = Vector2i(mini(resolution.x,usable.size.x),mini(resolution.y,usable.size.y))
		if not _valid_display_resolution(resolution): return
	_apply_display_settings(resolution,fullscreen)

func _content_view(title: String, spatial: bool) -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.name = title
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	var viewport := SubViewport.new()
	viewport.name = title+"Viewport"
	viewport.size = Vector2i(500,350)
	viewport.own_world_3d = spatial
	viewport.world_2d = World2D.new()
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(viewport)
	ui.view.add_child(container)
	ui.view.move_child(container,0)
	container.hide()
	return container

func _session_changed() -> void:
	if not is_instance_valid(ui) or not ui.is_node_ready(): return
	ui._refresh_sidebar()
	ui._update_header()

func location_name() -> String:
	if is_instance_valid(world_map) and world_map.interaction != null and world_map.interaction.active_location != null:
		return world_map.interaction.active_location.definition.display_name
	return "边境旅途"

func ui_route_changed(next: String) -> void:
	if next != _last_ui_route:
		_last_ui_route = next
		session.trace("route",{"route":next,"phase":phase})
	if next == "world" and phase == "main": enter_world.call_deferred()
	if is_instance_valid(map_container):
		map_container.visible = next == "world" and phase in ["world","loading_world","main"]
		battle_container.visible = next == "battle" and phase in ["battle","loading_battle","scenario"]
	refresh_input_gate()

func start_new_game() -> void:
	if phase != "main": return
	var previous := session.data.duplicate(true)
	session.reset()
	if not session.save(): session.data = previous; ui._notice(session.last_error); return
	ui.rules.import_layout(session.data.layout)
	ui._close_all()
	ui._show("world")

func enter_world() -> void:
	if phase != "main": return
	phase = "loading_world"
	ui.status.text = "正在准备地图导航…"
	world_map = world_scene.instantiate() as WorldMapController
	if world_map == null: phase = "main"; ui._notice("地图场景无效。"); return
	var content_error := _world_content_error()
	if not content_error.is_empty():
		world_map.free(); world_map = null; phase = "main"
		ui._show("main")
		ui._notice(content_error)
		return
	for title: String in ["FakeBattleAdapter","ScenarioOverlay"]:
		var demo := world_map.get_node_or_null(title)
		if demo != null: world_map.remove_child(demo); demo.free()
	world_map.auto_load = false
	var service := WORLD_SAVE.new()
	service.session = session
	service.map_id = str(world_map.definition.map_id)
	service.failed.connect(ui._notice)
	world_map.save_service = service
	world_map.battle_requested.connect(_battle_requested)
	world_map.location_interaction_started.connect(_interaction_started)
	world_map.location_interaction_completed.connect(_interaction_completed)
	map_viewport.add_child(world_map)
	if not world_map.is_initialized: await world_map.initialized
	# The paper shell replaces only the duplicate debug HUD, not map interactions.
	world_map.ui.get_child(0).get_child(0).hide()
	world_map.ui.get_child(0).get_child(1).hide()
	world_map.interaction.scenario_requested.connect(_scenario_requested)
	phase = "world"
	var snapshot: Dictionary = session.data.worlds.get(str(world_map.definition.map_id),{})
	if not snapshot.is_empty() and not world_map.import_session(snapshot,true):
		ui._notice("地图存档校验失败；未覆盖原存档。")
	map_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	map_container.show()
	ui._show("world")
	if session.data.battle.get("phase","") == "settlement":
		_pending_result = session.data.battle.result.duplicate(true)
		phase = "settlement"
		_show_settlement()
	elif not session.data.pending.is_empty(): ui._resume_pending()
	refresh_input_gate()

func _world_content_error() -> String:
	var editor: Dictionary = world_map.definition.editor_data
	for object: Dictionary in editor.get("map",{}).get("objects",[]):
		if object.type not in ["cloth","road","indestructible","town","camp","house","reveal_area","decoration","tree","grass"]:
			return "该地图包含尚未接入的探索对象规则："+str(object.id)
		if not str(object.get("discovery",{}).get("condition_ref","")).is_empty(): return "尚未接入的发现条件："+str(object.id)
		for field: String in ["condition_ref","event_id","post_event_id"]:
			if not str(object.get(field,"")).is_empty(): return "该地图包含尚未接入的条件/事件引用："+str(object[field])
	return ""

func _interaction_started(id: StringName) -> void:
	if not is_instance_valid(ui) or phase not in ["world","loading_world"]: return
	var location: WorldMapLocation = world_map.get_location(id)
	world_map.interaction.panel.hide()
	ui.location = str(id)
	ui._modal(location.definition.display_name,func(body):
		var page: Control = ui._text_screen(body,location.definition.short_description)
		var commands: Node = page.get_node("%Commands")
		match str(location.definition.type_id):
			"battle","monster":
				var button: Button = ui._btn(commands,"进入战斗",func(): world_map.interaction.request_battle())
				button.name = "EnterBattle"
				button.disabled = session.monsters("team").is_empty()
				button.tooltip_text = "请先召唤妖兽并加入出战队列。" if button.disabled else "使用当前出战队列进入战斗。"
			"settlement":
				if location.definition.scenario_scene != null:
					ui._btn(commands,"进入场景",func(): world_map.interaction.request_scenario())
				ui._btn(commands,"结束访问",func(): _resolve_location({"success":true,"complete_location":false,"action":"visit"}))
			"event":
				ui._btn(commands,"研读手记 · 魔力 +20",func(): _resolve_location({"success":true,"complete_location":true,"action":"study","reward":20}))
			"resource":
				ui._btn(commands,"收集 · 魔力 +10",func(): _resolve_location({"success":true,"complete_location":true,"action":"collect","reward":10}))
			_:
				ui._notice("该地点类型尚未接入。")
		ui._btn(commands,"返回地图",func(): _resolve_location({"success":false,"complete_location":false,"action":"leave"})),"event")

func _resolve_location(result: Dictionary) -> void:
	if world_map.interaction.active_location == null: return
	var before := session.data.duplicate(true)
	var id: StringName = world_map.interaction.active_location.location_id
	var reward_id := "location_"+str(world_map.definition.map_id)+"_"+str(id)
	if result.get("success",false) and result.get("reward",0)>0 and reward_id not in session.data.completed:
		session.data.magic += int(result.reward)
		session.data.completed.append(reward_id)
	if not world_map.resolve_location_interaction(id,result):
		session.data = before
		ui._notice(session.last_error)
		return
	ui._close_all()
	ui._show("world")
	refresh_input_gate()

func _interaction_completed(_id: StringName, _result: Dictionary) -> void:
	refresh_input_gate.call_deferred()

func open_event(_id: String) -> void:
	ui._notice("请先前往大地图上的事件地点。")

func _battle_requested(_request: Dictionary) -> void:
	if phase != "world" or is_instance_valid(battle): return
	if session.monsters("team").is_empty(): ui._notice("出战队伍为空。"); return
	phase = "loading_battle"
	ui._close_all()
	world_map.set_world_map_paused(true)
	map_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	map_container.hide()
	battle = BATTLE.new()
	battle.name = "BattleHost"
	battle.application = self
	battle.definition = default_battle_definition
	var editor: Dictionary = _request.get("encounter_data",{}).get("editor_object",{})
	var map_id: String = editor.get("battle_map_id","")
	if not map_id.is_empty():
		if not battle_definitions.get(map_id) is SceneDefinition:
			battle.free(); battle = null; phase = "world"
			_resolve_location({"success":false,"complete_location":false,"action":"load_failed"})
			ui._notice("战场 %s 尚未在 GameRoot 的 Battle Definitions 中指定。" % map_id)
			return
		battle.definition = battle_definitions[map_id]
	battle.monster_config_definitions = monster_config_definitions.duplicate()
	battle.finished.connect(_battle_finished)
	battle_viewport.add_child(battle)
	ui._show("battle")
	battle_container.show()
	battle_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	session.trace("battle_load",session.data.battle)
	var records: Array = []
	for id: String in session.data.battle.get("party_ids",[]): records.append(session.monster_by_id(id))
	if not await battle.deploy(records,str(session.data.battle.get("battle_id",""))):
		var deployment_error: String = battle.last_error
		_cleanup_battle()
		phase = "world"
		_resolve_location({"success":false,"complete_location":false,"action":"load_failed"})
		ui._notice("战场部署失败；原地图和队伍已保留。"+deployment_error)
		return
	phase = "battle"
	refresh_input_gate()
	session.trace("battle_start",{"battle_id":battle.battle_id})

func _battle_finished(result: Dictionary) -> void:
	if phase != "battle": return
	_pending_result = result.duplicate(true)
	_finalize_battle()

func _finalize_battle() -> void:
	phase = "settlement"
	free_mouse_enabled = false
	_pause_reasons.erase(&"manual")
	refresh_input_gate()
	session.pending_result = _pending_result
	var location_id := StringName(session.data.battle.get("location_id",""))
	var success := world_map.resolve_location_interaction(location_id,{"success":_pending_result.outcome=="victory","result_type":_pending_result.outcome,"complete_location":_pending_result.outcome=="victory"})
	session.pending_result = {}
	if not success:
		ui._modal("结算保存失败",func(body):
			var page: Control = ui._text_screen(body,session.last_error+"\n战斗已停止，奖励尚未提交。")
			ui._btn(page.get_node("%Commands"),"重试保存",_finalize_battle))
		return
	_show_settlement()

func _show_settlement() -> void:
	ui._close_all()
	ui._modal("战斗结算",func(body):
		var page: Control = ui._text_screen(body,"结果：%s\n魔力奖励：%d\n部位战损已记录。本轮采用战后恢复，不永久删除库存生物。" % [_pending_result.outcome,int(_pending_result.reward)])
		ui._btn(page.get_node("%Commands"),"返回大地图",return_to_world))
	ui.close_button.disabled = true

func request_retreat() -> void:
	if phase == "battle" and is_instance_valid(battle): battle.finish("retreat")

func return_to_world() -> void:
	if phase != "settlement": return
	var before: Dictionary = session.data.battle.duplicate(true)
	session.data.battle = {}
	if not session.save(): session.data.battle = before; ui._notice(session.last_error); return
	phase = "returning"
	ui.close_button.disabled = false
	ui._close_all()
	_cleanup_battle()
	_pending_result = {}
	map_container.show()
	map_container.position.y = -ui.view.size.y
	map_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_transition = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_transition.tween_property(map_container,"position:y",0.0,0.5 if ui.animate_panels else 0.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await _transition.finished
	phase = "world"
	ui._show("world")
	map_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	refresh_input_gate()
	session.trace("map_restore")

func _cleanup_battle() -> void:
	free_mouse_enabled = false
	_pause_reasons.erase(&"manual")
	if is_instance_valid(battle):
		battle_viewport.remove_child(battle)
		battle.queue_free()
	battle = null
	battle_container.hide()
	battle_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _scenario_requested(_id: StringName, packed: PackedScene) -> void:
	if phase != "world" or scenario != null: return
	var instance := packed.instantiate()
	if not instance is ScenarioController: instance.free(); ui._notice("场景根节点必须是ScenarioController。"); return
	scenario = instance
	var demo_ui := scenario.get_node_or_null("DemoUI")
	if demo_ui != null: scenario.remove_child(demo_ui); demo_ui.free()
	phase = "scenario"
	ui._close_all()
	map_container.hide()
	map_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	battle_viewport.add_child(scenario)
	if not scenario.initialized:
		scenario.queue_free(); scenario = null; phase = "world"
		ui._show("world")
		map_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		ui._notice("场景控制器未完整配置。")
		return
	scenario.scenario_exit_requested.connect(_scenario_exit)
	ui._show("battle")
	battle_container.show()
	battle_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	ui._btn(ui.actions,"返回大地图",func(): scenario.request_scenario_exit(&"return_to_map"))
	ui.actions.show()

func _scenario_exit(_reason: StringName) -> void:
	if scenario == null: return
	if not world_map.resolve_location_interaction(world_map.interaction.active_location.location_id,{"success":true,"complete_location":false,"action":"scenario_exit"}): ui._notice(session.last_error); return
	battle_viewport.remove_child(scenario)
	scenario.queue_free()
	scenario = null
	battle_container.hide()
	battle_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	phase = "world"
	map_container.show()
	map_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	ui._show("world")
	refresh_input_gate()

func get_active_controller() -> Node:
	return null

func get_active_level() -> Node:
	return battle if is_instance_valid(battle) else scenario

func is_gameplay_blocked() -> bool:
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	return phase != "battle" or free_mouse_enabled or not _pause_reasons.is_empty() or (ui!=null and (ui.overlay.visible or ui.route=="eruption")) or (console!=null and console.is_console_open())

func allow_workshop() -> bool:
	return phase == "battle" and not is_gameplay_blocked()

func set_pause_reason(reason: StringName, active: bool) -> void:
	if _pause_reasons.has(reason) == active: return
	if active: _pause_reasons[reason] = true
	else: _pause_reasons.erase(reason)
	session.trace("pause",{"reason":reason,"active":active})
	_apply_pause()

func refresh_input_gate() -> void:
	if ui == null or not ui.is_node_ready() or ui.overlay == null: return
	var paper_blocked: bool = ui.overlay.visible or ui.route == "eruption"
	if phase in ["battle","settlement","returning"]: _pause_reasons[&"paper"] = paper_blocked or phase != "battle"
	else: _pause_reasons.erase(&"paper")
	if _pause_reasons.get(&"paper") == false: _pause_reasons.erase(&"paper")
	_apply_pause()
	var blocked := is_gameplay_blocked()
	if blocked != _last_blocked:
		_last_blocked = blocked
		if is_instance_valid(battle) and is_instance_valid(battle.camera):
			battle.camera.cancel_orbit()
			battle.camera.input_enabled = not blocked
	if world_map != null and world_map.is_initialized:
		world_map.set_world_map_paused(phase != "world" or paper_blocked or world_map.interaction.active_location != null)
	if scenario != null: scenario.set_camera_input_enabled(not paper_blocked)
	ui.update_battle_controls(phase=="battle",is_battle_manually_paused(),free_mouse_enabled)

func _apply_pause() -> void:
	var should_pause := not _pause_reasons.is_empty()
	if should_pause and not _owned_pause:
		_previous_pause = get_tree().paused
		_owned_pause = true
		get_tree().paused = true
	elif not should_pause and _owned_pause:
		get_tree().paused = _previous_pause
		_owned_pause = false

func save_session() -> bool:
	return world_map.save_world_map() if world_map != null and world_map.is_initialized else session.save()

func _window_close_requested() -> void:
	if save_session(): get_tree().quit()
	else: ui._notice(session.last_error)

func _exit_tree() -> void:
	if _owned_pause: get_tree().paused = _previous_pause
	get_tree().auto_accept_quit = _previous_auto_quit
	get_window().min_size = _previous_minimum
	if get_window().close_requested.is_connected(_window_close_requested): get_window().close_requested.disconnect(_window_close_requested)
