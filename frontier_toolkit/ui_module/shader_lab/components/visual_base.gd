@tool
extends Control
## Visual-only base: never receives input or applies material to child labels.
const DefaultProfile = preload("res://ui_module/shader_lab/presets/medium.tres")
@export var profile: Resource = DefaultProfile:
	set(value):
		if profile != null and profile.changed.is_connected(_refresh):
			profile.changed.disconnect(_refresh)
		profile = value
		if profile != null:
			profile.changed.connect(_refresh)
		_refresh()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_refresh)
	if profile != null and not profile.changed.is_connected(_refresh):
		profile.changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	queue_redraw()

