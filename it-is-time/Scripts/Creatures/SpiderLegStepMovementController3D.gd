extends "res://Scripts/Creatures/GeneratedLegStepMovementController3D.gd"

const STRIDE_GEOMETRY = preload("res://Scripts/Creatures/SpiderStrideGeometry.gd")
@export_group("Spider Structural Stride")
@export var structural_stride_enabled: bool = true
@export_range(0.1, 0.95, 0.05) var structural_stride_safety_ratio: float = 0.8
## Landing stays inside the leading half; leave room before either reach boundary.
@export_range(0.2, 0.9, 0.05) var structural_landing_forward_ratio: float = 0.65
var _spider_reach_geometry: Dictionary = {}
var _spider_stride_intervals: Dictionary = {}
var _spider_last_touchdowns: Dictionary = {}
var _spider_recovery_steps: Dictionary = {}
@export_group("Spider Catch-up Steps")
@export_range(1.0, 3.0, 0.05) var step_lift_multiplier: float = 1.35
@export_range(0.1, 2.0, 0.05) var catch_up_speed_ratio: float = 0.75
@export_range(0.35, 3.0, 0.05) var maximum_catch_up_duration: float = 1.2
@export_range(0.1, 1.0, 0.05) var touchdown_target_tolerance_ratio: float = 0.5

@export_group("Spider Independent Torso Support")
@export_range(0.1, 5.0, 0.1) var torso_support_frequency: float = 1.5
@export_range(0.1, 3.0, 0.05) var torso_support_damping_ratio: float = 1.0
@export_range(1.0, 100.0, 1.0) var torso_support_maximum_acceleration: float = 30.0
@export_range(0.1, 10.0, 0.1) var root_follow_frequency: float = 3.0
@export_range(1.0, 100.0, 1.0) var root_follow_maximum_acceleration: float = 30.0
var _spider_support_rows: Array[Dictionary] = []
var _spider_root_rows: Array[Dictionary] = []
var _spider_support_exclusions: Array[RID] = []

func _independent_support_enabled() -> bool:
	return is_instance_valid(get_parent()) and bool(get_parent().get("spider_independent_torso_support"))

func _physics_process(delta: float) -> void:
	var full_started := Time.get_ticks_usec() if _performance_tracking_enabled else 0
	var prior_total := _performance_total_usec
	var started := _movement_perf.start()
	super._physics_process(delta)
	_spider_support_rows.clear()
	_spider_root_rows.clear()
	if _independent_support_enabled() and not _planar_mode_active() and not simplified_physics_mode:
		var support_started := _movement_perf.start()
		_apply_spider_independent_support()
		_movement_perf.finish(&"spider_independent_support", support_started)
	if _performance_tracking_enabled:
		var elapsed := Time.get_ticks_usec() - full_started
		_performance_total_usec = prior_total + elapsed
		_performance_max_usec = maxi(_performance_max_usec, elapsed)
	_movement_perf.finish(&"movement_spider_full", started)

func _apply_torso_response() -> void:
	if not _independent_support_enabled():
		super._apply_torso_response()
		return
	# Keep grounded horizontal propulsion, without the inherited vertical servo.
	_last_torso_response_force = Vector3.ZERO
	_last_auxiliary_support_force = Vector3.ZERO
	_update_segment_metrics()
	_update_gallop_contacts()
	var gravity := _gravity_acceleration()
	var up := -gravity.normalized() if not gravity.is_zero_approx() else Vector3.UP
	var total_mass := 0.0
	for body: RigidBody3D in get_torso_parts():
		if not _is_body_broken(body): total_mass += body.mass
	if not torso_response_enabled: return
	for segment: Dictionary in _segments.values():
		var mass := 0.0
		var velocity := Vector3.ZERO
		for body: RigidBody3D in segment.bodies:
			if not is_instance_valid(body) or body.freeze or _is_body_broken(body): continue
			mass += body.mass
			velocity += body.linear_velocity * body.mass
		if mass <= 0.0: continue
		velocity /= mass
		var requested := _contact_velocity_force(velocity, float(segment.mass), up)
		requested += _contact_extra_force.slide(up) * mass / maxf(total_mass, 0.001)
		requested *= _segment_movement_scale(segment, up)
		requested = requested.limit_length(minf(maximum_contact_drive_force * mass / maxf(total_mass, 0.001), float(segment.mass) * _motion_setting("contact_acceleration", maximum_grounded_drive_acceleration)))
		_last_torso_response_force += _apply_contact_drive(segment.feet, requested, float(segment.mass), up)

func _apply_spider_independent_support() -> void:
	_update_segment_metrics()
	var gravity := _gravity_acceleration()
	var up := -gravity.normalized() if not gravity.is_zero_approx() else Vector3.UP
	var omega := TAU * torso_support_frequency
	for segment: Dictionary in _segments.values():
		var center: Vector3 = segment.torso_center
		var query := PhysicsRayQueryParameters3D.create(center + up * ray_start_height, center - up * ray_length)
		query.exclude = _spider_support_exclusions
		query.collision_mask = terrain_collision_mask
		var hit := get_viewport().world_3d.direct_space_state.intersect_ray(query)
		var error := 0.0
		var has_floor := not hit.is_empty() and _surface_is_walkable(hit.normal)
		if has_floor: error = Vector3(hit.position).dot(up) + float(segment.reference_height) - center.dot(up)
		for body: RigidBody3D in segment.bodies:
			if not is_instance_valid(body) or body.freeze or _is_body_broken(body): continue
			var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
			if state == null: continue
			var correction := clampf(error * omega * omega - body.linear_velocity.dot(up) * 2.0 * torso_support_damping_ratio * omega, -torso_support_maximum_acceleration, torso_support_maximum_acceleration) if has_floor else 0.0
			var compensation := -state.total_gravity * body.mass
			var force := compensation + up * correction * body.mass
			body.apply_central_force(force)
			_spider_support_rows.append({"body": body.name, "gravity_compensation": compensation, "height_error": error, "has_floor": has_floor, "force": force})
	# Follow the Torso attachment with force on the upper limb only. No equal
	# reaction is applied to Torso, so this servo cannot make the leg carry it.
	for chain: Dictionary in _chains.values():
		for joint: Generic6DOFJoint3D in chain.joints:
			if not is_instance_valid(joint): continue
			if not joint.get_meta(&"spider_independent_root", false): continue
			var upper := joint.get_node_or_null(joint.node_a) as RigidBody3D
			var torso := joint.get_node_or_null(joint.node_b) as RigidBody3D
			if upper == null or torso == null or upper.freeze or _is_body_broken(upper) or _is_body_broken(torso): continue
			var upper_frame: Transform3D = joint.get_meta(&"generated_joint_frame_a")
			var torso_frame: Transform3D = joint.get_meta(&"generated_joint_frame_b")
			var anchor := torso.to_global(torso_frame.origin)
			var current := upper.to_global(upper_frame.origin)
			var target_velocity := torso.linear_velocity + torso.angular_velocity.cross(anchor - torso.global_position)
			var current_velocity := upper.linear_velocity + upper.angular_velocity.cross(current - upper.global_position)
			var rate := TAU * root_follow_frequency
			var acceleration := ((anchor - current) * rate * rate + (target_velocity - current_velocity) * 2.0 * rate).limit_length(root_follow_maximum_acceleration)
			var state := PhysicsServer3D.body_get_direct_state(upper.get_rid())
			if state == null: continue
			upper.apply_central_force((acceleration - state.total_gravity) * upper.mass)
			_spider_root_rows.append({"upper": upper.name, "torso": torso.name, "gap": anchor.distance_to(current), "force": (acceleration - state.total_gravity) * upper.mass, "reaction_on_torso": Vector3.ZERO})

