extends "res://Modules/PaperUI/Scripts/GameDemo.gd"
## Keep the paper presentation; the application owns all route and data changes.
var application: Node
var pause_hint: Label
var deployment_hint: Label
var start_battle_button: Button
var _main_menu_button: Button
var _portrait_renderer: Node
var visual_preset: Resource
var skin_binding: Node
var _task_page: Control
var _task_notifications: Array = []

func _request_creature_portrait(portrait: Control, monster: Dictionary) -> void:
	if not is_instance_valid(_portrait_renderer):
		_portrait_renderer = preload("res://Scripts/Application/CreaturePortraitRenderer.gd").new()
		_portrait_renderer.name = "CreaturePortraitRenderer"
		add_child(_portrait_renderer)
	_portrait_renderer.request(portrait,monster)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rules.import_layout(state.data.layout)
	_build()
	pause_hint = Label.new()
	pause_hint.name = "BattlePauseHint"
	pause_hint.text = "战斗已暂停 · 按 Space 继续"
	pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_hint.add_theme_font_size_override("font_size",26)
	pause_hint.add_theme_color_override("font_color",Color.WHITE)
	pause_hint.add_theme_color_override("font_outline_color",Color("29231d"))
	pause_hint.add_theme_constant_override("outline_size",8)
	view.add_child(pause_hint)
	pause_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	pause_hint.offset_top = 18
	pause_hint.offset_bottom = 60
	pause_hint.hide()
	deployment_hint = pause_hint.duplicate()
	deployment_hint.name = "DeploymentHint"
	deployment_hint.add_theme_font_size_override("font_size",19)
	view.add_child(deployment_hint)
	deployment_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	deployment_hint.offset_top = 14
	deployment_hint.offset_bottom = 78
	start_battle_button = _btn(view,"开始战斗",func(): application.start_battle())
	start_battle_button.name = "StartBattle"
	start_battle_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	start_battle_button.offset_left = -100
	start_battle_button.offset_right = 100
	start_battle_button.offset_top = -72
	start_battle_button.offset_bottom = -20
	start_battle_button.focus_mode = Control.FOCUS_NONE
	start_battle_button.hide()
	resized.connect(_resize_event)
	main_menu.get_node("%Continue").disabled = not state.has_save()
	_show("main")
	skin_binding = preload("res://Modules/PaperUI/TA/ShaderSkinBinding.gd").new()
	skin_binding.name = "ShaderSkinBinding"
	skin_binding.initial_preset = visual_preset
	add_child(skin_binding)

func set_visual_preset(preset: Resource) -> void:
	visual_preset = preset
	if not is_instance_valid(skin_binding): return
	if preset == null: skin_binding.restore()
	else: skin_binding.apply_preset(preset)

func update_battle_controls(in_battle: bool, manually_paused: bool, free_mouse: bool) -> void:
	if is_instance_valid(pause_hint): pause_hint.visible = in_battle and manually_paused
	if route=="battle" and in_battle and not overlay.visible:
		status.text = "战斗已暂停 · Space 继续；Q 切换鼠标" if manually_paused else ("自由鼠标 · Q 返回地形光标；Space 暂停战斗" if free_mouse else "Q 显示自由鼠标；Space 暂停战斗；双方由 AI 控制。")

func update_deployment_controls(deploying: bool, can_start: bool, error: String) -> void:
	var shown := deploying and route == "battle" and not overlay.visible
	start_battle_button.visible = shown
	start_battle_button.disabled = not can_start
	start_battle_button.tooltip_text = "请先在合法位置放下正在拖动的生物。" if not can_start else "结束部署并启用双方 AI。"
	deployment_hint.visible = shown
	deployment_hint.text = "部署阶段 · 蓝色边界内调整友军 · Q 切换鼠标"
	deployment_hint.text += "\n" + (error if not error.is_empty() else ("再次点击左键放置；放置后才可开始战斗。" if not can_start else "靠近友军后点击左键拾起，再次点击放置；按 Q 后点击开始战斗。"))
	if shown: status.text = "部署期间双方保持静止，位置调整仅在本场战斗生效。"

