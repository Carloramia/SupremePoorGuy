extends CanvasLayer

@export_range(1, 100, 1) var maximum_lines: int = 16
@export var mirror_to_console: bool = true
@export var output_visible: bool = false:
	set(value):
		output_visible = value
		if is_instance_valid(_panel):
			_panel.visible = value

@onready var _label: RichTextLabel = $MarginContainer/PanelContainer/MarginContainer/Output
@onready var _panel: Control = $MarginContainer

var _lines: Array[String] = []

func _ready() -> void:
	_panel.visible = output_visible
	log_line("RuntimeDebugOutput ready")

func log_line(message: String) -> void:
	var timestamp := Time.get_time_string_from_system()
	var formatted := "[%s] %s" % [timestamp, message]
	_lines.append(formatted)
	while _lines.size() > maximum_lines:
		_lines.pop_front()
	if is_instance_valid(_label):
		_label.text = "\n".join(_lines)
	if mirror_to_console:
		print(formatted)

func clear_output() -> void:
	_lines.clear()
	if is_instance_valid(_label):
		_label.text = ""
