extends Node

signal state_changed(previous: int, current: int)
enum State { STANDING, FALLEN, ESTABLISH_SUPPORT, RIGHTING, STABILIZING, RETRY }

@export_group("Recovery")
@export var enabled: bool = true:
	set(value):
		enabled = value
		if is_instance_valid(_movement): _movement.set_recovery_control_active(value and _character_enabled and state != State.STANDING)
@export var movement_controller_path: NodePath = NodePath("../GeneratedLegStepMovementController3D")
@export_group("Fall Detection")
@export_range(10.0, 90.0, 1.0) var fallen_angle_degrees: float = 60.0
@export_range(0.1, 0.9, 0.01) var fallen_height_ratio: float = 0.65
## Require a settled body for upright collapse detection; tilted falls still react immediately.
@export_range(0.1, 10.0, 0.1) var collapse_detection_speed: float = 2.0
@export_range(0.1, 3.0, 0.05) var fall_confirmation_duration: float = 0.5
@export_range(0.05, 2.0, 0.01) var contact_distance: float = 0.25
@export_group("Recovery Timing")
@export_range(0.0, 2.0, 0.05) var fallen_pause_duration: float = 0.25
@export_range(0.1, 10.0, 0.1) var support_setup_duration: float = 2.0
@export_range(1.0, 30.0, 0.1) var recovery_timeout: float = 8.0
@export_range(0.1, 10.0, 0.1) var retry_delay: float = 2.0
@export_range(0.1, 3.0, 0.05) var stable_confirmation_duration: float = 1.0
@export_group("Physical Recovery")
@export_range(0.0, 200.0, 0.1) var pose_strength: float = 40.0
@export_range(0.0, 50.0, 0.1) var pose_damping: float = 10.0
@export_range(0.0, 200.0, 0.1) var maximum_angular_acceleration: float = 60.0
@export_range(0.0, 2000.0, 1.0, "or_greater") var maximum_joint_torque: float = 10000.0
@export_range(0.0, 2000.0, 1.0, "or_greater") var maximum_torso_torque: float = 500.0
@export_range(0.0, 200.0, 0.1) var foot_strength: float = 30.0
@export_range(0.0, 50.0, 0.1) var foot_damping: float = 10.0
@export_range(0.0, 2000.0, 1.0, "or_greater") var maximum_foot_force: float = 3000.0
@export_range(0.0, 30.0, 0.1) var lift_strength: float = 8.0
@export_range(0.0, 30.0, 0.1) var lift_damping: float = 6.0
@export_range(0.0, 20.0, 0.1) var maximum_lift_acceleration: float = 6.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var maximum_total_lift_force: float = 20000.0
@export_range(0.1, 10.0, 0.1) var rise_speed: float = 1.5
@export_range(0.1, 1.0, 0.05) var minimum_support_ratio: float = 0.5
@export_range(1.0, 45.0, 1.0) var stable_angle_degrees: float = 15.0
@export_range(0.5, 1.0, 0.05) var stable_height_ratio: float = 0.9
@export_range(0.1, 10.0, 0.1) var stable_speed: float = 1.5

var state: State = State.STANDING
var _movement: Node
var _elapsed: float = 0.0
var _fall_elapsed: float = 0.0
var _stable_elapsed: float = 0.0
var _reference_height: float = 0.0
var _rise_height: float = 0.0
var _rest_offsets: Dictionary = {}
var _targets: Dictionary = {}
var _target_surfaces: Dictionary = {}
var _attempts: int = 0
var _attempt_elapsed: float = 0.0
var _metrics: Dictionary = {}
var _character_enabled: bool = true
var _log_elapsed: float = 0.0
var _last_lift_force: float = 0.0
var _lift_force_limited: bool = false

func _ready() -> void:
	add_to_group(&"creature_recovery_state_machines")
	refresh_physics_query_cache()

func refresh_physics_query_cache() -> void:
	_movement = get_node_or_null(movement_controller_path)
	if not is_instance_valid(_movement) or not _movement.has_method("set_recovery_control_active"):
		set_physics_process(false)
		return
	var damage := get_parent().get_node_or_null("CharacterDamageController3D")
	if damage != null and damage.has_method("is_character_disabled"):
		_character_enabled = not damage.is_character_disabled()
	_movement.set_recovery_control_active(false)
	state = State.STANDING
	_attempt_elapsed = 0.0
	_elapsed = 0.0
	_fall_elapsed = 0.0
	_stable_elapsed = 0.0
	_targets.clear()
	_target_surfaces.clear()
	_rest_offsets.clear()
	_attempts = 0
	var torsos: Array[RigidBody3D] = _movement.get_torso_parts()
	var feet: Array[RigidBody3D] = _movement.get_leg_parts()
	if torsos.is_empty() or feet.is_empty(): return
	var center := _torso_center(torsos)
	var up := _up()
	var floor_height := 0.0
	var yaw := _yaw_basis(up)
	for foot: RigidBody3D in feet:
		_rest_offsets[foot] = yaw.inverse() * (foot.global_position - center).slide(up)
		floor_height += _movement._get_foot_world_position(foot).dot(up)
	_reference_height = maxf(0.1, center.dot(up) - floor_height / float(feet.size()))
	set_physics_process(_character_enabled)

