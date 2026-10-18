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
	L10N.bind(pause_hint,&"text","ui.d154fda07dc8")
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
	start_battle_button = _btn(view,"ui.f09db6116878",func(): application.start_battle())
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
		L10N.bind(status,&"text",func(): return L10N.text(L10N.text("ui.e356dcf01e24") if manually_paused else (L10N.text("ui.df551b21bc32") if free_mouse else L10N.text("ui.309ca908d28d"))))

func update_deployment_controls(deploying: bool, can_start: bool, error: String) -> void:
	var shown := deploying and route == "battle" and not overlay.visible
	start_battle_button.visible = shown
	start_battle_button.disabled = not can_start
	L10N.bind(start_battle_button,&"tooltip_text",func(): return L10N.text(L10N.text("ui.59397f10bc47") if not can_start else L10N.text("ui.c8fd5f6d3736")))
	deployment_hint.visible = shown
	L10N.bind(deployment_hint,&"text",func(): return L10N.text("ui.dd7609dd208b")+"\n" + (L10N.text(error) if not error.is_empty() else ("再次点击左键放置；放置后才可开始战斗。" if not can_start else "靠近友军后点击左键拾起，再次点击放置；按 Q 后点击开始战斗。")))
	if shown: L10N.bind(status,&"text","ui.7077c680a8c6")

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
		_btn(actions,"ui.63ccfb01fdfc",func(): view.skip_eruption())
	L10N.bind(status,&"text",func(): return L10N.text({"main":"ItIsTime","world":L10N.text("ui.24305da04d78"),"battle":L10N.text("ui.aabd5072736f"),"eruption":L10N.text("ui.ca7f4a820a00")}.get(next,"")))
	actions.visible = actions.get_child_count()>0
	main_content.visible = not _has_page_root()
	status.visible = next != "main" and not _has_page_root()
	_update_header()
	if application != null: application.ui_route_changed(next)

func _update_header() -> void:
	if header == null: return
	var place: String = application.location_name() if application != null else "边境"
	L10N.bind(header,&"text",func(): return L10N.text(L10N.text("ui.1f2d217d0c75") % [place,int(state.data.day),state.data.magic]))
	L10N.bind(header,&"tooltip_text","ui.1749a4558b14")

func _update_motion_status() -> void:
	pass

func _start_new() -> void:
	application.start_new_game()

func _location_clicked(id: String, _kind: String) -> void:
	application.world_map.select_location(StringName(id))

func _navigation_requested(action: String) -> void:
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
		_notice("ui.7d2dc48c1c2b")
		return
	var serial: int = state.data.serial
	super._perform_summon()
	application.trace_map_event("event_completed" if state.data.serial>serial else "event_rejected",{"event_id":"summon","serial":state.data.serial,"pending_ids":state.data.pending.duplicate(),"magic":state.data.magic,"reason":"" if state.data.serial>serial else state.last_error})

func _build_ritual(body: VBoxContainer) -> void:
	super._build_ritual(body)
	var species := PackedStringArray()
	for id: String in state.FACTORY.SUMMON_POOL: species.append(state.FACTORY.DEFINITIONS[id].name)
	L10N.bind(ritual_page.get_node("%Context"),&"text",func(): return L10N.text(L10N.text("ui.f4caa8ddae37") % [application.location_name()," / ".join(species)]))
	L10N.bind(ritual_page.get_node("%Upgrade"),&"text","ui.fe216b104dab")
	L10N.bind(ritual_page.get_node("%Upgrade"),&"tooltip_text","ui.b3929481adbb")
	L10N.bind(ritual_page.get_node("%Examples"),&"tooltip_text","ui.70e87367c1e1")

func _refresh_ritual() -> void:
	super._refresh_ritual()
	var error: String = state.supported_layout(rules)
	if not error.is_empty():
		summon_button.disabled = true
		L10N.bind(summon_button,&"tooltip_text",func(): return L10N.text(error))

func _open_event(id: String) -> void:
	application.open_event(id)

func _monster_card(parent: Node, monster: Dictionary, result_card: bool) -> void:
	super._monster_card(parent,monster,result_card)
	var card := parent.get_child(parent.get_child_count()-1)
	_request_creature_portrait(card.get_node("%Portrait"),monster)
	var stats: Node = card.get_node("%Stats")
	for index: int in 4:
		L10N.bind(stats.get_child(index),&"text",func(): return L10N.text([L10N.text("ui.8ce33e80ad0a") % monster.hp,L10N.text("ui.d7efa579fa05") % monster.attack,L10N.text("ui.e3e64ba9babf") % monster.armor,L10N.text("ui.2de403b8ff0b") % monster.speed][index]))

