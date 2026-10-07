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
## Autonomous NPCs use their enemy direction instead of the player's cursor.
@export var npc_target_turning_enabled: bool = true

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

@export_group("NPC Turn Stabilization")
@export_range(5.0, 60.0, 1.0) var npc_stabilization_angle: float = 20.0
@export_range(5.0, 90.0, 1.0) var npc_stabilization_exit_angle: float = 28.0
@export_range(0.0, 1.0, 0.01) var npc_stable_confirmation_time: float = 0.15
@export_range(0.1, 30.0, 0.1) var npc_yaw_braking_acceleration: float = 4.0
@export_range(0.1, 30.0, 0.1) var npc_yaw_velocity_gain: float = 8.0
@export_range(1.0, 45.0, 1.0) var npc_correction_start_angle: float = 8.0
@export_range(0.0, 1.0, 0.01) var npc_correction_confirmation_time: float = 0.2
@export_range(0.0, 1.0, 0.01) var npc_movement_resume_time: float = 0.25
@export_range(0.0, 1.0, 0.01) var npc_walking_correction_multiplier: float = 0.5
## Combat alignment is separate from the precision needed to finish a body turn.
@export_range(1.0, 45.0, 1.0) var npc_attack_angle_tolerance: float = 12.0
@export_range(0.0, 5.0, 0.01) var npc_attack_angular_speed: float = 0.75
@export_range(0.0, 1.0, 0.01) var npc_large_turn_movement_multiplier: float = 0.25
## Resume locomotion before the precision correction finishes; keep correcting while walking.
@export_range(4.0, 20.0, 0.5) var npc_walk_resume_angle: float = 12.0
@export_range(0.05, 1.0, 0.05) var npc_walk_resume_angular_speed: float = 0.5

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
var _npc_stabilizing := false
var _npc_stable_elapsed := 0.0
var _npc_correction_elapsed := 0.0
var _npc_retry_correction := false
var _recent_error := PI
var _npc_resume_elapsed := -1.0
var _npc_resume_start := 1.0
var _npc_walking_correction := false
var _yaw_bodies: Array[RigidBody3D] = []

func _npc_stabilization_active() -> bool:
	var npc := _get_autonomous_npc()
	return npc != null and npc.humanoid_xz_positioning

func _ready() -> void:
	add_to_group(&"physical_facing_controllers_3d")
	_resolve_dependencies()
	if unlock_character_yaw:
		_unlock_body_part_yaw()
	_capture_right_reference()
	if is_instance_valid(_torso):
		for node: Node in get_parent().find_children("*", "RigidBody3D", true, false):
			_yaw_bodies.append(node as RigidBody3D)
			if node is PhysicalBodyPart3D and 1 in node.tags:
				var leg := node as RigidBody3D
				_leg_offsets[leg] = _torso.global_basis.inverse() * (leg.global_position - _torso.global_position)
	_facing = FacingDirection.LEFT if initial_facing == FacingDirection.LEFT else FacingDirection.RIGHT
	if _facing == FacingDirection.LEFT:
		_right_reference = -_right_reference
	var npc := _get_autonomous_npc()
	if npc != null and npc.humanoid_xz_positioning:
		_right_reference = Vector3.RIGHT
	_last_raw_yaw = _get_raw_yaw()
	_unwrapped_yaw = _last_raw_yaw
	_target_yaw = _unwrapped_yaw
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	if console != null and console.has_method("is_turn_tracking_enabled"):
		diagnostic_logging = bool(console.call("is_turn_tracking_enabled"))

func _exit_tree() -> void:
	_release_turn_planning()

func _motion_setting(key: String, fallback: float) -> float:
	if _movement_controller != null and _movement_controller.has_method("_motion_setting"):
		return float(_movement_controller.call("_motion_setting", key, fallback))
	return fallback

func _planar_mode_active() -> bool:
	var actor := get_parent()
	return actor != null and actor.has_method("is_planar_mode_active") and actor.is_planar_mode_active()

