class_name WorldMapCameraController
extends Camera2D

enum Mode { FOLLOW_PLAYER, FREE }
@export var camera_margin: float = 180.0
@export var zoom_min: float = 0.55
@export var zoom_max: float = 1.8
@export var zoom_step: float = 0.1
@export var follow_on_move_command: bool = true
var mode: Mode = Mode.FOLLOW_PLAYER
var player: WorldMapPlayer
var bounds: Rect2
var map_paused: bool = false
var dragging: bool = false

func _process(_delta: float) -> void:
	if map_paused:
		return
	if mode == Mode.FOLLOW_PLAYER and player:
		global_position = player.global_position
	_clamp_position()

func _unhandled_input(event: InputEvent) -> void:
	if map_paused:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
			if dragging:
				mode = Mode.FREE
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var change := zoom_step if event.button_index == MOUSE_BUTTON_WHEEL_UP else -zoom_step
			zoom = Vector2.ONE * clampf(zoom.x + change, zoom_min, zoom_max)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging:
		global_position -= event.relative / zoom
		_clamp_position()
		get_viewport().set_input_as_handled()

func _clamp_position() -> void:
	var allowed := bounds.grow(camera_margin)
	global_position = global_position.clamp(allowed.position, allowed.end)

func focus_on_player() -> void:
	if map_paused:
		return
	mode = Mode.FOLLOW_PLAYER
	dragging = false
	if player:
		global_position = player.global_position
