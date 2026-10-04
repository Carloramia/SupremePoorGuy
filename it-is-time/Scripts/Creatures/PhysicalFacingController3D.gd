class_name PhysicalFacingController3D
extends Node

const PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")

signal turn_started(target_facing: FacingDirection)
signal turn_completed(current_facing: FacingDirection)

enum FacingDirection {
	RIGHT,
	LEFT,
}

@export_group("Control")
@export var turning_enabled: bool = true
@export_enum("Right", "Left") var initial_facing: int = FacingDirection.RIGHT
@export_range(1.0, 179.0, 1.0) var sector_angle_degrees: float = 120.0
@export_range(0.0, 10.0, 0.01, "or_greater") var cursor_dead_zone: float = 0.5
@export_range(0.0, 1.0, 0.01) var facing_confirmation_time: float = 0.1
@export_range(0.0, 30.0, 1.0) var walking_correction_angle_degrees: float = 10.0
@export_range(15.0, 90.0, 1.0) var full_turn_recovery_angle_degrees: float = 45.0
@export var terrain_cursor: Node3D
@export var terrain_cursor_group: StringName = &"terrain_cursor_3d"

@export_group("Bodies")
@export var torso_path: NodePath = NodePath("../Torso")
@export var movement_controller_path: NodePath = NodePath("../LegStepMovementController3D")
@export var unlock_character_yaw: bool = true
@export_range(0.0, 1.0, 0.01) var turning_movement_multiplier: float = 0.5

@export_group("Physical Turn")
@export var turn_axis: Vector3 = Vector3.UP
@export_range(0.1, 20.0, 0.1, "or_greater") var maximum_yaw_speed: float = 4.0
@export_range(0.1, 30.0, 0.1) var completion_angle_degrees: float = 4.0
@export_range(0.0, 5.0, 0.01, "or_greater") var completion_angular_speed: float = 0.25

@export_group("Ground Turn Assist")
@export_range(0.1, 30.0, 0.1) var maximum_turn_duration: float = 8.0
@export_range(0.1, 10.0, 0.1) var no_progress_timeout: float = 2.0
@export var diagnostic_logging: bool = true
@export_range(0.1, 5.0, 0.1) var diagnostic_interval: float = 0.5

@export_group("Turning Steps")
@export var turning_steps_enabled: bool = true
@export_range(1.0, 90.0, 1.0) var turn_step_angle_degrees: float = 35.0
@export_range(0.05, 2.0, 0.01) var turn_step_duration: float = 0.22
@export_range(0.0, 2.0, 0.01) var turn_step_height: float = 0.4
@export_range(0.0, 500.0, 1.0) var leg_torso_traction_strength: float = 200.0
@export_range(0.0, 200.0, 1.0) var leg_torso_traction_damping: float = 45.0
@export_range(0.0, 1000.0, 1.0) var maximum_leg_torso_traction: float = 200.0

var _torso: RigidBody3D
var _movement_controller: Node
var _right_reference: Vector3 = Vector3.RIGHT
var _facing: FacingDirection = FacingDirection.RIGHT
var _is_turning: bool = false
var _preferred_turn_sign: float = 1.0
var _candidate_facing: int = -1
var _candidate_elapsed: float = 0.0
var _unwrapped_yaw: float = 0.0
var _last_raw_yaw: float = 0.0
var _target_yaw: float = 0.0
var _retry_remaining: float = 0.0
var _movement_lead: Vector3 = Vector3.ZERO
var _planned_target: Vector3 = Vector3.ZERO
var _cursor_dot: float = 0.0
var _movement_multiplier: float = 1.0
var _turn_elapsed: float = 0.0
var _no_progress_elapsed: float = 0.0
var _best_error: float = PI
var _log_elapsed: float = 0.0
var _leg_offsets: Dictionary[RigidBody3D, Vector3] = {}
var _turn_leg_index: int = 0
var _traction_torque: float = 0.0

