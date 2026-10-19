extends "res://Scripts/Creatures/GeneratedLegStepMovementController3D.gd"

var _wolf_traction: Dictionary = {}
var _wolf_joint_torques: Array[Dictionary] = []
var _wolf_step_times: Dictionary = {}
var _wolf_profiles: Dictionary = {}
var _wolf_profiles_frame: int = -1
var _wolf_recovery_steps: Dictionary = {}
var _wolf_last_landings: Dictionary = {}
var _wolf_auto_gallop: bool = false
var _wolf_gallop_timer: float = 0.0
var _wolf_walking_speed: float = 0.0
var _wolf_gallop_reason: String = "inactive"
var _wolf_relief_remaining: float = 0.0
var _wolf_deliberate_turn: bool = false
var _wolf_heading_recovery: bool = false
var _wolf_turn_stable_elapsed: float = 0.0
var _wolf_turn_goal: float = 0.0
var _wolf_turn_state_frame: int = -1
var _wolf_plane_blend: float = 1.0
var _wolf_turn_resume_blend: float = 1.0
var _wolf_turn_resume_speed: float = 0.0
var _wolf_rotation_locks: Dictionary = {}
var _wolf_rotation_diagnostics: Dictionary = {}
var _wolf_plane_links: Array[Dictionary] = []
var _wolf_plane_rows: Array[Dictionary] = []
var _wolf_foot_lock_timers: Dictionary = {}

func _restore_wolf_rotation_lock(body: Variant) -> void:
	if not _wolf_rotation_locks.has(body): return
	if is_instance_valid(body):
		var saved: Vector2 = _wolf_rotation_locks[body]
		body.axis_lock_angular_x = bool(saved.x)
		body.axis_lock_angular_y = bool(saved.y)
	_wolf_rotation_locks.erase(body)

func _release_wolf_rotation_locks() -> void:
	for body in _wolf_rotation_locks.keys(): _restore_wolf_rotation_lock(body)
	_wolf_rotation_diagnostics.clear()

func _exit_tree() -> void:
	_release_wolf_rotation_locks()
	super._exit_tree()

func _foot_heading_turn_active() -> bool:
	return _wolf_heading_turn_active()

func _update_foot_heading_constraints() -> void:
	if not _get_gait_data().world_rotation_constraints_enabled:
		_release_wolf_rotation_locks()
		if _get_gait_data().limb_plane_stabilization_enabled:
			_update_wolf_plane_constraints(get_physics_process_delta_time())
		else:
			_wolf_plane_rows.clear()
			_wolf_foot_lock_timers.clear()
			super._update_foot_heading_constraints()
		return
	_wolf_plane_rows.clear()
	_wolf_foot_lock_timers.clear()
	# One owner controls foot and body locks; never let the old foot servo undo them.
	_release_all_foot_heading_locks()
	if _planar_mode_active() or recovery_control_active or not is_instance_valid(_torso) or _is_body_broken(_torso):
		_release_wolf_rotation_locks()
		return
	var parts := get_node_or_null(parts_root_path)
	if parts == null: return
	for old_body in _wolf_rotation_locks.keys():
		if not is_instance_valid(old_body) or _is_body_broken(old_body) or not parts.is_ancestor_of(old_body): _restore_wolf_rotation_lock(old_body)
	for child in parts.get_children():
		if child is RigidBody3D and not _is_body_broken(child) and not _wolf_rotation_locks.has(child):
			_wolf_rotation_locks[child] = Vector2(float(child.axis_lock_angular_x), float(child.axis_lock_angular_y))
	var turning := _wolf_heading_turn_active()
	var target := _get_physical_heading_yaw()
	var tolerance := deg_to_rad(foot_heading_lock_tolerance_degrees)
	var aligned := not turning and (not _segment_heading_initialized or absf(wrapf(_segment_goal_yaw - target, -PI, PI)) <= tolerance)
	var maximum_error := 0.0
	var maximum_speed := 0.0
	for body: RigidBody3D in _wolf_rotation_locks:
		if body.freeze: continue
		# The plane normal is unaffected by the authored bend around Z.
		var error := wrapf(target - atan2(body.global_basis.z.x, body.global_basis.z.z), -PI, PI)
		maximum_error = maxf(maximum_error, absf(error))
		maximum_speed = maxf(maximum_speed, absf(body.angular_velocity.y))
		aligned = aligned and absf(error) <= tolerance and absf(body.angular_velocity.y) <= deg_to_rad(2.0)
	var reaction := Vector3.ZERO
	for body: RigidBody3D in _wolf_rotation_locks:
		var saved: Vector2 = _wolf_rotation_locks[body]
		body.axis_lock_angular_x = true
		body.axis_lock_angular_y = bool(saved.y) or aligned
		var torque := Vector3.ZERO
		if not turning and not aligned and body != _torso and not body.freeze and not bool(saved.y):
			var error := wrapf(target - atan2(body.global_basis.z.x, body.global_basis.z.z), -PI, PI)
			var relative_rate := body.angular_velocity.y - _torso.angular_velocity.y
			var inverse_y := Vector3.UP.dot(_stance_inverse_inertia(body) * Vector3.UP)
			if inverse_y > 0.000001:
				var acceleration := clampf(error * foot_heading_strength - relative_rate * foot_heading_damping, -foot_heading_maximum_acceleration, foot_heading_maximum_acceleration)
				torque = Vector3.UP * clampf(acceleration / inverse_y, -foot_heading_maximum_torque, foot_heading_maximum_torque)
				body.apply_torque(torque)
				reaction -= torque
		if _legs.has(body):
			_foot_heading_diagnostics[body] = {"state": &"locked" if aligned else (&"turning" if turning else &"aligning"), "target_degrees": rad_to_deg(target), "torque": torque}
	# Internal alignment cannot generate a net airborne turning torque.
	if not _torso.freeze: _torso.apply_torque(reaction)
	_wolf_rotation_diagnostics = {"enabled": true, "state": "turning" if turning else ("locked" if aligned else "aligning"), "parts": _wolf_rotation_locks.size(), "maximum_yaw_error_degrees": rad_to_deg(maximum_error), "maximum_yaw_speed_degrees": rad_to_deg(maximum_speed), "alignment_reaction": reaction}

func refresh_physics_query_cache() -> void:
	_release_wolf_rotation_locks()
	_wolf_step_times.clear()
	_wolf_profiles.clear()
	_wolf_profiles_frame = -1
	_wolf_recovery_steps.clear()
	_wolf_last_landings.clear()
	_wolf_auto_gallop = false
	_wolf_gallop_timer = 0.0
	_wolf_relief_remaining = 0.0
	_wolf_deliberate_turn = false
	_wolf_heading_recovery = false
	_wolf_turn_stable_elapsed = 0.0
	_wolf_turn_state_frame = -1
	_wolf_plane_blend = 1.0
	_wolf_turn_resume_blend = 1.0
	super.refresh_physics_query_cache()
	_cache_wolf_plane_links()

func _cache_wolf_plane_links() -> void:
	_wolf_plane_links.clear()
	_wolf_plane_rows.clear()
	_wolf_foot_lock_timers.clear()
	var parts := get_node_or_null(parts_root_path)
	if parts == null or not is_instance_valid(_torso): return
	# Every part shares the torso reference; neighboring-link errors must not accumulate.
	for body: Node in parts.get_children():
		if not body is RigidBody3D or body == _torso: continue
		if not (_has_body_tag(body, LEG_LIMB_TAG) or _has_body_tag(body, SUB_TORSO_TAG) or _has_body_tag(body, LEG_TAG) or _has_body_tag(body, FORELEG_TAG)): continue
		var reference: Basis = _torso.global_basis.orthonormalized().inverse() * body.global_basis.orthonormalized()
		_wolf_plane_links.append({"a": _torso, "b": body, "normal_a": reference.z, "normal_b": Vector3.BACK, "tangent_a": reference.x})

func _wolf_unlocked_inverse_inertia(body: RigidBody3D) -> Basis:
	if body.freeze: return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var mask := Vector3(0.0 if body.axis_lock_angular_x else 1.0, 0.0 if body.axis_lock_angular_y else 1.0, 0.0 if body.axis_lock_angular_z else 1.0)
	var projection := Basis.from_scale(mask)
	# Edited collision shapes can differ greatly from the generator's size metadata.
	var inverse := body.get_inverse_inertia_tensor()
	if inverse.x.is_zero_approx() and inverse.y.is_zero_approx() and inverse.z.is_zero_approx(): inverse = _stance_inverse_inertia(body)
	return projection * inverse * projection