func get_stance_support_diagnostics() -> Dictionary:
	var result := super.get_stance_support_diagnostics()
	result["spider_independent_support"] = {"enabled": _independent_support_enabled(), "torsos": _spider_support_rows, "roots": _spider_root_rows}
	return result

@export_group("Spider Step Planning")
## Conservative travel around the authored bent pose, not a chain-length sphere.
@export_range(0.01, 0.3, 0.01) var stance_travel_length_ratio: float = 0.06
## Low-speed recovery delay only; reaching the rear boundary has no cooldown.
@export_range(0.1, 3.0, 0.05) var stalled_step_delay: float = 0.8
@export_range(0.0, 15.0, 0.5) var joint_limit_reserve_degrees: float = 5.0
@export_group("Spider Support Selection")
@export_range(0.01, 1.0, 0.01) var support_polygon_tolerance: float = 0.2
@export_group("Spider Liftoff Assist")
@export_range(0.0, 100.0, 1.0) var liftoff_assist_acceleration: float = 20.0
@export_range(0.0, 1.0, 0.05) var liftoff_assist_delay: float = 0.2
@export_range(0.1, 2.0, 0.05) var maximum_liftoff_time: float = 1.0
@export_group("Spider Contact Pivot")
## Keep damping while allowing the bent leg to rotate around its grounded toe.
@export_range(0.0, 1.0, 0.05) var grounded_joint_stiffness_ratio: float = 0.5
## A stepping chain must bend freely enough to lift, without losing its spring.
@export_range(0.0, 1.0, 0.05) var stepping_joint_stiffness_ratio: float = 0.15
@export_range(0.0, 1.0, 0.05) var stepping_joint_damping_ratio: float = 0.5
@export_group("Spider Touchdown")
@export_range(0.02, 0.3, 0.01) var touchdown_brake_time: float = 0.08
@export_range(1.0, 100.0, 1.0) var touchdown_brake_acceleration: float = 40.0
@export_range(0.01, 0.2, 0.01) var touchdown_confirmation_time: float = 0.04
@export_range(0.05, 1.0, 0.05) var touchdown_contact_speed_limit: float = 0.3
var _spider_stall_since: Dictionary = {}
var _spider_stances: Dictionary = {}
var _spider_support_checks: Dictionary = {}
var _spider_step_times: Dictionary = {}
var _spider_profiles: Dictionary = {}
var _spider_profile_context: Array = []
var _spider_motion_summary: Dictionary = {}

func _ensure_spider_profile_cache() -> void:
	var data := _get_gait_data()
	var context: Array = [Engine.get_physics_frames(), data, _legs.size(), _spider_step_times.hash(),
		get_input_movement_direction(), input_enabled, _turn_planning_active, _layout_turn_owned,
		_segment_goal_yaw, _segment_heading_initialized, _action_feet.size(), recovery_control_active,
		simplified_physics_mode, _adhesion_release_time_remaining > 0.0, structural_stride_enabled,
		structural_stride_safety_ratio, structural_landing_forward_ratio, touchdown_confirmation_time,
		data.target_speed if data != null else 0.0, data.maximum_step_frequency if data != null else 0.0,
		data.automatic_motion if data != null else false, data.gallop_enabled if data != null else false,
		_planar_mode_active()]
	if context == _spider_profile_context: return
	_spider_profile_context = context
	_spider_profiles.clear()
	_spider_motion_summary.clear()
	_automatic_profiles.clear()

func _get_expected_horizontal_speed() -> float:
	var charge := get_parent().get_node_or_null("ChargeAttackController3D")
	if charge != null and charge.owns_velocity(): return charge.get_expected_speed()
	_ensure_spider_profile_cache()
	if not _spider_motion_summary.has("speed"):
		_spider_motion_summary.speed = super._get_expected_horizontal_speed()
	return float(_spider_motion_summary.speed)

func get_planned_step_frequency() -> float:
	_ensure_spider_profile_cache()
	if not _spider_motion_summary.has("frequency"):
		_spider_motion_summary.frequency = super.get_planned_step_frequency()
	return float(_spider_motion_summary.frequency)

func refresh_physics_query_cache() -> void:
	_spider_profile_context.clear()
	_spider_profiles.clear()
	_spider_motion_summary.clear()
	_spider_last_touchdowns.clear()
	_spider_recovery_steps.clear()
	_spider_reach_geometry.clear()
	_spider_stride_intervals.clear()
	_spider_stall_since.clear()
	_spider_stances.clear()
	_spider_support_checks.clear()
	_spider_step_times.clear()
	super.refresh_physics_query_cache()
	# Shared chain capture restores relative limits; restore the absolute-Y
	# bounds before both physics and structural reach capture use them.
	for joint: Generic6DOFJoint3D in get_parent()._spider_angle_joints:
		get_parent()._update_spider_world_limits(joint)
	_spider_support_exclusions.clear()
	for body: Node in get_parent().find_children("*", "PhysicsBody3D", true, false):
		_spider_support_exclusions.append(body.get_rid())
	for foot: RigidBody3D in _chains:
		var chain: Dictionary = _chains[foot]
		if chain.joints.size() != 2 or chain.bodies.size() != 3: continue
		var knee: Generic6DOFJoint3D = chain.joints[0]
		var root_joint: Generic6DOFJoint3D = chain.joints[1]
		if knee.get_node_or_null(knee.node_b) != foot or root_joint.get_node_or_null(root_joint.node_a) != chain.bodies[1]: continue
		_spider_reach_geometry[foot] = STRIDE_GEOMETRY.build(root_joint, knee, chain.bodies[1], foot, chain.root, _get_foot_world_position(foot), deg_to_rad(joint_limit_reserve_degrees))