func _ready() -> void:
	add_to_group(&"physical_facing_controllers_3d")
	_resolve_dependencies()
	if unlock_character_yaw:
		_unlock_body_part_yaw()
	_capture_right_reference()
	if is_instance_valid(_torso):
		for node: Node in get_parent().find_children("*", "RigidBody3D", true, false):
			if node is PhysicalBodyPart3D and 1 in node.tags:
				var leg := node as RigidBody3D
				_leg_offsets[leg] = _torso.global_basis.inverse() * (leg.global_position - _torso.global_position)
	_facing = FacingDirection.LEFT if initial_facing == FacingDirection.LEFT else FacingDirection.RIGHT
	if _facing == FacingDirection.LEFT:
		_right_reference = -_right_reference
	_last_raw_yaw = _get_raw_yaw()
	_unwrapped_yaw = _last_raw_yaw
	_target_yaw = _unwrapped_yaw
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	if console != null and console.has_method("is_turn_tracking_enabled"):
		diagnostic_logging = bool(console.call("is_turn_tracking_enabled"))

func _exit_tree() -> void:
	_release_turn_planning()

func _physics_process(delta: float) -> void:
	_resolve_dependencies()
	if not turning_enabled or not _can_control_torso() or not PLAYER_CONTEXT.input_allowed(self):
		_release_turn_planning()
		_is_turning = false
		return
	_resolve_terrain_cursor()
	_update_continuous_yaw()
	_retry_remaining = maxf(_retry_remaining - delta, 0.0)
	_try_request_turn_from_cursor(delta)
	_check_turn_completion()
	if _is_turning:
		_update_movement_lead()
		_update_turn_steps()
		_apply_leg_traction()
		_update_turn_watchdog(delta)
	elif absf(get_turn_angle_error()) > deg_to_rad(completion_angle_degrees):
		_apply_leg_traction()

func request_facing(target_facing: FacingDirection) -> bool:
	if not _can_control_torso() or (target_facing == _facing and _is_turning):
		return false
	if target_facing == _facing and absf(get_turn_angle_error()) <= deg_to_rad(completion_angle_degrees):
		return false
	var retarget := _is_turning
	_facing = target_facing
	_preferred_turn_sign = 1.0 if target_facing == FacingDirection.LEFT else -1.0
	var raw_target := PI if target_facing == FacingDirection.LEFT else 0.0
	var difference := wrapf(raw_target - _unwrapped_yaw, -PI, PI)
	if absf(absf(difference) - PI) < 0.01:
		difference = PI * _preferred_turn_sign
	_target_yaw = _unwrapped_yaw + difference
	_is_turning = true
	# One planner owns landing targets; input and torso feedback remain enabled.
	if not retarget and is_instance_valid(_movement_controller):
		_movement_controller.call("set_turn_planning_active", true)
		_turn_leg_index = 0
	_turn_elapsed = 0.0
	_traction_torque = 0.0
	_no_progress_elapsed = 0.0
	_log_elapsed = 0.0
	_best_error = absf(get_turn_angle_error())
	_log_turn("retargeted" if retarget else "started")
	turn_started.emit(_facing)
	return true

func get_facing() -> FacingDirection:
	return _facing

func is_turning() -> bool:
	return _is_turning

func get_right_reference() -> Vector3:
	return _right_reference

func get_walking_heading_correction() -> float:
	if not turning_enabled or _is_turning or not _can_control_torso():
		return 0.0
	return clampf(get_turn_angle_error(), -deg_to_rad(walking_correction_angle_degrees), deg_to_rad(walking_correction_angle_degrees))

func get_target_facing_direction() -> Vector3:
	return _right_reference if _facing == FacingDirection.RIGHT else -_right_reference

func is_direction_in_facing_sector(
	direction: Vector3,
	target_facing: FacingDirection
) -> bool:
	var axis := _get_turn_axis()
	var horizontal_direction := direction.slide(axis)
	if horizontal_direction.length_squared() <= cursor_dead_zone * cursor_dead_zone:
		return false
	horizontal_direction = horizontal_direction.normalized()
	var reference := _right_reference if target_facing == FacingDirection.RIGHT else -_right_reference
	var half_angle := deg_to_rad(clampf(sector_angle_degrees, 1.0, 179.0) * 0.5)
	return horizontal_direction.dot(reference) >= cos(half_angle)

