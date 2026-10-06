class_name ScrollingEventWindow
extends CanvasLayer
## Only presentation. No map lookup, inventory mutation, game pause, or save access.
signal reward_requested(request_id: String, rewards: Array)
signal choice_selected(event_id: String, choice_id: String)
signal event_closed(event_id: String)

const UI := preload("res://ui/layout_theme.gd")
const CARDS := preload("res://ui/event_cards.gd")
const INFO := preload("res://ui/info_panel.gd")
const GOLD := UI.TEXT
const INK := UI.PANEL
var _root: Control
var _scroll: ScrollContainer
var _log: VBoxContainer
var _continue: Button
var _latest: Button
var _title: Label
var _hint: Label
var _data: Dictionary = {}
var _nodes: Dictionary = {}
var _cursor := ""
var _state := "idle"
var _request := ""
var _session := ""
var _reward_node: Dictionary = {}
var _choices: GridContainer
var _reward_display: Control
var _badge: Label
var _info: CanvasLayer
var _scroll_tween: Tween
var _generation := 0
var _receipt_added := false
var transcript: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_info = INFO.new()
	add_child(_info)
	_root.hide()

func is_open() -> bool:
	return _state != "idle"

func get_state() -> String:
	return _state

func open_event(definition: Dictionary, session_id: String) -> Error:
	if is_open():
		return ERR_BUSY
	if session_id.is_empty() or not _valid(definition):
		return ERR_INVALID_DATA
	_generation += 1
	_data = definition.duplicate(true)
	_nodes = _data["nodes"]
	_cursor = str(_data["start"])
	_session = session_id
	_request = ""
	_receipt_added = false
	transcript.clear()
	for child in _log.get_children():
		_log.remove_child(child)
		child.queue_free()
	_choices = null
	_reward_display = null
	_title.text = str(_data["title"])
	_state = "line"
	_root.show()
	_advance()
	return OK

func _valid(definition: Dictionary) -> bool:
	for key in ["id", "title", "start", "nodes"]:
		if not definition.has(key):
			return false
	if not definition.nodes is Dictionary or not definition.nodes.has(str(definition.start)):
		return false
	if str(definition.get("reward_mode", "auto")) not in ["auto", "manual"]:
		return false
	for value in definition.nodes.values():
		if not value is Dictionary:
			return false
		var kind := str(value.get("type", ""))
		if kind not in ["line", "choice", "reward", "end"]:
			return false
		if kind == "choice":
			if not value.get("options", []) is Array or value.get("options", []).is_empty():
				return false
			for option in value.options:
				if not option is Dictionary or not option.has("id") or not option.has("text") or not definition.nodes.has(str(option.get("next", ""))):
					return false
		elif kind != "end" and not definition.nodes.has(str(value.get("next", ""))):
			return false
		if kind == "reward":
			if not value.get("rewards", []) is Array:
				return false
			for reward in value.get("rewards", []):
				if not reward is Dictionary or not reward.has("id") or not reward.has("type"):
					return false
	return true

func advance() -> void:
	if _info.is_modal_open():
		return
	if _state == "line":
		_advance()
	elif _state == "reward_ready":
		_request_rewards()
	elif _state == "end":
		close_event()

func _advance() -> void:
	var node: Dictionary = _nodes[_cursor]
	match str(node.type):
		"line":
			_badge.text = "地点事件 · 叙事"
			_add_line(str(node.get("speaker", "旁白")), str(node.get("text", "")))
			_cursor = str(node.next)
			_state = "line"
			_continue.text = "继续 ↓"
			_continue.disabled = false
			_hint.text = "点击继续，追加下一句话 · 可向上滚动回看"
		"choice":
			_badge.text = "地点事件 · 做出选择"
			_state = "choice"
			_continue.text = "请选择"
			_continue.disabled = true
			_hint.text = "选择只影响后续内容；已读对话会保留"
			_choices = CARDS.choice_grid(node.options, select_choice, _info.bind_hint)
			_log.add_child(_choices)
		"reward":
			_badge.text = "地点事件 · 奖励结算"
			_request = _session + ":" + str(_data.id) + ":" + _cursor
			_receipt_added = false
			_reward_node = node
			_show_reward(false, "预览奖励 · 尚未领取")
			if str(_data.get("reward_mode", "auto")) == "manual":
				_state = "reward_ready"
				_continue.text = "领取奖励"
				_continue.disabled = false
				_hint.text = "先查看奖励，确认后领取 · 悬停符文查看效果"
			else:
				_request_rewards()
		"end":
			_badge.text = "地点事件 · 已完成"
			_state = "end"
			_continue.text = "返回探索"
			_continue.disabled = false
			_hint.text = "事件结束 · 奖励已记录，不会再次发放"
	_scroll_to_latest.call_deferred(_generation)

func _request_rewards() -> void:
	_state = "reward_pending"
	_continue.text = "等待发放确认…"
	_continue.disabled = true
	_hint.text = "等待外部奖励系统确认；窗口本身不修改背包"
	reward_requested.emit(_request, _reward_node.get("rewards", []).duplicate(true))

