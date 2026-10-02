extends Node

const LEG_TAG: int = 1
const TORSO_TAG: int = 0
const MIN_STEP_TIME: float = 0.001

enum StepState { IDLE, MOVING, LANDING }

@export_group("Control")
@export var input_enabled: bool = true

@export_group("Landing Search")
@export_flags_3d_physics var terrain_collision_mask: int = 1
@export_range(0.01, 10.0, 0.01, "or_greater") var minimum_step_distance: float = 0.15
@export_range(1, 16, 1) var landing_search_samples: int = 4
@export_range(0.01, 10.0, 0.01, "or_greater") var ray_start_height: float = 1.0
@export_range(0.01, 20.0, 0.01, "or_greater") var ray_length: float = 3.0
@export_range(0.0, 89.0, 0.1) var maximum_slope_angle: float = 40.0
@export_range(0.0, 10.0, 0.01, "or_greater") var maximum_step_up: float = 0.6
@export_range(0.0, 10.0, 0.01, "or_greater") var maximum_step_down: float = 1.0
## Maximum XZ-plane distance from the Torso center to a landing point.
## Vertical reach is validated separately by maximum_step_up/down.
@export_range(0.0, 20.0, 0.01, "or_greater") var maximum_horizontal_leg_reach: float = 4.5
@export_range(0.0, 1.0, 0.001, "or_greater") var foot_ground_offset: float = 0.02
## Reduces each Leg's initial offset along the movement direction as speed increases.
@export var directional_projection_correction_enabled: bool = true
@export_range(0.0, 0.9, 0.01) var maximum_directional_projection_correction: float = 0.25
## Expected horizontal speed at which the maximum projection correction is reached.
@export_range(0.01, 100.0, 0.01, "or_greater") var full_projection_correction_speed: float = 12.0
## Minimum forward distance from the current foot to a fast-mode landing sample.
@export_range(0.0, 10.0, 0.01, "or_greater") var fast_minimum_leg_target_advance: float = 0.35

@export_group("Slow Speed Preset")
@export_range(0.01, 10.0, 0.01, "or_greater") var slow_step_distance: float = 0.35
@export_range(0.01, 5.0, 0.01, "or_greater") var slow_step_duration: float = 0.35

@export_group("Slow Movement Tuning")
## Target actual-speed multiplier for slow movement.
@export var use_slow_movement_scale: bool = false
@export_range(0.1, 3.0, 0.05, "or_greater") var slow_movement_scale: float = 1.0

@export_group("Fast Movement Tuning")
## Target actual-speed multiplier for fast movement.
@export var use_fast_movement_scale: bool = false
@export_range(0.1, 3.0, 0.05, "or_greater") var fast_movement_scale: float = 1.0

@export_group("Fast Velocity Gait")
## Desired horizontal Torso speed before the optional fast movement scale is applied.
@export_range(0.01, 100.0, 0.01, "or_greater") var fast_target_speed: float = 6.0
## Step events per second before the movement scale is applied.
@export_range(0.1, 30.0, 0.1, "or_greater") var fast_base_step_frequency: float = 4.0
@export_range(0.1, 30.0, 0.1, "or_greater") var fast_minimum_step_frequency: float = 2.0
@export_range(0.1, 30.0, 0.1, "or_greater") var fast_maximum_step_frequency: float = 8.0
## Fraction of one scheduled step interval spent following the swing curve.
@export_range(0.1, 1.0, 0.01) var fast_swing_duration_ratio: float = 0.8
## Base height of the Leg swing arc in fast mode.
@export_range(0.0, 10.0, 0.01, "or_greater") var fast_step_height: float = 0.6
## Maximum rate at which the expected horizontal velocity changes.
@export_range(0.01, 1000.0, 0.1, "or_greater") var fast_velocity_response: float = 30.0
## Converts horizontal velocity error into Torso acceleration.
@export var fast_torso_velocity_drive_enabled: bool = false
@export_range(0.0, 100.0, 0.1, "or_greater") var fast_torso_velocity_gain: float = 8.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var fast_maximum_torso_drive_force: float = 500.0

@export_group("Movement Scale Response")
## Maximum scaled height of the parabolic step arc.
@export_range(0.0, 10.0, 0.01, "or_greater") var maximum_scaled_step_height: float = 1.2
## Prevents scaled landing timeouts from becoming too short for physics contacts.
@export_range(0.01, 2.0, 0.01, "or_greater") var minimum_scaled_landing_timeout: float = 0.25
## A grounded Leg close to its target may finish after this confirmation time even if it still has residual velocity.
@export_range(0.0, 0.5, 0.01, "or_greater") var landing_confirmation_time: float = 0.05
## Smooths angular spring changes when switching movement presets.
@export var scale_joint_angular_springs: bool = true
@export_range(0.01, 2.0, 0.01, "or_greater") var joint_scale_transition_duration: float = 0.15

@export_group("Step Motion")
@export_range(0.0, 10.0, 0.01, "or_greater") var step_height: float = 0.25
@export_range(0.0, 10000.0, 1.0, "or_greater") var leg_move_stiffness: float = 200.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var leg_move_damping: float = 30.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var maximum_leg_force: float = 500.0
@export_range(0.001, 1.0, 0.001, "or_greater") var landing_tolerance: float = 0.18
@export_range(0.0, 10.0, 0.01, "or_greater") var landing_velocity_limit: float = 0.35
@export_range(0.01, 5.0, 0.01, "or_greater") var landing_timeout: float = 1.0

@export_group("Ground State")
@export_range(0.01, 2.0, 0.01, "or_greater") var ground_probe_distance: float = 0.25
@export_range(0.0, 1.0, 0.001, "or_greater") var ground_probe_start_offset: float = 0.05
## Allows fast movement to start a step without requiring any Leg to touch the ground.
@export var fast_mode_ignores_leg_support: bool = true
@export var parts_root_path: NodePath = NodePath("..")