func get_turn_angle_error() -> float:
	if not is_instance_valid(_torso):
		return 0.0
	if _is_turning:
		return _target_yaw - _unwrapped_yaw
	var target := PI if _facing == FacingDirection.LEFT else 0.0
	return wrapf(target - _get_raw_yaw(), -PI, PI)

func _get_raw_yaw() -> float:
	if not is_instance_valid(_torso):
		return 0.0
	var current := _torso.global_basis.x.slide(_get_turn_axis()).normalized()
	return atan2(_get_turn_axis().dot(_right_reference.cross(current)), _right_reference.dot(current))

func _update_continuous_yaw() -> void:
	var raw := _get_raw_yaw()
	_unwrapped_yaw += wrapf(raw - _last_raw_yaw, -PI, PI)
	_last_raw_yaw = raw

func _update_movement_lead() -> void:
	_movement_lead = Vector3.ZERO
	if not is_instance_valid(_movement_controller):
		return
	var remaining := clampf(absf(get_turn_angle_error()) / PI, 0.0, 1.0)
	_movement_multiplier = lerpf(1.0, turning_movement_multiplier, remaining)
	_movement_controller.call("set_turn_movement_multiplier", _movement_multiplier)
	if not bool(_movement_controller.get("input_enabled")):
		return
	var direction: Vector3 = _movement_controller.call("get_input_movement_direction")
	var speed: float = _movement_controller.call("get_expected_horizontal_speed")
	_movement_lead = direction.slide(_get_turn_axis()) * speed * turn_step_duration

func _try_request_turn_from_cursor(delta: float) -> void:
	if not _is_cursor_available():
		_candidate_facing = -1
		_candidate_elapsed = 0.0
		return
	var cursor_position := terrain_cursor.global_position
	if terrain_cursor.has_method("get_target_ground_position"):
		cursor_position = terrain_cursor.call("get_target_ground_position")
	var direction := (cursor_position - _torso.global_position).slide(_get_turn_axis())
	var candidate: int = -1
	_cursor_dot = 0.0 if direction.is_zero_approx() else direction.normalized().dot(_right_reference)
	if is_direction_in_facing_sector(direction, FacingDirection.LEFT):
		candidate = FacingDirection.LEFT
	elif is_direction_in_facing_sector(direction, FacingDirection.RIGHT):
		candidate = FacingDirection.RIGHT
	if candidate != _candidate_facing:
		_candidate_facing = candidate
		_candidate_elapsed = 0.0
		_log_turn("cursor_candidate_changed")
	if candidate < 0:
		return
	_candidate_elapsed += delta
	if _candidate_elapsed >= facing_confirmation_time and _retry_remaining <= 0.0:
		if candidate != _facing:
			request_facing(candidate as FacingDirection)
		elif not _is_turning and absf(get_turn_angle_error()) > deg_to_rad(full_turn_recovery_angle_degrees):
			request_facing(_facing)

func _check_turn_completion() -> void:
	var axis := _get_turn_axis()
	var angle_error := get_turn_angle_error()
	var yaw_speed := _torso.angular_velocity.dot(axis)
	if (
		_is_turning
		and absf(angle_error) <= deg_to_rad(completion_angle_degrees)
		and absf(yaw_speed) <= completion_angular_speed
		and (not is_instance_valid(_movement_controller) or int(_movement_controller.call("get_step_state")) == 0)
	):
		_is_turning = false
		_release_turn_planning()
		_log_turn("completed")
		turn_completed.emit(_facing)