func get_spider_stride_limits(foot: RigidBody3D) -> Dictionary:
	var result := {"valid": false, "reason": "disabled_or_uncaptured"}
	if structural_stride_enabled and _spider_reach_geometry.has(foot):
		var direction := get_input_movement_direction().slide(Vector3.UP).normalized()
		if direction.is_zero_approx(): direction = _chains[foot].root.global_basis.x.slide(Vector3.UP).normalized()
		var local_direction: Vector3 = _chains[foot].root.global_basis.orthonormalized().inverse() * direction
		var cached: Dictionary = _spider_stride_intervals.get(foot, {})
		if cached.get("frame", -1) == Engine.get_physics_frames() and is_equal_approx(float(cached.get("safety", 0.0)), structural_stride_safety_ratio) and Vector3(cached.direction).is_equal_approx(local_direction): return cached.result
		result = STRIDE_GEOMETRY.interval(_spider_reach_geometry[foot], local_direction, structural_stride_safety_ratio)
		_spider_stride_intervals[foot] = {"frame": Engine.get_physics_frames(), "direction": local_direction, "safety": structural_stride_safety_ratio, "result": result}
	return result

func _stance_budget(foot: RigidBody3D) -> float:
	var structural := get_spider_stride_limits(foot)
	if structural.valid: return float(structural.half_travel)
	var bend := deg_to_rad(float(get_parent().spider_leg_bend_limit_degrees))
	return maxf(0.03, float(_chains[foot].length) * stance_travel_length_ratio * sin(bend))

func get_leg_step_distance(foot: RigidBody3D) -> float:
	if not _chains.has(foot): return super.get_leg_step_distance(foot)
	return minf(super.get_leg_step_distance(foot), _stance_budget(foot) * 2.0)

func _structural_landing_enabled(leg: RigidBody3D) -> bool:
	return not _planar_mode_active() and not _foot_heading_turn_active() and _action_feet.is_empty() and not _gallop_active() and get_spider_stride_limits(leg).valid

func _structural_landing_frame(leg: RigidBody3D, direction: Vector3, remaining_time: float) -> Dictionary:
	var limits := get_spider_stride_limits(leg)
	var torso: RigidBody3D = _chains[leg].root
	var reference: Vector3 = torso.to_global(_spider_reach_geometry[leg].reference)
	# Predict only the remaining airborne travel. Never spend spring stretch as reach.
	var travel := torso.linear_velocity.slide(Vector3.UP) * maxf(remaining_time, 0.0)
	return {"reference": reference + travel, "direction": direction.slide(Vector3.UP).normalized(), "half": float(limits.half_travel)}

func _find_structural_landing(leg: RigidBody3D, direction: Vector3, remaining_time: float) -> Dictionary:
	var frame := _structural_landing_frame(leg, direction, remaining_time)
	var toe := _get_foot_world_position(leg)
	# Every fallback stays in the leading interior, rather than sampling back
	# through the rear boundary when the first terrain candidate is obstructed.
	var count := maxi(landing_search_samples, 2)
	for index: int in count:
		var ratio := lerpf(structural_landing_forward_ratio, 0.2, float(index) / float(count - 1))
		var sample: Vector3 = frame.reference + frame.direction * float(frame.half) * ratio
		var from := sample + Vector3.UP * ray_start_height
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * ray_length, terrain_collision_mask, _get_character_exclusion_rids())
		query.collide_with_areas = false
		var hit := _intersect_ray(query)
		if not _is_landing_point_valid(leg, toe, hit): continue
		var projection := (Vector3(hit.position) - Vector3(frame.reference)).dot(frame.direction)
		if projection < float(frame.half) * 0.2 - 0.001 or projection > float(frame.half) * structural_landing_forward_ratio + 0.001: continue
		return hit
	_last_landing_rejection_reason = &"spider_no_interior_landing"
	return {}

func find_landing_point(leg: RigidBody3D, movement_direction: Vector3 = Vector3.RIGHT) -> Dictionary:
	if not _structural_landing_enabled(leg) or movement_direction.slide(Vector3.UP).is_zero_approx():
		return super.find_landing_point(leg, movement_direction)
	_last_landing_rejection_reason = &""
	return _find_structural_landing(leg, movement_direction, float(get_leg_motion_profile(leg).swing_duration))

func _refresh_structural_landing() -> void:
	if not _structural_landing_enabled(_active_leg) or _current_step.direction.slide(Vector3.UP).is_zero_approx(): return
	var remaining := maxf(_active_step_duration - _step_elapsed, 0.0)
	var frame := _structural_landing_frame(_active_leg, _current_step.direction, remaining)
	var old_point: Vector3 = _current_step.extra.get("landing_surface_point", _get_foot_world_position(_active_leg))
	var projection := (old_point - Vector3(frame.reference)).dot(frame.direction)
	# Reuse a legal terrain hit until it leaves the interior band; avoid a
	# new ray query on every airborne foot on every physics tick.
	if projection >= float(frame.half) * 0.2 and projection <= float(frame.half) * structural_landing_forward_ratio and _current_step.extra.has("spider_landing"): return
	var hit := _find_structural_landing(_active_leg, _current_step.direction, remaining)
	if hit.is_empty(): return
	_step_target = _body_position_for_ground_contact(_active_leg, hit.position)
	_current_step.extra["landing_surface_point"] = hit.position
	_current_step.extra["spider_landing"] = {"target": hit.position, "predicted_reference": frame.reference, "remaining_air_time": remaining, "half_travel": frame.half, "forward_projection": (Vector3(hit.position) - Vector3(frame.reference)).dot(frame.direction)}

func _get_projected_landing_rest_position(leg: RigidBody3D, direction: Vector3) -> Vector3:
	if _planar_mode_active() or _foot_heading_turn_active() or not _action_feet.is_empty() or _gallop_active():
		return super._get_projected_landing_rest_position(leg, direction)
	var limits := get_spider_stride_limits(leg)
	if not limits.valid: return super._get_projected_landing_rest_position(leg, direction)
	var reference: Vector3 = _chains[leg].root.to_global(_spider_reach_geometry[leg].reference)
	# The shared terrain sampler adds a FULL stride. Aim its first candidate
	# at the leading half of the structural contact interval instead.
	return reference + direction.slide(Vector3.UP).normalized() * (minf(float(limits.half_travel), get_leg_step_distance(leg) * 0.5) - get_leg_step_distance(leg))

