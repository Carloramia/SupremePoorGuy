extends Control
## Demo host: snapshots and rewards only. UI components emit intent via signals.
@onready var event_window: ScrollingEventWindow = $EventWindow
@onready var session: Node = $Session
var mana := 320
var receipts: Dictionary = {}
var unlocked_runes: Dictionary = {}
var completed := false
@onready var _shell: Control = $Shell
@onready var _info: CanvasLayer = $ShellInfo
var _message := "图书馆开门日 · 对话事件 · 无消耗"

func _ready() -> void:
	_shell.configure_hints(_info.bind_hint)
	_shell.event_requested.connect(start_event)
	_shell.replay_requested.connect(reset_demo)
	_shell.explanation_requested.connect(_info.open_details)
	session.reward_requested.connect(_on_reward_requested)
	session.event_finished.connect(_on_event_finished)
	session.status_changed.connect(_update_hud)
	_update_hud()

func start_event() -> void:
	if completed or event_window.is_open() or _info.is_modal_open():
		return
	_info.close()
	var error: Error = session.play_file(session.source_file, "demo_session_001")
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
	session.acknowledge_reward(request_id, true, "已解锁 4 个符文 · 魔力已更新 · 下一次召唤可使用")

func _on_event_finished(_event_id: String, preview: bool) -> void:
	if preview:
		_message = "预览结束 · 正式资源与事件完成状态未修改"
		_update_hud()
		return
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
