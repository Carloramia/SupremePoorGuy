extends Node

## Moves this component's Node3D parent left or right relative to the first
## Camera3D found under the same parent level.

@export_range(0.0, 100.0, 0.1, "or_greater") var movement_speed: float = 3.0
@export var input_enabled: bool = true

@export_group("Debug")
## Pauses once after the component searches for its camera.
@export var break_on_ready: bool = false
## Pauses once when A or D first produces movement input.
@export var break_on_first_movement: bool = false
@export var trace_keyboard_input: bool = true

var _camera: Camera3D
var _warned_about_parent: bool = false
var _warned_about_camera: bool = false
var _movement_break_triggered: bool = false
var _debug_output: Node
var _last_input_axis: float = 0.0
var _trace_elapsed: float = 0.0

func _ready() -> void:
	_debug_output = _find_debug_output()
	_refresh_camera()
	_trace("Receiver ready; parent=%s" % _describe_node(get_parent()))
	_trace("Selected camera=%s" % _describe_node(_camera))
	if _camera != null and get_parent().is_ancestor_of(_camera):
		_trace("WARNING: Camera is inside the moving parent; camera and parent will move together.")
	if break_on_ready:
		breakpoint

func _physics_process(delta: float) -> void:
	if not input_enabled:
		return

	var target := get_parent() as Node3D
	if target == null:
		if not _warned_about_parent:
			push_warning("KeyboardMovementReceiver3D requires a Node3D parent.")
			_warned_about_parent = true
		return

	if not is_instance_valid(_camera):
		_refresh_camera()
	if _camera == null:
		return

	var left_pressed := Input.is_action_pressed("Left")
	var right_pressed := Input.is_action_pressed("Right")
	var input_axis := 0.0
	if right_pressed:
		input_axis += 1.0
	if left_pressed:
		input_axis -= 1.0
	_trace_elapsed += delta
	if not is_equal_approx(input_axis, _last_input_axis):
		_trace("Actions: Left=%s Right=%s axis=%.1f" % [
			left_pressed, right_pressed, input_axis])
		_last_input_axis = input_axis
	if is_zero_approx(input_axis):
		return
	if break_on_first_movement and not _movement_break_triggered:
		_movement_break_triggered = true
		breakpoint
	var before := target.global_position
	_move_parent(input_axis, delta)
	if _trace_elapsed >= 0.25:
		_trace_elapsed = 0.0
		_trace("Move: %s -> %s; camera_right=%s" % [
			before, target.global_position, _camera.global_basis.x])


func _move_parent(input_axis: float, delta: float) -> void:
	var target := get_parent() as Node3D
	if target == null or _camera == null:
		return
	# Ignore camera roll/pitch on the vertical axis so the parent remains on
	# the horizontal XZ movement plane.
	var camera_right := _camera.global_basis.x
	camera_right.y = 0.0
	if camera_right.is_zero_approx():
		return
	camera_right = camera_right.normalized()
	target.global_position += camera_right * input_axis * movement_speed * delta

func _refresh_camera() -> void:
	_camera = null
	var parent := get_parent()
	if parent == null:
		return
	for sibling in parent.get_children():
		if sibling == self:
			continue
		_camera = _find_first_camera(sibling)
		if _camera != null:
			_warned_about_camera = false
			return
	_camera = get_viewport().get_camera_3d()
	if _camera != null:
		_warned_about_camera = false
		return
	if not _warned_about_camera:
		push_warning("KeyboardMovementReceiver3D could not find a Camera3D at its parent level.")
		_warned_about_camera = true

func _find_first_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node as Camera3D
	for child in node.get_children():
		var camera := _find_first_camera(child)
		if camera != null:
			return camera
	return null

func get_camera() -> Camera3D:
	return _camera

func refresh_camera() -> void:
	_refresh_camera()
	_trace("Camera refreshed: %s" % _describe_node(_camera))

func _find_debug_output() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	for sibling in parent.get_children():
		if sibling != self and sibling.has_method(&"log_line"):
			return sibling
	return null

func _trace(message: String) -> void:
	if not trace_keyboard_input:
		return
	if is_instance_valid(_debug_output):
		_debug_output.call(&"log_line", message)
	else:
		print("[KeyboardMovementReceiver3D] ", message)

func _describe_node(node: Node) -> String:
	if node == null:
		return "<null>"
	return "%s (%s)" % [node.get_path(), node.get_class()]