func _get_extension_step_demand(foot: RigidBody3D, direction: Vector3) -> Dictionary:
	var result := super._get_extension_step_demand(foot, direction)
	if not _extension_gait_enabled() or direction.is_zero_approx() or not _chain_is_intact(foot) or is_leg_stepping(foot) or not is_leg_grounded(foot) or _action_feet.has(foot):
		_spider_stall_since.erase(foot)
		return result
	if _spider_recovery_steps.has(foot):
		result.requested = true
		result.reason = "spider_incomplete_landing_recovery"
		result.remaining_distance = 0.0
		result["retry_in"] = 0.0
		return result
	if result.reason == "startup": return result
	var travel := direction.slide(Vector3.UP).normalized()
	var root_body: RigidBody3D = _chains[foot].root
	var budget := _stance_budget(foot)
	var stance := _get_spider_stance_travel(foot, travel)
	var progress := float(stance.progress)
	var remaining := maxf(minf(float(result.remaining_distance), budget * 2.0 - progress), 0.0)
	var structural := get_spider_stride_limits(foot)
	if structural.valid:
		var reference: Vector3 = root_body.to_global(_spider_reach_geometry[foot].reference)
		var remaining_to_rear := (Vector3(stance.anchor) - reference).dot(travel) + float(structural.half_travel)
		remaining = maxf(minf(remaining, remaining_to_rear), 0.0)
	var margin := _get_spider_joint_margin(foot)
	var near_limit := margin <= joint_limit_reserve_degrees and progress > budget * 0.25
	if near_limit: remaining = 0.0
	var speed := root_body.linear_velocity.dot(travel)
	var stalled := speed < get_expected_horizontal_speed() * 0.25
	if stalled:
		if not _spider_stall_since.has(foot): _spider_stall_since[foot] = _physics_elapsed
	else:
		_spider_stall_since.erase(foot)
	var stalled_time := _physics_elapsed - float(_spider_stall_since.get(foot, _physics_elapsed))
	var predicted := maxf(speed, get_expected_horizontal_speed()) * 0.15
	result.policy = "spider_contact_travel"
	result["stance_progress"] = progress
	result["stance_anchor"] = stance.anchor
	result["joint_limit_margin_degrees"] = margin
	result["joint_limit_near"] = near_limit
	result["stance_travel_budget"] = budget
	result["geometric_remaining"] = result.remaining_distance
	result.remaining_distance = remaining
	result["stall_elapsed"] = stalled_time
	result["retry_in"] = 0.0
	result.requested = remaining <= maxf(budget * 0.2, predicted) or stalled_time >= stalled_step_delay
	result.reason = "spider_stall_recovery" if result.requested and stalled_time >= stalled_step_delay else ("spider_stance_limit" if result.requested else "spider_holding")
	return result

func _begin_leg_motion(foot: RigidBody3D, target: Vector3, normal: Vector3 = Vector3.UP, direction: Vector3 = Vector3.ZERO) -> void:
	_spider_stall_since.erase(foot)
	_spider_stances.erase(foot)
	super._begin_leg_motion(foot, target, normal, direction)
	_current_step.extra["spider_started_at"] = _physics_elapsed
	if _chains.has(foot): _current_step.extra["spider_root_at_start"] = _chains[foot].root.global_position
	if _structural_landing_enabled(foot) and not direction.slide(Vector3.UP).is_zero_approx():
		var profile: Dictionary = _current_step.extra.automatic_profile
		var distance := (target - foot.global_position).slide(Vector3.UP).length()
		var nominal := _active_step_duration
		var recovery := _spider_recovery_steps.has(foot)
		_external_step_height = minf(float(profile.lift) * step_lift_multiplier + distance * (0.15 if recovery else 0.08), float(_chains[foot].length) * 0.15)
		var plan := _plan_spider_catch_up(profile, distance, nominal, _external_step_height, recovery)
		_active_step_duration = plan.duration
		profile.position_gain = maxf(float(profile.position_gain), plan.position_gain)
		profile.velocity_gain = 2.0 * sqrt(float(profile.position_gain))
		profile.step_acceleration = plan.acceleration_budget
		_current_step.extra["spider_catch_up"] = plan

func _plan_spider_catch_up(profile: Dictionary, distance: float, nominal: float, height: float, recovery: bool) -> Dictionary:
	# Use configured demand, never the gait's already reduced reachable speed.
	var target_speed := maxf(float(profile.target_speed), 0.0)
	var reference_time := maxf(nominal, 0.06)
	var requested_speed := maxf(target_speed * catch_up_speed_ratio, distance / reference_time)
	var gravity := _gravity_acceleration().length()
	var acceleration_budget := clampf(maxf(float(profile.step_acceleration),
		8.0 * target_speed * target_speed / maxf(float(profile.stride), 0.1) + gravity), 30.0, 2000.0)
	var travel := maxf(distance, height)
	# The ideal acceleration envelope omits hinge resistance and solver delay.
	var minimum_time := sqrt(8.0 * travel / maxf(acceleration_budget - gravity, 1.0)) * 1.2
	var speed_cap := distance / maxf(minimum_time, 0.01)
	var relative_speed := minf(requested_speed, speed_cap)
	var requested_time := distance / maxf(relative_speed, 0.01) * (1.25 if recovery else 1.0)
	# A duration cap must not demand acceleration above the physical force budget.
	var duration := maxf(reference_time, maxf(minf(requested_time, maximum_catch_up_duration), minimum_time))
	return {"distance": distance, "target_speed": target_speed, "requested_relative_speed": requested_speed,
		"relative_speed": relative_speed, "speed_cap": speed_cap, "acceleration_limited": requested_speed > speed_cap + 0.001,
		"nominal_duration": nominal, "duration": duration, "minimum_safe_duration": minimum_time,
		"duration_cap_exceeded": duration > maximum_catch_up_duration + 0.001,
		"acceleration_budget": acceleration_budget, "position_gain": clampf(16.0 / (duration * duration), 20.0, 4000.0),
		"height": height, "recovery": recovery, "policy": "target_speed_and_distance"}

func _spider_landing_verdict(leg: RigidBody3D, target: Vector3, frame: Dictionary) -> Dictionary:
	var toe := _get_foot_world_position(leg)
	var error := (target - toe).slide(Vector3.UP).length()
	var projection := (toe - Vector3(frame.reference)).dot(frame.direction)
	var tolerance := maxf(float(frame.half) * touchdown_target_tolerance_ratio, 0.02)
	var inside := absf(projection) < float(frame.half)
	return {"target": target, "target_error": error, "target_tolerance": tolerance, "inside_interval": inside, "forward_projection": projection, "rear_remaining": projection + float(frame.half), "valid": inside and error <= tolerance}