func _fill_detail(body: VBoxContainer, id: String) -> void:
	var monster: Dictionary = state.monster_by_id(id)
	var page := MonsterDetail.instantiate()
	body.add_child(page)
	page.get_node("%Portrait").form = monster.form
	page.get_node("%Portrait").tint = Color(monster.color)
	_request_creature_portrait(page.get_node("%Portrait"),monster)
	L10N.bind(page.get_node("%Name"),&"text",func(): return L10N.creature_name(monster))
	L10N.bind(page.get_node("%Stats"),&"text",func(): return L10N.text(L10N.text("ui.9a8cdfe96ffa") % [monster.hp,monster.attack,monster.armor,monster.speed,monster.get("interval_multiplier",1.0),monster.parts.size()]))
	L10N.bind(page.get_node("%Stats"),&"tooltip_text","ui.96f971268212")
	var name_input: LineEdit = page.get_node("%NameInput")
	name_input.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	L10N.bind(name_input,&"placeholder_text",name_input.placeholder_text)
	name_input.text = monster.name
	page.get_node("%Save").pressed.connect(func():
		if state.rename_monster(id,name_input.text): _render_modal()
		else: _notice(func(): return L10N.text(state.last_error if not state.last_error.is_empty() else L10N.text("ui.e83654164a44"))))
	for trait_name: String in monster.traits:
		_btn(page.get_node("%Traits"),func(): return L10N.text("【%s】" % L10N.text(trait_name)),func(): _trait(trait_name))

func _trait(name_text: String) -> void:
	for rune: Dictionary in Rules.RUNES:
		if rune.name == name_text:
			_term(name_text,rune.effect+"\n"+rune.detail+"\n\n"+("已映射到真实部位属性或攻击冷却。" if rune.id in state.SUPPORTED_RUNES else "此效果尚未开放，召唤会在扣费前被阻止。"))
			return

func _book() -> void:
	_modal("符文辞典",func(body):
		var page := _text_screen(body,"ui.2273576d6eef")
		for rune: Dictionary in Rules.RUNES:
			_btn(page.get_node("%Commands"),func(): return L10N.text(L10N.text(rune.name)+(L10N.text("ui.f83e2ccb040e") if rune.id in state.SUPPORTED_RUNES else L10N.text("ui.e3c3cda9872d"))),func(): _trait(rune.name)))

func _help() -> void:
	_term("旅途指南","地图点击地点并沿路径抵达后交互。召唤结果可加入出战或存入仓库，队位上限6。\n战场默认使用自由地形光标，双方由AI控制。Q切换系统鼠标与地形光标，Space暂停/继续战斗；鼠标移动地形光标，右键拖拽旋转镜头，滚轮缩放。\nESC在所有阶段打开设置，再按一次返回原界面。设置中可选择分辨率、全屏和保存后返回主菜单。B工坊入口和Q轮盘仍禁用。法阵中Enter刻入、Backspace撤回；纸页可点击返回按钮关闭。\n存档同时保存仓库、召唤结果和地图；中途退出战斗会从初始部署重开。")

func _term(title: String, content: String) -> void:
	var descriptions := {"生命":"真实部位生命上限的总和；各部位独立受伤与断裂。","攻击":"冲量10时的挥击原始伤害参考。实际伤害由接触冲量、护甲与DamageService规则计算。","护甲":"真实部位护甲的平均值，命中时使用被击中部位自己的护甲。","移速":"移动预设中的目标速度，实际速度受物理结构与地面接触影响。"}
	super._term(title,descriptions.get(title,content))

func _task_action(action: String) -> void:
	if action == "event":
		_close_all()
		_notice("ui.06835cd32070")
	else: super._task_action(action)

func _skip_battle() -> void:
	_notice("ui.5c7fbcd9b770")

func toggle_settings() -> void:
	if not modal_stack.is_empty() and modal_stack.back().get("kind","") == "settings": _close_modal(false)
	else: _settings()