func _update_wolf_plane_constraints(delta: float) -> void:
	_wolf_plane_rows.clear()
	_foot_heading_diagnostics.clear()
	if _planar_mode_active() or recovery_control_active or not is_instance_valid(_torso) or _is_body_broken(_torso):
		_wolf_plane_blend = 0.0
		_wolf_foot_lock_timers.clear()
		_release_all_foot_heading_locks()
		return
	var data = _get_gait_data()
	_wolf_plane_blend = move_toward(_wolf_plane_blend, 1.0, delta / maxf(data.limb_plane_restore_time, delta))
	var generator: Node = get_parent().get_node_or_null(get_parent().generator_path)
	var scale: float = float(generator.overall_scale) if generator != null else 1.0
	# Couples only plane normals: rotation about the hinge normal remains free.
	for link: Dictionary in _wolf_plane_links:
		if not is_instance_valid(link.a) or not is_instance_valid(link.b): continue
		var a: RigidBody3D = link.a
		var b: RigidBody3D = link.b
		if _is_body_broken(a) or _is_body_broken(b): continue
		if _wolf_heading_turn_active() and not _wolf_heading_recovery and not _has_body_tag(b, SUB_TORSO_TAG): continue
		var na: Vector3 = (a.global_basis * Vector3(link.normal_a)).normalized()
		var nb: Vector3 = (b.global_basis * Vector3(link.normal_b)).normalized()
		var angle := nb.angle_to(na)
		var axis := nb.cross(na).normalized()
		if axis.is_zero_approx() and angle > PI * 0.5:
			axis = (a.global_basis * Vector3(link.tangent_a)).slide(na).normalized()
		var relative_rate := (b.angular_velocity - a.angular_velocity).slide(na)
		var acceleration: Vector3 = (axis * angle * data.limb_plane_strength - relative_rate * data.limb_plane_damping).limit_length(data.limb_plane_maximum_acceleration)
		var torque := Vector3.ZERO
		if not acceleration.is_zero_approx():
			var ia := _wolf_unlocked_inverse_inertia(a)
			var ib := _wolf_unlocked_inverse_inertia(b)
			var normal_projection := Basis(na*na.x,na*na.y,na*na.z)
			var plane_projection := Basis(Vector3.RIGHT-normal_projection.x,Vector3.UP-normal_projection.y,Vector3.BACK-normal_projection.z)
			# Solve both plane axes together; a scalar inertia approximation couples thin parts into the wrong axis.
			var projected := plane_projection*Basis(ia.x+ib.x,ia.y+ib.y,ia.z+ib.z)*plane_projection
			var inverse := Basis(projected.x+normal_projection.x,projected.y+normal_projection.y,projected.z+normal_projection.z)
			if absf(inverse.determinant()) > 1e-18:
				torque = (inverse.inverse()*acceleration).slide(na).limit_length(data.limb_plane_maximum_torque*pow(scale,5.0))*_wolf_plane_blend
				if not a.freeze: a.apply_torque(-torque)
				if not b.freeze: b.apply_torque(torque)
		_wolf_plane_rows.append({"frame": Engine.get_physics_frames(), "a": a.name, "b": b.name, "plane_error_degrees": rad_to_deg(angle), "relative_rate": relative_rate, "a_torque": -torque, "b_torque": torque})
	if _wolf_heading_turn_active():
		_wolf_foot_lock_timers.clear()
		_release_all_foot_heading_locks()
	elif _wolf_plane_blend >= 1.0: _update_wolf_foot_plane_locks(delta)

func _update_wolf_foot_plane_locks(delta: float) -> void:
	if not foot_heading_lock_enabled:
		_wolf_foot_lock_timers.clear()
		_release_all_foot_heading_locks()
		return
	var data = _get_gait_data()
	var normal := _torso.global_basis.z.normalized()
	for old_foot: Variant in _foot_heading_previous_locks.keys():
		if not is_instance_valid(old_foot) or not _legs.has(old_foot) or not _chain_is_intact(old_foot):
			_release_foot_heading_lock(old_foot)
			_wolf_foot_lock_timers.erase(old_foot)
	for foot: RigidBody3D in _legs:
		if not _chain_is_intact(foot) or foot.freeze or _is_body_broken(foot):
			_release_foot_heading_lock(foot)
			_wolf_foot_lock_timers.erase(foot)
			continue
		if not _foot_heading_previous_locks.has(foot): _foot_heading_previous_locks[foot] = foot.axis_lock_angular_y
		if bool(_foot_heading_previous_locks[foot]): continue
		var angle := rad_to_deg(foot.global_basis.z.normalized().angle_to(normal))
		var rate := rad_to_deg(absf(foot.angular_velocity.y - _torso.angular_velocity.y))
		var settled: bool = angle <= data.foot_plane_lock_degrees and rate <= 2.0 and absf(_torso.angular_velocity.y) <= deg_to_rad(2.0)
		var release := angle > maxf(data.foot_plane_unlock_degrees, data.foot_plane_lock_degrees) or absf(_torso.angular_velocity.y) > deg_to_rad(8.0)
		var pending: bool = release if foot.axis_lock_angular_y else settled
		var timer: float = float(_wolf_foot_lock_timers.get(foot, 0.0)) + delta if pending else 0.0
		var confirmation: float = data.foot_plane_unlock_confirmation if foot.axis_lock_angular_y else data.foot_plane_lock_confirmation
		if pending and timer >= confirmation:
			foot.axis_lock_angular_y = not foot.axis_lock_angular_y
			timer = 0.0
		_wolf_foot_lock_timers[foot] = timer
		_foot_heading_diagnostics[foot] = {"state": &"locked" if foot.axis_lock_angular_y else &"plane_aligning", "plane_error_degrees": angle, "confirmation_elapsed": timer, "torque": Vector3.ZERO, "owner": "wolf_limb_plane"}

func get_leg_motion_profile(leg: RigidBody3D) -> Dictionary:
	var original := super.get_leg_motion_profile(leg)
	if original.is_empty() or not _wolf_stride_enabled(leg) or _gallop_active(): return original
	return _get_wolf_walking_profile(leg, original)

func _get_wolf_walking_profile(leg: RigidBody3D, original: Dictionary) -> Dictionary:
	# This independent walking budget never calls _gallop_active().
	if _wolf_profiles_frame != Engine.get_physics_frames():
		_wolf_profiles.clear()
		_wolf_profiles_frame = Engine.get_physics_frames()
	if not _wolf_profiles.has(leg):
		var direction := get_input_movement_direction().slide(Vector3.UP).normalized()
		if direction.is_zero_approx(): direction = get_parent().global_basis.x.normalized()
		var bounds := _wolf_stride_bounds(leg, direction)
		var stance_distance := maxf(float(bounds.radius) * 1.6, 0.01)
		_wolf_profiles[leg] = _get_gait_data().stabilize_profile(original, stance_distance, _legs.size(), float(_wolf_step_times.get(leg, 0.0)))
	return _wolf_profiles[leg]

func _wolf_gallop_eligible() -> bool:
	return input_enabled and not recovery_control_active and not simplified_physics_mode and not _planar_mode_active() and not _wolf_heading_turn_active() and _action_feet.is_empty() and _adhesion_release_time_remaining <= 0.0 and not get_input_movement_direction().is_zero_approx() and not _legs.is_empty()

func _wolf_heading_turn_active() -> bool:
	if _turn_planning_active and not _layout_turn_owned: return true
	return _wolf_deliberate_turn

func _update_segment_layout(delta: float) -> void:
	_update_wolf_heading_state(delta)
	super._update_segment_layout(delta)

func _update_wolf_heading_state(delta: float) -> void:
	if _wolf_turn_state_frame == Engine.get_physics_frames(): return
	_wolf_turn_state_frame = Engine.get_physics_frames()
	if not _segment_heading_initialized or recovery_control_active or _planar_mode_active() or not _action_feet.is_empty():
		_wolf_deliberate_turn = false
		_wolf_heading_recovery = false
		_wolf_turn_stable_elapsed = 0.0
		return
	var data = _get_gait_data()
	var error := _get_maximum_heading_error(_segment_goal_yaw)
	_wolf_turn_resume_blend = move_toward(_wolf_turn_resume_blend, 1.0, delta / maxf(data.deliberate_turn_resume_time, delta))
	var entry := deg_to_rad(data.deliberate_turn_entry_degrees)
	var exit := deg_to_rad(minf(data.deliberate_turn_exit_degrees, data.deliberate_turn_entry_degrees * 0.5))
	if absf(wrapf(_segment_goal_yaw - _wolf_turn_goal, -PI, PI)) > 0.001:
		_wolf_turn_goal = _segment_goal_yaw
		_wolf_turn_stable_elapsed = 0.0
	if not _wolf_deliberate_turn:
		_wolf_deliberate_turn = error >= entry
		_wolf_heading_recovery = _wolf_deliberate_turn and not _turn_command_pending
		return
	if _turn_command_pending: _wolf_heading_recovery = false
	var maximum_rate := 0.0
	for body: RigidBody3D in get_torso_parts():
		if not _is_body_broken(body): maximum_rate = maxf(maximum_rate, absf(body.angular_velocity.y))
	var settled := error <= exit and maximum_rate <= deg_to_rad(data.deliberate_turn_settle_speed_degrees)
	_wolf_turn_stable_elapsed = _wolf_turn_stable_elapsed + delta if settled else 0.0
	if _wolf_turn_stable_elapsed >= data.deliberate_turn_settle_time:
		_wolf_deliberate_turn = false
		_wolf_heading_recovery = false
		_wolf_turn_stable_elapsed = 0.0
		_wolf_plane_blend = 0.0
		_wolf_turn_resume_speed = minf(super._get_expected_horizontal_speed(), _get_requested_movement_speed())
		_wolf_turn_resume_blend = 0.0