func _finish_current_step() -> void:
	if is_instance_valid(_active_leg) and _structural_landing_enabled(_active_leg) and not _current_step.direction.slide(Vector3.UP).is_zero_approx():
		var verdict: Dictionary = _current_step.extra.get("spider_completion", {})
		if _current_step.extra.has("spider_completion_frame"):
			verdict = _spider_landing_verdict(_active_leg, verdict.target, _current_step.extra.spider_completion_frame)
			_current_step.extra.spider_completion = verdict
			if _spider_last_touchdowns.has(_active_leg): _spider_last_touchdowns[_active_leg]["completion"] = verdict
		if verdict.is_empty() or not verdict.valid:
			var foot := _active_leg
			_spider_recovery_steps[foot] = int(_spider_recovery_steps.get(foot, 0)) + 1
			if _spider_last_touchdowns.has(foot):
				_spider_last_touchdowns[foot]["completed"] = false
				_spider_last_touchdowns[foot]["recovery_attempts"] = _spider_recovery_steps[foot]
			_record_spider_step_time()
			_log_gait_event(&"step_incomplete", foot, &"early_touchdown", _current_step.direction, _step_target)
			cancel_step(&"spider_early_touchdown")
			return
		_spider_recovery_steps.erase(_active_leg)
		if _spider_last_touchdowns.has(_active_leg): _spider_last_touchdowns[_active_leg]["completed"] = true
	super._finish_current_step()

func _record_touchdown() -> void:
	_record_spider_step_time()
	super._record_touchdown()

func _handle_step_timeout(grounded: bool) -> void:
	_record_spider_step_time()
	super._handle_step_timeout(grounded)

func _record_spider_step_time() -> void:
	if not is_instance_valid(_active_leg) or not _current_step.extra.has("spider_started_at"): return
	if _current_step.extra.get("spider_time_recorded", false): return
	_current_step.extra["spider_time_recorded"] = true
	var elapsed := maxf(_physics_elapsed - float(_current_step.extra.spider_started_at), 0.05)
	var previous := float(_spider_step_times.get(_active_leg, elapsed))
	# Bound adaptation so a single collision cannot abruptly change gait speed.
	_spider_step_times[_active_leg] = lerpf(previous, clampf(elapsed, previous * 0.75, previous * 1.25), 0.2)

func get_automatic_motion_diagnostics() -> Dictionary:
	var result := super.get_automatic_motion_diagnostics()
	for profile: Dictionary in result.legs:
		for foot: RigidBody3D in _legs:
			if profile.foot != foot.name or not _chains.has(foot): continue
			profile["spider_stance_budget"] = _stance_budget(foot)
			profile["spider_landing_stride"] = get_leg_step_distance(foot)
			profile["spider_stall_delay"] = stalled_step_delay
			profile["spider_structural_stride"] = get_spider_stride_limits(foot)
	return result

# A box's vertical extent gives the correct height but the wrong horizontal
# position for an inclined long leg. Use the centre of its lowest edge/face.
func _get_foot_world_position(leg: RigidBody3D) -> Vector3:
	var collision := _find_leg_collision_shape(leg)
	if collision == null or not collision.shape is BoxShape3D:
		return super._get_foot_world_position(leg)
	var gravity := _gravity_acceleration()
	var up := -gravity.normalized() if not gravity.is_zero_approx() else Vector3.UP
	var half: Vector3 = collision.shape.size * 0.5
	var local_point := Vector3.ZERO
	for axis: int in 3:
		var slope := collision.global_basis[axis].dot(up)
		if absf(slope) > 0.0001: local_point[axis] = -signf(slope) * half[axis]
	return collision.to_global(local_point)

func _get_support_pin_world_position(leg: RigidBody3D) -> Vector3:
	return _get_foot_world_position(leg)

func _update_support_foot_lock(leg: RigidBody3D, normal: Vector3) -> void:
	if _foot_heading_turn_active() and not _planar_mode_active():
		_release_support_pin(leg)
		return
	super._update_support_foot_lock(leg, normal)

func _keep_touchdown_support_pin(leg: RigidBody3D) -> bool:
	if _foot_heading_turn_active() and not _planar_mode_active(): return false
	return _keep_touchdown_support_pin_for_spider(leg) or super._keep_touchdown_support_pin(leg)

func update_leg_surface_adhesion() -> void:
	super.update_leg_surface_adhesion()
	var character := get_parent()
	for foot: RigidBody3D in _chains:
		var stepping := is_leg_stepping(foot)
		var ratio := stepping_joint_stiffness_ratio if stepping else grounded_joint_stiffness_ratio
		for joint: Generic6DOFJoint3D in _chains[foot].joints:
			if not is_instance_valid(joint) or not joint.has_meta(&"authored_walk_limits"): continue
			var spring: Vector2 = character.get_spider_joint_spring(joint)
			var weights := Vector2(ratio, stepping_joint_damping_ratio if stepping else 1.0)
			# Release promptly for lift; restore over 0.15 seconds after contact.
			if not stepping:
				weights = Vector2(joint.get_meta(&"spider_spring_weights", weights)).move_toward(weights, get_physics_process_delta_time() / 0.15)
			joint.set_meta(&"spider_spring_weights", weights)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, spring.x * weights.x)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, spring.y * weights.y)