func _show(next: String) -> void:
	if next == "main":
		view.running = false
		if page_tween: page_tween.kill()
		if is_instance_valid(outgoing_page):
			outgoing_page.hide()
			outgoing_page.queue_free()
	route = next
	main_menu.visible = next == "main"
	base.visible = next != "main"
	_clear(actions)
	base.get_node("%Navigation").present_context(next == "battle",animate_panels)
	_refresh_sidebar()
	view.configure(next,location,state.monsters("team"))
	if next == "eruption":
		view.erupt()
		_btn(actions,"跳过召唤演出",func(): view.skip_eruption())
	status.text = {"main":"ItIsTime","world":"点击地点后前往，抵达后交互。","battle":"自由光标观察战斗，双方由 AI 控制；队伍变更在下一战生效。","eruption":"召唤结果已保存，演出不会再次生成。"}.get(next,"")
	actions.visible = actions.get_child_count()>0
	main_content.visible = not _has_page_root()
	status.visible = next != "main" and not _has_page_root()
	_update_header()
	if application != null: application.ui_route_changed(next)

func _update_header() -> void:
	if header == null: return
	var place: String = application.location_name() if application != null else "边境"
	var clock: Dictionary=state.data.get("story_events",{}).get("clock",{})
	var day: float=clock.day if clock.get("ready",false) else state.data.day
	header.text = "%s　|　第 %d 天　|　魔力 %d" % [place,int(day),state.data.magic]
	header.tooltip_text = "正式会话；地图、仓库与召唤共用同一个存档槽。"

func _update_motion_status() -> void:
	pass

func _start_new() -> void:
	application.start_new_game()

func _location_clicked(id: String, _kind: String) -> void:
	application.world_map.select_location(StringName(id))

func _navigation_requested(action: String) -> void:
	if action=="tasks" and not _tasks_available(): return
	if application.phase in ["loading_world","loading_battle","settlement","returning"]: return
	if action == "world" and application.phase == "scenario":
		application._scenario_exit(&"return_to_map")
		return
	if action == "world" and application.phase in ["deployment","battle"]:
		_confirm("撤退？","返回大地图，本次战斗不发放胜利奖励。",func(): application.request_retreat())
	else: super._navigation_requested(action)

func _open_ritual() -> void:
	if application.phase in ["world","battle"]:
		if curtain_busy:
			application.trace_map_event("event_rejected",{"event_id":"summon","reason":"界面正在转场。"})
		elif not state.data.pending.is_empty():
			application.trace_map_event("event_routed",{"event_id":"summon","handler":"resume_pending","pending_ids":state.data.pending.duplicate()})
		else: application.trace_map_event("event_opened",{"event_id":"summon","source":"ui"})
		super._open_ritual()
	else: application.trace_map_event("event_rejected",{"event_id":"summon","reason":"当前阶段不能打开召唤界面。"})

func _warehouse(filter: String = "warehouse") -> void:
	if application.phase in ["world","battle"]: super._warehouse(filter)

func _perform_summon() -> void:
	application.trace_map_event("event_requested",{"event_id":"summon","magic":state.data.magic})
	if not application.phase in ["world","battle"]:
		application.trace_map_event("event_rejected",{"event_id":"summon","reason":"当前阶段不能召唤。"})
		_notice("当前阶段不能召唤。")
		return
	var serial: int = state.data.serial
	super._perform_summon()
	application.trace_map_event("event_completed" if state.data.serial>serial else "event_rejected",{"event_id":"summon","serial":state.data.serial,"pending_ids":state.data.pending.duplicate(),"magic":state.data.magic,"reason":"" if state.data.serial>serial else state.last_error})

func _build_ritual(body: VBoxContainer) -> void:
	super._build_ritual(body)
	var species := PackedStringArray()
	for id: String in state.FACTORY.SUMMON_POOL: species.append(state.FACTORY.DEFINITIONS[id].name)
	var rain: bool=preload("res://Scripts/Events/HexMapProgress.gd").rain_active(state.data)
	ritual_page.get_node("%Context").text = "[b]当前位置[/b]\n%s\n\n[b]可召唤物种（等概率）[/b]\n%s\n\n[b]区域效果[/b]\n%s" % [application.location_name()," / ".join(species),"血雨：本次新召唤生命与部位耐久 +10%。" if rain else "当前无血雨加成。"]
	ritual_page.get_node("%Upgrade").text = "胜利后解锁下一圈"
	ritual_page.get_node("%Upgrade").tooltip_text = "累计胜利达到当前阶数后开放。"
	ritual_page.get_node("%Examples").tooltip_text = "示例只填入法阵，不赠送魔力；未接入能力会阻止召唤。"