@export_group("Surface Adhesion")
@export var surface_adhesion_enabled: bool = true
## Force pulling every non-stepping leg into its detected support surface.
@export_range(0.0, 10000.0, 1.0, "or_greater") var surface_adhesion_force: float = 80.0
@export_range(0.01, 2.0, 0.01, "or_greater") var surface_adhesion_probe_distance: float = 0.25

@export_group("Fast Float Gait")
## Lets the active Leg support a short, centrally applied lift on the Torso in fast mode.
@export var fast_float_enabled: bool = true
@export_range(0.0, 2.0, 0.01, "or_greater") var fast_lift_duration_ratio: float = 0.5
@export_range(0.0, 2.0, 0.01, "or_greater") var fast_gravity_compensation: float = 0.75
@export_range(0.0, 20.0, 0.01, "or_greater") var fast_target_vertical_velocity: float = 1.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var fast_maximum_lift_force: float = 200.0
@export_range(0.0, 10.0, 0.01, "or_greater") var fast_maximum_float_height: float = 0.35
## Reduces the force pulling support Legs downward while lift is active.
@export_range(0.0, 1.0, 0.01) var fast_lift_adhesion_multiplier: float = 0.25
@export_group("Fast Landing Assist")
@export var fast_landing_assist_enabled: bool = true
## Normalized step progress at which the landing force starts to fade in.
@export_range(0.0, 1.0, 0.01) var fast_landing_start_progress: float = 0.7
@export_range(0.0, 10000.0, 1.0, "or_greater") var fast_landing_stiffness: float = 300.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var fast_landing_damping: float = 50.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var fast_maximum_landing_force: float = 400.0
## Stops the assist once the Leg is grounded and this close to the target along the surface normal.
@export_range(0.001, 1.0, 0.001, "or_greater") var fast_landing_stop_distance: float = 0.05
## Extra horizontal tolerance used only while finishing a fast step.
@export_range(1.0, 10.0, 0.05, "or_greater") var fast_landing_tolerance_multiplier: float = 1.5
## A grounded fast Leg finishes after this time even if joint resistance leaves horizontal error.
@export_range(0.0, 1.0, 0.01, "or_greater") var fast_grounded_landing_timeout: float = 0.1

@export_group("Surface Burst")
## Central impulse applied to every Torso along the combined support-surface normal.
@export_range(0.0, 10000.0, 1.0, "or_greater") var surface_burst_impulse: float = 20.0
@export_range(0.0, 5.0, 0.01, "or_greater") var adhesion_release_duration: float = 0.5

@export_group("Torso Response")
@export var torso_response_enabled: bool = true
@export var torso_path: NodePath = NodePath("../Torso")
@export_range(0.0, 10000.0, 1.0, "or_greater") var torso_force_per_unit: float = 80.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var maximum_torso_force: float = 300.0

var _step_state: StepState = StepState.IDLE
var _active_leg: RigidBody3D
var _legs: Array[RigidBody3D] = []
var _next_leg_index: int = 0
var _step_start: Vector3 = Vector3.ZERO
var _step_target: Vector3 = Vector3.ZERO
var _step_target_normal: Vector3 = Vector3.UP
var _step_elapsed: float = 0.0
var _landing_elapsed: float = 0.0
var _grounded_confirmation_elapsed: float = 0.0
var _active_step_duration: float = 0.35
var _active_movement_scale: float = 1.0
var _torso: RigidBody3D
## Initial leg positions in Torso-local space. They remain the source of every future landing sample.
var _leg_initial_local_positions: Dictionary[RigidBody3D, Vector3] = {}
var _leg_initial_center_local: Vector3 = Vector3.ZERO
var _leg_adhesion_surface_normals: Dictionary[RigidBody3D, Vector3] = {}
var _last_input_direction: Vector3 = Vector3.ZERO
var _last_fast_speed_active: bool = false
var _adhesion_release_time_remaining: float = 0.0
var _joint_spring_scale: float = 1.0
var _joint_base_springs: Dictionary[Generic6DOFJoint3D, Vector2] = {}
var _physics_elapsed: float = 0.0
var _next_fast_step_start_time: float = 0.0
var _desired_fast_velocity: Vector3 = Vector3.ZERO
var _fast_step_frequency: float = 0.0
var _fast_step_interval: float = 0.0
var _fast_computed_step_distance: float = 0.0
var _fast_gait_center_world: Vector3 = Vector3.ZERO
var _fast_gait_center_basis: Basis = Basis.IDENTITY
var _fast_gait_anchor_direction: Vector3 = Vector3.ZERO
var _fast_gait_anchor_valid: bool = false
var _fast_lift_time_remaining: float = 0.0
var _fast_lift_start_height: float = 0.0
var _current_fast_lift_force: float = 0.0
var _current_fast_landing_force: Vector3 = Vector3.ZERO
var _step_sequence: int = 0
var _last_touchdown_leg: StringName = &""
var _last_touchdown_interval: float = -1.0
var _last_touchdown_time: float = -1.0
var _last_touchdown_times_by_leg: Dictionary[StringName, float] = {}

func _ready() -> void:
	add_to_group(&"leg_step_movement_controllers")
	_torso = get_node_or_null(torso_path) as RigidBody3D
	_refresh_leg_order()
	_capture_leg_initial_positions()
	_last_fast_speed_active = is_fast_speed_active()
	_active_movement_scale = _get_configured_movement_scale()
	_joint_spring_scale = _active_movement_scale
	_capture_joint_spring_settings()
	_apply_joint_spring_scale(_joint_spring_scale)

