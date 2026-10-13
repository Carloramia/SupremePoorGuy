class_name ScrollingEventWindow
extends CanvasLayer
## Only presentation. No map lookup, inventory mutation, game pause, or save access.
signal reward_requested(request_id: String, rewards: Array)
signal choice_selected(event_id: String, choice_id: String)
signal event_closed(event_id: String)

const UI := preload("res://ui/layout_theme.gd")
const CARDS := preload("res://ui/event_cards.gd")
const DEFINITION := preload("res://core/event_definition.gd")
const LINE := preload("res://ui/dialogue_line.tscn")
const GOLD := UI.TEXT
const INK := UI.PANEL
@onready var _root: Control = get_node("Root")
@onready var _scroll: ScrollContainer = get_node("%Scroll")
@onready var _log: VBoxContainer = get_node("%Log")
@onready var _continue: Button = get_node("%Continue")
@onready var _latest: Button = get_node("%Latest")
@onready var _title: Label = get_node("%Title")
@onready var _hint: Label = get_node("%Hint")
var _data: Dictionary = {}
var _nodes: Dictionary = {}
var _cursor := ""
var _visible_node := ""
var _state := "idle"
var _request := ""
var _session := ""
var _reward_node: Dictionary = {}
var _choices: GridContainer
var _reward_display: Control
@onready var _badge: Label = get_node("%Badge")
@onready var _info: CanvasLayer = get_node("%Info")
var _scroll_tween: Tween
var _generation := 0
var _receipt_added := false
var transcript: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_continue.pressed.connect(advance)
	_latest.pressed.connect(func(): _scroll_to_latest(_generation))
	_latest.modulate.a = 0.0
	_latest.disabled = true
	_scroll.get_v_scroll_bar().value_changed.connect(_update_history_hint)
	_scroll.get_v_scroll_bar().changed.connect(_update_history_hint)
	_scroll.gui_input.connect(func(event: InputEvent):
		if _scroll_tween and (event is InputEventMouseButton or event is InputEventPanGesture):
			_scroll_tween.kill())
	get_node("%Rules").pressed.connect(func(): _info.open_details("事件说明", [{"title": "记录", "text": "继续逐句追加。回看不推进剧情。"}, {"title": "奖励", "text": "预览会话不修改背包；正式奖励必须由外部系统确认。"}]))
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
	return DEFINITION.validate(definition).ok

func get_runtime_snapshot() -> Dictionary:
	return {"state": _state, "node_id": _visible_node, "next": _cursor, "event_id": str(_data.get("id", "")), "request_id": _request, "lines": transcript.size()}

func abort_event() -> void:
	# Cancellation is not completion and never emits event_closed.
	_generation += 1
	if _scroll_tween:
		_scroll_tween.kill()
	_state = "idle"
	_info.close()
	_root.hide()

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
	_visible_node = _cursor
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
			_reward_display = null # Keep preceding reward receipts in the transcript.
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
	var line := LINE.instantiate()
	line.get_node("%Speaker").text = ("你 · " if player else "") + speaker
	line.get_node("%Body").text = body
	_log.add_child(line)
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