func _update_layout_turn_steps(delta: float) -> void:
	if _charge_gait_active() or recovery_control_active or _planar_mode_active() or not _action_feet.is_empty() or _wolf_heading_turn_active():
		super._update_layout_turn_steps(delta)
		return
	# Small drift uses stance traction without taking ownership of the walking sequence.
	if _layout_turn_owned: set_turn_planning_active(false)
	_layout_turn_owned = false
	_layout_turn_status = &"heading_correction"
	_turn_leg_forces.clear()
	_turn_drive_diagnostics = {"blocked": &"correction_disabled"}
	if segment_layout_enabled and segment_layout_turn_steps_enabled and _motion_setting("turning_speed_degrees", segment_heading_speed_degrees) > 0.0:
		_apply_grounded_turn_traction()

func _turn_traction_control(error: float, actual_rate: float, limit_rate: float) -> Dictionary:
	if _charge_gait_active() or _wolf_heading_turn_active(): return super._turn_traction_control(error, actual_rate, limit_rate)
	return _get_gait_data().calculate_heading_correction(error, actual_rate, limit_rate)

func _airborne_height_support_authorized() -> bool:
	if _gallop_active(): return true
	if recovery_control_active or simplified_physics_mode or _planar_mode_active() or not _action_feet.is_empty() or _adhesion_release_time_remaining > 0.0: return false
	for motion: StepMotion in _active_steps:
		if motion.extra.get("gallop_step", false) and motion.extra.has("wolf_step") and _chain_is_intact(motion.leg) and not motion.leg.freeze: return true
	return false

func _wolf_needs_support_relief(foot: RigidBody3D) -> bool:
	if not _chain_is_intact(foot) or foot.freeze or is_leg_stepping(foot) or not is_leg_grounded(foot): return false
	if _wolf_traction.get(foot, {}).get("confirmed", false): return true
	var bounds := _wolf_stride_bounds(foot, get_input_movement_direction())
	var remaining: float = (foot.global_position - Vector3(bounds.center)).dot(bounds.direction) + float(bounds.radius)
	return float(bounds.radius) > 0.01 and remaining <= maxf(float(bounds.radius) * 0.05, 0.01)

func _can_start_step_with_support(leg: RigidBody3D) -> bool:
	if _wolf_relief_remaining > 0.0 and _gallop_active() and _wolf_needs_support_relief(leg):
		# Urgent grounded launches bypass stagger/support counts, but still require a real-ground lease.
		return _active_steps.size() < _automatic_flight_capacity() and _gallop_flight_available()
	return super._can_start_step_with_support(leg)

func _update_automatic_wolf_gallop(delta: float) -> void:
	var data = _get_gait_data()
	if data == null or not data.automatic_motion or not data.speed_based_gait or not data.automatic_gallop_enabled or _charge_gait_active() or not _wolf_gallop_eligible():
		_wolf_auto_gallop = false
		_wolf_gallop_timer = 0.0
		_wolf_relief_remaining = 0.0
		_wolf_walking_speed = 0.0
		_wolf_gallop_reason = "inactive"
		return
	_wolf_walking_speed = _get_requested_movement_speed()
	var support := false
	var count := 0
	for foot: RigidBody3D in _legs:
		if not _chain_is_intact(foot) or foot.freeze: continue
		count += 1
		support = support or is_leg_grounded(foot)
		var original := super.get_leg_motion_profile(foot)
		if not original.is_empty(): _wolf_walking_speed = minf(_wolf_walking_speed, float(_get_wolf_walking_profile(foot, original).reachable_speed))
	if count == 0 or _get_requested_movement_speed() <= 0.0:
		_wolf_auto_gallop = false
		_wolf_gallop_timer = 0.0
		_wolf_relief_remaining = 0.0
		_wolf_gallop_reason = "no_available_feet_or_speed"
		return
	_wolf_relief_remaining = maxf(_wolf_relief_remaining - delta, 0.0) if data.traction_gallop_enabled else 0.0
	if data.traction_gallop_enabled:
		for foot: RigidBody3D in _legs:
			if _wolf_needs_support_relief(foot): _wolf_relief_remaining = data.traction_gallop_hold_time
	if _wolf_relief_remaining > 0.0:
		if not _wolf_auto_gallop:
			_log_gait_event(&"wolf_gait_switch", _legs[0], &"support_relief", get_input_movement_direction())
		_wolf_auto_gallop = true
		_wolf_gallop_timer = 0.0
		_wolf_gallop_reason = "traction_or_extension_relief"
		_update_gallop_contacts()
		return
	var deficit: float = maxf(1.0 - _wolf_walking_speed / _get_requested_movement_speed(), 0.0)
	var requested: bool = deficit <= minf(data.gallop_exit_speed_deficit, data.gallop_entry_speed_deficit * 0.5) if _wolf_auto_gallop else deficit >= data.gallop_entry_speed_deficit and support
	var confirmation: float = data.gallop_exit_confirmation if _wolf_auto_gallop else data.gallop_entry_confirmation
	_wolf_gallop_timer = _wolf_gallop_timer + delta if requested else 0.0
	if _wolf_auto_gallop:
		_wolf_gallop_reason = "confirming_walking_recovery" if requested else "walking_capacity_insufficient"
	else:
		_wolf_gallop_reason = "confirming_gallop" if requested else ("awaiting_ground_support" if not support else "walking_capacity_sufficient")
	if requested and _wolf_gallop_timer >= confirmation:
		_wolf_auto_gallop = not _wolf_auto_gallop
		_wolf_gallop_timer = 0.0
		_wolf_gallop_reason = "walking_capacity_insufficient" if _wolf_auto_gallop else "walking_capacity_recovered"
		_log_gait_event(&"wolf_gait_switch", _legs[0], StringName("gallop" if _wolf_auto_gallop else "walk"), get_input_movement_direction())

func _gallop_active() -> bool:
	var data = _get_gait_data()
	if data == null or _charge_gait_active() or not data.automatic_motion or not data.speed_based_gait or not data.automatic_gallop_enabled:
		return super._gallop_active()
	return _wolf_auto_gallop and _wolf_gallop_eligible()

func _gallop_intensity() -> float:
	if _wolf_auto_gallop and _gallop_active():
		var data = _get_gait_data()
		var minimum: float = maxf(data.minimum_automatic_gallop_intensity, data.traction_gallop_intensity if _wolf_relief_remaining > 0.0 else 0.0)
		return clampf(maxf(minimum, _get_requested_movement_speed() / maxf(_wolf_walking_speed, 0.01) - 1.0), 0.0, 1.0)
	return super._gallop_intensity()

func _get_expected_horizontal_speed() -> float:
	if _wolf_auto_gallop and _gallop_active() and not _charge_gait_active(): return lerpf(_wolf_turn_resume_speed, _get_requested_movement_speed(), smoothstep(0.0, 1.0, _wolf_turn_resume_blend))
	return super._get_expected_horizontal_speed()

func _height_support_carries_limb_weight() -> bool:
	return not _charge_gait_active()

func _height_support_external_gravity_mass() -> float:
	var support := get_parent().get_node_or_null("HeadPositionSupport3D")
	return support.get_gravity_supported_mass(get_parent()._get_physical_body_parts()) if support != null else 0.0

func _height_support_weight_share() -> float:
	return maxf(1.0, sub_torso_weight_share) if _height_support_carries_limb_weight() else super._height_support_weight_share()

func _landing_reach_attachment(leg: RigidBody3D) -> Vector3:
	if not _wolf_stride_enabled(leg) or _charge_gait_active(): return super._landing_reach_attachment(leg)
	# Wolf's trajectory already follows root travel; reach uses the current root.
	var chain: Dictionary = _chains[leg]
	return chain.root.to_global(chain.anchor)

func _airborne_height_support_limit(weight: float) -> float:
	if not _height_support_carries_limb_weight(): return super._airborne_height_support_limit(weight)
	# A finite real-ground lease authorizes full weight support plus height recovery.
	return minf(sub_torso_maximum_weight_share, auxiliary_support_weight_limit) * clampf(weight, 0.0, 1.0)