func set_character_control_enabled(value: bool) -> void:
	_character_enabled = value
	if not value and is_instance_valid(_movement): _movement.set_recovery_control_active(false)
	set_physics_process(value)

func _up() -> Vector3:
	var gravity: Vector3 = _movement._gravity_acceleration()
	return -gravity.normalized() if not gravity.is_zero_approx() else Vector3.UP

func _yaw_basis(up: Vector3) -> Basis:
	# Preserve horizontal heading while correcting pitch and roll.
	var forward: Vector3 = _movement._torso.global_basis.x.slide(up)
	if forward.is_zero_approx(): forward = Vector3.RIGHT.slide(up)
	if forward.is_zero_approx(): forward = Vector3.FORWARD.slide(up)
	forward = forward.normalized()
	return Basis(forward, up, forward.cross(up).normalized())

func _torso_center(torsos: Array[RigidBody3D]) -> Vector3:
	var center := Vector3.ZERO
	var mass := 0.0
	for body: RigidBody3D in torsos:
		center += _movement._stance_body_center(body) * body.mass
		mass += body.mass
	return center / maxf(mass, 0.001)

func _probe(from: Vector3, distance: float) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from - _up() * distance)
	query.exclude = _movement._character_exclusion_rids
	query.collision_mask = _movement.terrain_collision_mask
	return get_viewport().find_world_3d().direct_space_state.intersect_ray(query)

func _measure(torsos: Array[RigidBody3D], feet: Array[RigidBody3D]) -> Dictionary:
	var up := _up()
	var center := _torso_center(torsos)
	var angle := 0.0
	var speed := 0.0
	var mass := 0.0
	var near_ground := false
	var lowest_point := Vector3.ZERO
	var lowest_height := INF
	for body: RigidBody3D in torsos:
		mass += body.mass
		angle += acos(clampf(body.global_basis.y.normalized().dot(up), -1.0, 1.0)) * body.mass
		speed += body.linear_velocity.length() * body.mass
		var size: Vector3 = body.get_meta(&"generated_size", Vector3.ONE)
		var extent := (absf(body.global_basis.x.dot(up)) * size.x + absf(body.global_basis.y.dot(up)) * size.y + absf(body.global_basis.z.dot(up)) * size.z) * 0.5
		var bottom := body.global_position - up * extent
		if bottom.dot(up) < lowest_height:
			lowest_height = bottom.dot(up)
			lowest_point = bottom
	near_ground = not _probe(lowest_point + up * contact_distance, contact_distance * 2.0).is_empty()
	var grounded := 0
	for foot: RigidBody3D in feet:
		if _movement.is_leg_grounded(foot): grounded += 1
	var hit := _probe(center + up * contact_distance, maxf(_reference_height * 3.0, 3.0))
	var height := center.dot(up) - Vector3(hit.position).dot(up) if not hit.is_empty() else INF
	return {"center": center, "angle": rad_to_deg(angle / maxf(mass, 0.001)), "height": height, "speed": speed / maxf(mass, 0.001), "grounded": grounded, "ground_contact": near_ground or grounded > 0}

func _is_fallen(metrics: Dictionary) -> bool:
	if not metrics.ground_contact: return false
	var tilted: bool = metrics.angle >= fallen_angle_degrees
	var collapsed: bool = metrics.height < _reference_height * fallen_height_ratio and metrics.speed <= collapse_detection_speed
	return tilted or collapsed

func _transition(next: State, reason: StringName) -> void:
	if state == next: return
	var previous := state
	state = next
	_elapsed = 0.0
	_stable_elapsed = 0.0
	_last_lift_force = 0.0
	_lift_force_limited = false
	_movement.set_recovery_control_active(next != State.STANDING)
	if next == State.ESTABLISH_SUPPORT:
		_attempts += 1
		_attempt_elapsed = 0.0
		_plan_support()
		_rise_height = minf(float(_metrics.get("height", _reference_height)), _reference_height)
	if next == State.RIGHTING:
		_rise_height = minf(float(_metrics.get("height", _reference_height)), _reference_height)
	state_changed.emit(previous, state)
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	if console != null and console.is_generated_motion_tracking_enabled():
		print("[creature_recovery] character=", get_parent().name, " from=", State.keys()[previous], " to=", State.keys()[state], " reason=", reason, " metrics=", _metrics, " attempt=", _attempts)