func get_support_foot_diagnostics(leg: RigidBody3D) -> Dictionary:
	var result := super.get_support_foot_diagnostics(leg)
	result["pin_kind"] = "contact_pivot" if _support_pins.has(leg) else "none"
	result["contact_point"] = _get_ground_contact_world_position(leg)
	result["body_center"] = leg.global_position
	var hit := _get_surface_below_leg(leg, surface_adhesion_probe_distance)
	result["contact_velocity"] = _get_ground_contact_velocity(leg, hit)
	result["speed"] = Vector3(result.contact_velocity).slide(Vector3.UP).length()
	var motion := _find_step_motion_for_spider(leg)
	result["spider_touchdown"] = motion.extra.get("spider_touchdown", {}).duplicate() if motion != null else {}
	result["spider_landing"] = motion.extra.get("spider_landing", {}).duplicate() if motion != null else {}
	result["spider_last_touchdown"] = _spider_last_touchdowns.get(leg, {})
	result["spider_catch_up"] = motion.extra.get("spider_catch_up", {}) if motion != null else {}
	result["spider_recovery_attempts"] = int(_spider_recovery_steps.get(leg, 0))
	result["grounded_stiffness_ratio"] = grounded_joint_stiffness_ratio
	result["stepping_stiffness_ratio"] = stepping_joint_stiffness_ratio
	result["stepping_damping_ratio"] = stepping_joint_damping_ratio
	var springs: Array[Dictionary] = []
	if _chains.has(leg):
		for joint: Generic6DOFJoint3D in _chains[leg].joints:
			if not is_instance_valid(joint): continue
			springs.append({"joint": joint.name, "effective_inertia": joint.get_meta(&"spider_effective_inertia", 1.0), "stiffness": joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS), "damping": joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING), "weights": joint.get_meta(&"spider_spring_weights", Vector2.ONE)})
			if joint.has_meta(&"spider_world_angle"):
				springs[-1]["absolute_limit_degrees"] = get_parent().spider_leg_bend_limit_degrees
				springs[-1]["relative_z_limits_degrees"] = Vector2(rad_to_deg(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)), rad_to_deg(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)))
			if joint.has_meta(&"spider_axial_slide"):
				var slide: Dictionary = joint.get_meta(&"spider_axial_slide").duplicate()
				slide["independent_root"] = joint.get_meta(&"spider_independent_root", false)
				slide["linear_limit_enabled"] = joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)
				slide["linear_spring_enabled"] = joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING)
				var a := joint.get_node_or_null(joint.node_a) as RigidBody3D
				var b := joint.get_node_or_null(joint.node_b) as RigidBody3D
				if a != null and b != null:
					var frame_a: Transform3D = a.global_transform * Transform3D(joint.get_meta(&"generated_joint_frame_a"))
					var frame_b: Transform3D = b.global_transform * Transform3D(joint.get_meta(&"generated_joint_frame_b"))
					slide["axis_world"] = frame_a.basis.y.normalized()
					slide["offset"] = (frame_b.origin - frame_a.origin).dot(slide.axis_world)
				springs[-1]["axial_slide"] = slide
	result["spider_joint_springs"] = springs
	result["turn_released"] = _foot_heading_turn_active() and not _planar_mode_active()
	result["spider_support_selection"] = _spider_support_checks.get(leg, {}).duplicate()
	result["spider_liftoff"] = motion.extra.get("spider_liftoff", {}).duplicate() if motion != null else {}
	return result

# Keep the real geometry for reach/turning, but derive walking time and lift
# from the same short stride that the bent chain actually uses.
func get_leg_motion_profile(leg: RigidBody3D) -> Dictionary:
	var started := _movement_perf.start()
	_ensure_spider_profile_cache()
	if _spider_profiles.has(leg):
		_movement_perf.count(&"spider_profile_cache_hits")
		_movement_perf.finish(&"spider_profile_lookup", started)
		return _spider_profiles[leg]
	var profile := _calculate_spider_motion_profile(leg)
	_spider_profiles[leg] = profile
	_movement_perf.count(&"spider_profile_builds")
	_movement_perf.finish(&"spider_profile_lookup", started)
	return profile

func _calculate_spider_motion_profile(leg: RigidBody3D) -> Dictionary:
	var original := super.get_leg_motion_profile(leg)
	if original.is_empty() or not _chains.has(leg): return original
	var profile := original.duplicate()
	var stride := minf(float(original.stride), _stance_budget(leg) * 2.0)
	var count := maxi(_legs.size(), 1)
	var capacity := maxi(int(profile.support_capacity), 1)
	var observed := float(_spider_step_times.get(leg, 0.0))
	var structural_limit := _stance_budget(leg) * 2.0
	var usable_limit := structural_limit
	var required_stride := stride
	var admission_reserve := 0.0
	if _automatic_motion_enabled() and _structural_landing_enabled(leg):
		var half := structural_limit * 0.5
		# A support phase runs from an interior landing to the rear trigger,
		# not from the full front boundary to the full rear boundary.
		admission_reserve = maxf(half * 0.2, float(profile.target_speed) * 0.15)
		usable_limit = maxf(0.02, half * (1.0 + structural_landing_forward_ratio) - admission_reserve)
		usable_limit = minf(usable_limit, structural_limit)
		var occupied_estimate := maxf(observed * 1.1, float(original.swing_duration) + touchdown_confirmation_time)
		var support_time := occupied_estimate * maxf(float(count) / capacity - 1.0, 0.0)
		required_stride = float(profile.target_speed) * support_time
		stride = minf(maxf(stride, required_stride), usable_limit)
	# The reach budget is spent while planted. During swing the body keeps
	# travelling; charging that time against the planted reach underestimates
	# attainable speed. The global frequency and support budget still apply.
	var duty := minf(float(capacity) / count * 0.8, 0.8)
	var cycle := stride / maxf(float(profile.target_speed) * (1.0 - duty), 0.01)
	var frequency_limit := float(profile.maximum_step_frequency)
	if frequency_limit > 0.0: cycle = maxf(cycle, count / frequency_limit)
	cycle = maxf(cycle, count * 0.10 / capacity)
	var available := cycle * capacity / count
	var swing := clampf(available * 0.8, 0.06, 0.35)
	# The assist delay is when extra lift ramps in, not a mandatory phase.
	# Observed time already includes lift, travel and contact confirmation.
	var nominal_occupied := swing + touchdown_confirmation_time
	var occupied := maxf(nominal_occupied, observed * 1.1)
	cycle = maxf(cycle, count * occupied / capacity)
	# Long inclined collision boxes need geometric clearance even with short strides.
	var lift := clampf(float(profile.length) * 0.035 + stride * 0.04, 0.03, float(profile.length) * 0.1)
	var gain := clampf(16.0 / (swing * swing), 20.0, 4000.0)
	profile.stride = stride
	profile.maximum_stride = usable_limit
	profile["structural_stride_limit"] = structural_limit
	profile["usable_stance_stride_limit"] = usable_limit
	profile["required_stance_stride"] = required_stride
	profile["step_admission_distance_reserve"] = admission_reserve
	profile["stride_adapted_to_observed_time"] = stride > float(original.stride) + 0.001
	profile.cycle = cycle
	profile.frequency = 1.0 / cycle if profile.target_speed > 0.0 else 0.0
	profile.total_frequency = profile.frequency * count
	profile.swing_duration = swing
	profile.lift = lift
	profile.landing_timeout = maxf(0.3, swing * 2.0)
	profile.position_gain = gain
	profile.velocity_gain = 2.0 * sqrt(gain)
	profile.required_step_acceleration = 8.0 * maxf(stride, lift) / (swing * swing) + 9.8
	profile.step_acceleration = clampf(profile.required_step_acceleration, 30.0, 2000.0)
	profile.drive_acceleration_limited = profile.required_step_acceleration > profile.step_acceleration
	profile["observed_step_duration"] = observed
	profile["nominal_occupied_step_duration"] = nominal_occupied
	profile["observed_duration_safety_ratio"] = 1.1
	profile["occupied_duration_source"] = "observed_with_margin" if observed * 1.1 > nominal_occupied else "nominal_swing_and_confirmation"
	profile["occupied_step_duration"] = occupied
	profile["stance_duration"] = maxf(cycle - occupied, 0.01)
	profile.reachable_speed = minf(float(profile.target_speed), stride / profile.stance_duration)
	profile["cycle_travel"] = profile.reachable_speed * cycle
	profile["airborne_body_travel"] = profile.reachable_speed * occupied
	profile.speed_limited = profile.reachable_speed + 0.001 < profile.target_speed
	profile.limiting_reason = "spider_stride_and_reference_frequency" if profile.speed_limited else "none"
	profile["spider_profile"] = true
	return profile