func _settings() -> void:
	if not modal_stack.is_empty() and modal_stack.back().get("kind","") == "settings": return
	_modal("设置 / 保存 / 退出",func(body):
		var page := _text_screen(body,"ui.d6789f4647ff")
		var commands: Node = page.get_node("%Commands")
		var current: Dictionary = application.get_display_settings()
		var language_caption := Label.new()
		L10N.bind(language_caption,&"text","ui.settings.language")
		commands.add_child(language_caption)
		var language := OptionButton.new()
		language.name = "Language"
		language.custom_minimum_size.y = 42
		var localization: Node = get_node("/root/GameLocalization")
		var locales: Array = localization.configuration.locales.keys()
		for locale: String in locales: language.add_item(localization.configuration.locales[locale].name)
		language.select(maxi(0,locales.find(localization.current_locale())))
		language.item_selected.connect(func(index: int):
			if not localization.set_locale(locales[index]):
				language.select(maxi(0,locales.find(localization.current_locale())))
				_notice(L10N.text("ui.settings.language_error")))
		commands.add_child(language)
		var choices: Array = application.DISPLAY_RESOLUTIONS.duplicate()
		if current.resolution not in choices: choices.append(current.resolution)
		var caption := Label.new()
		L10N.bind(caption,&"text","ui.c10644a0c7e3")
		commands.add_child(caption)
		var resolution := OptionButton.new()
		resolution.name = "Resolution"
		resolution.custom_minimum_size.y = 42
		for size: Vector2i in choices: resolution.add_item("%d × %d" % [size.x,size.y])
		resolution.select(choices.find(current.resolution))
		commands.add_child(resolution)
		var fullscreen := CheckButton.new()
		fullscreen.name = "Fullscreen"
		L10N.bind(fullscreen,&"text","ui.22ea3f47fee8")
		fullscreen.button_pressed = current.fullscreen
		commands.add_child(fullscreen)
		var apply := _btn(commands,"ui.5865f6bc31f0",func():
			if application.apply_display_settings(choices[resolution.selected],fullscreen.button_pressed): _notice("ui.f3a57f243657")
			else: _notice(func(): return L10N.text(application.display_error)))
		apply.name = "ApplyDisplay"
		L10N.bind(apply,&"tooltip_text","ui.af2c63d32afc")
		_btn(commands,"ui.aa75a16696a6",func(): _notice(func(): return L10N.text(L10N.text("ui.1bd91a7d0c53") if application.save_session() else state.last_error)))
		_btn(page.get_node("%Commands"),func(): return L10N.text(L10N.text("ui.c66e646390a9") if animate_panels else L10N.text("ui.6827b4782982")),func():
			animate_panels = not animate_panels
			board_motion.enabled = animate_panels
			_render_modal())
		_main_menu_button = _btn(commands,"ui.e34e61a243be",func(): application.return_to_main_menu())
		_main_menu_button.name = "ReturnToMainMenu"
		_main_menu_button.disabled = application.phase == "main" or application.returning_to_main_menu
		L10N.bind(_main_menu_button,&"tooltip_text","ui.b8328c8f3763")
		_btn(page.get_node("%Commands"),"ui.dbc0fe120d31",func():
			if application.save_session(): get_tree().quit()
			else: _notice(func(): return L10N.text(state.last_error))),"settings")

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
	if not modal_stack.is_empty() and modal_stack.back().get("kind","") != "settings":
		var kind: String = modal_stack.back().get("kind","")
		L10N.bind(close_button,&"text","离开" if kind=="event" else "关闭" if kind=="tasks" else "返回")
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
	var button := _btn(commands,"ui.8cbd7b90a986",func(): application.delivery_map.confirm_setup())
	button.name = "ConfirmBattleSetup"
	button.disabled = state.monsters("team").is_empty() or not error.is_empty()
	L10N.bind(button,&"tooltip_text",func(): return L10N.text(error if not error.is_empty() else L10N.text("ui.706dd02d943b") if button.disabled else L10N.text("ui.9ba08e110d33")))

func _process(_delta: float) -> void:
	view.set_process(modal_stack.is_empty() or modal_stack.back().get("kind","") != "settings")
	if is_instance_valid(_main_menu_button): _main_menu_button.disabled = application.phase == "main" or application.returning_to_main_menu
	if application != null: application.refresh_input_gate()

func _curtain(_raising: bool) -> void:
	pass

func _tasks() -> void:
	_modal("待办事项",func(body):
		var page := TasksPanel.instantiate()
		body.add_child(page)
		page.present_tasks([
			{"title":"探索边境","description":"发现地点并沿真实路径抵达。","done":not state.data.worlds.is_empty(),"action":"world"},
			{"title":"召唤妖兽","description":"刻入已接入的符文并安置同一批实例。","done":state.data.serial>0,"action":"summon"},
			{"title":"准备出战队伍","description":L10N.text("ui.e92f6294f7a5") % state.occupied_slots(),"done":state.occupied_slots()>0,"action":"party"}])
		page.action_requested.connect(_task_action),"tasks")

