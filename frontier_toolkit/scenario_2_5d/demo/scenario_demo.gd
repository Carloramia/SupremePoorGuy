extends ScenarioController

var previous_scale_size: Vector2i
var previous_scale_mode: int
var changed_window_scale: bool = false

func _enter_tree() -> void:
	# Embedded scenarios belong to their SubViewport; never resize the host map.
	if get_viewport() is SubViewport:
		return
	var window := get_window()
	changed_window_scale = true
	previous_scale_size = window.content_scale_size
	previous_scale_mode = window.content_scale_mode
	window.content_scale_size = Vector2i(1920, 1080)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS

func _exit_tree() -> void:
	if not changed_window_scale:
		return
	var window := get_window()
	window.content_scale_size = previous_scale_size
	window.content_scale_mode = previous_scale_mode