func _physics_process(delta: float) -> void:
	_resolve_dependencies()
	var npc := _get_autonomous_npc()
	var autonomous_actor := get_parent().has_node("NPCStateMachine3D") and PLAYER_CONTEXT.controlled_character(self) != get_parent()
	if _planar_mode_active() or _motion_setting("turning_speed_degrees", 1.0) <= 0.0 or not turning_enabled or not _can_control_torso() or (npc == null and (autonomous_actor or not PLAYER_CONTEXT.input_allowed(self))):
		_release_turn_planning()
		_is_turning = false
		return
	_resolve_terrain_cursor()
	_update_continuous_yaw()
	_retry_remaining = maxf(_retry_remaining - delta, 0.0)
	if _npc_stabilization_active() and npc.current_state == npc.State.ATTACK:
		if _is_turning:
			_is_turning = false
			_release_turn_planning()
		return
	_try_request_turn_from_cursor(delta)
	if _npc_stabilization_active():
		_update_npc_stabilization(delta)
	_check_turn_completion()
	if _is_turning:
		_update_movement_lead()
		_update_turn_steps()
		_apply_leg_traction()
		_update_turn_watchdog(delta)
	elif _npc_stabilization_active() or absf(get_turn_angle_error()) > deg_to_rad(completion_angle_degrees):
		_apply_leg_traction()

func request_facing(target_facing: FacingDirection) -> bool:
	if _planar_mode_active() or not _can_control_torso() or (target_facing == _facing and _is_turning):
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
	_recent_error = _best_error
	_npc_stabilizing = false
	_npc_stable_elapsed = 0.0
	_npc_correction_elapsed = 0.0
	_npc_retry_correction = false
	_npc_resume_elapsed = -1.0
	_npc_walking_correction = false
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
	if _npc_stabilization_active():
		_movement_multiplier = minf(_movement_multiplier, npc_large_turn_movement_multiplier)
		var blend := smoothstep(deg_to_rad(completion_angle_degrees), deg_to_rad(npc_stabilization_angle * 2.0), absf(get_turn_angle_error()))
		_movement_multiplier *= blend
		if _npc_stabilizing: _movement_multiplier = 0.0
	_movement_controller.call("set_turn_movement_multiplier", _movement_multiplier)
	if not bool(_movement_controller.get("input_enabled")):
		return
	var direction: Vector3 = _movement_controller.call("get_input_movement_direction")
	var speed: float = _movement_controller.call("get_expected_horizontal_speed")
	_movement_lead = direction.slide(_get_turn_axis()) * speed * _motion_setting("turn_step_duration", turn_step_duration)

func _try_request_turn_from_cursor(delta: float) -> void:
	var npc := _get_autonomous_npc()
	var direction := Vector3.ZERO
	if npc != null:
		# Preserve the established body heading throughout charge and follow-through.
		if npc.current_state == npc.State.ATTACK:
			return
		direction = npc.get_npc_body_facing_direction()
	elif _is_cursor_available():
		var cursor_position := terrain_cursor.global_position
		if terrain_cursor.has_method("get_target_ground_position"):
			cursor_position = terrain_cursor.call("get_target_ground_position")
		direction = (cursor_position - _torso.global_position).slide(_get_turn_axis())
	if direction.is_zero_approx():
		_candidate_facing = -1
		_candidate_elapsed = 0.0
		return
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
		elif not _is_turning:
			if _npc_stabilization_active():
				# An attack waiting on heading must not remain in the 4–8 degree
				# correction dead band. Confirmation still filters brief drift.
				var attack_waiting: bool = npc._attack_block_reason == &"body_turn_pending"
				var threshold := completion_angle_degrees if _npc_retry_correction or attack_waiting else maxf(npc_correction_start_angle, completion_angle_degrees + 1.0)
				_npc_correction_elapsed = _npc_correction_elapsed + delta if absf(get_turn_angle_error()) > deg_to_rad(threshold) else 0.0
				if _npc_correction_elapsed >= npc_correction_confirmation_time and (attack_waiting or absf(get_turn_angle_error()) > deg_to_rad(npc_stabilization_exit_angle)):
					request_facing(_facing)
			elif absf(get_turn_angle_error()) > deg_to_rad(full_turn_recovery_angle_degrees):
				request_facing(_facing)

