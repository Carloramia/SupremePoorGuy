extends Node3D

## Reusable 3D camera rig.
## Right drag orbits and the mouse wheel zooms.

@export_group("Controls")
@export var input_enabled: bool = true
@export var orbit_enabled: bool = true
@export var zoom_enabled: bool = true

@export_group("Follow")
## Optional target whose global position becomes this rig's orbit center.
@export var follow_target: Node3D

@export_group("Orbit")
@export_range(0.01, 2.0, 0.01, "or_greater") var orbit_speed_degrees: float = 0.25
@export_range(-89.0, 0.0, 0.1) var minimum_pitch_degrees: float = -80.0
@export_range(0.0, 89.0, 0.1) var maximum_pitch_degrees: float = -5.0

@export_group("Zoom")
@export_range(0.1, 1000.0, 0.1, "or_greater") var minimum_distance: float = 1.0
@export_range(0.1, 1000.0, 0.1, "or_greater") var maximum_distance: float = 50.0
@export_range(0.01, 1.0, 0.01, "or_greater") var zoom_step_ratio: float = 0.12

@onready var _pitch_pivot: Node3D = $PitchPivot
@onready var _camera: Camera3D = $PitchPivot/Camera3D

var _orbiting: bool = false
var _distance: float = 10.0
var _pitch_radians: float = 0.0

func _ready() -> void:
	_distance = clampf(_camera.position.z, minimum_distance, maximum_distance)
	_pitch_radians = _pitch_pivot.rotation.x
	_update_follow_position()
	_apply_camera_transform()

func _process(_delta: float) -> void:
	_update_follow_position()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return

	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT and orbit_enabled:
		_orbiting = event.pressed
		get_viewport().set_input_as_handled()
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP and zoom_enabled:
		_zoom(-1.0)
		get_viewport().set_input_as_handled()
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and zoom_enabled:
		_zoom(1.0)
		get_viewport().set_input_as_handled()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _orbiting and orbit_enabled:
		_orbit(event.relative)
		get_viewport().set_input_as_handled()

func _orbit(mouse_delta: Vector2) -> void:
	var sensitivity := deg_to_rad(orbit_speed_degrees)
	rotate_y(-mouse_delta.x * sensitivity)
	_pitch_radians = clampf(
		_pitch_radians - mouse_delta.y * sensitivity,
		deg_to_rad(minimum_pitch_degrees),
		deg_to_rad(maximum_pitch_degrees)
	)
	_pitch_pivot.rotation.x = _pitch_radians

func _zoom(direction: float) -> void:
	var change := maxf(_distance * zoom_step_ratio, 0.01)
	_distance = clampf(_distance + direction * change, minimum_distance, maximum_distance)
	_apply_camera_transform()

func _apply_camera_transform() -> void:
	_camera.position.z = _distance

func _update_follow_position() -> void:
	if is_instance_valid(follow_target):
		global_position = follow_target.global_position

func get_camera() -> Camera3D:
	return _camera

func set_distance(value: float) -> void:
	_distance = clampf(value, minimum_distance, maximum_distance)
	if is_node_ready():
		_apply_camera_transform()

func get_distance() -> float:
	return _distance