func _apply_leg_traction() -> void:
	_traction_torque = 0.0
	var axis := _get_turn_axis()
	var current_right := _torso.global_basis.x.slide(axis).normalized()
	var net_traction := Vector3.ZERO
	# Common translation is excluded from rotational traction, preserving walking direction.
	var common_offset := Vector3.ZERO
	var valid_count := 0
	var rest_basis := Basis(current_right, axis, current_right.cross(axis)).orthonormalized()
	for body: RigidBody3D in _leg_offsets:
		if is_instance_valid(body) and not (body is PhysicalBodyPart3D and body.is_broken):
			common_offset += (body.global_position - _torso.global_position - rest_basis * _leg_offsets[body]).slide(axis)
			valid_count += 1
	if valid_count > 0:
		common_offset /= float(valid_count)
	for leg: RigidBody3D in _leg_offsets:
		if not is_instance_valid(leg) or (leg is PhysicalBodyPart3D and leg.is_broken):
			continue
		if turning_steps_enabled and is_instance_valid(_movement_controller):
			if _movement_controller.call("is_leg_stepping", leg):
				continue
		if turning_steps_enabled and is_instance_valid(_movement_controller) and bool(_movement_controller.call("is_leg_grounded", leg)):
			var rest := _torso.global_position + Basis(current_right, axis, current_right.cross(axis)) * _leg_offsets[leg]
			var lever := (rest - _torso.global_position).slide(axis)
			var tangent := axis.cross(lever).normalized()
			var speed := _torso.angular_velocity.dot(axis)
			var pull := (leg.global_position - rest - common_offset).dot(tangent) * leg_torso_traction_strength
			pull -= speed * lever.length() * leg_torso_traction_damping
			if absf(speed) >= maximum_yaw_speed and signf(pull) == signf(speed):
				pull = -speed * lever.length() * leg_torso_traction_damping
			var traction := tangent * clampf(pull, -maximum_leg_torso_traction, maximum_leg_torso_traction)
			_torso.apply_force(traction, lever)
			net_traction += traction
			_traction_torque += lever.cross(traction).dot(axis)

	# A force couple transfers Leg-derived yaw without adding a net walking force.
	_torso.apply_central_force(-net_traction)

func _update_turn_steps() -> void:
	if not turning_steps_enabled or not is_instance_valid(_movement_controller):
		return
	if not _movement_controller.has_method("try_start_turn_step") or int(_movement_controller.call("get_step_state")) != 0:
		return
	var error := get_turn_angle_error()
	if absf(error) <= deg_to_rad(completion_angle_degrees):
		return
	var legs: Array[RigidBody3D] = []
	for leg: RigidBody3D in _leg_offsets:
		if is_instance_valid(leg) and not (leg is PhysicalBodyPart3D and leg.is_broken):
			legs.append(leg)
	if legs.is_empty():
		return
	var axis := _get_turn_axis()
	var predicted_error := error - _torso.angular_velocity.dot(axis) * turn_step_duration
	var right := _torso.global_basis.x.slide(axis).normalized().rotated(axis, clampf(predicted_error, -deg_to_rad(turn_step_angle_degrees), deg_to_rad(turn_step_angle_degrees)))
	var basis := Basis(right, axis, right.cross(axis)).orthonormalized()
	for offset: int in legs.size():
		var index := (_turn_leg_index + offset) % legs.size()
		var leg := legs[index]
		var target := _torso.global_position + _movement_lead + basis * _leg_offsets[leg]
		_planned_target = target
		if bool(_movement_controller.call("try_start_turn_step", leg, target, turn_step_duration, turn_step_height)):
			_turn_leg_index = (index + 1) % legs.size()
			_planned_target = _movement_controller.call("get_step_target")
			_log_turn("step_started_" + String(leg.name))
			return
	# Throttled progress logs distinguish no legal landing from a slow physical turn.
	if _log_elapsed >= diagnostic_interval - 0.02:
		_log_turn("landing_rejected_all_legs")

func _update_turn_watchdog(delta: float) -> void:
	_turn_elapsed += delta
	_no_progress_elapsed += delta
	_log_elapsed += delta
	var error := absf(get_turn_angle_error())
	if error < _best_error - deg_to_rad(2.0):
		_best_error = error
		_no_progress_elapsed = 0.0
	if _log_elapsed >= diagnostic_interval:
		_log_elapsed = 0.0
		_log_turn("progress")
	if _turn_elapsed >= maximum_turn_duration or _no_progress_elapsed >= no_progress_timeout:
		_is_turning = false
		_retry_remaining = 1.0
		if is_instance_valid(_movement_controller):
			_movement_controller.call("cancel_step", &"turn_timeout")
		_release_turn_planning()
		_log_turn("timeout")