func _update_npc_stabilization(delta: float) -> void:
	if not _is_turning:
		var correcting := absf(get_turn_angle_error()) > deg_to_rad(completion_angle_degrees) or absf(_torso.angular_velocity.dot(_get_turn_axis())) > completion_angular_speed
		if correcting != _npc_walking_correction:
			_npc_walking_correction = correcting
			_log_turn("walking_correction" if correcting else "walking_aligned")
		if _npc_resume_elapsed >= 0.0 and is_instance_valid(_movement_controller):
			# Completion already confirmed quiet Torso motion. Limb jitter must not
			# indefinitely suspend the locomotion ramp; heading correction continues.
			_npc_resume_elapsed += delta
			var blend := clampf(_npc_resume_elapsed / maxf(npc_movement_resume_time,0.001),0.0,1.0)
			_movement_multiplier = lerpf(_npc_resume_start,1.0,blend)
			_movement_controller.set_turn_movement_multiplier(_movement_multiplier)
			if blend >= 1.0: _npc_resume_elapsed = -1.0
		if is_instance_valid(_movement_controller):
			# Minor heading drift is corrected while walking, without changing
			# the step planner or repeatedly stopping navigation.
			if correcting:
				_movement_multiplier = minf(_movement_multiplier, npc_walking_correction_multiplier) if _npc_resume_elapsed >= 0.0 else npc_walking_correction_multiplier
			elif _npc_resume_elapsed < 0.0:
				_movement_multiplier = 1.0
			_movement_controller.set_turn_movement_multiplier(_movement_multiplier)
		return
	var error := absf(get_turn_angle_error())
	var was_stabilizing := _npc_stabilizing
	if not _npc_stabilizing and error <= deg_to_rad(npc_stabilization_angle): _npc_stabilizing = true
	elif _npc_stabilizing and error > deg_to_rad(maxf(npc_stabilization_exit_angle,npc_stabilization_angle+1.0)): _npc_stabilizing = false
	if was_stabilizing != _npc_stabilizing: _log_turn("stabilizing" if _npc_stabilizing else "large_correction")
	var quiet := error <= deg_to_rad(maxf(completion_angle_degrees,npc_walk_resume_angle)) and absf(_torso.angular_velocity.dot(_get_turn_axis())) <= maxf(completion_angular_speed,npc_walk_resume_angular_speed)
	_npc_stable_elapsed = _npc_stable_elapsed + delta if quiet else 0.0

func _get_autonomous_npc() -> Node:
	if PLAYER_CONTEXT.controlled_character(self) == get_parent(): return null
	var npc := get_parent().get_node_or_null("NPCStateMachine3D")
	if npc == null or not npc_target_turning_enabled or not npc.enabled or not npc._character_enabled: return null
	return npc

## Called before attack prediction: Arm aiming must not substitute for a body turn.
func is_npc_facing_ready(direction: Vector3) -> bool:
	if not npc_target_turning_enabled or not turning_enabled or _planar_mode_active(): return true
	if not _can_control_torso(): return false
	var desired := -1
	if is_direction_in_facing_sector(direction, FacingDirection.LEFT): desired = FacingDirection.LEFT
	elif is_direction_in_facing_sector(direction, FacingDirection.RIGHT): desired = FacingDirection.RIGHT
	if desired >= 0 and desired != _facing: return false
	if _npc_stabilization_active():
		var step_idle := not is_instance_valid(_movement_controller) or int(_movement_controller.get_step_state()) == 0
		# Hand over a small correction to Arm aiming only between foot swings.
		return (not _is_turning or (_npc_stabilizing and step_idle)) and absf(get_turn_angle_error()) <= deg_to_rad(npc_attack_angle_tolerance) and absf(_torso.angular_velocity.dot(_get_turn_axis())) <= npc_attack_angular_speed
	return not _is_turning and absf(get_turn_angle_error()) <= deg_to_rad(completion_angle_degrees) and absf(_torso.angular_velocity.dot(_get_turn_axis())) <= completion_angular_speed

