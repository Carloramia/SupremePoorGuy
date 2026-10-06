extends Control
## Demo host replaces map, trigger, inventory and persistence adapters.
const WINDOW := preload("res://ui/event_window.tscn")
var event_window: ScrollingEventWindow
var mana := 320
var receipts: Dictionary = {}
var unlocked_runes: Dictionary = {}
var completed := false
var _hud: Label
var _map_button: Button
var _status: Label
var _replay: Button

func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "SimHei"])
	var ui_theme := Theme.new()
	ui_theme.default_font = font
	theme = ui_theme
	_build_map()
	event_window = WINDOW.instantiate()
	add_child(event_window)
	event_window.reward_requested.connect(_on_reward_requested)
	event_window.event_closed.connect(_on_event_closed)
	_update_hud()

func _draw() -> void:
	for row in range(10):
		for col in range(18):
			var origin := Vector2(40 + col * 76 + (row % 2) * 38, 100 + row * 65)
			var points := PackedVector2Array()
			for i in range(7):
				var angle := PI / 3 * i + PI / 6
				points.append(origin + Vector2(cos(angle), sin(angle)) * 42)
			draw_polyline(points, Color(0.19, 0.30, 0.25, 0.6), 1, true)
	draw_circle(Vector2(715, 337), 13, Color("d4ba80"))
	draw_line(Vector2(735, 332), Vector2(785, 286), Color("827952"), 2, true)

func _build_map() -> void:
	_hud = Label.new()
	_hud.position = Vector2(45, 28)
	_hud.add_theme_font_size_override("font_size", 25)
	add_child(_hud)
	_status = Label.new()
	_status.position = Vector2(45, 625)
	_status.add_theme_font_size_override("font_size", 20)
	_status.text = "点击图书馆图标，开始事件演示。"
	add_child(_status)
	_map_button = Button.new()
	_map_button.position = Vector2(770, 225)
	_map_button.size = Vector2(220, 90)
	_map_button.text = "▤  福斯特镇图书馆\n图书馆开门日"
	_map_button.add_theme_font_size_override("font_size", 20)
	_map_button.pressed.connect(start_event)
	add_child(_map_button)
	_replay = Button.new()
	_replay.position = Vector2(1040, 28)
	_replay.size = Vector2(190, 48)
	_replay.text = "重置演示（仅测试）"
	_replay.pressed.connect(reset_demo)
	add_child(_replay)

func start_event() -> void:
	if completed or event_window.is_open():
		return
	var content = JSON.parse_string(FileAccess.get_file_as_string("res://data/library_demo.json"))
	var error := event_window.open_event(content, "demo_session_001")
	if error != OK:
		_status.text = "无法开始事件：" + error_string(error)
	else:
		_replay.disabled = true

func _on_reward_requested(request_id: String, rewards: Array) -> void:
	# In production: the save/inventory service owns this receipt ledger.
	if not receipts.has(request_id):
		for reward in rewards:
			match str(reward.type):
				"mana": mana += int(reward.get("amount", 0))
				"rune": unlocked_runes[str(reward.id)] = true
		receipts[request_id] = true
	_update_hud()
	event_window.acknowledge_reward(request_id, true, "四个符文已加入符文书 · 魔力 320 → 420\n下一次召唤可使用新符文。")

func _on_event_closed(_event_id: String) -> void:
	completed = true
	_map_button.disabled = true
	_map_button.text = "▤  福斯特镇图书馆\n事件已完成"
	_status.text = "新符文已解锁。下一次召唤可使用：变大大 / 变多多 / 变硬硬 / 变毛毛"
	_replay.disabled = false

func reset_demo() -> void:
	if event_window.is_open():
		return
	mana = 320
	receipts.clear()
	unlocked_runes.clear()
	completed = false
	_map_button.disabled = false
	_map_button.text = "▤  福斯特镇图书馆\n图书馆开门日"
	_status.text = "演示已重置。点击图书馆图标再次体验。"
	_update_hud()

func _update_hud() -> void:
	_hud.text = "超级怪物计划     /     第 06 日     /     魔力 %d" % mana