func _log_turn(event: String) -> void:
	if not diagnostic_logging or not is_instance_valid(_torso):
		return
	var direction := Vector3.ZERO
	var state := "unavailable"
	var active_leg := "none"
	if is_instance_valid(_movement_controller):
		direction = _movement_controller.call("get_input_movement_direction")
		state = _movement_controller.call("get_step_state_name")
		var leg: RigidBody3D = _movement_controller.call("get_active_leg")
		if is_instance_valid(leg):
			active_leg = String(leg.name)
	print("[turnmotion] character=%s event=%s target=%s actual_deg=%.2f target_deg=%.2f error_deg=%.2f cursor_dot=%.3f candidate=%d confirm=%.3f input=%s movement_multiplier=%.3f center_lead=%s planned_target=%s step_state=%s leg=%s yaw_speed=%.3f leg_traction_torque=%.3f elapsed=%.2f no_progress=%.2f" % [
		get_parent().name, event, "RIGHT" if _facing == FacingDirection.RIGHT else "LEFT",
		rad_to_deg(_unwrapped_yaw), rad_to_deg(_target_yaw), rad_to_deg(get_turn_angle_error()),
		_cursor_dot, _candidate_facing, _candidate_elapsed, direction, _movement_multiplier,
		_movement_lead, _planned_target, state, active_leg, _torso.angular_velocity.dot(_get_turn_axis()),
		_traction_torque, _turn_elapsed, _no_progress_elapsed])

func _capture_right_reference() -> void:
	if not is_instance_valid(_torso):
		return
	var axis := _get_turn_axis()
	var candidate := _torso.global_basis.x.slide(axis)
	if candidate.is_zero_approx():
		candidate = Vector3.RIGHT.slide(axis)
	_right_reference = candidate.normalized()

func _unlock_body_part_yaw() -> void:
	var character := get_parent()
	if character == null:
		return
	for node: Node in character.find_children("*", "RigidBody3D", true, false):
		(node as RigidBody3D).axis_lock_angular_y = false

func _resolve_dependencies() -> void:
	if not is_instance_valid(_torso):
		_torso = get_node_or_null(torso_path) as RigidBody3D
	if not is_instance_valid(_movement_controller):
		_movement_controller = get_node_or_null(movement_controller_path)

func _resolve_terrain_cursor() -> void:
	if is_instance_valid(terrain_cursor):
		return
	terrain_cursor = get_tree().get_first_node_in_group(terrain_cursor_group) as Node3D

func _is_cursor_available() -> bool:
	if not is_instance_valid(terrain_cursor) or not terrain_cursor.visible:
		return false
	if terrain_cursor.has_method("is_gameplay_cursor_active"):
		if not bool(terrain_cursor.call("is_gameplay_cursor_active")):
			return false
	if terrain_cursor.has_method("has_valid_ground_position"):
		if not bool(terrain_cursor.call("has_valid_ground_position")):
			return false
	return true

func _can_control_torso() -> bool:
	if not is_instance_valid(_torso):
		return false
	return not (_torso is PhysicalBodyPart3D and (_torso as PhysicalBodyPart3D).is_broken)

func _get_turn_axis() -> Vector3:
	return turn_axis.normalized() if not turn_axis.is_zero_approx() else Vector3.UP

func set_diagnostic_logging_enabled(enabled: bool) -> void:
	diagnostic_logging = enabled
	_log_elapsed = 0.0

func _release_turn_planning() -> void:
	if is_instance_valid(_movement_controller):
		_movement_controller.call("set_turn_planning_active", false)
		_movement_controller.call("set_turn_movement_multiplier", 1.0)
	_movement_lead = Vector3.ZERO
	_movement_multiplier = 1.0