func _check_turn_completion() -> void:
	var axis := _get_turn_axis()
	var angle_error := get_turn_angle_error()
	var yaw_speed := _torso.angular_velocity.dot(axis)
	var npc_mode := _npc_stabilization_active()
	var angle_limit := maxf(completion_angle_degrees,npc_walk_resume_angle) if npc_mode else completion_angle_degrees
	var speed_limit := maxf(completion_angular_speed,npc_walk_resume_angular_speed) if npc_mode else completion_angular_speed
	if (
		_is_turning
		and absf(angle_error) <= deg_to_rad(angle_limit)
		and absf(yaw_speed) <= speed_limit
		and (not is_instance_valid(_movement_controller) or int(_movement_controller.call("get_step_state")) == 0)
		and (not _npc_stabilization_active() or _npc_stable_elapsed >= npc_stable_confirmation_time)
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
	var grounded_count := 0
	if _npc_stabilization_active() and is_instance_valid(_movement_controller):
		for foot: RigidBody3D in _leg_offsets:
			if is_instance_valid(foot) and not (foot is PhysicalBodyPart3D and foot.is_broken) and not _movement_controller.is_leg_stepping(foot) and _movement_controller.is_leg_grounded(foot):
				grounded_count += 1
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
			var pull := (leg.global_position - rest - common_offset).dot(tangent) * _motion_setting("turn_gain", leg_torso_traction_strength / maxf(_torso.mass, 0.001)) * _torso.mass
			pull -= speed * lever.length() * _motion_setting("turn_damping", leg_torso_traction_damping / maxf(_torso.mass, 0.001)) * _torso.mass
			if _npc_stabilization_active():
				var error := get_turn_angle_error()
				var desired_speed := signf(error) * minf(maximum_yaw_speed, minf(sqrt(2.0*npc_yaw_braking_acceleration*absf(error)),absf(error)*4.0))
				if not _is_turning or speed * signf(error) < 0.0 or speed * signf(error) > absf(desired_speed):
					# Corrective force is authorized only by a grounded stance foot.
					var acceleration := clampf((desired_speed-speed) * npc_yaw_velocity_gain, -npc_yaw_braking_acceleration, npc_yaw_braking_acceleration)
					pull = acceleration * _npc_yaw_inertia() / (maxi(grounded_count, 1) * maxf(lever.length(), 0.1))
			if absf(speed) >= deg_to_rad(_motion_setting("turning_speed_degrees", rad_to_deg(maximum_yaw_speed))) and signf(pull) == signf(speed):
				pull = -speed * lever.length() * _motion_setting("turn_damping", leg_torso_traction_damping / maxf(_torso.mass, 0.001)) * _torso.mass
			var traction := tangent * clampf(pull, -_motion_setting("turn_acceleration", maximum_leg_torso_traction / maxf(_torso.mass, 0.001)) * _torso.mass, _motion_setting("turn_acceleration", maximum_leg_torso_traction / maxf(_torso.mass, 0.001)) * _torso.mass)
			_torso.apply_force(traction, lever)
			net_traction += traction
			_traction_torque += lever.cross(traction).dot(axis)

	# A force couple transfers Leg-derived yaw without adding a net walking force.
	_torso.apply_central_force(-net_traction)

func _npc_yaw_inertia() -> float:
	var inertia := 0.0
	for body: RigidBody3D in _yaw_bodies:
		if is_instance_valid(body) and not (body is PhysicalBodyPart3D and body.is_broken):
			var radius := (body.global_position - _torso.global_position).slide(_get_turn_axis())
			inertia += body.mass * (radius.length_squared() + 0.25)
	return maxf(inertia, _torso.mass * 0.25)

func _update_turn_steps() -> void:
	if not turning_steps_enabled or not is_instance_valid(_movement_controller):
		return
	if not _movement_controller.has_method("try_start_turn_step") or int(_movement_controller.call("get_step_state")) != 0:
		return
	var error := get_turn_angle_error()
	if _npc_stabilization_active() and _npc_stabilizing:
		var has_support := false
		for foot: RigidBody3D in _leg_offsets:
			if is_instance_valid(foot) and not (foot is PhysicalBodyPart3D and foot.is_broken) and _movement_controller.is_leg_grounded(foot): has_support = true
		# Existing swings finish normally. Request small correction steps only if
		# planted feet cannot settle the heading, or support needs restoring.
		if has_support and absf(error) <= deg_to_rad(completion_angle_degrees): return
	if absf(error) <= deg_to_rad(completion_angle_degrees):
		return
	var legs: Array[RigidBody3D] = []
	for leg: RigidBody3D in _leg_offsets:
		if is_instance_valid(leg) and not (leg is PhysicalBodyPart3D and leg.is_broken):
			legs.append(leg)
	if legs.is_empty():
		return
	var axis := _get_turn_axis()
	var predicted_error := error - _torso.angular_velocity.dot(axis) * _motion_setting("turn_step_duration", turn_step_duration)
	var right := _torso.global_basis.x.slide(axis).normalized().rotated(axis, clampf(predicted_error, -deg_to_rad(_motion_setting("turn_step_angle", turn_step_angle_degrees)), deg_to_rad(_motion_setting("turn_step_angle", turn_step_angle_degrees))))
	var basis := Basis(right, axis, right.cross(axis)).orthonormalized()
	for offset: int in legs.size():
		var index := (_turn_leg_index + offset) % legs.size()
		var leg := legs[index]
		var target := _torso.global_position + _movement_lead + basis * _leg_offsets[leg]
		for attempt: int in range(3 if _npc_stabilization_active() else 1):
			if attempt > 0:
				# A rejected long landing must not permanently exclude one foot.
				# Reduce the angular excursion and exclude chase translation.
				var excursion := clampf(predicted_error, -deg_to_rad(_motion_setting("turn_step_angle", turn_step_angle_degrees)), deg_to_rad(_motion_setting("turn_step_angle", turn_step_angle_degrees)))
				var reduced := _current_turn_basis(axis, excursion * pow(0.5, attempt))
				target = _torso.global_position + reduced * _leg_offsets[leg]
			_planned_target = target
			if bool(_movement_controller.call("try_start_turn_step", leg, target, _motion_setting("turn_step_duration", turn_step_duration), _motion_setting("turn_lift", turn_step_height))):
				_turn_leg_index = (index + 1) % legs.size()
				_planned_target = _movement_controller.call("get_step_target")
				_log_turn("step_started_" + String(leg.name))
				return
			var reason: StringName = _movement_controller.get_turn_step_rejection_reason()
			if diagnostic_logging and _log_elapsed >= diagnostic_interval - 0.02:
				print("[turnmotion_landing] character=%s leg=%s attempt=%d sample=%s reason=%s" % [get_parent().name, leg.name, attempt, target, reason])
			if reason not in [&"hip_target_out_of_reach", &"horizontal_reach_exceeded"]: break
	# Throttled progress logs distinguish no legal landing from a slow physical turn.
	if _log_elapsed >= diagnostic_interval - 0.02:
		_log_turn("landing_rejected_all_legs")

func _current_turn_basis(axis: Vector3, error: float) -> Basis:
	var right := _torso.global_basis.x.slide(axis).normalized().rotated(axis, clampf(error, -deg_to_rad(_motion_setting("turn_step_angle", turn_step_angle_degrees)), deg_to_rad(_motion_setting("turn_step_angle", turn_step_angle_degrees))))
	return Basis(right, axis, right.cross(axis)).orthonormalized()

func _update_turn_watchdog(delta: float) -> void:
	_turn_elapsed += delta
	_no_progress_elapsed += delta
	_log_elapsed += delta
	var error := absf(get_turn_angle_error())
	if error < _best_error - deg_to_rad(2.0):
		_best_error = error
		_no_progress_elapsed = 0.0
	if _npc_stabilization_active():
		if error < _recent_error - deg_to_rad(0.5):
			_no_progress_elapsed = 0.0
			_recent_error = error
		elif error > _recent_error: _recent_error = error
	if _log_elapsed >= diagnostic_interval:
		_log_elapsed = 0.0
		_log_turn("progress")
	if _turn_elapsed >= _motion_setting("turn_timeout", maximum_turn_duration) or _no_progress_elapsed >= no_progress_timeout:
		_is_turning = false
		_retry_remaining = 1.0
		_npc_retry_correction = _npc_stabilization_active() and error > deg_to_rad(completion_angle_degrees)
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
	print("[turnmotion] character=%s event=%s target=%s actual_deg=%.2f target_deg=%.2f error_deg=%.2f cursor_dot=%.3f candidate=%d confirm=%.3f input=%s movement_multiplier=%.3f center_lead=%s planned_target=%s step_state=%s leg=%s yaw_speed=%.3f leg_traction_torque=%.3f elapsed=%.2f no_progress=%.2f npc_phase=%s stable_time=%.2f retry_correction=%s resume_elapsed=%.2f resume_duration=%.2f resume_angle=%.2f" % [
		get_parent().name, event, "RIGHT" if _facing == FacingDirection.RIGHT else "LEFT",
		rad_to_deg(_unwrapped_yaw), rad_to_deg(_target_yaw), rad_to_deg(get_turn_angle_error()),
		_cursor_dot, _candidate_facing, _candidate_elapsed, direction, _movement_multiplier,
		_movement_lead, _planned_target, state, active_leg, _torso.angular_velocity.dot(_get_turn_axis()),
		_traction_torque, _turn_elapsed, _no_progress_elapsed,
		("stabilizing" if _npc_stabilizing else "turning") if _is_turning else ("walking_correction" if _npc_walking_correction else "idle"),
		_npc_stable_elapsed, _npc_retry_correction, _npc_resume_elapsed, npc_movement_resume_time, npc_walk_resume_angle])

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
	var resume := _npc_stabilization_active() and _movement_multiplier < 1.0
	var previous_multiplier := _movement_multiplier
	if is_instance_valid(_movement_controller):
		_movement_controller.call("set_turn_planning_active", false)
		_movement_controller.call("set_turn_movement_multiplier", previous_multiplier if resume else 1.0)
	_movement_lead = Vector3.ZERO
	_movement_multiplier = previous_multiplier if resume else 1.0
	if resume:
		_npc_resume_elapsed = 0.0
		_npc_resume_start = previous_multiplier

