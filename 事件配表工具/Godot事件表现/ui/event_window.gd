class_name ScrollingEventWindow
extends CanvasLayer
## Only presentation. No map lookup, inventory mutation, game pause, or save access.
signal reward_requested(request_id: String, rewards: Array)
signal choice_selected(event_id: String, choice_id: String)
signal event_closed(event_id: String)

const GOLD := Color("d4ba80")
const INK := Color("101e1b")
const RUNE_ICON := preload("res://ui/rune_icon.gd")
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
var _choices: VBoxContainer
var _scroll_tween: Tween
var _generation := 0
var _receipt_added := false
var transcript: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
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
	if _state == "line":
		_advance()
	elif _state == "end":
		close_event()

func _advance() -> void:
	var node: Dictionary = _nodes[_cursor]
	match str(node.type):
		"line":
			_add_line(str(node.get("speaker", "旁白")), str(node.get("text", "")))
			_cursor = str(node.next)
			_state = "line"
			_continue.text = "继续 ↓"
			_continue.disabled = false
			_hint.text = "点击继续，追加下一句话 · 可向上滚动回看"
		"choice":
			_state = "choice"
			_continue.text = "请选择"
			_continue.disabled = true
			_hint.text = "选择只影响后续内容；已读对话会保留"
			_choices = VBoxContainer.new()
			_choices.add_theme_constant_override("separation", 8)
			_log.add_child(_choices)
			for option in node.options:
				var button := _button(str(option.text))
				_choices.add_child(button)
				button.pressed.connect(select_choice.bind(str(option.id)))
		"reward":
			_state = "reward_pending"
			_request = _session + ":" + str(_data.id) + ":" + _cursor
			_receipt_added = false
			_reward_node = node
			_continue.text = "等待奖励确认…"
			_continue.disabled = true
			_hint.text = "等待外部奖励系统确认；窗口本身不修改背包"
			reward_requested.emit(_request, node.get("rewards", []).duplicate(true))
		"end":
			_state = "end"
			_continue.text = "收好，返回地图"
			_continue.disabled = false
			_hint.text = "事件结束 · 奖励已记录，不会再次发放"
	_scroll_to_latest.call_deferred(_generation)

func select_choice(choice_id: String) -> void:
	if _state != "choice":
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
	var receipt := VBoxContainer.new()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(Color("263426"), GOLD, 18))
	receipt.add_theme_constant_override("separation", 12)
	card.add_child(receipt)
	_log.add_child(card)
	receipt.add_child(_label(str(_reward_node.get("title", "获得奖励")), 23, GOLD))
	var rune_row := HBoxContainer.new()
	rune_row.add_theme_constant_override("separation", 8)
	receipt.add_child(rune_row)
	for reward in _reward_node.get("rewards", []):
		if str(reward.type) == "rune":
			var rune_card := VBoxContainer.new()
			rune_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rune_row.add_child(rune_card)
			var icon := Control.new()
			icon.set_script(RUNE_ICON)
			icon.rune_id = str(reward.id)
			rune_card.add_child(icon)
			var rune_name := _label(str(reward.get("label", reward.id)).split(" · ")[0], 20, GOLD)
			rune_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rune_card.add_child(rune_name)
		else:
			receipt.add_child(_label("✦  " + str(reward.get("label", reward.get("id", ""))), 20))
	receipt.add_child(_label(message if not message.is_empty() else "奖励已发放", 17, Color("a7bea4")))
	transcript.append({"type": "reward", "request_id": request_id, "rewards": _reward_node.get("rewards", []).duplicate(true)})
	_cursor = str(_reward_node.next)
	_advance()
	return true

func close_event() -> void:
	if _state != "end":
		return
	var event_id := str(_data.id)
	_state = "idle"
	_generation += 1
	_root.hide()
	event_closed.emit(event_id)

func _add_line(speaker: String, body: String, player := false) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_log.add_child(box)
	box.add_child(_label(speaker, 17, Color("8dd2bc") if player else GOLD))
	box.add_child(_label(body, 23))
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
	var ui_theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "SimHei"])
	ui_theme.default_font = font
	_root.theme = ui_theme
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(870, 530)
	panel.add_theme_stylebox_override("panel", _style(INK, GOLD, 28))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	_title = _label("事件", 29, GOLD)
	column.add_child(_title)
	column.add_child(_label("同一记录 · 可回看     /     对话按时间顺序保留", 16, Color("9caaa0")))
	column.add_child(HSeparator.new())
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(810, 320)
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
	help.custom_minimum_size.y = 56
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(help)
	_hint = _label("", 14, Color("a3b0a6"))
	help.add_child(_hint)
	_latest = _button("回到最新 ↓")
	_latest.custom_minimum_size.y = 32
	help.add_child(_latest)
	_latest.pressed.connect(func(): _scroll_to_latest(_generation))
	_latest.modulate.a = 0.0
	_latest.disabled = true
	_continue = _button("继续 ↓")
	_continue.custom_minimum_size = Vector2(210, 52)
	footer.add_child(_continue)
	_continue.pressed.connect(advance)

func _label(value: String, size: int, color := Color("e5e4d7")) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", GOLD)
	button.add_theme_stylebox_override("normal", _style(Color("203029"), Color("796e50"), 10))
	button.add_theme_stylebox_override("hover", _style(Color("354739"), GOLD, 10))
	button.add_theme_stylebox_override("pressed", _style(Color("18271f"), GOLD, 10))
	return button

func _style(background: Color, border: Color, margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style
