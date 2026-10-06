extends Control
## Receives display snapshots. Emits intent, never modifies exploration or inventory.
signal event_requested
signal replay_requested
signal explanation_requested(title: String, entries: Array)
const UI := preload("res://ui/layout_theme.gd")
var _mana: Label
var _start: Button
var _replay: Button
var _status: Label
var _current: Label
var hint_binder: Callable

func _ready() -> void:
	theme = UI.create()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_sidebar()
	_build_top()
	_build_stage()
	_build_actions()

func apply_snapshot(mana: int, completed: bool, busy: bool, status: String) -> void:
	_mana.text = "魔力  %d" % mana
	_start.disabled = completed or busy
	_start.text = "事件已完成" if completed else "进入图书馆"
	_replay.disabled = busy
	_status.text = status
	_current.text = "图书馆  ✓" if completed else "图书馆  ●"

func _box(rect: Rect2, background: Color = UI.PANEL, padding := 16) -> PanelContainer:
	var box := UI.panel(background, padding)
	box.position = rect.position
	box.size = rect.size
	add_child(box)
	return box

func _build_sidebar() -> void:
	var sidebar := _box(Rect2(0, 0, 288, 720), UI.PANEL, 18)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	sidebar.add_child(column)
	var title := UI.label("2 / 2  召唤物", 29)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(HSeparator.new())
	for unit in [{"name": "石壳兽", "count": "1 / 1", "stats": "生命 160  /  力量 24\n速度 12  /  护甲 30", "trait": "甲壳", "detail": "甲壳：质量更大、护甲更高，行动更慢。此处属性仅用于排版演示。"}, {"name": "菌丝游魂", "count": "1 / 1", "stats": "生命 100  /  力量 18\n速度 20  /  护甲 10", "trait": "菌群", "detail": "菌群：受击时释放孢子。此处属性仅用于排版演示。"}]:
		var card := UI.panel(UI.WELL, 10)
		column.add_child(card)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 6)
		card.add_child(inner)
		inner.add_child(UI.label(str(unit.count) + "  " + str(unit.name), 20))
		inner.add_child(UI.label(str(unit.stats), 16, UI.MUTED))
		var trait_button := UI.button(str(unit.trait) + "  ⓘ")
		inner.add_child(trait_button)
		var entries := [{"title": str(unit.trait), "text": str(unit.detail)}]
		trait_button.pressed.connect(func(): explanation_requested.emit(str(unit.trait), entries))
		if hint_binder.is_valid():
			hint_binder.call(trait_button, str(unit.trait), entries)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	column.add_child(UI.label("队伍信息示意\n不连接战斗或怪物生成", 15, UI.MUTED))

func _build_top() -> void:
	var top := _box(Rect2(308, 18, 950, 66), UI.PANEL, 10)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	top.add_child(row)
	for value in ["平原", "营地 ✓", "战斗 ✓", "图书馆 ●", "遗迹", "首领"]:
		var cell := UI.panel(UI.WELL, 8)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cell)
		var label := UI.label(value, 16)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(label)
		if value.begins_with("图书馆"):
			_current = label
	var day := UI.button("第 06 日")
	row.add_child(day)
	if hint_binder.is_valid():
		hint_binder.call(day, "探索时间", [{"title": "第 06 日", "text": "时间与路线仅作展示，本原型没有时间流逝或地图推进逻辑。"}])
	_mana = UI.label("魔力 320", 20)
	_mana.custom_minimum_size.x = 100
	row.add_child(_mana)

func _build_stage() -> void:
	var stage := _box(Rect2(308, 100, 950, 460), Color("343940"), 28)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 15)
	stage.add_child(column)
	column.add_child(UI.label("第一章  /  平原", 17, UI.MUTED))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var location := UI.label("福斯特镇图书馆", 39)
	location.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(location)
	var intro := UI.label("你的召唤手记，还留在旧友的图书馆里。", 20, UI.MUTED)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(intro)
	var spacer_bottom := Control.new()
	spacer_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer_bottom)
	column.add_child(UI.label("场景区域 · 正式地图与角色形象后续接入", 15, UI.MUTED))

func _build_actions() -> void:
	var bottom := _box(Rect2(308, 578, 950, 124), UI.PANEL, 12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bottom.add_child(row)
	var step := UI.panel(UI.WELL, 12)
	step.custom_minimum_size.x = 120
	row.add_child(step)
	var step_column := VBoxContainer.new()
	step.add_child(step_column)
	step_column.add_child(UI.label("当前地点", 15, UI.MUTED))
	step_column.add_child(UI.label("图书馆", 24))
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(main)
	_status = UI.label("", 16, UI.MUTED)
	main.add_child(_status)
	_start = UI.button("进入图书馆", true)
	main.add_child(_start)
	_start.pressed.connect(func(): event_requested.emit())
	var secondary := VBoxContainer.new()
	secondary.custom_minimum_size.x = 210
	row.add_child(secondary)
	var glossary := UI.button("词条说明  ⓘ")
	secondary.add_child(glossary)
	glossary.pressed.connect(func(): explanation_requested.emit("召唤物百科", [{"title": "甲壳", "text": "质量更大、护甲更高、行动更慢。"}, {"title": "菌群", "text": "身体附着活性菌群，受击时释放孢子。"}, {"title": "护甲 / 速度", "text": "此处数字仅用于验证信息分组，尚未接入实际战斗属性。"}]))
	_replay = UI.button("重置演示")
	secondary.add_child(_replay)
	_replay.pressed.connect(func(): replay_requested.emit())