func get_automatic_motion_diagnostics() -> Dictionary:
	var result := super.get_automatic_motion_diagnostics()
	result["wolf_auto_gallop"] = {"enabled": _get_gait_data().automatic_gallop_enabled, "active": _wolf_auto_gallop, "walking_speed": _wolf_walking_speed, "target_speed": _get_requested_movement_speed(), "confirmation_elapsed": _wolf_gallop_timer, "reason": _wolf_gallop_reason}
	result.wolf_auto_gallop["support_relief_remaining"] = _wolf_relief_remaining
	if _gallop_active():
		result.speed_based_gait = true
		for profile: Dictionary in result.legs:
			for foot: RigidBody3D in _legs:
				if profile.foot == foot.name: profile["speed_gait"] = _get_speed_leg_plan(foot)
	return result

func _begin_leg_motion(leg: RigidBody3D, target: Vector3, normal: Vector3 = Vector3.UP, direction: Vector3 = Vector3.ZERO) -> void:
	super._begin_leg_motion(leg, target, normal, direction)
	if not _wolf_stride_enabled(leg) or _charge_gait_active() or _wolf_heading_turn_active(): return
	_current_step.extra["wolf_step"] = {"phase":"lift", "elapsed":0.0, "started_at":_physics_elapsed, "horizontal_tracking":false}
	_plan_wolf_swing()

func try_start_turn_step(leg: RigidBody3D, sample_position: Vector3, duration: float, height: float) -> bool:
	var data = _get_gait_data()
	var distance := (sample_position - leg.global_position).slide(Vector3.UP).length()
	var safe_duration: float = data.safe_swing_time(distance, height, duration)
	if not super.try_start_turn_step(leg, sample_position, safe_duration, height): return false
	var profile: Dictionary = _current_step.extra.get("automatic_profile", {})
	if not profile.is_empty():
		profile.position_gain = minf(float(profile.position_gain), data.maximum_tracking_gain)
		profile.velocity_gain = 2.0 * sqrt(float(profile.position_gain))
		profile.step_acceleration = minf(float(profile.step_acceleration), data.maximum_tracking_acceleration)
	return true

func _plan_wolf_swing() -> void:
	var profile: Dictionary = _current_step.extra.automatic_profile
	var data = _get_gait_data()
	var distance := (_step_target - _active_leg.global_position).slide(Vector3.UP).length()
	_external_step_height = minf(float(profile.lift) + distance * data.distance_lift_ratio, float(_chains[_active_leg].length) * data.maximum_lift_length_ratio)
	var safe_duration: float = data.safe_swing_time(distance, _get_effective_step_height(), float(profile.swing_duration))
	if _current_step.extra.get("gallop_step", false):
		safe_duration = maxf(safe_duration, float(_current_step.extra.get("speed_gait", {}).get("air_duration", 0.0)))
	var attempts := mini(int(_wolf_recovery_steps.get(_active_leg, 0)), 4)
	_active_step_duration = safe_duration * (1.0 + attempts * data.recovery_time_increase)
	# Extra recovery time must not weaken the position servo.
	profile.position_gain = minf(16.0 / (safe_duration * safe_duration), data.maximum_tracking_gain)
	profile.velocity_gain = 2.0 * sqrt(float(profile.position_gain))
	profile.step_acceleration = data.maximum_tracking_acceleration
	_current_step.extra.landing_timeout = maxf(0.5, _active_step_duration)
	_current_step.extra.wolf_step["swing_duration"] = _active_step_duration
	_current_step.extra.wolf_step["distance"] = distance
	_current_step.extra.wolf_step["swing_deadline"] = _active_step_duration * 2.0
	_current_step.extra.wolf_step["recovery_stride_scale"] = data.recovery_stride_scale(int(_wolf_recovery_steps.get(_active_leg, 0)))
	if _current_step.extra.get("gallop_step", false) and _gallop_contacts.has(_active_leg):
		# Budget lift, pursuit and braking from the last real contact, never renew its timestamp in air.
		var lease := minf(3.0, _active_step_duration * 2.0 + 0.5)
		_gallop_contacts[_active_leg].duration = maxf(float(_gallop_contacts[_active_leg].duration), lease)
		if _current_step.extra.has("speed_gait"): _current_step.extra.speed_gait.lease_duration = _gallop_contacts[_active_leg].duration

func _apply_wolf_tracking(position: Vector3, velocity: Vector3, _delta: float) -> void:
	var profile: Dictionary = _current_step.extra.automatic_profile
	var gain := float(profile.position_gain)
	if _current_step.extra.wolf_step.phase == "lift": gain = minf(maxf(gain, 100.0), _get_gait_data().maximum_tracking_gain)
	var acceleration := (position - _active_leg.global_position) * gain + (velocity - _active_leg.linear_velocity) * (2.0 * sqrt(gain))
	# Include the linked limb mass, but cap acceleration after all scaling.
	_tracking_mass = _active_leg.mass
	var gravity_mass := _active_leg.mass * _active_leg.gravity_scale
	var chain: Dictionary = _chains[_active_leg]
	for index: int in range(1, chain.bodies.size() - 1):
		var body: RigidBody3D = chain.bodies[index]
		if not body.freeze:
			_tracking_mass += body.mass * stepping_chain_mass_ratio
			gravity_mass += body.mass * body.gravity_scale * stepping_chain_mass_ratio
	var data = _get_gait_data()
	var gravity := _gravity_acceleration()
	var up := -gravity.normalized() if not gravity.is_zero_approx() else Vector3.UP
	# Vertical height correction has its own servo and cannot be diluted by X/Z demand.
	var vertical_gain: float = minf(data.vertical_tracking_gain, data.maximum_tracking_gain)
	var vertical_acceleration := (position - _active_leg.global_position).dot(up) * vertical_gain + (velocity - _active_leg.linear_velocity).dot(up) * (2.0 * sqrt(vertical_gain))
	acceleration = acceleration.slide(up).limit_length(data.maximum_tracking_acceleration) + up * clampf(vertical_acceleration, -data.maximum_tracking_acceleration, data.maximum_tracking_acceleration)
	_tracking_gravity_force = -gravity * gravity_mass if step_gravity_compensation else Vector3.ZERO
	_tracking_position_error = position - _active_leg.global_position
	_tracking_force_limit = minf(maximum_mass_scaled_step_force, _tracking_mass * data.maximum_tracking_acceleration)
	var requested := acceleration * _tracking_mass + _tracking_gravity_force
	_tracking_force_limited = requested.length() > _tracking_force_limit
	var allocation: Dictionary = data.allocate_tracking_force(requested, up, _tracking_force_limit)
	_tracking_force = allocation.force
	_active_leg.apply_central_force(_tracking_force)
	_current_step.extra.wolf_step["tracking_force"] = _tracking_force
	_current_step.extra.wolf_step["acceleration_limit"] = data.maximum_tracking_acceleration
	_current_step.extra.wolf_step["vertical_force"] = allocation.vertical_force
	_current_step.extra.wolf_step["horizontal_force_budget"] = allocation.horizontal_limit

func _wolf_braking_mass(foot: RigidBody3D) -> float:
	var mass := foot.mass
	var chain: Dictionary = _chains[foot]
	for index: int in range(1, chain.bodies.size() - 1):
		var body: RigidBody3D = chain.bodies[index]
		if not body.freeze: mass += body.mass * stepping_chain_mass_ratio
	return mass

func _update_touchdown_support_pin(leg: RigidBody3D, normal: Vector3, delta: float) -> void:
	super._update_touchdown_support_pin(leg, normal, delta)
	if not _current_step.extra.has("wolf_step") or not _support_pins.has(leg): return
	var data = _get_gait_data()
	var elapsed := maxf(float(_current_step.extra.touchdown_pin_elapsed) - delta, 0.0)
	var progress := 1.0 if data.wolf_touchdown_pin_transition_time <= 0.0 else clampf(elapsed / data.wolf_touchdown_pin_transition_time, 0.0, 1.0)
	var slack: float = data.wolf_touchdown_pin_initial_slack * (1.0 - smoothstep(0.0, 1.0, progress))
	_set_touchdown_pin_slack(leg, slack)
	_current_step.extra.touchdown_pin.progress = progress
	_current_step.extra.touchdown_pin.slack = slack