func _refresh_ritual() -> void:
	super._refresh_ritual()
	var error: String = state.supported_layout(rules)
	if not error.is_empty():
		summon_button.disabled = true
		summon_button.tooltip_text = error

func _open_event(id: String) -> void:
	application.open_event(id)

func _monster_card(parent: Node, monster: Dictionary, result_card: bool) -> void:
	super._monster_card(parent,monster,result_card)
	var card := parent.get_child(parent.get_child_count()-1)
	_request_creature_portrait(card.get_node("%Portrait"),monster)
	var stats: Node = card.get_node("%Stats")
	for index: int in 4:
		stats.get_child(index).text = ["生命 %.0f" % monster.hp,"攻击 %.1f" % monster.attack,"护甲 %.1f" % monster.armor,"移速 %.1f" % monster.speed][index]

func _fill_detail(body: VBoxContainer, id: String) -> void:
	var monster: Dictionary = state.monster_by_id(id)
	var page := MonsterDetail.instantiate()
	body.add_child(page)
	page.get_node("%Portrait").form = monster.form
	page.get_node("%Portrait").tint = Color(monster.color)
	_request_creature_portrait(page.get_node("%Portrait"),monster)
	page.get_node("%Name").text = monster.name
	page.get_node("%Stats").text = "生命 %.0f　攻击参考 %.1f\n平均护甲 %.1f　目标移速 %.1f\n攻击冷却倍率 %.2f\n真实物理部位 %d 个" % [monster.hp,monster.attack,monster.armor,monster.speed,monster.get("interval_multiplier",1.0),monster.parts.size()]
	page.get_node("%Stats").tooltip_text = "生命为各部位上限之和；护甲为部位平均值。攻击参考为冲量10的挥击原始伤害，实际伤害仍由接触冲量、护甲和全局规则决定。冷却倍率缩放AI与动作自身冷却，不缩放物理动作时长。"
	var name_input: LineEdit = page.get_node("%NameInput")
	name_input.text = monster.name
	page.get_node("%Save").pressed.connect(func():
		if state.rename_monster(id,name_input.text): _render_modal()
		else: _notice(state.last_error if not state.last_error.is_empty() else "名称不能为空"))
	for trait_name: String in monster.traits:
		_btn(page.get_node("%Traits"),"【%s】" % trait_name,func(): _trait(trait_name))

func _trait(name_text: String) -> void:
	for rune: Dictionary in Rules.RUNES:
		if rune.name == name_text:
			_term(name_text,rune.effect+"\n"+rune.detail+"\n\n"+("已映射到真实部位属性或攻击冷却。" if rune.id in state.SUPPORTED_RUNES else "此效果尚未开放，召唤会在扣费前被阻止。"))
			return

func _book() -> void:
	_modal("符文辞典",func(body):
		var page := _text_screen(body,"首轮开放普通结构及数值符文；未接入的结构、特殊效果和奇物会在扣费前阻止召唤。")
		for rune: Dictionary in Rules.RUNES:
			_btn(page.get_node("%Commands"),rune.name+(" · 已接入" if rune.id in state.SUPPORTED_RUNES else " · 未开放"),func(): _trait(rune.name)))

func _help() -> void:
	_term("旅途指南","地图点击地点并沿路径抵达后交互。召唤结果可加入出战或存入仓库，队位上限6。\n战场默认使用自由地形光标，双方由AI控制。Q切换系统鼠标与地形光标，Space暂停/继续战斗；鼠标移动地形光标，右键拖拽旋转镜头，滚轮缩放。\nESC在所有阶段打开设置，再按一次返回原界面。设置中可选择分辨率、全屏和保存后返回主菜单。B工坊入口和Q轮盘仍禁用。法阵中Enter刻入、Backspace撤回；纸页可点击返回按钮关闭。\n存档同时保存仓库、召唤结果和地图；中途退出战斗会从初始部署重开。")

func _term(title: String, content: String) -> void:
	var descriptions := {"生命":"真实部位生命上限的总和；各部位独立受伤与断裂。","攻击":"冲量10时的挥击原始伤害参考。实际伤害由接触冲量、护甲与DamageService规则计算。","护甲":"真实部位护甲的平均值，命中时使用被击中部位自己的护甲。","移速":"移动预设中的目标速度，实际速度受物理结构与地面接触影响。"}
	super._term(title,descriptions.get(title,content))

