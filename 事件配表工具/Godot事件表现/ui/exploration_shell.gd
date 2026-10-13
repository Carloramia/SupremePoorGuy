extends Control
## Scene layout is editor-owned. Snapshot display and user intent only.
signal event_requested
signal replay_requested
signal explanation_requested(title: String, entries: Array)
@onready var _mana: Label = %Mana
@onready var _start: Button = %Start
@onready var _replay: Button = %Replay
@onready var _status: Label = %Status
@onready var _current: Label = %Current
var hint_binder: Callable

func _ready() -> void:
	_start.pressed.connect(func(): event_requested.emit())
	_replay.pressed.connect(func(): replay_requested.emit())
	%Glossary.pressed.connect(func(): explanation_requested.emit("召唤物百科", [{"title": "甲壳", "text": "质量更大、护甲更高、行动更慢。"}, {"title": "菌群", "text": "受击时释放孢子；这里是属性排版示意。"}]))
	for item in [[%ShellTrait, "甲壳", "质量更大、护甲更高、行动更慢。"], [%FungusTrait, "菌群", "身体附着活性菌群，受击时释放孢子。"]]:
		var button: Button = item[0]
		var title: String = item[1]
		var entries := [{"title": title, "text": item[2]}]
		button.pressed.connect(func(): explanation_requested.emit(title, entries))
		if hint_binder.is_valid():
			hint_binder.call(button, title, entries)
	if hint_binder.is_valid():
		hint_binder.call(%Day, "探索时间", [{"title": "第 06 日", "text": "路线与时间仅作展示，没有实际时间结算。"}])

func apply_snapshot(mana: int, completed: bool, busy: bool, status: String) -> void:
	_mana.text = "魔力  %d" % mana
	_start.disabled = completed or busy
	_start.text = "事件已完成" if completed else "进入图书馆"
	_replay.disabled = busy
	_status.text = status
	_current.text = "图书馆  ✓" if completed else "图书馆  ●"

func configure_hints(binder: Callable) -> void:
	hint_binder = binder
	binder.call(%ShellTrait, "甲壳", [{"title": "甲壳", "text": "护甲更高、质量更大、行动更慢。"}])
	binder.call(%FungusTrait, "菌群", [{"title": "菌群", "text": "受击时释放孢子。"}])
	binder.call(%Day, "探索时间", [{"title": "第 06 日", "text": "时间仅为排版演示，不实际结算。"}])
