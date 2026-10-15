class_name ScenarioCameraController
extends Node3D

signal camera_focus_requested(target: Node3D)
@export var camera: Camera3D
@export var bounds_node: CameraBounds3D
@export var yaw_degrees: float = 0.0
@export var pitch_degrees: float = -50.0
@export var distance: float = 30.0
var definition: SceneDefinition
var target_camera_size: float = 20.0
var target_position: Vector3
var input_enabled: bool = true
var dragging: bool = false
var focus_target: Node3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not camera:
		camera = Camera3D.new()
		add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.rotation_degrees = Vector3(pitch_degrees, yaw_degrees, 0)
	camera.position = camera.basis.z * distance
	camera.current = true
	target_position = position
	get_viewport().size_changed.connect(_clamp_targets)

func configure(value: SceneDefinition) -> void:
	definition = value
	target_camera_size = clampf(value.default_camera_size, value.min_camera_size, value.max_camera_size)
	camera.size = target_camera_size
	_clamp_targets()

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not definition:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
			if not dragging:
				target_position = position
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var direction: float = -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			target_camera_size = clampf(target_camera_size + direction * definition.zoom_step, definition.min_camera_size, definition.max_camera_size)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragging:
		var before := ground_projection(event.position - event.relative)
		var after := ground_projection(event.position)
		target_position += before - after
		_clamp_targets()
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	# Receive release even over a UI panel, so a drag can never stick.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		dragging = false
		target_position = position

func ground_projection(screen: Vector2) -> Vector3:
	var ray_origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	if absf(direction.y) < 0.001:
		return position
	return ray_origin + direction * ((global_position.y - ray_origin.y) / direction.y)

func _process(delta: float) -> void:
	if not definition or not is_inside_tree():
		return
	camera.size = lerpf(camera.size, target_camera_size, 1.0 - exp(-definition.camera_zoom_smoothing * delta))
	_clamp_targets()
	if dragging:
		position = position.lerp(target_position, 1.0 - exp(-definition.camera_drag_smoothing * delta))
	position = clamp_position(position)

func clamp_position(value: Vector3) -> Vector3:
	if not definition or not is_inside_tree():
		return value
	var bounds: Rect2 = bounds_node.bounds if bounds_node else definition.camera_bounds
	var viewport_size := get_viewport().get_visible_rect().size
	var extents := Vector2.ZERO
	var zoom_ratio: float = maxf(camera.size, target_camera_size) / maxf(camera.size, 0.01)
	for corner in [Vector2.ZERO, Vector2(viewport_size.x, 0), viewport_size, Vector2(0, viewport_size.y)]:
		var offset := ground_projection(corner) - global_position
		extents.x = maxf(extents.x, absf(offset.x) * zoom_ratio)
		extents.y = maxf(extents.y, absf(offset.z) * zoom_ratio)
	var minimum := bounds.position + extents - Vector2.ONE * definition.camera_margin
	var maximum := bounds.end - extents + Vector2.ONE * definition.camera_margin
	var center := bounds.get_center()
	value.x = clampf(value.x, minimum.x, maximum.x) if minimum.x <= maximum.x else center.x
	value.z = clampf(value.z, minimum.y, maximum.y) if minimum.y <= maximum.y else center.y
	return value

func _clamp_targets() -> void:
	target_position = clamp_position(target_position)

func set_camera_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		dragging = false
		target_position = position

func set_focus_target(target: Node3D) -> void:
	focus_target = target

func focus_on_target() -> void:
	if not is_instance_valid(focus_target):
		push_warning("Camera focus target missing or freed")
		return
	position = clamp_position(Vector3(focus_target.global_position.x, position.y, focus_target.global_position.z))
	target_position = position
	camera_focus_requested.emit(focus_target)

func clear_focus_target() -> void:
	focus_target = null