func _task_action(action: String) -> void:
	if not _tasks_available() or modal_stack.is_empty() or modal_stack.back().get("kind")!="tasks": return
	if action.begins_with("story:") and is_instance_valid(application.hex_map):
		var id:=action.trim_prefix("story:")
		_close_all()
		var request: Dictionary=state.pending_story_request(id)
		if not request.is_empty(): application.story_controller.execute(request); return
		var site: String=preload("res://Scripts/Events/StoryObjectives.gd").new().target(state.data,id)
		if not site.is_empty(): application.hex_map.request_location(site)
		return
	var target: String = state.new_player_task_action(action)
	if target.is_empty(): return
	_close_all()
	if not modal_stack.is_empty(): return
	match target:
		"world": _show("world")
		"summon": _open_ritual()
		"party": _warehouse("team")

func _skip_battle() -> void:
	_notice("真实战斗不能跳过。")

func toggle_settings() -> void:
	if not modal_stack.is_empty() and modal_stack.back().get("kind","") == "settings": _close_modal(false)
	else: _settings()

func _settings() -> void:
	if not modal_stack.is_empty() and modal_stack.back().get("kind","") == "settings": return
	_modal("设置 / 保存 / 退出",func(body):
		var page := _text_screen(body,"ItIsTime · 正式会话")
		var commands: Node = page.get_node("%Commands")
		var current: Dictionary = application.get_display_settings()
		var choices: Array = application.DISPLAY_RESOLUTIONS.duplicate()
		if current.resolution not in choices: choices.append(current.resolution)
		var caption := Label.new()
		caption.text = "分辨率（窗口尺寸 / 全屏渲染尺寸）"
		commands.add_child(caption)
		var resolution := OptionButton.new()
		resolution.name = "Resolution"
		resolution.custom_minimum_size.y = 42
		for size: Vector2i in choices: resolution.add_item("%d × %d" % [size.x,size.y])
		resolution.select(choices.find(current.resolution))
		commands.add_child(resolution)
		var fullscreen := CheckButton.new()
		fullscreen.name = "Fullscreen"
		fullscreen.text = "全屏"
		fullscreen.button_pressed = current.fullscreen
		commands.add_child(fullscreen)
		var apply := _btn(commands,"应用显示设置",func():
			if application.apply_display_settings(choices[resolution.selected],fullscreen.button_pressed): _notice("显示设置已应用并保存。")
			else: _notice(application.display_error))
		apply.name = "ApplyDisplay"
		apply.tooltip_text = "全屏保持显示器桌面模式，画面按所选分辨率渲染。"
		_btn(commands,"保存游戏",func(): _notice("已保存" if application.save_session() else state.last_error))
		_btn(page.get_node("%Commands"),"动效：开启" if animate_panels else "动效：简化",func():
			animate_panels = not animate_panels
			board_motion.enabled = animate_panels
			_render_modal())
		_main_menu_button = _btn(commands,"返回主菜单",func(): application.return_to_main_menu())
		_main_menu_button.name = "ReturnToMainMenu"
		_main_menu_button.disabled = application.phase == "main" or application.returning_to_main_menu
		_main_menu_button.tooltip_text = "先保存进度；未结束的战斗在继续游戏时从部署阶段重开。"
		_btn(page.get_node("%Commands"),"退出游戏",func():
			if application.save_session(): get_tree().quit()
			else: _notice(state.last_error)),"settings")

func _resize_event() -> void:
	super._resize_event()
	if modal_stack.is_empty() or modal_stack.back().get("kind","")!="settings": return
	var margin: MarginContainer = overlay.get_node("BoardMotion/MotionRoot/Margin")
	var side := maxi(32,int(size.x*0.2))
	margin.add_theme_constant_override("margin_left",side)
	margin.add_theme_constant_override("margin_right",side)
	margin.add_theme_constant_override("margin_top",24)
	margin.add_theme_constant_override("margin_bottom",24)

func _render_modal() -> void:
	super._render_modal()
	_resize_event()
	if not modal_stack.is_empty() and modal_stack.back().get("kind","") != "settings": close_button.text = close_button.text.replace(" / Esc","")
	if application != null: close_button.disabled = (application.phase=="settlement" or _battle_cancel_needs_save()) and modal_stack.size()==1 and modal_stack.back().get("kind","") != "settings"
	if application != null: application.refresh_input_gate()