func _keep_touchdown_support_pin_for_spider(leg: RigidBody3D) -> bool:
	for motion: StepMotion in _active_steps:
		if motion.leg == leg and motion.extra.has("spider_touchdown"):
			return _support_pins.has(leg) and not is_leg_slipping(leg) and not _is_body_broken(leg) and is_leg_grounded(leg) and _adhesion_release_time_remaining <= 0.0
	return false

func _update_active_step(delta: float) -> void:
	if _planar_mode_active() or not is_instance_valid(_active_leg) or not _chain_is_intact(_active_leg):
		super._update_active_step(delta)
		return
	# Separate toe lift from horizontal travel. A short-stride trajectory must
	# not spend its entire swing dragging a long, inclined box on the ground.
	if not _step_has_lifted:
		var elapsed := float(_current_step.extra.get("spider_liftoff_elapsed", 0.0)) + delta
		_current_step.extra["spider_liftoff_elapsed"] = elapsed
		var contact := _get_surface_below_leg(_active_leg, surface_adhesion_probe_distance)
		var normal: Vector3 = contact.get("normal", Vector3.UP)
		var toe := _get_foot_world_position(_active_leg)
		var gap: float = (toe - Vector3(contact.position)).dot(normal) if not contact.is_empty() else _step_start_clearance + minimum_step_lift_clearance
		var clearance := _step_start_clearance + maxf(_get_effective_step_height() * 0.6, minimum_step_lift_clearance * 2.0)
		# Track toe clearance, not an old body-centre Y. Rotation can raise the
		# centre while leaving the toe on the floor.
		var desired := _active_leg.global_position + normal * maxf(clearance - gap, 0.0)
		var root_body: RigidBody3D = _chains[_active_leg].root
		var root_velocity := root_body.linear_velocity + root_body.angular_velocity.cross(_active_leg.global_position - root_body.global_position)
		var contact_spin := _active_leg.angular_velocity.cross(toe - _active_leg.global_position)
		var desired_velocity := root_velocity.slide(normal) - normal * contact_spin.dot(normal)
		super._apply_leg_tracking_force(desired, desired_velocity)
		var gravity := _gravity_acceleration()
		var up := -gravity.normalized() if not gravity.is_zero_approx() else Vector3.UP
		var ramp := smoothstep(liftoff_assist_delay, liftoff_assist_delay + 0.3, elapsed)
		var acceleration := liftoff_assist_acceleration * ramp
		var assist := up * _active_leg.mass * acceleration
		# Bounded extra lift is local to this foot. No Torso force or teleport.
		_active_leg.apply_central_force(assist)
		_tracking_force += assist
		# The servo above applies its resultant at the centre. Add only the
		# equivalent moment of its normal component at the toe, so lifting bends
		# the chain instead of merely raising/rotating the centre around the toe.
		_active_leg.apply_torque((toe - _active_leg.global_position).cross(normal * _tracking_force.dot(normal)))
		_current_step.extra["spider_liftoff"] = {"elapsed": elapsed, "assist_force": assist, "assist_acceleration": acceleration, "timeout": maxf(maximum_liftoff_time, _active_step_duration * 2.0), "toe_gap": gap, "target_clearance": clearance, "horizontal_reference": desired_velocity.slide(normal)}
		if _step_has_lifted:
			_current_step.extra["liftoff_complete"] = true
			# Start the travel curve from the actual lifted pose, not the pose
			# from before the body advanced during the liftoff phase.
			_step_start = _active_leg.global_position
			var root_travel: Vector3 = root_body.global_position - Vector3(_current_step.extra.get("spider_root_at_start", root_body.global_position))
			_step_target += root_travel.slide(normal)
		elif elapsed >= maxf(maximum_liftoff_time, _active_step_duration * 2.0):
			_handle_step_timeout(is_leg_grounded(_active_leg))
		return
	var hit := _support_surface_contact(_active_leg)
	var landed := false
	if _step_has_lifted and not hit.is_empty():
		var normal: Vector3 = hit.normal
		var gap := (_get_foot_world_position(_active_leg) - Vector3(hit.position)).dot(normal)
		landed = absf(gap) <= 0.04 and (_current_step.extra.has("spider_touchdown") or _get_ground_contact_velocity(_active_leg, hit).dot(normal) <= 0.5)
	if not landed:
		if _current_step.extra.has("spider_touchdown"):
			_current_step.extra.erase("spider_touchdown")
			_release_support_pin(_active_leg)
		_refresh_structural_landing()
		super._update_active_step(delta)
		return
	var normal: Vector3 = hit.normal
	if not _current_step.extra.has("spider_touchdown"):
		if _structural_landing_enabled(_active_leg) and not _current_step.direction.slide(Vector3.UP).is_zero_approx():
			var frame := _structural_landing_frame(_active_leg, _current_step.direction, 0.0)
			var frozen_target: Vector3 = _current_step.extra.get("landing_surface_point", hit.position)
			_current_step.extra["spider_completion_frame"] = frame
			_current_step.extra["spider_completion"] = _spider_landing_verdict(_active_leg, frozen_target, frame)
			var projection := (_get_foot_world_position(_active_leg) - Vector3(frame.reference)).dot(frame.direction)
			_spider_last_touchdowns[_active_leg] = {"time": _physics_elapsed, "sequence": _current_step.sequence, "forward_projection": projection, "rear_remaining": projection + float(frame.half), "half_travel": frame.half, "inside_interval": absf(projection) < float(frame.half), "target_error": (frozen_target - _get_foot_world_position(_active_leg)).slide(Vector3.UP).length(), "completion": _current_step.extra.spider_completion, "completed": false}
		_current_step.extra["spider_touchdown"] = {"local_point": _active_leg.to_local(_get_foot_world_position(_active_leg)), "elapsed": 0.0, "stable_time": 0.0}
		_step_state = StepState.LANDING
		_landing_elapsed = 0.0
	var touchdown: Dictionary = _current_step.extra.spider_touchdown
	var point := _active_leg.to_global(touchdown.local_point)
	var velocity := _get_ground_contact_velocity(_active_leg, hit)
	# Discard the launch-time destination immediately. Only contact braking
	# remains; applying it at the toe preserves rotation about a fixed pivot.
	_step_target = _active_leg.global_position
	_current_step.extra.landing_surface_point = hit.position
	_tracking_position_error = Vector3.ZERO
	_tracking_gravity_force = Vector3.ZERO
	var acceleration := (-velocity.slide(normal) / maxf(touchdown_brake_time, 0.001)).limit_length(touchdown_brake_acceleration)
	_tracking_force = acceleration * _active_leg.mass
	_active_leg.apply_force(_tracking_force, point - _active_leg.global_position)
	_update_support_foot_lock(_active_leg, normal)
	touchdown.elapsed += delta
	touchdown["contact_velocity"] = velocity
	touchdown["brake_force"] = _tracking_force
	touchdown["horizontal_tracking"] = false
	touchdown.stable_time = float(touchdown.stable_time) + delta if velocity.slide(normal).length() <= touchdown_contact_speed_limit and absf(velocity.dot(normal)) <= 0.5 else 0.0
	_landing_elapsed += delta
	if touchdown.stable_time >= touchdown_confirmation_time:
		_finish_current_step()
	elif _landing_elapsed >= _get_effective_landing_timeout():
		_handle_step_timeout(true)