func _physics_process(delta: float) -> void:
	_physics_elapsed += delta
	_current_fast_landing_force = Vector3.ZERO
	_adhesion_release_time_remaining = maxf(_adhesion_release_time_remaining - delta, 0.0)
	_update_joint_spring_scale(delta)
	if input_enabled and is_burst_requested():
		try_surface_burst()

	var input_direction := get_input_movement_direction() if input_enabled else Vector3.ZERO
	var fast_speed_active := is_fast_speed_active() if input_enabled else false
	_update_fast_velocity_gait(delta, input_direction, fast_speed_active)
	if (
		_adhesion_release_time_remaining <= 0.0
		and not input_direction.is_zero_approx()
		and not input_direction.is_equal_approx(_last_input_direction)
		and _step_state != StepState.IDLE
	):
		replan_active_step(input_direction)
	elif (
		fast_speed_active != _last_fast_speed_active
		and not input_direction.is_zero_approx()
		and _step_state != StepState.IDLE
	):
		replan_active_step(input_direction)
	_last_input_direction = input_direction
	_last_fast_speed_active = fast_speed_active

	if fast_speed_active:
		_update_fast_gait_clock(input_direction)
	elif _step_state == StepState.IDLE and _adhesion_release_time_remaining <= 0.0:
		if not input_direction.is_zero_approx():
			try_start_step(input_direction)
	if _step_state != StepState.IDLE:
		_update_active_step(delta)
	_update_fast_float_lift(delta, input_direction, fast_speed_active)
	update_leg_surface_adhesion()
	if _adhesion_release_time_remaining <= 0.0:
		_apply_torso_response()
		if fast_speed_active:
			_apply_fast_torso_velocity_drive()

func _update_fast_velocity_gait(
	delta: float,
	input_direction: Vector3,
	fast_speed_active: bool
) -> void:
	var scale := _get_fast_movement_scale()
	_fast_step_frequency = _calculate_fast_step_frequency()
	_fast_step_interval = 1.0 / maxf(_fast_step_frequency, MIN_STEP_TIME)
	var planned_speed := fast_target_speed * scale
	_fast_computed_step_distance = maxf(planned_speed / _fast_step_frequency, minimum_step_distance)
	var target_velocity := input_direction * planned_speed if fast_speed_active else Vector3.ZERO
	_desired_fast_velocity = _desired_fast_velocity.move_toward(
		target_velocity,
		fast_velocity_response * delta
	)
	if not fast_speed_active or input_direction.is_zero_approx():
		_next_fast_step_start_time = _physics_elapsed
		_fast_gait_anchor_valid = false
	elif not _last_fast_speed_active:
		_next_fast_step_start_time = _physics_elapsed

## Fast gait timing is authoritative: an unfinished Leg phase cannot delay the next one.
func _update_fast_gait_clock(input_direction: Vector3) -> void:
	if (
		input_direction.is_zero_approx()
		or _adhesion_release_time_remaining > 0.0
		or _physics_elapsed < _next_fast_step_start_time
	):
		return
	if _step_state != StepState.IDLE:
		_finish_fast_gait_phase()
	if _next_leg_index == 0 or not _fast_gait_anchor_matches(input_direction):
		_capture_fast_gait_cycle_anchor(input_direction)
	var started := try_start_step(input_direction)
	if not started and not _legs.is_empty():
		# A missing landing point skips this phase instead of retrying one Leg forever.
		_next_leg_index = (_next_leg_index + 1) % _legs.size()
	_next_fast_step_start_time = _physics_elapsed + _fast_step_interval

func _finish_fast_gait_phase() -> void:
	if is_instance_valid(_active_leg) and is_leg_grounded(_active_leg):
		_record_touchdown()
	if not _legs.is_empty():
		_next_leg_index = (_next_leg_index + 1) % _legs.size()
	cancel_step()

func _apply_fast_torso_velocity_drive() -> void:
	if not fast_torso_velocity_drive_enabled or not is_instance_valid(_torso):
		return
	var actual_velocity := _torso.linear_velocity
	actual_velocity.y = 0.0
	var velocity_error := _desired_fast_velocity - actual_velocity
	velocity_error.y = 0.0
	var force := velocity_error * _torso.mass * fast_torso_velocity_gain
	if fast_maximum_torso_drive_force > 0.0:
		force = force.limit_length(fast_maximum_torso_drive_force)
	if force.is_zero_approx():
		return
	_torso.sleeping = false
	_torso.apply_central_force(force)

## Starts the next leg in the stable alternating order when it has a valid landing point.
func try_start_step(movement_direction: Vector3 = Vector3.RIGHT) -> bool:
	if _step_state != StepState.IDLE:
		return false
	movement_direction.y = 0.0
	if movement_direction.is_zero_approx():
		return false
	movement_direction = movement_direction.normalized()
	_remove_invalid_legs()
	if _legs.is_empty():
		_refresh_leg_order()
	if _legs.is_empty():
		return false
	var candidate := _legs[_next_leg_index % _legs.size()]
	if not _can_start_step_with_support(candidate):
		return false
	var landing := find_landing_point(candidate, movement_direction)
	if landing.is_empty():
		return false
	_begin_leg_motion(
		candidate,
		_body_position_for_ground_contact(candidate, landing[&"position"]),
		landing[&"normal"]
	)
	return true

## Keeps the same moving leg, but replaces its old target with one based on the new input.
func replan_active_step(new_direction: Vector3) -> bool:
	if _step_state == StepState.IDLE or not is_instance_valid(_active_leg):
		return false
	new_direction.y = 0.0
	if new_direction.is_zero_approx():
		return false
	new_direction = new_direction.normalized()
	var landing := find_landing_point(_active_leg, new_direction)
	if landing.is_empty():
		return false
	_begin_leg_motion(
		_active_leg,
		_body_position_for_ground_contact(_active_leg, landing[&"position"]),
		landing[&"normal"]
	)
	return true