func _update_active_step(delta: float) -> void:
	if not _current_step.extra.has("wolf_step") or not is_instance_valid(_active_leg):
		super._update_active_step(delta)
		return
	if not _chain_is_intact(_active_leg):
		cancel_step(&"wolf_chain_broken")
		return
	if _planar_mode_active() or recovery_control_active or _action_feet.has(_active_leg):
		cancel_step(&"wolf_step_interrupted")
		return
	var state: Dictionary = _current_step.extra.wolf_step
	var root_body: RigidBody3D = _chains[_active_leg].root
	var data = _get_gait_data()
	state.elapsed += delta
	if state.phase == "lift":
		var surface := _get_surface_below_leg(_active_leg, maxf(ray_length, _get_effective_step_height() * 2.0))
		var gap := 0.0 if surface.is_empty() else (_get_foot_world_position(_active_leg) - Vector3(surface.position)).dot(Vector3(surface.normal))
		var clearance := _step_start_clearance + maxf(_get_effective_step_height() * 0.6, minimum_step_lift_clearance * 2.0)
		# Aim slightly above the threshold so hinge resistance cannot stall exactly below it.
		var desired := _active_leg.global_position + Vector3.UP * (maxf(clearance - gap, 0.0) * 1.5 + maxf(clearance * 0.2, 0.02))
		var lift_velocity := root_body.linear_velocity.slide(Vector3.UP)
		lift_velocity.y = maxf(clearance - gap, 0.0) / maxf(data.minimum_safe_swing_time * 0.6, 0.15)
		# Add bounded lift inside the existing acceleration budget, never after its cap.
		var assist: float = data.liftoff_assist_acceleration * smoothstep(0.2, 0.5, float(state.elapsed))
		var lift_gain := minf(maxf(float(_current_step.extra.automatic_profile.position_gain), 100.0), data.maximum_tracking_gain)
		lift_velocity.y += assist / (2.0 * sqrt(lift_gain))
		state["lift_assist_acceleration"] = assist
		_apply_wolf_tracking(desired, lift_velocity, delta)
		state["clearance"] = gap
		state["required_clearance"] = clearance
		if gap > float(state.get("best_clearance", -INF)) + 0.002:
			state["best_clearance"] = gap
			state["last_lift_progress"] = state.elapsed
		if not surface.is_empty() and gap >= clearance:
			_step_has_lifted = true
			var landing := find_landing_point(_active_leg, _active_step_input_direction)
			if landing.is_empty():
				_handle_step_timeout(false)
				return
			_step_target = _body_position_for_ground_contact(_active_leg, landing.position)
			_step_target_normal = landing.normal
			_step_start = _active_leg.global_position
			state["root_origin"] = root_body.global_position
			state["local_start"] = _step_start
			state["local_target"] = _step_target
			state.phase = "swing"
			state.elapsed = 0.0
			state.horizontal_tracking = true
			_plan_wolf_swing()
		else:
			var timeout := maxf(0.6, _active_step_duration * 2.0)
			if state.elapsed >= timeout and (state.elapsed - float(state.get("last_lift_progress", 0.0)) >= 0.3 or state.elapsed >= timeout * 2.0):
				_handle_step_timeout(is_leg_grounded(_active_leg))
		return
	var contact := _support_surface_contact(_active_leg)
	var landed := false
	if not contact.is_empty():
		var gap := (_get_foot_world_position(_active_leg) - Vector3(contact.position)).dot(Vector3(contact.normal))
		landed = absf(gap) <= 0.04 and _get_ground_contact_velocity(_active_leg, contact).dot(contact.normal) <= 0.5
	if state.phase == "brake" or landed:
		if contact.is_empty():
			_release_support_pin(_active_leg)
			_handle_step_timeout(false)
			return
		if state.phase != "brake":
			state.phase = "brake"
			state.elapsed = 0.0
			state["stable_time"] = 0.0
			state["arrival_error"] = (_step_target - _active_leg.global_position).slide(Vector3.UP).length()
			state["completion"] = _wolf_landing_verdict(_active_leg, _step_target, _active_step_input_direction)
			state.horizontal_tracking = false
			_step_state = StepState.LANDING
			_landing_elapsed = 0.0
		_step_target = _active_leg.global_position
		var velocity := _get_ground_contact_velocity(_active_leg, contact)
		var normal: Vector3 = contact.normal
		var acceleration := (-velocity.slide(normal) / maxf(data.contact_brake_time, delta)).limit_length(data.maximum_contact_brake_acceleration)
		_tracking_position_error = Vector3.ZERO
		_tracking_gravity_force = Vector3.ZERO
		_tracking_mass = _wolf_braking_mass(_active_leg)
		_tracking_force_limit = minf(maximum_mass_scaled_step_force, _tracking_mass * data.maximum_contact_brake_acceleration)
		var requested := acceleration * _tracking_mass
		_tracking_force_limited = velocity.slide(normal).length() / maxf(data.contact_brake_time, delta) > data.maximum_contact_brake_acceleration or requested.length() > _tracking_force_limit
		_tracking_force = requested.limit_length(_tracking_force_limit)
		_active_leg.apply_force(_tracking_force, _get_ground_contact_world_position(_active_leg) - _active_leg.global_position)
		_update_touchdown_support_pin(_active_leg, normal, delta)
		state["contact_speed"] = velocity.slide(normal).length()
		state["brake_force"] = _tracking_force
		state["brake_mass"] = _tracking_mass
		state["brake_force_limit"] = _tracking_force_limit
		state.stable_time = float(state.stable_time) + delta if velocity.slide(normal).length() <= 0.5 and absf(velocity.dot(normal)) <= 0.5 else 0.0
		_landing_elapsed += delta
		if state.stable_time >= 0.04: _finish_current_step()
		elif _landing_elapsed >= _get_effective_landing_timeout(): _handle_step_timeout(true)
		return
	_step_elapsed += delta
	var progress := clampf(_step_elapsed / _active_step_duration, 0.0, 1.0)
	var root_travel: Vector3 = (root_body.global_position - Vector3(state.root_origin)).slide(Vector3.UP)
	_step_start = Vector3(state.local_start) + root_travel
	_step_target = Vector3(state.local_target) + root_travel
	# A translating frame preserves the airborne body travel; terrain still owns landing height.
	var bounds := _wolf_stride_bounds(_active_leg, _active_step_input_direction)
	var projection := (_step_target - Vector3(bounds.center)).dot(bounds.direction)
	_step_target += Vector3(bounds.direction) * (clampf(projection, -float(bounds.radius) * 0.8, float(bounds.radius) * 0.8) - projection)
	var from := _step_target + Vector3.UP * ray_start_height
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * ray_length, terrain_collision_mask, _get_character_exclusion_rids())
	query.collide_with_areas = false
	var surface := _intersect_ray(query)
	# Compare terrain heights, so the swing's own lift cannot reject flat ground.
	var below := _get_surface_below_leg(_active_leg, maxf(ray_length, float(_chains[_active_leg].length) * 2.0))
	var validation_origin: Vector3 = below.position if not below.is_empty() else _get_foot_world_position(_active_leg)
	var valid := _is_landing_point_valid(_active_leg, validation_origin, surface)
	state["target_valid"] = valid
	state["target_rejection"] = _last_landing_rejection_reason
	if valid:
		_step_target.y = _body_position_for_ground_contact(_active_leg, surface.position).y
		_step_target_normal = surface.normal
	else:
		_apply_wolf_tracking(_active_leg.global_position + Vector3.UP * _get_effective_step_height(), root_body.linear_velocity.slide(Vector3.UP), delta)
		if state.elapsed >= _active_step_duration * 2.0: _handle_step_timeout(false)
		return
	var t := smoothstep(0.0, 1.0, progress)
	var lift := _get_effective_step_height()
	var travel := (_step_target - _step_start).slide(Vector3.UP)
	var actual_progress := clampf((_active_leg.global_position - _step_start).slide(Vector3.UP).dot(travel) / maxf(travel.length_squared(), 0.0001), 0.0, 1.0)
	var horizontal_error := (_step_target - _active_leg.global_position).slide(Vector3.UP)
	var tolerance := maxf(float(bounds.radius) * data.touchdown_target_tolerance_ratio, 0.05)
	if progress >= 0.65 and horizontal_error.length() > tolerance:
		var relative_speed := (_active_leg.linear_velocity - root_body.linear_velocity).slide(Vector3.UP).dot(horizontal_error.normalized())
		state["swing_deadline"] = data.catch_up_deadline(state.elapsed, _active_step_duration, horizontal_error.length(), relative_speed, float(state.swing_deadline))
	state["catch_up_extension"] = maxf(float(state.swing_deadline) - _active_step_duration * 2.0, 0.0)
	state["horizontal_error"] = horizontal_error.length()
	var height_progress := minf(progress, actual_progress + 0.15)
	state["horizontal_progress"] = actual_progress
	state["height_progress"] = height_progress
	var position := _step_start.lerp(_step_target, t) + Vector3.UP * 4.0 * lift * height_progress * (1.0 - height_progress)
	var velocity := ((_step_target - _step_start) * 6.0 * progress * (1.0 - progress) + Vector3.UP * 4.0 * lift * (1.0 - 2.0 * height_progress)) / _active_step_duration
	if progress >= 1.0: velocity = Vector3.ZERO
	# Finish horizontal pursuit before commanded descent; once descending, never lift again.
	if state.phase == "swing" and progress >= 0.5 and (actual_progress >= 0.85 or horizontal_error.length() <= tolerance):
		state.phase = "descend"
		state["descent_elapsed"] = 0.0
	if state.phase == "descend":
		state.descent_elapsed += delta
		position.y = _step_target.y - data.touchdown_press_depth
		velocity.y = -data.touchdown_descent_speed
	else:
		position.y = maxf(position.y, _step_target.y + maxf(lift * 0.6, minimum_step_lift_clearance * 2.0))
		velocity.y = maxf(velocity.y, 0.0)
	state["descent_target_y"] = position.y
	velocity += root_body.linear_velocity.slide(Vector3.UP)
	_apply_wolf_tracking(position, velocity, delta)
	if progress >= 1.0:
		if state.phase == "descend": _landing_elapsed += delta
		if _landing_elapsed >= _get_effective_landing_timeout() or state.elapsed >= float(state.swing_deadline): _handle_step_timeout(false)

