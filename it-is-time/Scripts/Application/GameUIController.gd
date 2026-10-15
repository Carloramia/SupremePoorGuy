extends "res://Modules/PaperUI/Scripts/GameDemo.gd"
## Keep the paper presentation; the application owns all route and data changes.
var application: Node
var pause_hint: Label

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
	resized.connect(_resize_event)
	main_menu.get_node("%Continue").disabled = not state.has_save()
	_show("main")

func update_battle_controls(in_battle: bool, manually_paused: bool, free_mouse: bool) -> void:
	if is_instance_valid(pause_hint): pause_hint.visible = in_battle and manually_paused
	if route=="battle" and in_battle and not overlay.visible:
		status.text = "战斗已暂停 · Space 继续；Q 切换鼠标" if manually_paused else ("自由鼠标 · Q 返回地形光标；Space 暂停战斗" if free_mouse else "Q 显示自由鼠标；Space 暂停战斗；双方由 AI 控制。")

func _show(next: String) -> void:
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
	header.text = "%s　|　第 %d 天　|　魔力 %d" % [place,int(state.data.day),state.data.magic]
	header.tooltip_text = "正式会话；地图、仓库与召唤共用同一个存档槽。"

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
	if action == "world" and application.phase == "battle":
		_confirm("撤退？","返回大地图，本次战斗不发放胜利奖励。",func(): application.request_retreat())
	else: super._navigation_requested(action)

func _open_ritual() -> void:
	if application.phase in ["world","battle"]: super._open_ritual()

func _warehouse(filter: String = "warehouse") -> void:
	if application.phase in ["world","battle"]: super._warehouse(filter)

func _perform_summon() -> void:
	if not application.phase in ["world","battle"]:
		_notice("当前阶段不能召唤。")
		return
	super._perform_summon()

func _build_ritual(body: VBoxContainer) -> void:
	super._build_ritual(body)
	ritual_page.get_node("%Context").text = "[b]当前位置[/b]\n%s\n\n[b]可召唤物种[/b]\n人形 / 狼 / 蛇\n\n[b]能力边界[/b]\n普通结构与数值符文已接入；天气权重与特殊结构尚未开放。" % application.location_name()
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
	var stats: Node = card.get_node("%Stats")
	for index: int in 4:
		stats.get_child(index).text = ["生命 %.0f" % monster.hp,"攻击 %.1f" % monster.attack,"护甲 %.1f" % monster.armor,"移速 %.1f" % monster.speed][index]

func _fill_detail(body: VBoxContainer, id: String) -> void:
	var monster: Dictionary = state.monster_by_id(id)
	var page := MonsterDetail.instantiate()
	body.add_child(page)
	page.get_node("%Portrait").form = monster.form
	page.get_node("%Portrait").tint = Color(monster.color)
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
	_term("旅途指南","地图点击地点并沿路径抵达后交互。召唤结果可加入出战或存入仓库，队位上限6。\n战场默认使用自由地形光标，双方由AI控制。Q切换系统鼠标与地形光标，Space暂停/继续战斗；鼠标移动地形光标，右键拖拽旋转镜头，滚轮缩放。\n设置中可选择分辨率与全屏。B工坊入口和Q轮盘仍禁用。Esc返回最上层纸页。法阵中Enter刻入、Backspace撤回。\n存档同时保存仓库、召唤结果和地图；中途退出战斗会从初始部署重开。")

func _term(title: String, content: String) -> void:
	var descriptions := {"生命":"真实部位生命上限的总和；各部位独立受伤与断裂。","攻击":"冲量10时的挥击原始伤害参考。实际伤害由接触冲量、护甲与DamageService规则计算。","护甲":"真实部位护甲的平均值，命中时使用被击中部位自己的护甲。","移速":"移动预设中的目标速度，实际速度受物理结构与地面接触影响。"}
	super._term(title,descriptions.get(title,content))

func _task_action(action: String) -> void:
	if action == "event":
		_close_all()
		_notice("前往大地图的事件地点；抵达后方可领取奖励。")
	else: super._task_action(action)

func _skip_battle() -> void:
	_notice("真实战斗不能跳过。")

func _settings() -> void:
	if board_motion.busy: return
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
	if application != null: close_button.disabled = application.phase=="settlement" and modal_stack.size()==1
	if application != null: application.refresh_input_gate()

func _close_modal(store_results: bool = true) -> void:
	if application != null and application.phase == "settlement" and modal_stack.size()<=1: return
	if application != null and application.phase=="world" and modal_stack.size()==1 and application.world_map.interaction.active_location!=null:
		application._resolve_location({"success":false,"complete_location":false,"action":"leave"})
		return
	super._close_modal(store_results)

func _process(_delta: float) -> void:
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
			{"title":"准备出战队伍","description":"当前 %d / 6 队位。" % state.occupied_slots(),"done":state.occupied_slots()>0,"action":"party"}])
		page.action_requested.connect(_task_action),"tasks")