## Searches from the preferred stride back toward the leg and returns the first legal hit.
func find_landing_point(leg: RigidBody3D, movement_direction: Vector3 = Vector3.RIGHT) -> Dictionary:
	if not is_instance_valid(leg) or not is_inside_tree():
		return {}
	movement_direction.y = 0.0
	if movement_direction.is_zero_approx():
		return {}
	movement_direction = movement_direction.normalized()
	if is_fast_speed_active() and not _fast_gait_anchor_matches(movement_direction):
		_capture_fast_gait_cycle_anchor(movement_direction)
	var foot_position := _get_foot_world_position(leg)
	var rest_position := _get_projected_landing_rest_position(leg, movement_direction)
	var sample_count := maxi(ceili(float(landing_search_samples) * sqrt(_get_configured_movement_scale())), 1)
	for sample_index: int in range(sample_count):
		var ratio := 0.0 if sample_count == 1 else float(sample_index) / float(sample_count - 1)
		var forward_distance := lerpf(get_current_step_distance(), minimum_step_distance, ratio)
		var sample_position := rest_position + movement_direction * forward_distance
		if is_fast_speed_active() and fast_minimum_leg_target_advance > 0.0:
			var current_forward_distance := (sample_position - foot_position).dot(movement_direction)
			if current_forward_distance < fast_minimum_leg_target_advance:
				sample_position += (
					movement_direction
					* (fast_minimum_leg_target_advance - current_forward_distance)
				)
		var ray_from := Vector3(sample_position.x, rest_position.y + ray_start_height, sample_position.z)
		var ray_to := ray_from + Vector3.DOWN * ray_length
		var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, terrain_collision_mask, _get_character_exclusion_rids())
		query.collide_with_areas = false
		var hit: Dictionary = _get_space_state().intersect_ray(query)
		if _is_landing_point_valid(leg, foot_position, hit):
			return hit
	return {}

func get_leg_parts() -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	var parts_root := get_node_or_null(parts_root_path)
	if parts_root == null:
		return result
	for node: Node in parts_root.find_children("*", "RigidBody3D", true, false):
		var body := node as RigidBody3D
		if _has_leg_tag(body):
			result.append(body)
	return result

func get_active_leg() -> RigidBody3D:
	return _active_leg

## Input seam implemented by player, AI, replay, or network-controlled subclasses.
func get_input_movement_direction() -> Vector3:
	return Vector3.ZERO

func is_burst_requested() -> bool:
	return false

func is_fast_speed_active() -> bool:
	return false

func get_current_speed_preset_name() -> String:
	return "FAST" if is_fast_speed_active() else "SLOW"

func get_current_step_distance() -> float:
	if is_fast_speed_active():
		return maxf(
			fast_target_speed * _get_fast_movement_scale() / _calculate_fast_step_frequency(),
			minimum_step_distance
		)
	return slow_step_distance * sqrt(_get_configured_movement_scale())

func get_current_step_duration() -> float:
	if is_fast_speed_active():
		return maxf(
			fast_swing_duration_ratio / _calculate_fast_step_frequency(),
			MIN_STEP_TIME
		)
	return slow_step_duration / sqrt(_get_configured_movement_scale())

func get_desired_fast_velocity() -> Vector3:
	return _desired_fast_velocity

func get_fast_step_frequency() -> float:
	return _calculate_fast_step_frequency()

func get_fast_step_interval() -> float:
	return 1.0 / _calculate_fast_step_frequency()

func _get_fast_movement_scale() -> float:
	return maxf(fast_movement_scale, 0.1) if use_fast_movement_scale else 1.0

func _calculate_fast_step_frequency() -> float:
	return clampf(
		fast_base_step_frequency * sqrt(_get_fast_movement_scale()),
		fast_minimum_step_frequency,
		maxf(fast_maximum_step_frequency, fast_minimum_step_frequency)
	)

func _get_configured_movement_scale() -> float:
	if is_fast_speed_active():
		return maxf(fast_movement_scale, 0.1) if use_fast_movement_scale else 1.0
	return maxf(slow_movement_scale, 0.1) if use_slow_movement_scale else 1.0

func get_current_movement_scale() -> float:
	return _get_configured_movement_scale()

func get_step_state() -> StepState:
	return _step_state

func get_step_state_name() -> String:
	return String(StepState.find_key(_step_state))

func get_step_target() -> Vector3:
	return _step_target

func get_step_target_normal() -> Vector3:
	return _step_target_normal

func get_active_leg_horizontal_target_distance() -> float:
	if not is_instance_valid(_active_leg):
		return 0.0
	var error := _step_target - _active_leg.global_position
	error.y = 0.0
	return error.length()

func get_landing_timeout_remaining() -> float:
	if _step_state != StepState.LANDING:
		return -1.0
	return maxf(_get_effective_landing_timeout() - _landing_elapsed, 0.0)

func get_last_input_direction() -> Vector3:
	return _last_input_direction

func get_step_sequence() -> int:
	return _step_sequence

func get_last_touchdown_leg() -> StringName:
	return _last_touchdown_leg

func get_last_touchdown_interval() -> float:
	return _last_touchdown_interval

func get_fast_lift_time_remaining() -> float:
	return _fast_lift_time_remaining

func get_current_fast_lift_force() -> float:
	return _current_fast_lift_force

func get_current_fast_landing_force() -> Vector3:
	return _current_fast_landing_force

func cancel_step() -> void:
	_active_leg = null
	_step_elapsed = 0.0
	_landing_elapsed = 0.0
	_grounded_confirmation_elapsed = 0.0
	_step_state = StepState.IDLE

func is_leg_grounded(leg: RigidBody3D) -> bool:
	if not is_instance_valid(leg) or not is_inside_tree():
		return false
	var hit := _get_surface_below_leg(leg, ground_probe_distance)
	return not hit.is_empty() and _surface_is_walkable(hit[&"normal"])

## Refreshes cached world-space normals and applies adhesion to every non-stepping leg.
func update_leg_surface_adhesion() -> void:
	_remove_invalid_legs()
	if _adhesion_release_time_remaining > 0.0:
		_clear_leg_adhesion_surface_normals()
		return
	for leg: RigidBody3D in _legs:
		if leg == _active_leg:
			_leg_adhesion_surface_normals[leg] = Vector3.ZERO
			continue
		var hit := _get_surface_below_leg(leg, surface_adhesion_probe_distance)
		if hit.is_empty():
			_leg_adhesion_surface_normals[leg] = Vector3.ZERO
			continue
		var surface_normal: Vector3 = hit[&"normal"].normalized()
		_leg_adhesion_surface_normals[leg] = surface_normal
		var adhesion_multiplier := fast_lift_adhesion_multiplier if _fast_lift_time_remaining > 0.0 else 1.0
		var effective_adhesion_force := (
			surface_adhesion_force
			* _get_configured_movement_scale()
			* adhesion_multiplier
		)
		if surface_adhesion_enabled and effective_adhesion_force > 0.0:
			leg.sleeping = false
			leg.apply_central_force(-surface_normal * effective_adhesion_force)