func _physics_process(delta: float) -> void:
	if not enabled or not _character_enabled or not is_instance_valid(_movement): return
	_movement._begin_ground_probe_frame()
	var torsos: Array[RigidBody3D] = _movement.get_torso_parts()
	var feet: Array[RigidBody3D] = _movement.get_leg_parts()
	if torsos.is_empty() or feet.is_empty() or _reference_height <= 0.0:
		_movement.set_recovery_control_active(false)
		return
	_metrics = _measure(torsos, feet)
	_last_lift_force = 0.0
	_lift_force_limited = false
	_log_elapsed += delta
	if _log_elapsed >= 1.0:
		_log_elapsed = 0.0
		var console := get_tree().root.get_node_or_null("RuntimeConsole")
		if state != State.STANDING and console != null and console.is_generated_motion_tracking_enabled():
			print("[creature_recovery] character=", get_parent().name, " diagnostics=", get_recovery_diagnostics())
	_elapsed += delta
	if state in [State.ESTABLISH_SUPPORT, State.RIGHTING, State.STABILIZING]:
		_attempt_elapsed += delta
		if _attempt_elapsed >= support_setup_duration + recovery_timeout:
			_transition(State.RETRY, &"attempt_timeout")
	var required := maxi(1, ceili(float(feet.size()) * minimum_support_ratio))
	var stable: bool = _metrics.angle <= stable_angle_degrees and _metrics.height >= _reference_height * stable_height_ratio and _metrics.speed <= stable_speed and _metrics.grounded >= required
	match state:
		State.STANDING:
			var fallen: bool = _is_fallen(_metrics)
			_fall_elapsed = _fall_elapsed + delta if fallen else 0.0
			if _fall_elapsed >= fall_confirmation_duration: _transition(State.FALLEN, &"fall_confirmed")
		State.FALLEN:
			if _elapsed >= fallen_pause_duration: _transition(State.ESTABLISH_SUPPORT, &"begin_recovery")
		State.ESTABLISH_SUPPORT:
			_apply_support_forces()
			_restore_limbs()
			_right_torso(torsos)
			if _can_assist_lift(required): _lift_torso(torsos, delta)
			if _metrics.grounded >= required: _transition(State.RIGHTING, &"support_ready")
			elif _elapsed >= support_setup_duration: _transition(State.RETRY, &"no_support")
		State.RIGHTING, State.STABILIZING:
			_apply_support_forces()
			_restore_limbs()
			_right_torso(torsos)
			if _metrics.grounded >= required or _can_assist_lift(required): _lift_torso(torsos, delta)
			if state == State.RIGHTING:
				if stable: _transition(State.STABILIZING, &"pose_reached")
				elif _elapsed >= recovery_timeout: _transition(State.RETRY, &"recovery_timeout")
			else:
				_stable_elapsed = _stable_elapsed + delta if stable else 0.0
				if not stable: _transition(State.RIGHTING, &"pose_unstable")
				elif _stable_elapsed >= stable_confirmation_duration:
					_fall_elapsed = 0.0
					_transition(State.STANDING, &"recovered")
		State.RETRY:
			if _elapsed >= retry_delay: _transition(State.ESTABLISH_SUPPORT, &"retry")

func _plan_support() -> void:
	_targets.clear()
	_target_surfaces.clear()
	var center: Vector3 = _metrics.get("center", Vector3.ZERO)
	var up := _up()
	var yaw := _yaw_basis(up)
	for foot: RigidBody3D in _movement.get_leg_parts():
		if not _rest_offsets.has(foot) or not _movement._chain_is_intact(foot): continue
		var hit := _probe(center + yaw * Vector3(_rest_offsets[foot]) + up * _reference_height, _reference_height * 3.0)
		if hit.is_empty() or not _movement._surface_is_walkable(hit.normal): continue
		var target: Vector3 = _movement._body_position_for_ground_contact(foot, hit.position)
		var chain: Dictionary = _movement._chains[foot]
		var anchor: Vector3 = chain.root.to_global(chain.anchor)
		if target.distance_to(anchor) <= float(chain.length) * _movement.chain_reach_ratio:
			_targets[foot] = target
			_target_surfaces[foot] = hit.position