func _wolf_landing_verdict(foot: RigidBody3D, target: Vector3, direction: Vector3) -> Dictionary:
	var bounds := _wolf_stride_bounds(foot, direction)
	var error := (target - foot.global_position).slide(Vector3.UP).length()
	var tolerance := maxf(float(bounds.radius) * _get_gait_data().touchdown_target_tolerance_ratio, 0.05)
	var inside := absf((foot.global_position - Vector3(bounds.center)).dot(bounds.direction)) < float(bounds.radius)
	return {"valid": inside and error <= tolerance, "target": target, "target_error": error, "tolerance": tolerance, "inside_interval": inside}

func _finish_current_step() -> void:
	if is_instance_valid(_active_leg) and _current_step.extra.has("wolf_step"):
		var state: Dictionary = _current_step.extra.wolf_step
		var verdict: Dictionary = state.get("completion", {})
		var foot := _active_leg
		if not verdict.is_empty(): verdict = _wolf_landing_verdict(foot, verdict.target, _active_step_input_direction)
		_wolf_last_landings[foot] = verdict.duplicate()
		if verdict.is_empty() or not verdict.valid:
			_wolf_recovery_steps[foot] = int(_wolf_recovery_steps.get(foot, 0)) + 1
			_record_wolf_step_time()
			_log_gait_event(&"step_incomplete", foot, &"wolf_early_touchdown", _active_step_input_direction, _step_target)
			cancel_step(&"wolf_early_touchdown")
			return
		_wolf_recovery_steps.erase(foot)
	super._finish_current_step()

func _record_wolf_step_time() -> void:
	if not is_instance_valid(_active_leg) or not _current_step.extra.has("wolf_step"): return
	var state: Dictionary = _current_step.extra.wolf_step
	var elapsed := clampf(_physics_elapsed - float(state.started_at), 0.1, 2.0)
	var previous := float(_wolf_step_times.get(_active_leg, elapsed))
	_wolf_step_times[_active_leg] = lerpf(previous, clampf(elapsed, previous * 0.75, previous * 1.25), 0.2)
	_wolf_profiles.clear()

func _keep_touchdown_support_pin(leg: RigidBody3D) -> bool:
	for motion: StepMotion in _active_steps:
		if motion.leg != leg or motion.extra.get("wolf_step", {}).get("phase", "") != "brake": continue
		return _support_pins.has(leg) and not _support_surface_contact(leg).is_empty() and not leg.freeze and not is_leg_slipping(leg) and not _is_body_broken(leg) and _adhesion_release_time_remaining <= 0.0
	return super._keep_touchdown_support_pin(leg)

func _record_touchdown() -> void:
	_record_wolf_step_time()
	super._record_touchdown()

func _handle_step_timeout(grounded: bool) -> void:
	if is_instance_valid(_active_leg) and _current_step.extra.has("wolf_step"):
		_wolf_recovery_steps[_active_leg] = int(_wolf_recovery_steps.get(_active_leg, 0)) + 1
	_record_wolf_step_time()
	super._handle_step_timeout(grounded)

func get_support_foot_diagnostics(leg: RigidBody3D) -> Dictionary:
	var result := super.get_support_foot_diagnostics(leg)
	var state: Dictionary = {}
	for motion: StepMotion in _active_steps:
		if motion.leg == leg: state = motion.extra.get("wolf_step", {})
	result["gallop"]["wolf_step"] = state.duplicate()
	result["gallop"]["wolf_last_landing"] = _wolf_last_landings.get(leg, {})
	result["gallop"]["wolf_recovery_attempts"] = _wolf_recovery_steps.get(leg, 0)
	return result

func _configure_foreleg_elbow(chain: Dictionary) -> void:
	var preset = get_parent().wolf_physics
	if not preset.foreleg_anti_reverse_enabled or chain.joints.size()!=3: return
	_configure_limb_bend_limit(chain,"wolf_elbow",0.0)

func _configure_limb_bend_limit(chain: Dictionary, prefix: String, minimum_bend: float) -> void:
	var elbow: Generic6DOFJoint3D = chain.joints[1]
	if not elbow.has_meta(prefix+"_straight"):
		var upper: RigidBody3D = chain.bodies[2]
		var a: RigidBody3D = elbow.get_node(elbow.node_a)
		var b: RigidBody3D = elbow.get_node(elbow.node_b)
		var frame_a: Transform3D = a.global_transform*Transform3D(elbow.get_meta(&"generated_joint_frame_a"))
		var frame_b: Transform3D = b.global_transform*Transform3D(elbow.get_meta(&"generated_joint_frame_b"))
		var axis := frame_a.basis.z.normalized()
		var thigh: Vector3 = elbow.global_position-chain.joints[2].global_position
		var shin: Vector3 = chain.joints[0].global_position-elbow.global_position
		var bend := thigh.signed_angle_to(shin,axis)
		var normal_side := 1.0 if bend>=0.0 else -1.0
		var frame_sign := 1.0 if a==upper else -1.0
		var current := (frame_a.basis.orthonormalized().inverse()*frame_b.basis.orthonormalized()).get_euler().z
		var straight := current-frame_sign*bend
		elbow.set_meta(prefix+"_straight",straight)
		elbow.set_meta(prefix+"_allowed_sign",frame_sign*normal_side)
	var straight: float = elbow.get_meta(prefix+"_straight")
	var side: float = elbow.get_meta(prefix+"_allowed_sign")
	var extended := straight+side*minimum_bend
	var folded := straight+side*PI
	# Generic6DOF limits use A relative to B, opposite our measured B-relative-to-A angle.
	var limits := Vector2(-maxf(extended,folded),-minf(extended,folded))
	elbow.set_meta(prefix+"_z_limits",limits)
	elbow.set_meta(&"wolf_bend_z_limits",limits)
	elbow.set_meta(prefix+"_minimum_bend",minimum_bend)
	elbow.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,true)
	elbow.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,limits.x)
	elbow.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,limits.y)

func _apply_passive_limb_damping() -> void:
	super._apply_passive_limb_damping()
	_wolf_joint_torques.clear()
	var preset = get_parent().get("wolf_physics")
	if preset == null or not preset.enabled or recovery_control_active or _planar_mode_active(): return
	for foot: RigidBody3D in _chains:
		if not _chain_is_intact(foot) or _action_feet.has(foot): continue
		var chain: Dictionary = _chains[foot]
		if chain.joints.size()<2: continue
		var child: RigidBody3D = chain.bodies[1]
		var parent_body: RigidBody3D = chain.bodies[2]
		var joint: Generic6DOFJoint3D = chain.joints[1]
		if child.freeze or parent_body.freeze: continue
		var axis: Vector3 = parent_body.global_basis*Vector3(joint.get_meta(&"passive_hinge_axis_parent",Vector3.BACK))
		axis = axis.normalized()
		var rate := (child.angular_velocity-parent_body.angular_velocity).dot(axis)
		var acceleration := 0.0
		var error := 0.0
		var mode := "hind_lower_spring"
		if _has_body_tag(foot,FORELEG_TAG):
			if not preset.foreleg_anti_reverse_enabled or not joint.has_meta(&"wolf_elbow_z_limits"): continue
			var a: RigidBody3D = joint.get_node(joint.node_a)
			var b: RigidBody3D = joint.get_node(joint.node_b)
			var frame_a: Transform3D = a.global_transform*Transform3D(joint.get_meta(&"generated_joint_frame_a"))
			var frame_b: Transform3D = b.global_transform*Transform3D(joint.get_meta(&"generated_joint_frame_b"))
			var angle := (frame_a.basis.orthonormalized().inverse()*frame_b.basis.orthonormalized()).get_euler().z
			var side: float = joint.get_meta(&"wolf_elbow_allowed_sign")
			var distance := wrapf(angle-float(joint.get_meta(&"wolf_elbow_straight")),-PI,PI)*side
			var frame_rate := (b.angular_velocity-a.angular_velocity).dot(frame_a.basis.z.normalized())
			var buffer := deg_to_rad(preset.foreleg_straight_buffer_degrees)
			if buffer<=0.0 or distance>=buffer or frame_rate*side>=0.0: continue
			acceleration = -rate*preset.foreleg_straight_buffer_damping*clampf(1.0-distance/buffer,0.0,1.0)
			mode = "foreleg_straight_buffer"
		elif preset.hind_lower_spring_enabled and chain.has("wolf_natural_pose"):
			error = _stance_rotation_error(child,parent_body,chain.rest_rotations[1]).dot(axis)
			var restoring := signf(error)*maxf(absf(error)-deg_to_rad(preset.hind_lower_spring_dead_zone),0.0)
			acceleration = restoring*preset.hind_lower_spring_strength-rate*preset.hind_lower_spring_damping
			if is_leg_stepping(foot): acceleration *= preset.hind_lower_spring_step_multiplier
		else: continue
		if mode == "hind_lower_spring": acceleration = clampf(acceleration,-preset.hind_lower_spring_maximum_acceleration,preset.hind_lower_spring_maximum_acceleration)
		var inverse := axis.dot(_stance_inverse_inertia(child)*axis)+axis.dot(_stance_inverse_inertia(parent_body)*axis)
		var scale: float = get_parent().get_node(get_parent().generator_path).overall_scale
		var limit: float = (preset.hind_lower_spring_maximum_torque if mode == "hind_lower_spring" else preset.foreleg_straight_buffer_maximum_torque)*pow(scale,5.0)
		var torque := axis*clampf(acceleration/maxf(inverse,0.000001),-limit,limit)
		child.apply_torque(torque)
		parent_body.apply_torque(-torque)
		_wolf_joint_torques.append({"frame":Engine.get_physics_frames(),"foot":foot.name,"joint":joint.name,"mode":mode,"error_degrees":rad_to_deg(error),"relative_speed":rate,"child_torque":torque,"parent_torque":-torque,"limit":limit})