## Uses the combined attached-leg normal to launch every Torso and temporarily releases the legs.
func try_surface_burst() -> bool:
	_refresh_leg_adhesion_surface_normals()
	var burst_direction := get_combined_adhesion_surface_normal()
	if burst_direction.is_zero_approx():
		return false
	var torsos := get_torso_parts()
	if torsos.is_empty():
		return false
	burst_direction = burst_direction.normalized()
	for torso: RigidBody3D in torsos:
		torso.sleeping = false
		torso.apply_central_impulse(burst_direction * surface_burst_impulse)
	cancel_step()
	_fast_lift_time_remaining = 0.0
	_current_fast_lift_force = 0.0
	_adhesion_release_time_remaining = adhesion_release_duration
	_clear_leg_adhesion_surface_normals()
	return true

func get_torso_parts() -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	var parts_root := get_node_or_null(parts_root_path)
	if parts_root == null:
		return result
	for node: Node in parts_root.find_children("*", "RigidBody3D", true, false):
		var body := node as RigidBody3D
		if _has_body_tag(body, TORSO_TAG):
			result.append(body)
	return result

## Returns the normalized sum of all currently attached Leg surface normals.
func get_combined_adhesion_surface_normal() -> Vector3:
	var combined_normal := Vector3.ZERO
	for leg: RigidBody3D in _legs:
		combined_normal += get_leg_adhesion_surface_normal(leg)
	return combined_normal.normalized() if not combined_normal.is_zero_approx() else Vector3.ZERO

func get_adhesion_release_time_remaining() -> float:
	return _adhesion_release_time_remaining

## Returns the cached world-space normal for one leg, or Vector3.ZERO when it is not attached.
func get_leg_adhesion_surface_normal(leg: RigidBody3D) -> Vector3:
	return _leg_adhesion_surface_normals.get(leg, Vector3.ZERO)

## Returns a snapshot of every currently tracked Leg and its world-space adhesion normal.
func get_leg_adhesion_surface_normals() -> Dictionary[RigidBody3D, Vector3]:
	var result: Dictionary[RigidBody3D, Vector3] = {}
	for leg: RigidBody3D in _legs:
		result[leg] = get_leg_adhesion_surface_normal(leg)
	return result

func _refresh_leg_adhesion_surface_normals() -> void:
	_remove_invalid_legs()
	for leg: RigidBody3D in _legs:
		if leg == _active_leg:
			_leg_adhesion_surface_normals[leg] = Vector3.ZERO
			continue
		var hit := _get_surface_below_leg(leg, surface_adhesion_probe_distance)
		_leg_adhesion_surface_normals[leg] = (
			Vector3.ZERO if hit.is_empty() else (hit[&"normal"] as Vector3).normalized()
		)

func _clear_leg_adhesion_surface_normals() -> void:
	for leg: RigidBody3D in _legs:
		_leg_adhesion_surface_normals[leg] = Vector3.ZERO

func _get_surface_below_leg(leg: RigidBody3D, probe_distance: float) -> Dictionary:
	if not is_instance_valid(leg) or not is_inside_tree():
		return {}
	var foot_position := _get_foot_world_position(leg)
	var query := PhysicsRayQueryParameters3D.create(
		foot_position + Vector3.UP * ground_probe_start_offset,
		foot_position + Vector3.DOWN * maxf(probe_distance, 0.001),
		terrain_collision_mask,
		_get_character_exclusion_rids()
	)
	query.collide_with_areas = false
	return _get_space_state().intersect_ray(query)

func get_combined_leg_offset() -> Vector3:
	if not is_instance_valid(_torso):
		return Vector3.ZERO
	var combined_offset := Vector3.ZERO
	for leg: RigidBody3D in get_leg_parts():
		var rest_world_position := _get_leg_rest_world_position(leg)
		combined_offset += leg.global_position - rest_world_position
	return combined_offset

func calculate_torso_force() -> Vector3:
	var scale := _get_configured_movement_scale()
	var force := get_combined_leg_offset() * torso_force_per_unit * sqrt(scale)
	var effective_maximum_force := maximum_torso_force * scale
	if effective_maximum_force > 0.0 and force.length() > effective_maximum_force:
		force = force.normalized() * effective_maximum_force
	return force

func _begin_leg_motion(leg: RigidBody3D, target: Vector3, target_normal: Vector3 = Vector3.UP) -> void:
	var starts_new_step := _step_state == StepState.IDLE or leg != _active_leg
	_active_leg = leg
	_active_movement_scale = _get_configured_movement_scale()
	_step_start = leg.global_position
	_step_target = target
	_step_target_normal = target_normal.normalized() if not target_normal.is_zero_approx() else Vector3.UP
	_step_elapsed = 0.0
	_landing_elapsed = 0.0
	_grounded_confirmation_elapsed = 0.0
	_active_step_duration = maxf(get_current_step_duration(), MIN_STEP_TIME)
	_step_state = StepState.MOVING
	_active_leg.sleeping = false
	if starts_new_step:
		_step_sequence += 1
		if is_fast_speed_active():
			_start_fast_float_lift()