## A collapsed body may need clearance before its feet can reach the ground.
## Use confirmed terrain targets to allow a bounded bootstrap below standing
## height, instead of requiring feet to support a body that cannot yet unfold.
func _can_assist_lift(required: int) -> bool:
	return _targets.size() >= required and is_finite(_metrics.height) and _metrics.height < _reference_height * stable_height_ratio

func _apply_support_forces() -> void:
	for foot: RigidBody3D in _targets:
		if not is_instance_valid(foot) or not _movement._chain_is_intact(foot): continue
		# Keep the sole on the selected terrain as the foot rotates upright.
		_targets[foot] = _movement._body_position_for_ground_contact(foot, _target_surfaces[foot])
		var acceleration: Vector3 = (_targets[foot] - foot.global_position) * foot_strength - foot.linear_velocity * foot_damping
		foot.apply_central_force((acceleration * foot.mass).limit_length(maximum_foot_force))

func _restore_limbs() -> void:
	for foot: RigidBody3D in _movement.get_leg_parts():
		if not _movement._chain_is_intact(foot): continue
		var chain: Dictionary = _movement._chains[foot]
		for index: int in range(chain.joints.size()):
			var child: RigidBody3D = chain.bodies[index]
			var parent_body: RigidBody3D = chain.bodies[index + 1]
			var a: Basis = _movement._stance_inverse_inertia(child)
			var b: Basis = _movement._stance_inverse_inertia(parent_body)
			var inverse := Basis(a.x + b.x, a.y + b.y, a.z + b.z)
			if absf(inverse.determinant()) < 1e-18: continue
			var error: Vector3 = _movement._stance_rotation_error(child, parent_body, chain.rest_rotations[index])
			var acceleration := (error * pose_strength - (child.angular_velocity - parent_body.angular_velocity) * pose_damping).limit_length(maximum_angular_acceleration)
			# The lift servo carries the Torso during recovery. Compensate only the
			# foot-side chain's own gravity, avoiding double compensation of Torso weight.
			var gravity_load := Vector3.ZERO
			var gravity: Vector3 = _movement._gravity_acceleration()
			for body_index: int in range(index + 1):
				var limb: RigidBody3D = chain.bodies[body_index]
				gravity_load -= (_movement._stance_body_center(limb) - chain.joints[index].global_position).cross(gravity * limb.mass)
			var inertia: Basis = inverse.inverse()
			var torque := (gravity_load + inertia * acceleration).limit_length(maximum_joint_torque)
			child.apply_torque(torque)
			parent_body.apply_torque(-torque)

func _right_torso(torsos: Array[RigidBody3D]) -> void:
	var up := _up()
	for body: RigidBody3D in torsos:
		var current := body.global_basis.y.normalized()
		var cross := current.cross(up)
		# Handle an upside-down body, where the cross product alone is zero.
		var axis := cross.normalized() if cross.length_squared() > 0.000001 else body.global_basis.x.normalized()
		var error := axis * acos(clampf(current.dot(up), -1.0, 1.0))
		var acceleration := (error * pose_strength - body.angular_velocity.slide(up) * pose_damping).limit_length(maximum_angular_acceleration)
		var inverse: Basis = _movement._stance_inverse_inertia(body)
		if absf(inverse.determinant()) > 1e-18: body.apply_torque((inverse.inverse() * acceleration).limit_length(maximum_torso_torque))

func _lift_torso(torsos: Array[RigidBody3D], delta: float) -> void:
	if not is_finite(_metrics.height): return
	_rise_height = minf(_reference_height, _rise_height + rise_speed * delta)
	var mass := 0.0
	var velocity := 0.0
	for body: RigidBody3D in torsos:
		mass += body.mass
		velocity += body.linear_velocity.dot(_up()) * body.mass
	var acceleration := clampf((_rise_height - float(_metrics.height)) * lift_strength - velocity / maxf(mass, 0.001) * lift_damping, -maximum_lift_acceleration, maximum_lift_acceleration)
	var gravity: Vector3 = _movement._gravity_acceleration()
	var requested := (_up() * (acceleration + gravity.length()) * mass)
	var force := requested.limit_length(maximum_total_lift_force)
	_last_lift_force = force.length()
	_lift_force_limited = requested.length() > maximum_total_lift_force
	for body: RigidBody3D in torsos: body.apply_central_force(force * body.mass / maxf(mass, 0.001))

func get_recovery_diagnostics() -> Dictionary:
	return {"state": State.keys()[state], "attempt": _attempts, "elapsed": _elapsed, "reference_height": _reference_height, "targets": _targets.size(), "height_ratio": float(_metrics.get("height", 0.0)) / maxf(_reference_height, 0.001), "fall_confirmation": _fall_elapsed, "lift_force": _last_lift_force, "lift_force_limited": _lift_force_limited, "metrics": _metrics}
