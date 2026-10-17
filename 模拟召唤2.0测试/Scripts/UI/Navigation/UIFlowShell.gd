extends Control
## Standalone wireframe shell. No dependency on the game or event project.
const TITLES = {
	&"main": "涌现 · 主菜单", &"world": "大地图", &"local": "探索小地图",
	&"summon": "召唤法阵", &"summon_result": "破茧与召唤结果",
	&"deployment": "战前布阵", &"battle": "自动战斗", &"settlement": "战斗结算",
	&"warehouse": "妖兽仓库", &"monster": "妖兽详情", &"book": "符文书与引导物",
	&"event": "事件与对话", &"trade": "交易", &"settings": "设置", &"help": "操作帮助"
}
const DESCRIPTIONS = {
	&"main": "独立 UI 跳转原型。所有数据均为占位，不读取或修改正式存档。",
	&"world": "地图显示区\n位置、路线、时间、地形词条占位；不决定连续移动或按格移动规则。",
	&"local": "当地探索区\nNPC、召唤位置、敌人、出口占位；返回位置由宿主通过 context 接入。",
	&"summon": "法阵画布占位\n左：奇物与引导物　中：蜂窝阵面　右：符文书\n资源、绘制、识别及预览待接入。",
	&"summon_result": "结茧 → 破茧 → 怪物展示\n不实际生成或入库，不提前定产出数量与数值。",
	&"deployment": "敌方信息／部署区域／出战列表占位\n选队、拖放、统御检查待接入。",
	&"battle": "战斗视口与敌我状态占位\n不能通过返回键跳过结算；暂停请求不会直接暂停场景树。",
	&"settlement": "胜负、掉落、魔力与负伤占位\n领取按钮只发请求，宿主确认结算成功后才能返回探索。",
	&"warehouse": "怪物卡片、筛选、队伍管理占位。",
	&"monster": "外观、名称、形态、能力、出战和负伤状态占位。",
	&"book": "已收录符文、奇物、引导物及线索占位；不提前暴露未知符文。",
	&"event": "滚动正文、分支选项、奖励回执占位。后续接入现有事件系统。",
	&"trade": "商品、条件、价格与确认占位。不实际交易。",
	&"settings": "音量、显示、输入设置占位。不会更改全局配置。",
	&"help": "点击按钮检查跳转。Esc 优先关闭最上层弹窗，其次返回页面。\n“请求”只发送接口信号；“演示”只改变 UI，不代表玩法完成。"
}
@onready var router = $Router
var page: VBoxContainer
var page_scroll: ScrollContainer
var modal: PanelContainer
var modal_body: VBoxContainer
var blocker: ColorRect
var back_button: Button
var status: Label
var route_label: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_shell()
	router.screen_changed.connect(_show_screen)
	router.overlay_changed.connect(_show_overlay)
	router.action_requested.connect(_on_action)
	router.start({"origin": "ui_demo", "location_id": "placeholder_location"})

func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color("17252d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)
	route_label = _label("UI FLOW / PLACEHOLDER", 16)
	layout.add_child(route_label)
	var toolbar := HFlowContainer.new()
	layout.add_child(toolbar)
	back_button = _button(toolbar, "返回 / Esc", func(): router.go_back())
	for id in [&"warehouse", &"book", &"settings", &"help"]:
		_button(toolbar, TITLES[id], func(): router.open_overlay(id))
	page_scroll = ScrollContainer.new()
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(page_scroll)
	page = VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 18)
	page_scroll.add_child(page)
	status = _label("未连接正式功能；等待操作。", 16)
	layout.add_child(status)
	blocker = ColorRect.new()
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.color = Color(0, 0, 0, 0.78)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	modal = PanelContainer.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.offset_left = 40
	modal.offset_top = 40
	modal.offset_right = -40
	modal.offset_bottom = -40
	blocker.add_child(modal)
	var modal_margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		modal_margin.add_theme_constant_override("margin_" + side, 24)
	modal.add_child(modal_margin)
	var scroll := ScrollContainer.new()
	modal_margin.add_child(scroll)
	modal_body = VBoxContainer.new()
	modal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_body.add_theme_constant_override("separation", 18)
	scroll.add_child(modal_body)
	blocker.hide()