func _update_active_step(delta: float) -> void:
	if not is_instance_valid(_active_leg):
		cancel_step()
		return
	_active_leg.sleeping = false
	if _step_state == StepState.MOVING:
		_step_elapsed += delta
		var duration := _active_step_duration
		var progress := clampf(_step_elapsed / duration, 0.0, 1.0)
		_apply_leg_tracking_force(_quadratic_step_position(progress), _quadratic_step_velocity(progress, duration))
		_apply_fast_landing_assist(progress)
		if progress >= 1.0:
			_step_state = StepState.LANDING
			_landing_elapsed = 0.0
			_grounded_confirmation_elapsed = 0.0
	else:
		_landing_elapsed += delta
		_apply_leg_tracking_force(_step_target, Vector3.ZERO)
		_apply_fast_landing_assist(1.0)
		var target_error := _step_target - _active_leg.global_position
		target_error.y = 0.0
		var close_enough := target_error.length() <= _get_effective_landing_tolerance()
		var slow_enough := _active_leg.linear_velocity.length() <= _get_effective_landing_velocity_limit()
		var grounded := is_leg_grounded(_active_leg)
		if grounded and close_enough:
			_grounded_confirmation_elapsed += delta
			if slow_enough or _grounded_confirmation_elapsed >= landing_confirmation_time:
				_finish_current_step()
		else:
			_grounded_confirmation_elapsed = 0.0
		if (
			_step_state == StepState.LANDING
			and grounded
			and is_fast_speed_active()
			and _landing_elapsed >= fast_grounded_landing_timeout
		):
			_finish_current_step()
		if _step_state == StepState.LANDING and _landing_elapsed >= _get_effective_landing_timeout():
			# A grounded leg has produced a usable step even if its joint cannot reach the exact target.
			if grounded:
				_finish_current_step()
			else:
				cancel_step()

func _quadratic_step_position(progress: float) -> Vector3:
	var middle := (_step_start + _step_target) * 0.5 + Vector3.UP * _get_effective_step_height()
	var inverse := 1.0 - progress
	return _step_start * inverse * inverse + middle * 2.0 * inverse * progress + _step_target * progress * progress

func _quadratic_step_velocity(progress: float, duration: float) -> Vector3:
	var middle := (_step_start + _step_target) * 0.5 + Vector3.UP * _get_effective_step_height()
	return (2.0 * (1.0 - progress) * (middle - _step_start) + 2.0 * progress * (_step_target - middle)) / duration

func _apply_leg_tracking_force(desired_position: Vector3, desired_velocity: Vector3) -> void:
	var position_error := desired_position - _active_leg.global_position
	var velocity_error := desired_velocity - _active_leg.linear_velocity
	var root_scale := sqrt(_active_movement_scale)
	var effective_stiffness := leg_move_stiffness * _active_movement_scale
	var effective_damping := leg_move_damping * root_scale
	var effective_maximum_force := maximum_leg_force * pow(_active_movement_scale, 1.5)
	var force := position_error * effective_stiffness + velocity_error * effective_damping
	if effective_maximum_force > 0.0:
		force = force.limit_length(effective_maximum_force)
	_active_leg.apply_central_force(force)

func _apply_fast_landing_assist(progress: float) -> void:
	if (
		not fast_landing_assist_enabled
		or not is_fast_speed_active()
		or not is_instance_valid(_active_leg)
		or progress < fast_landing_start_progress
	):
		return
	# The landing phase replaces the lift phase so the two forces never fight each other.
	_fast_lift_time_remaining = 0.0
	_current_fast_lift_force = 0.0
	var normal := _step_target_normal
	var to_target := _step_target - _active_leg.global_position
	var normal_error := to_target.dot(normal)
	if is_leg_grounded(_active_leg) and absf(normal_error) <= fast_landing_stop_distance:
		return
	var normal_velocity := _active_leg.linear_velocity.dot(normal)
	var root_scale := sqrt(_active_movement_scale)
	var effective_stiffness := fast_landing_stiffness * _active_movement_scale
	var effective_damping := fast_landing_damping * root_scale
	var force_magnitude := normal_error * effective_stiffness - normal_velocity * effective_damping
	var effective_maximum_force := fast_maximum_landing_force * pow(_active_movement_scale, 1.5)
	if effective_maximum_force > 0.0:
		force_magnitude = clampf(force_magnitude, -effective_maximum_force, effective_maximum_force)
	var weight := (
		1.0
		if fast_landing_start_progress >= 1.0
		else smoothstep(fast_landing_start_progress, 1.0, progress)
	)
	_current_fast_landing_force = normal * force_magnitude * weight
	_active_leg.apply_central_force(_current_fast_landing_force)

func _get_effective_step_height() -> float:
	var base_height := fast_step_height if is_fast_speed_active() else step_height
	return minf(base_height * sqrt(_active_movement_scale), maximum_scaled_step_height)

func _get_effective_landing_tolerance() -> float:
	var tolerance := landing_tolerance * sqrt(_active_movement_scale)
	if is_fast_speed_active():
		tolerance *= fast_landing_tolerance_multiplier
	return tolerance

func _get_effective_landing_velocity_limit() -> float:
	return landing_velocity_limit * _active_movement_scale

func _get_effective_landing_timeout() -> float:
	return maxf(landing_timeout / sqrt(_active_movement_scale), minimum_scaled_landing_timeout)

func _finish_current_step() -> void:
	_record_touchdown()
	if not _legs.is_empty():
		_next_leg_index = (_next_leg_index + 1) % _legs.size()
	cancel_step()

func _record_touchdown() -> void:
	if not is_instance_valid(_active_leg):
		return
	_last_touchdown_leg = _active_leg.name
	_last_touchdown_interval = (
		-1.0 if _last_touchdown_time < 0.0 else _physics_elapsed - _last_touchdown_time
	)
	_last_touchdown_time = _physics_elapsed
	_last_touchdown_times_by_leg[_last_touchdown_leg] = _physics_elapsed

func _start_fast_float_lift() -> void:
	if not fast_float_enabled or not is_instance_valid(_torso):
		return
	_fast_lift_time_remaining = _active_step_duration * fast_lift_duration_ratio
	_fast_lift_start_height = _torso.global_position.y
	_current_fast_lift_force = 0.0

