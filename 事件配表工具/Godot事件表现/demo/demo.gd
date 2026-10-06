extends Control
## Demo host: snapshots and rewards only. UI components emit intent via signals.
const WINDOW := preload("res://ui/event_window.tscn")
const SHELL := preload("res://ui/exploration_shell.gd")
const INFO := preload("res://ui/info_panel.gd")
var event_window: ScrollingEventWindow
var mana := 320
var receipts: Dictionary = {}
var unlocked_runes: Dictionary = {}
var completed := false
var _shell: Control
var _info: CanvasLayer
var _message := "图书馆开门日 · 对话事件 · 无消耗"

func _ready() -> void:
	_info = INFO.new()
	add_child(_info)
	_info.layer = 118
	_shell = SHELL.new()
	_shell.hint_binder = _info.bind_hint
	add_child(_shell)
	_shell.event_requested.connect(start_event)
	_shell.replay_requested.connect(reset_demo)
	_shell.explanation_requested.connect(_info.open_details)
	event_window = WINDOW.instantiate()
	add_child(event_window)
	event_window.reward_requested.connect(_on_reward_requested)
	event_window.event_closed.connect(_on_event_closed)
	_update_hud()

func start_event() -> void:
	if completed or event_window.is_open() or _info.is_modal_open():
		return
	_info.close()
	var content = JSON.parse_string(FileAccess.get_file_as_string("res://data/library_demo.json"))
	var error := event_window.open_event(content, "demo_session_001")
	if error != OK:
		_message = "无法开始事件：" + error_string(error)
	_update_hud()

func _on_reward_requested(request_id: String, rewards: Array) -> void:
	# In production: the save/inventory service owns this receipt ledger.
	if not receipts.has(request_id):
		for reward in rewards:
			match str(reward.type):
				"mana": mana += int(reward.get("amount", 0))
				"rune": unlocked_runes[str(reward.id)] = true
		receipts[request_id] = true
	_update_hud()
	event_window.acknowledge_reward(request_id, true, "已解锁 4 个符文 · 魔力 320 → 420 · 下一次召唤可使用")

func _on_event_closed(_event_id: String) -> void:
	completed = true
	_message = "新符文已解锁：变大大 / 变多多 / 变硬硬 / 变毛毛"
	_update_hud()

func reset_demo() -> void:
	if event_window.is_open() or _info.is_modal_open():
		return
	mana = 320
	receipts.clear()
	unlocked_runes.clear()
	completed = false
	_message = "演示已重置 · 点击进入图书馆再次体验"
	_update_hud()

func _update_hud() -> void:
	_shell.apply_snapshot(mana, completed, event_window.is_open(), _message)