func _find_step_motion_for_spider(leg: RigidBody3D) -> StepMotion:
	for motion: StepMotion in _active_steps:
		if motion.leg == leg: return motion
	return null

func _get_ground_contact_world_position(leg: RigidBody3D) -> Vector3:
	if _support_pins.has(leg): return super._get_ground_contact_world_position(leg)
	var motion := _find_step_motion_for_spider(leg)
	if motion != null and motion.extra.has("spider_touchdown"):
		return leg.to_global(motion.extra.spider_touchdown.local_point)
	return super._get_ground_contact_world_position(leg)

# Each stance starts at the actual touchdown pose. Measure root travel relative
# to the terrain anchor, not motion of the rotating lower-leg centre.
func _get_spider_stance_travel(foot: RigidBody3D, travel: Vector3) -> Dictionary:
	var root_body: RigidBody3D = _chains[foot].root
	var anchor := _get_ground_contact_world_position(foot)
	if _support_pins.has(foot):
		var entry: Dictionary = _support_pins[foot]
		anchor = entry.terrain.to_global(entry.local_anchor) if is_instance_valid(entry.terrain) else entry.local_anchor
	var pin: Object = _support_pins[foot].joint if _support_pins.has(foot) else null
	if not _spider_stances.has(foot) or _spider_stances[foot].pin != pin:
		_spider_stances[foot] = {"pin": pin, "root_offset": root_body.global_position - anchor}
	var progress := (root_body.global_position - anchor - Vector3(_spider_stances[foot].root_offset)).dot(travel)
	return {"anchor": anchor, "progress": progress}

func _release_support_pin(leg) -> void:
	_spider_stances.erase(leg)
	super._release_support_pin(leg)

func _get_spider_joint_margin(foot: RigidBody3D) -> float:
	var chain: Dictionary = _chains[foot]
	var margin := 180.0
	for index: int in range(chain.joints.size()):
		var joint: Generic6DOFJoint3D = chain.joints[index]
		var child: RigidBody3D = chain.bodies[index]
		if child.has_meta(&"spider_world_bend_limit"):
			var up_axis := child.global_basis.y.normalized() * float(child.get_meta(&"spider_up_axis_sign"))
			margin = minf(margin, rad_to_deg(float(child.get_meta(&"spider_world_bend_limit")) - acos(clampf(up_axis.dot(Vector3.UP), -1.0, 1.0))))
			continue
		var parent_body: RigidBody3D = chain.bodies[index + 1]
		if not is_instance_valid(joint) or not joint.has_meta(&"authored_walk_limits"): continue
		var relative := parent_body.global_basis.orthonormalized().get_rotation_quaternion().inverse() * child.global_basis.orthonormalized().get_rotation_quaternion()
		var error: Quaternion = relative * Quaternion(chain.rest_rotations[index]).inverse()
		var axis := parent_body.global_basis.orthonormalized().inverse() * joint.global_basis.z.normalized()
		var angle := wrapf(2.0 * atan2(Vector3(error.x, error.y, error.z).dot(axis), error.w), -PI, PI)
		margin = minf(margin, rad_to_deg(Vector3(joint.get_meta(&"authored_walk_limits")).z - absf(angle)))
	return margin

func _support_polygon_error(points: PackedVector2Array, center: Vector2) -> float:
	if points.is_empty(): return INF
	if points.size() == 1: return center.distance_to(points[0])
	var hull := Geometry2D.convex_hull(points)
	if hull.size() >= 4 and Geometry2D.is_point_in_polygon(center, hull): return 0.0
	var distance := INF
	for index: int in range(hull.size() - 1):
		distance = minf(distance, center.distance_to(Geometry2D.get_closest_point_to_segment(center, hull[index], hull[index + 1])))
	return distance

func _can_start_step_with_support(leg: RigidBody3D) -> bool:
	if not super._can_start_step_with_support(leg):
		_spider_support_checks[leg] = {"allowed": false, "reason": "base_support_budget", "time": _physics_elapsed}
		return false
	# Keep the existing physical turn/action/flight admission contracts.
	if _planar_mode_active() or _foot_heading_turn_active() or not _action_feet.is_empty() or _gallop_active(): return true
	var all_contacts := PackedVector2Array()
	var remaining := PackedVector2Array()
	for foot: RigidBody3D in _legs:
		if not _chain_is_intact(foot) or is_leg_stepping(foot) or not is_leg_grounded(foot) or is_leg_slipping(foot): continue
		var point := _get_ground_contact_world_position(foot)
		var flat := Vector2(point.x, point.z)
		all_contacts.append(flat)
		if foot != leg: remaining.append(flat)
	var center := _stance_center_of_mass if _stance_total_mass > 0.0 else _torso.global_position
	var flat_center := Vector2(center.x, center.z)
	var before := _support_polygon_error(all_contacts, flat_center)
	var after := _support_polygon_error(remaining, flat_center)
	# An already unbalanced stance can still recover by removing an unloaded
	# foot, but removing a foot must never further shrink its usable support.
	var allowed := after <= support_polygon_tolerance or (before > support_polygon_tolerance and after <= before + 0.001)
	_spider_support_checks[leg] = {"allowed": allowed, "reason": "stable_support" if allowed else "support_polygon_would_shrink", "before_error": before, "after_error": after, "remaining_feet": remaining.size(), "time": _physics_elapsed}
	return allowed