func _battle_cancel_needs_save() -> bool:
	return application!=null and application._delivery_cancel_save_pending

func _close_modal(store_results: bool = true) -> void:
	if not modal_stack.is_empty() and modal_stack.back().get("kind","") == "settings":
		super._close_modal(false)
		return
	if application != null and (application.phase=="settlement" or _battle_cancel_needs_save()) and modal_stack.size()<=1: return
	if application != null and application.phase=="world" and modal_stack.size()==1 and is_instance_valid(application.delivery_map):
		if not application.delivery_map.cancel_setup(): return
	if application != null and application.phase=="world" and modal_stack.size()==1 and application.world_map!=null and application.world_map.interaction.active_location!=null:
		application._resolve_location({"success":false,"complete_location":false,"action":"leave"})
		return
	super._close_modal(store_results)

func _close_all() -> void:
	if _battle_cancel_needs_save(): return
	if application!=null and application.phase=="world" and is_instance_valid(application.delivery_map):
		if not application.delivery_map.cancel_setup(): return
	super._close_all()

func _refresh_warehouse_filters(animate := true) -> void:
	super._refresh_warehouse_filters(animate)
	_append_battle_confirmation()

func _select_monster(id: String) -> void:
	super._select_monster(id)
	_append_battle_confirmation()

func _append_battle_confirmation() -> void:
	if application==null or not is_instance_valid(application.delivery_map) or not is_instance_valid(warehouse_page): return
	var setup: Dictionary = application.delivery_map.runtime.data.pending_battle_setup
	if setup.is_empty(): return
	var commands: Node = warehouse_page.get_node("%DetailCommands")
	if commands.get_node_or_null("ConfirmBattleSetup")!=null: return
	var error: String = application.delivery_map.roster_error(setup.location_id,setup.kind)
	var button := _btn(commands,"确认出战并进入战场",func(): application.delivery_map.confirm_setup())
	button.name = "ConfirmBattleSetup"
	button.disabled = state.monsters("team").is_empty() or not error.is_empty()
	button.tooltip_text = error if not error.is_empty() else "请先将至少一只妖兽加入出战队列。" if button.disabled else "使用已选队伍进入本次遭遇。"

func _process(_delta: float) -> void:
	view.set_process(modal_stack.is_empty() or modal_stack.back().get("kind","") != "settings")
	if is_instance_valid(_main_menu_button): _main_menu_button.disabled = application.phase == "main" or application.returning_to_main_menu
	if application != null: application.refresh_input_gate()
	var task_button: Button = base.get_node("%Navigation").get_node("%Tasks")
	task_button.disabled = not _tasks_available() or overlay.visible
	task_button.tooltip_text = "查看新手任务" if _tasks_available() else "新手任务仅在大地图可用"
	if not _task_notifications.is_empty() and _tasks_available() and modal_stack.is_empty():
		_notice("新手任务已完成："+"、".join(_task_notifications))
		_task_notifications.clear()

func _curtain(_raising: bool) -> void:
	pass

func _tasks() -> void:
	if not _tasks_available(): return
	if not state.enable_new_player_tasks():
		_notice(state.last_error)
		return
	_modal("待办事项",func(body):
		var page := TasksPanel.instantiate()
		body.add_child(page)
		_task_page = page
		page.present_tasks(_journey_rows())
		page.action_requested.connect(_task_action),"tasks")

func _tasks_available() -> bool:
	return application!=null and application.phase=="world" and route=="world" and not _battle_cancel_needs_save()

func refresh_task_list() -> void:
	if is_instance_valid(_task_page) and not modal_stack.is_empty() and modal_stack.back().get("kind")=="tasks":
		_task_page.present_tasks(_journey_rows())

func queue_task_completion(task_ids: Array) -> void:
	for task: Dictionary in state.task_definitions:
		if task.id in task_ids and task.title not in _task_notifications: _task_notifications.append(task.title)


func _journey_rows() -> Array:
	var rows: Array=state.new_player_task_rows()
	if application!=null and is_instance_valid(application.hex_map): rows.append_array(preload("res://Scripts/Events/StoryObjectives.gd").new().rows(state.data))
	return rows