func _update_fast_float_lift(delta: float, input_direction: Vector3, fast_speed_active: bool) -> void:
	_current_fast_lift_force = 0.0
	if _fast_lift_time_remaining <= 0.0:
		return
	if (
		not fast_float_enabled
		or not fast_speed_active
		or input_direction.is_zero_approx()
		or not is_instance_valid(_torso)
	):
		_fast_lift_time_remaining = 0.0
		return
	var height_gain := _torso.global_position.y - _fast_lift_start_height
	if height_gain >= fast_maximum_float_height:
		_fast_lift_time_remaining = 0.0
		return
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var safe_duration := maxf(maxf(_fast_lift_time_remaining, delta), MIN_STEP_TIME)
	var gravity_compensation_force := _torso.mass * gravity * fast_gravity_compensation
	var velocity_correction_force := (
		(fast_target_vertical_velocity - _torso.linear_velocity.y)
		* _torso.mass
		/ safe_duration
	)
	var lift_force := maxf(gravity_compensation_force + velocity_correction_force, 0.0)
	if fast_maximum_lift_force > 0.0:
		lift_force = minf(lift_force, fast_maximum_lift_force)
	if lift_force > 0.0:
		_torso.sleeping = false
		_torso.apply_central_force(Vector3.UP * lift_force)
	_current_fast_lift_force = lift_force
	_fast_lift_time_remaining = maxf(_fast_lift_time_remaining - delta, 0.0)

func _has_enough_support(moving_leg: RigidBody3D) -> bool:
	if _legs.size() <= 1:
		return true
	var supported_count := 0
	for leg: RigidBody3D in _legs:
		if leg != moving_leg and is_leg_grounded(leg):
			supported_count += 1
	var required_count := maxi(1, ceili(float(_legs.size() - 1) * 0.5))
	return supported_count >= required_count

## Keeps the strict support rule in slow mode and optionally bypasses it in fast mode.
func _can_start_step_with_support(moving_leg: RigidBody3D) -> bool:
	if fast_mode_ignores_leg_support and is_fast_speed_active():
		return true
	return _has_enough_support(moving_leg)

func _is_landing_point_valid(leg: RigidBody3D, current_foot: Vector3, hit: Dictionary) -> bool:
	if hit.is_empty() or not _surface_is_walkable(hit[&"normal"]):
		return false
	var ground_position: Vector3 = hit[&"position"]
	var height_difference := ground_position.y - current_foot.y
	if height_difference > maximum_step_up or height_difference < -maximum_step_down:
		return false
	if is_instance_valid(_torso) and maximum_horizontal_leg_reach > 0.0:
		var horizontal_reach := ground_position - _torso.global_position
		horizontal_reach.y = 0.0
		if horizontal_reach.length() > maximum_horizontal_leg_reach:
			return false
	var body_target := _body_position_for_ground_contact(leg, ground_position)
	return _has_leg_clearance(leg, body_target, hit.get(&"rid", RID()))

func _surface_is_walkable(normal: Vector3) -> bool:
	return normal.normalized().dot(Vector3.UP) >= cos(deg_to_rad(maximum_slope_angle))

func _has_leg_clearance(leg: RigidBody3D, body_target: Vector3, landing_rid: RID) -> bool:
	var collision := _find_leg_collision_shape(leg)
	if collision == null or collision.shape == null:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	query.transform = collision.global_transform.translated(body_target - leg.global_position)
	query.collision_mask = terrain_collision_mask
	query.exclude = _get_character_exclusion_rids()
	query.collide_with_areas = false
	for overlap: Dictionary in _get_space_state().intersect_shape(query, 16):
		if overlap.get(&"rid", RID()) != landing_rid:
			return false
	return true

func _body_position_for_ground_contact(leg: RigidBody3D, ground_position: Vector3) -> Vector3:
	return leg.global_position + ground_position - _get_foot_world_position(leg) + Vector3.UP * foot_ground_offset

func _get_foot_world_position(leg: RigidBody3D) -> Vector3:
	var collision := _find_leg_collision_shape(leg)
	if collision == null:
		return leg.global_position
	var box := collision.shape as BoxShape3D
	if box == null:
		return collision.global_position
	return collision.global_transform * Vector3(0.0, -box.size.y * 0.5, 0.0)

func _find_leg_collision_shape(leg: RigidBody3D) -> CollisionShape3D:
	for node: Node in leg.find_children("*", "CollisionShape3D", true, false):
		var collision := node as CollisionShape3D
		if not collision.disabled and collision.shape != null:
			return collision
	return null

func _get_character_exclusion_rids() -> Array[RID]:
	var result: Array[RID] = []
	var parts_root := get_node_or_null(parts_root_path)
	if parts_root == null:
		return result
	for node: Node in parts_root.find_children("*", "CollisionObject3D", true, false):
		result.append((node as CollisionObject3D).get_rid())
	return result

func _get_space_state() -> PhysicsDirectSpaceState3D:
	var parts_root := get_node_or_null(parts_root_path) as Node3D
	if parts_root == null:
		return null
	return parts_root.get_world_3d().direct_space_state

func _refresh_leg_order() -> void:
	_legs = get_leg_parts()
	_legs.sort_custom(func(a: RigidBody3D, b: RigidBody3D) -> bool:
		if not is_equal_approx(a.global_position.x, b.global_position.x):
			return a.global_position.x < b.global_position.x
		return String(a.get_path()) < String(b.get_path())
	)
	_next_leg_index = 0

func _remove_invalid_legs() -> void:
	for index: int in range(_legs.size() - 1, -1, -1):
		if not is_instance_valid(_legs[index]):
			_legs.remove_at(index)
	if not _legs.is_empty():
		_next_leg_index %= _legs.size()
	else:
		_next_leg_index = 0

func _capture_joint_spring_settings() -> void:
	_joint_base_springs.clear()
	var parts_root := get_node_or_null(parts_root_path)
	if parts_root == null:
		return
	for node: Node in parts_root.find_children("*", "Generic6DOFJoint3D", true, false):
		var joint := node as Generic6DOFJoint3D
		if joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING):
			_joint_base_springs[joint] = Vector2(
				joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS),
				joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING)
			)