func _get_passive_limb_damping(foot: RigidBody3D) -> float:
	var preset = get_parent().get("wolf_physics")
	if preset != null and preset.enabled and _has_body_tag(foot,LEG_TAG) and not _has_body_tag(foot,FORELEG_TAG):
		return maxf(preset.hind_limb_hinge_damping,0.0)
	return super._get_passive_limb_damping(foot)

func _capture_chains() -> void:
	super._capture_chains()
	var preset = get_parent().get("wolf_physics")
	if preset == null or not preset.enabled: return
	for foot: RigidBody3D in _chains:
		if foot.has_meta(&"generated_module_id"): continue
		if _has_body_tag(foot,LEG_TAG) and not _has_body_tag(foot,FORELEG_TAG) and preset.hind_lower_angle_limit_enabled and _chains[foot].joints.size()==4:
			_configure_limb_bend_limit(_chains[foot],"wolf_hind_lower",deg_to_rad(180.0-preset.hind_lower_maximum_angle_degrees))
		if not _has_body_tag(foot,FORELEG_TAG): continue
		for joint: Generic6DOFJoint3D in _chains[foot].joints:
			joint.set_meta(&"wolf_foreleg_joint",true)
			joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,not preset.foreleg_z_rotation_unlimited)
		_configure_foreleg_elbow(_chains[foot])
	var reference: RigidBody3D
	for foot: RigidBody3D in _chains:
		if foot.name == &"Leg_1": reference = foot
	if reference == null: return
	var reference_chain: Dictionary = _chains[reference]
	var top: int = reference_chain.bodies.size()-2
	if top<3: return
	var thigh_basis: Basis = reference_chain.bodies[top].global_basis.orthonormalized()
	for foot: RigidBody3D in _chains:
		if not _has_body_tag(foot,LEG_TAG) or _has_body_tag(foot,FORELEG_TAG): continue
		if foot.has_meta(&"generated_module_id"): continue
		var chain: Dictionary = _chains[foot]
		if chain.bodies.size()!=5: continue
		var root_body: RigidBody3D = chain.root
		var axis: Vector3 = get_parent().global_basis.z.normalized()
		var forward: Vector3 = get_parent().global_basis.x.normalized()
		var upper: Vector3 = chain.joints[3].global_position
		var upper_vector: Vector3 = chain.bodies[3].global_basis.inverse()*(chain.joints[2].global_position-upper)
		var first := thigh_basis*upper_vector
		var middle_vector: Vector3 = chain.joints[1].global_position-chain.joints[2].global_position
		var lower_vector: Vector3 = chain.joints[0].global_position-chain.joints[1].global_position
		var angle := deg_to_rad(preset.hind_knee_reference_degrees)
		var second := first.normalized().rotated(axis,angle)*middle_vector.length()
		var alternative := first.normalized().rotated(axis,-angle)*middle_vector.length()
		var ankle_offset: float = (chain.joints[0].global_position-foot.global_position).dot(forward)
		var goal: Vector3 = root_body.global_position+forward*ankle_offset
		if absf((upper+first+alternative-goal).dot(forward))<absf((upper+first+second-goal).dot(forward)): second = alternative
		var knee := upper+first+second
		var dx := clampf((goal-knee).dot(forward),-lower_vector.length(),lower_vector.length())
		var third: Vector3 = forward*dx-get_parent().global_basis.y.normalized()*sqrt(maxf(lower_vector.length_squared()-dx*dx,0.0))
		var rotations: Array[Quaternion] = []
		for body: RigidBody3D in chain.bodies: rotations.append(body.global_basis.orthonormalized().get_rotation_quaternion())
		rotations[3] = thigh_basis.get_rotation_quaternion()
		rotations[2] = Basis(axis,middle_vector.signed_angle_to(second,axis)).get_rotation_quaternion()*rotations[2]
		rotations[1] = Basis(axis,lower_vector.signed_angle_to(third,axis)).get_rotation_quaternion()*rotations[1]
		# Reference data only: never move bodies, anchors or joint limit frames.
		for index: int in range(1,4): chain.rest_rotations[index] = rotations[index+1].inverse()*rotations[index]
		chain["wolf_natural_pose"] = {"thigh_rotation":rotations[3],"knee_angle_degrees":rad_to_deg(first.angle_to(second)),"ankle_position":knee+third,"foot_position":knee+third-forward*ankle_offset,"subtorso_x_error":absf((knee+third-goal).dot(forward)),"active_restoring_torque":false}

func get_stance_support_diagnostics() -> Dictionary:
	var result := super.get_stance_support_diagnostics()
	result["wolf_rotation_constraints"] = _wolf_rotation_diagnostics.duplicate()
	result["wolf_limb_planes"] = {"enabled": _get_gait_data().limb_plane_stabilization_enabled, "active": not _wolf_plane_rows.is_empty() and int(_wolf_plane_rows[0].frame) == Engine.get_physics_frames(), "parts": _wolf_plane_rows.duplicate(true), "force_meaning": "paired commanded torques, not measured solver impulses"}
	result["wolf_heading"] = {"deliberate_turn": _wolf_heading_turn_active(), "recovering_drift": _wolf_heading_recovery, "error_degrees": rad_to_deg(wrapf(_segment_goal_yaw - _get_physical_heading_yaw(), -PI, PI)), "maximum_error_degrees": rad_to_deg(_get_maximum_heading_error(_segment_goal_yaw)), "stable_seconds": _wolf_turn_stable_elapsed, "plane_restore_blend": _wolf_plane_blend, "walk_resume_blend": _wolf_turn_resume_blend, "entry_degrees": _get_gait_data().deliberate_turn_entry_degrees, "exit_degrees": _get_gait_data().deliberate_turn_exit_degrees, "retained_flight_support": not _gallop_active() and _airborne_height_support_authorized()}
	result["wolf_flight_height_support"] = {"carries_limb_weight": _height_support_carries_limb_weight(), "gravity_weight_share": _height_support_weight_share(), "maximum_airborne_weight_share": _airborne_height_support_limit(1.0), "real_ground_lease_required": true}
	var references: Array[Dictionary] = []
	for foot: RigidBody3D in _chains:
		if _chains[foot].has("wolf_natural_pose"):
			var row: Dictionary = _chains[foot].wolf_natural_pose.duplicate()
			row["foot"] = foot.name
			row["hinge_damping"] = _get_passive_limb_damping(foot)
			row.active_restoring_torque = _wolf_joint_torques.any(func(torque_row): return torque_row.foot==foot.name and torque_row.mode=="hind_lower_spring" and not Vector3(torque_row.child_torque).is_zero_approx() and Engine.get_physics_frames()-int(torque_row.frame)<=1)
			references.append(row)
	result["wolf_hind_leg_references"] = references
	result["wolf_joint_torques"] = _wolf_joint_torques
	return result

func _physics_process(delta: float) -> void:
	var attacks := get_parent().get_node_or_null("WolfAttackController3D")
	if attacks != null and attacks.blocks_locomotion():
		_wolf_deliberate_turn = false
		_wolf_turn_stable_elapsed = 0.0
		_apply_passive_limb_damping()
		_apply_torso_tilt_stabilization()
		_update_wolf_plane_constraints(delta)
		return
	if recovery_control_active or _planar_mode_active(): _release_wolf_rotation_locks()
	_update_wolf_traction(delta)
	_update_automatic_wolf_gallop(delta)
	super._physics_process(delta)