func _show_screen(route: StringName, _context: Dictionary) -> void:
	_clear(page)
	route_label.text = "UI FLOW / %s · 独立占位原型" % route
	page.add_child(_label(TITLES[route], 32))
	page.add_child(_label(DESCRIPTIONS[route], 20))
	var actions := HFlowContainer.new()
	page.add_child(actions)
	match route:
		&"main":
			_button(actions, "开始跳转演示", func(): router.navigate(&"world"))
			_request(actions, "继续游戏 · 待接入", &"load_game")
		&"world":
			_request(actions, "移动 / 暂停 / 改道", &"world_move")
			_button(actions, "进入小地图 · 演示", func(): router.navigate(&"local"))
		&"local":
			_button(actions, "打开当地法阵", func(): router.navigate(&"summon"))
			_button(actions, "查看敌情并布阵", func(): router.navigate(&"deployment"))
			_button(actions, "交谈", func(): router.open_overlay(&"event", {"event_id": "placeholder_event"}))
			_button(actions, "交易", func(): router.open_overlay(&"trade"))
		&"summon":
			_request(actions, "确认召唤 · 请求", &"summon_confirm")
			_button(actions, "预览破茧结果 · 演示", func(): router.navigate(&"summon_result", {"preview_only": true}))
		&"summon_result":
			_button(actions, "返回法阵", func(): router.finish_summon_preview())
			_button(actions, "查看仓库", func(): router.open_overlay(&"warehouse"))
		&"deployment":
			_request(actions, "确认阵容 · 请求", &"battle_start")
			_button(actions, "进入战斗视图 · 演示", func(): router.navigate(&"battle", {"preview_only": true}))
		&"battle":
			_request(actions, "暂停 / 恢复 · 请求", &"battle_pause_toggle")
			_button(actions, "预览结算 · 演示", func(): router.navigate(&"settlement", {"preview_only": true}))
		&"settlement":
			_request(actions, "领取并返回 · 请求", &"settlement_confirm")
			_button(actions, "返回探索 · 演示，不发奖励", func(): router.return_to_exploration())
	_update_back()
	page_scroll.scroll_vertical = 0
	back_button.grab_focus()

func _show_overlay(route: StringName, _context: Dictionary) -> void:
	_clear(modal_body)
	blocker.visible = route != &""
	page_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE if blocker.visible else Control.MOUSE_FILTER_STOP
	# Prevent keyboard focus from reaching controls behind the modal.
	_set_buttons_enabled(get_child(1), not blocker.visible)
	_update_back()
	if route == &"":
		back_button.grab_focus()
		return
	modal_body.add_child(_label(TITLES[route], 28))
	modal_body.add_child(_label(DESCRIPTIONS[route], 20))
	var actions := HFlowContainer.new()
	modal_body.add_child(actions)
	match route:
		&"warehouse":
			_button(actions, "查看示例怪物", func(): router.open_overlay(&"monster", {"monster_id": "placeholder_monster"}))
			_request(actions, "管理队伍 · 请求", &"party_edit")
		&"monster":
			_request(actions, "改名 · 请求", &"monster_rename")
			_request(actions, "解契确认 · 请求", &"monster_release_confirm")
		&"event":
			_request(actions, "继续 / 选择 · 请求", &"event_advance")
			_request(actions, "领取奖励 · 请求", &"event_claim")
		&"trade":
			_request(actions, "购买确认 · 请求", &"trade_confirm")
		&"settings":
			_request(actions, "应用设置 · 请求", &"settings_apply")
	var close := _button(actions, "关闭 / Esc", func(): router.go_back())
	close.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		router.go_back()
		get_viewport().set_input_as_handled()

func _request(parent: Node, title: String, action: StringName) -> void:
	_button(parent, title, func(): router.request_action(action))

func _on_action(action: StringName, _context: Dictionary) -> void:
	status.text = "已发送接口请求：%s（占位：尚未执行真实功能）" % action

func _update_back() -> void:
	if is_instance_valid(back_button):
		back_button.disabled = not router.can_go_back() or not router.overlays.is_empty()

func _set_buttons_enabled(node: Node, enabled: bool) -> void:
	if node is Button:
		node.disabled = not enabled
	for child in node.get_children():
		_set_buttons_enabled(child, enabled)

func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(160, 48)
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _label(value: String, size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	return label

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