func _update_joint_spring_scale(delta: float) -> void:
	if not scale_joint_angular_springs or _joint_base_springs.is_empty():
		return
	var target_scale := _get_configured_movement_scale()
	var weight := clampf(delta / maxf(joint_scale_transition_duration, 0.001), 0.0, 1.0)
	_joint_spring_scale = lerpf(_joint_spring_scale, target_scale, weight)
	_apply_joint_spring_scale(_joint_spring_scale)

func _apply_joint_spring_scale(scale: float) -> void:
	if not scale_joint_angular_springs:
		return
	for joint: Generic6DOFJoint3D in _joint_base_springs:
		if not is_instance_valid(joint):
			continue
		var base_values: Vector2 = _joint_base_springs[joint]
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, base_values.x * scale)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, base_values.y * sqrt(scale))

func _apply_torso_response() -> void:
	if not torso_response_enabled or not is_instance_valid(_torso):
		return
	var force := calculate_torso_force()
	if force.is_zero_approx():
		return
	_torso.sleeping = false
	_torso.apply_central_force(force)

func _capture_leg_initial_positions() -> void:
	_leg_initial_local_positions.clear()
	_leg_initial_center_local = Vector3.ZERO
	if not is_instance_valid(_torso):
		return
	for leg: RigidBody3D in _legs:
		var local_position := _torso.to_local(leg.global_position)
		_leg_initial_local_positions[leg] = local_position
		_leg_initial_center_local += local_position
	if not _legs.is_empty():
		_leg_initial_center_local /= float(_legs.size())

func _get_leg_rest_world_position(leg: RigidBody3D) -> Vector3:
	if not is_instance_valid(_torso):
		return leg.global_position
	if not _leg_initial_local_positions.has(leg):
		_leg_initial_local_positions[leg] = _torso.to_local(leg.global_position)
	var local_position: Vector3 = _leg_initial_local_positions[leg]
	# Only Torso yaw affects the stance. Roll and pitch must not move sampling points up and down.
	var horizontal_basis := Basis(Vector3.UP, _torso.global_rotation.y)
	return _torso.global_position + horizontal_basis * local_position

func _get_projected_landing_rest_position(
	leg: RigidBody3D,
	movement_direction: Vector3
) -> Vector3:
	var rest_position := _get_fast_cycle_leg_rest_position(leg) if (
		is_fast_speed_active() and _fast_gait_anchor_valid
	) else _get_leg_rest_world_position(leg)
	if not directional_projection_correction_enabled or not is_instance_valid(_torso):
		return rest_position
	var horizontal_direction := movement_direction
	horizontal_direction.y = 0.0
	if horizontal_direction.is_zero_approx():
		return rest_position
	horizontal_direction = horizontal_direction.normalized()
	var local_position: Vector3 = _leg_initial_local_positions.get(
		leg,
		_torso.to_local(leg.global_position)
	)
	var local_offset := local_position - _leg_initial_center_local
	local_offset.y = 0.0
	var horizontal_basis := (
		_fast_gait_center_basis
		if is_fast_speed_active() and _fast_gait_anchor_valid
		else Basis(Vector3.UP, _torso.global_rotation.y)
	)
	var world_offset := horizontal_basis * local_offset
	var longitudinal_projection := (
		horizontal_direction * world_offset.dot(horizontal_direction)
	)
	return (
		rest_position
		- longitudinal_projection * get_directional_projection_correction_strength()
	)

func _capture_fast_gait_cycle_anchor(movement_direction: Vector3) -> void:
	if not is_instance_valid(_torso):
		_fast_gait_anchor_valid = false
		return
	var horizontal_direction := movement_direction
	horizontal_direction.y = 0.0
	if horizontal_direction.is_zero_approx():
		_fast_gait_anchor_valid = false
		return
	_fast_gait_anchor_direction = horizontal_direction.normalized()
	_fast_gait_center_basis = Basis(Vector3.UP, _torso.global_rotation.y)
	_fast_gait_center_world = (
		_torso.global_position
		+ _fast_gait_center_basis * _leg_initial_center_local
	)
	_fast_gait_anchor_valid = true

func _fast_gait_anchor_matches(movement_direction: Vector3) -> bool:
	if not _fast_gait_anchor_valid:
		return false
	var horizontal_direction := movement_direction
	horizontal_direction.y = 0.0
	return (
		not horizontal_direction.is_zero_approx()
		and _fast_gait_anchor_direction.dot(horizontal_direction.normalized()) >= 0.999
	)

func _get_fast_cycle_leg_rest_position(leg: RigidBody3D) -> Vector3:
	if not _fast_gait_anchor_valid:
		return _get_leg_rest_world_position(leg)
	var local_position: Vector3 = _leg_initial_local_positions.get(
		leg,
		_leg_initial_center_local
	)
	return (
		_fast_gait_center_world
		+ _fast_gait_center_basis * (local_position - _leg_initial_center_local)
	)

func get_directional_projection_correction_strength() -> float:
	if not directional_projection_correction_enabled:
		return 0.0
	var expected_speed := _get_expected_horizontal_speed()
	var speed_ratio := clampf(expected_speed / full_projection_correction_speed, 0.0, 1.0)
	return maximum_directional_projection_correction * smoothstep(0.0, 1.0, speed_ratio)

func _get_expected_horizontal_speed() -> float:
	if is_fast_speed_active():
		# The planned speed keeps landing selection stable while input acceleration catches up.
		return fast_target_speed * _get_fast_movement_scale()
	return slow_step_distance * sqrt(_get_configured_movement_scale()) / maxf(
		slow_step_duration / sqrt(_get_configured_movement_scale()),
		MIN_STEP_TIME
	)

func _has_leg_tag(body: RigidBody3D) -> bool:
	return _has_body_tag(body, LEG_TAG)

func _has_body_tag(body: RigidBody3D, required_tag: int) -> bool:
	for property: Dictionary in body.get_property_list():
		if property.name == &"tags":
			var tags: Array = body.get(&"tags")
			return tags != null and required_tag in tags
	return false