func _update_wolf_traction(delta: float) -> void:
	var direction := get_input_movement_direction().slide(Vector3.UP).normalized()
	if direction.is_zero_approx() or not _extension_gait_enabled():
		_wolf_traction.clear()
		return
	for old_foot in _wolf_traction.keys():
		if not is_instance_valid(old_foot) or not _chains.has(old_foot): _wolf_traction.erase(old_foot)
	for foot: RigidBody3D in _chains:
		var previous: Dictionary = _wolf_traction.get(foot,{})
		var cooldown := maxf(float(previous.get("cooldown",0.0))-delta,0.0)
		var data = _get_gait_data()
		if is_leg_stepping(foot): cooldown = data.traction_step_cooldown
		var sample := _estimate_wolf_traction(foot,direction)
		var same_direction := direction.dot(Vector3(previous.get("direction",direction))) > 0.9
		var elapsed := float(previous.get("elapsed",0.0))+delta if sample.overloaded and cooldown<=0.0 and same_direction else 0.0
		sample["elapsed"] = elapsed
		sample["cooldown"] = cooldown
		sample["direction"] = direction
		sample["confirmed"] = sample.overloaded and elapsed>=data.traction_confirmation_time and cooldown<=0.0
		_wolf_traction[foot] = sample

func _estimate_wolf_traction(foot: RigidBody3D, direction: Vector3) -> Dictionary:
	var result := {"overloaded":false,"estimated_force":0.0,"weight_ratio":0.0,"rear_extension":0.0,"speed_deficit":0.0}
	var data = _get_gait_data()
	if not _wolf_stride_enabled(foot) or not data.traction_recovery_enabled or is_leg_stepping(foot) or not is_leg_grounded(foot): return result
	if Engine.get_physics_frames()-_contact_drive_frame>1: return result
	var chain: Dictionary = _chains[foot]
	var root_body: RigidBody3D = chain.root
	var rear := maxf((_get_leg_rest_world_position(foot)-foot.global_position).dot(direction),0.0)
	var target_speed := get_expected_horizontal_speed()
	if target_speed<=0.0: return result
	var deficit := clampf((target_speed-root_body.linear_velocity.dot(direction))/target_speed,0.0,1.0)
	for row: Dictionary in _contact_drive_rows:
		if row.foot != foot.name: continue
		var force := maxf(Vector3(row.applied).dot(direction),0.0)
		var weight := maxf(float(row.carried_mass)*float(ProjectSettings.get_setting("physics/3d/default_gravity",9.8))/maxi(_contact_drive_rows.size(),1),0.001)
		# Rearward stance under sustained drive is evidence of limb resistance; walls alone are insufficient.
		var estimate := force*deficit*clampf(rear/maxf(float(chain.length)*0.15,0.01),0.0,2.0)
		result.estimated_force = estimate
		result.weight_ratio = estimate/weight
		result.rear_extension = rear
		result.speed_deficit = deficit
		result.overloaded = rear>float(chain.length)*0.05 and result.weight_ratio>=data.traction_weight_threshold
		break
	return result

func _wolf_stride_enabled(foot: RigidBody3D) -> bool:
	return _automatic_motion_enabled() and _chain_is_intact(foot) and not _planar_mode_active() and not _wolf_heading_turn_active() and not _charge_gait_active() and not _action_feet.has(foot)

func _wolf_stride_bounds(foot: RigidBody3D, direction: Vector3) -> Dictionary:
	var chain: Dictionary = _chains[foot]
	var root_body: RigidBody3D = chain.root
	var travel := direction.slide(Vector3.UP).normalized()
	var rest_offset := _get_leg_rest_world_position(foot)-root_body.global_position
	# Keep each foot's authored lateral lane; only longitudinal reach is symmetric.
	var center := root_body.global_position + rest_offset.slide(Vector3.UP)-travel*rest_offset.dot(travel)
	var data = _get_gait_data()
	var stride_offset: float = data.foreleg_stride_forward_offset if _has_body_tag(foot,FORELEG_TAG) else -data.hindleg_stride_backward_offset
	center += travel*stride_offset
	var hit := _get_surface_below_leg(foot, maxf(ray_length, float(chain.length)*2.0))
	center.y = _body_position_for_ground_contact(foot, hit.position).y if not hit.is_empty() else foot.global_position.y
	var configured: Variant = _get_gait_data().get("maximum_foot_extension_ratio")
	var ratio := float(configured) if configured != null else 0.25
	var radius := float(chain.length)*clampf(ratio,0.01,1.0)
	var attachment: Vector3 = root_body.to_global(chain.anchor)
	var offset := center-attachment
	var sideways := offset.slide(Vector3.UP)-travel*offset.dot(travel)
	var outer_radius := float(chain.length)*chain_reach_ratio*0.95
	var reachable := sqrt(maxf(outer_radius*outer_radius-offset.y*offset.y-sideways.length_squared(),0.0))
	radius = minf(radius,maxf(reachable-absf(offset.dot(travel)),0.0))
	return {"center":center,"radius":radius,"direction":travel,"offset":stride_offset}

func _get_extension_step_demand(foot: RigidBody3D, direction: Vector3) -> Dictionary:
	var result := super._get_extension_step_demand(foot,direction)
	if _wolf_relief_remaining > 0.0 and _gallop_active() and _wolf_needs_support_relief(foot):
		result.requested = true
		result.reason = "wolf_support_relief"
		result["step_priority"] = 1000.0
		return result
	if _gallop_active(): return result
	if not _wolf_stride_enabled(foot) or direction.is_zero_approx() or is_leg_stepping(foot) or not is_leg_grounded(foot): return result
	if _wolf_recovery_steps.has(foot):
		result.requested = true
		result.reason = "wolf_incomplete_landing_recovery"
		return result
	if result.reason in ["startup","inactive","action_controlled"]: return result
	var bounds := _wolf_stride_bounds(foot,direction)
	var root_body: RigidBody3D = _chains[foot].root
	var raw_remaining: float = (foot.global_position-Vector3(bounds.center)).dot(bounds.direction)+float(bounds.radius)
	var remaining := maxf(raw_remaining,0.0)
	var approach := (root_body.linear_velocity-foot.linear_velocity).dot(bounds.direction)
	var threshold := maxf(float(bounds.radius)*0.2,0.02)
	var emergency := remaining <= maxf(float(bounds.radius)*0.05,0.01)
	result["wolf_stride_center"] = bounds.center
	result["wolf_stride_radius"] = bounds.radius
	result["wolf_stride_offset"] = bounds.offset
	result.remaining_distance = remaining
	result.approach_speed = approach
	result.time_to_limit = remaining/approach if approach>0.05 else -1.0
	result.distance_threshold = threshold
	result.overextension = maxf(-raw_remaining,0.0)
	result.emergency = emergency
	result.requested = remaining<=threshold or (approach>0.05 and remaining/approach<=float(result.lead_time))
	result.reason = "extension_emergency" if emergency else ("distance_limit" if result.requested else "holding")
	var traction: Dictionary = _wolf_traction.get(foot,{})
	result["wolf_traction"] = traction.duplicate()
	if traction.get("confirmed",false):
		result.requested = true
		result.reason = "traction_recovery"
		result["step_priority"] = float(traction.weight_ratio)
	return result

func _get_projected_landing_rest_position(leg: RigidBody3D, direction: Vector3) -> Vector3:
	if not _wolf_stride_enabled(leg) or _charge_gait_active(): return super._get_projected_landing_rest_position(leg,direction)
	var bounds := _wolf_stride_bounds(leg,direction)
	var profile := get_leg_motion_profile(leg)
	var data = _get_gait_data()
	# Recenter every landing on the torso; a rearward foot must not drag the next target back.
	var forward := maxf(get_leg_step_distance(leg) * 0.5, _get_requested_movement_speed() * float(profile.swing_duration))
	var attempts := int(_wolf_recovery_steps.get(leg, 0))
	forward = clampf(forward * data.recovery_stride_scale(attempts), 0.0, float(bounds.radius) * 0.8)
	# The shared sampler still adds the unscaled step distance.
	return Vector3(bounds.center)+Vector3(bounds.direction)*(forward-get_leg_step_distance(leg))

func _is_landing_point_valid(leg: RigidBody3D, current_foot: Vector3, hit: Dictionary) -> bool:
	if not super._is_landing_point_valid(leg,current_foot,hit): return false
	if not _wolf_stride_enabled(leg) or _charge_gait_active(): return true
	var direction := get_input_movement_direction().slide(Vector3.UP)
	if direction.is_zero_approx(): return true
	var bounds := _wolf_stride_bounds(leg,direction)
	var offset: float = (_body_position_for_ground_contact(leg,hit.position)-Vector3(bounds.center)).dot(bounds.direction)
	if absf(offset)>float(bounds.radius)+0.0001:
		_last_landing_rejection_reason = &"wolf_stride_limit"
		return false
	return true