func _show_reward(confirmed: bool, message: String) -> void:
	var index := _log.get_child_count()
	if is_instance_valid(_reward_display):
		index = _reward_display.get_index()
		_log.remove_child(_reward_display)
		_reward_display.queue_free()
	_reward_display = CARDS.reward_summary(_reward_node, confirmed, message, _info.bind_hint)
	_log.add_child(_reward_display)
	_log.move_child(_reward_display, index)

func select_choice(choice_id: String) -> void:
	if _state != "choice" or _info.is_modal_open():
		return
	var node: Dictionary = _nodes[_cursor]
	for option in node.options:
		if str(option.id) != choice_id:
			continue
		_log.remove_child(_choices)
		_choices.queue_free()
		_choices = null
		_add_line("召唤师", str(option.text), true)
		_cursor = str(option.next)
		_state = "line"
		choice_selected.emit(str(_data.id), choice_id)
		_advance()
		return

## Host must apply rewards idempotently, then acknowledge the matching request.
func acknowledge_reward(request_id: String, success: bool, message: String = "") -> bool:
	if _state != "reward_pending" or request_id != _request or _receipt_added:
		return false
	if not success:
		_hint.text = message if not message.is_empty() else "奖励未发放，请检查外部系统后重新确认"
		return false
	_receipt_added = true
	_show_reward(true, message)
	transcript.append({"type": "reward", "request_id": request_id, "rewards": _reward_node.get("rewards", []).duplicate(true)})
	_cursor = str(_reward_node.next)
	_advance()
	return true

func close_event() -> void:
	if _state != "end" or _info.is_modal_open():
		return
	var event_id := str(_data.id)
	_state = "idle"
	_generation += 1
	_root.hide()
	_info.close()
	event_closed.emit(event_id)

func _add_line(speaker: String, body: String, player := false) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_log.add_child(box)
	box.add_child(_label(("你 · " if player else "") + speaker, 17, UI.MUTED))
	box.add_child(_label(body, 21))
	transcript.append({"type": "line", "speaker": speaker, "text": body})

func _scroll_to_latest(generation: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if generation != _generation or not is_open():
		return
	if _scroll_tween:
		_scroll_tween.kill()
	var bar := _scroll.get_v_scroll_bar()
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(_scroll, "scroll_vertical", int(maxf(0, bar.max_value - bar.page)), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _update_history_hint(_value: float = 0) -> void:
	var bar := _scroll.get_v_scroll_bar()
	var show_latest := bar.max_value - bar.page - bar.value > 24
	# Reserve its layout even when hidden, so header/footer never shift on scrolling.
	_latest.modulate.a = 1.0 if show_latest else 0.0
	_latest.disabled = not show_latest
	_latest.mouse_filter = Control.MOUSE_FILTER_STOP if show_latest else Control.MOUSE_FILTER_IGNORE

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_root.theme = UI.create()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.32)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.anchor_left = 0.23
	center.anchor_top = 0.12
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(922, 560)
	panel.add_theme_stylebox_override("panel", UI.style(INK, UI.BORDER, 24))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var badge_row := HBoxContainer.new()
	column.add_child(badge_row)
	_badge = _label("地点事件", 15, UI.MUTED)
	badge_row.add_child(_badge)
	var rules := _button("说明 ⓘ")
	rules.custom_minimum_size.y = 36
	badge_row.add_child(rules)
	rules.pressed.connect(func(): _info.open_details("事件说明", [{"title": "对话记录", "text": "继续会在同一记录中追加一句话。滚轮回看或回到最新不会推进剧情。"}, {"title": "选择与奖励", "text": "选择只显示对应分支；奖励先预览，再点击领取。返回探索不会再发一次奖励。"}, {"title": "当前演示", "text": "布局参考来自你提供的截图，颜色、图标与材质均为占位。"}]))
	var title_row := HBoxContainer.new()
	column.add_child(title_row)
	var line_left := HSeparator.new()
	line_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(line_left)
	_title = _label("事件", 29)
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_row.add_child(_title)
	var line_right := HSeparator.new()
	line_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(line_right)
	column.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(874, 310)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_log = VBoxContainer.new()
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.add_theme_constant_override("separation", 22)
	_scroll.add_child(_log)
	_scroll.get_v_scroll_bar().value_changed.connect(_update_history_hint)
	_scroll.get_v_scroll_bar().changed.connect(_update_history_hint)
	_scroll.gui_input.connect(func(event: InputEvent):
		if _scroll_tween and (event is InputEventMouseButton or event is InputEventPanGesture):
			_scroll_tween.kill())
	column.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	var help := VBoxContainer.new()
	help.custom_minimum_size.y = 76
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(help)
	_hint = _label("", 14, UI.MUTED)
	help.add_child(_hint)
	_latest = _button("回到最新 ↓")
	_latest.custom_minimum_size.y = 48
	help.add_child(_latest)
	_latest.pressed.connect(func(): _scroll_to_latest(_generation))
	_latest.modulate.a = 0.0
	_latest.disabled = true
	_continue = UI.button("继续 ↓", true)
	_continue.custom_minimum_size = Vector2(210, 52)
	footer.add_child(_continue)
	_continue.pressed.connect(advance)

func _label(value: String, size: int, color := Color("e5e4d7")) -> Label:
	return UI.label(value, size, color)

func _button(value: String) -> Button:
	return UI.button(value)
