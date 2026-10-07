extends Node

var _movement_perf := preload("res://Scripts/Debug/ControlPerformanceStats.gd").new()

const PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")

const LEG_TAG: int = 1
const TORSO_TAG: int = 0
const MIN_STEP_TIME: float = 0.001

enum StepState { IDLE, MOVING, LANDING }
const GAIT_DATA = preload("res://Scripts/Creatures/LegMovementData.gd")

class StepMotion extends RefCounted:
	var leg: RigidBody3D
	var state: int = 0
	var sequence: int = 0
	var start: Vector3 = Vector3.ZERO
	var target: Vector3 = Vector3.ZERO
	var normal: Vector3 = Vector3.UP
	var elapsed: float = 0.0
	var landing_elapsed: float = 0.0
	var confirmation: float = 0.0
	var duration: float = 0.35
	var scale: float = 1.0
	var direction: Vector3 = Vector3.ZERO
	var last_replan_time: float = -INF
	var height: float = -1.0
	var extra: Dictionary = {}

@export_group("Gait Resources")
## Empty uses the existing Inspector settings and sequential scheduler.
@export var slow_gait_data: GAIT_DATA
@export var fast_gait_data: GAIT_DATA

var _current_step := StepMotion.new()
var _active_steps: Array[StepMotion] = []
var _updating_steps: bool = false
var _next_resource_step_time: float = 0.0
var _last_scheduler_resource: Resource


@export_group("Walk Start Stagger")
@export var walk_start_stagger_enabled: bool = true
## First-start spacing references cadence; normal gait is unchanged after the first cycle.
@export_range(0.0, 2.0, 0.05) var walk_start_interval_ratio: float = 0.5
@export_range(0.01, 0.5, 0.01) var walk_start_maximum_interval: float = 0.12
@export_range(0.0, 2.0, 0.05) var walk_start_speed_threshold: float = 0.4
@export_range(0.0, 1.0, 0.01) var walk_start_stop_speed: float = 0.15
@export_range(0.0, 1.0, 0.05) var walk_start_stop_confirmation: float = 0.2
var _walk_start_pending: Array[RigidBody3D] = []
var _walk_start_due: Dictionary = {}
var _walk_start_input_active := false
var _walk_start_stop_elapsed := 0.0
var _walk_start_direction := Vector3.ZERO
var _walk_start_interval := 0.0
var _walk_start_last_start := -INF
var _walk_start_last_frame := -1
var _walk_start_status: StringName = &"idle"
var _walk_start_bypasses := 0

@export_group("Control")
@export var input_enabled: bool = true
## Player input is supplied by a separate Controller; NPCs may keep their state-machine source.
@export var command_source: Node

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

@export_group("Dynamic Hip Limits")
## Expands each Leg's Generic6DOFJoint3D horizontal limits to accommodate its planned stride.
@export var auto_expand_hip_limits: bool = true
## Fast gait keeps its existing limits unless explicitly enabled here.
@export var expand_hip_limits_in_fast_mode: bool = false
@export_range(0.0, 2.0, 0.05, "or_greater") var hip_limit_stride_ratio: float = 0.75
@export_range(0.0, 2.0, 0.01, "or_greater") var hip_limit_margin: float = 0.15
@export_range(0.01, 10.0, 0.01, "or_greater") var maximum_dynamic_hip_limit: float = 2.0

@export_group("Step Motion")
@export_range(0.0, 10.0, 0.01, "or_greater") var step_height: float = 0.25
@export_range(0.0, 10000.0, 1.0, "or_greater") var leg_move_stiffness: float = 200.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var leg_move_damping: float = 30.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var maximum_leg_force: float = 500.0
@export_range(0.001, 1.0, 0.001, "or_greater") var landing_tolerance: float = 0.18
@export_range(0.0, 10.0, 0.01, "or_greater") var landing_velocity_limit: float = 0.35
@export_range(0.01, 5.0, 0.01, "or_greater") var landing_timeout: float = 1.0

@export_group("Step Replanning")
## An active step is replanned only after the requested horizontal direction changes by this angle.
## This prevents small NavigationAgent3D path-direction changes from restarting the step every frame.
@export_range(0.0, 180.0, 0.5) var replan_direction_angle_degrees: float = 10.0
## Minimum time between ordinary direction replans. A true reversal is still handled immediately.
@export_range(0.0, 1.0, 0.01, "or_greater") var replan_cooldown: float = 0.12

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

@export_group("Support Foot Lock")
## Grounded support feet retain a landing anchor until they step or leave the surface.
@export var support_foot_lock_enabled: bool = true
@export_storage var support_foot_stiffness: float = 250.0
@export_storage var support_foot_damping: float = 40.0
@export_storage var maximum_support_foot_force: float = 500.0

@export_group("Ground Movement Brake")
@export var ground_movement_brake_enabled: bool = true
@export_range(0.0, 100.0, 0.1, "or_greater") var ground_brake_gain: float = 12.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var maximum_ground_brake_force: float = 1200.0

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
@export_storage var torso_force_per_unit: float = 80.0
@export_storage var maximum_torso_force: float = 300.0

@export_group("Contact Movement Drive")
## Velocity demand replaces foot-displacement feedback. Forces require real stance contact.
@export_range(0.0, 50.0, 0.1) var contact_velocity_gain: float = 4.0
@export_range(0.0, 30.0, 0.1) var contact_maximum_acceleration: float = 4.0
@export_range(0.0, 100000.0, 1.0, "or_greater") var maximum_contact_drive_force: float = 20000.0
@export_range(0.0, 3.0, 0.05) var contact_traction_coefficient: float = 0.8
## Additional persistent world-space demand; clear explicitly after the requesting action ends.
var _contact_extra_force: Vector3 = Vector3.ZERO
var _contact_drive_diagnostics: Dictionary = {}
var _contact_drive_frame: int = -1
var _contact_drive_rows: Array[Dictionary] = []

@export_group("Torso Ground Support")
## Legacy setting retained for saved scenes; contact drive always requires stance contact.
@export_storage var torso_movement_force_requires_leg_support: bool = true
## Legacy setting retained for saved scenes; airborne contact drive is disabled.
@export_storage var fast_airborne_force_grace_duration: float = 0.18

@export_group("Diagnostics")
@export var diagnostic_logging_enabled: bool = false
@export_range(0.1, 10.0, 0.1, "or_greater") var diagnostic_log_interval: float = 0.5
@export_range(0.1, 10.0, 0.1, "or_greater") var diagnostic_rejection_interval: float = 0.5

var _step_state: StepState:
	get: return _current_step.state
	set(value): _current_step.state = value
var _active_leg: RigidBody3D:
	get: return _current_step.leg
	set(value): _current_step.leg = value
var _legs: Array[RigidBody3D] = []
var _next_leg_index: int = 0
var _step_start: Vector3:
	get: return _current_step.start
	set(value): _current_step.start = value
var _step_target: Vector3:
	get: return _current_step.target
	set(value): _current_step.target = value
var _step_target_normal: Vector3:
	get: return _current_step.normal
	set(value): _current_step.normal = value
var _step_elapsed: float:
	get: return _current_step.elapsed
	set(value): _current_step.elapsed = value
var _landing_elapsed: float:
	get: return _current_step.landing_elapsed
	set(value): _current_step.landing_elapsed = value
var _grounded_confirmation_elapsed: float:
	get: return _current_step.confirmation
	set(value): _current_step.confirmation = value
var _active_step_duration: float:
	get: return _current_step.duration
	set(value): _current_step.duration = value
var _active_movement_scale: float:
	get: return _current_step.scale
	set(value): _current_step.scale = value
var _torso: RigidBody3D
## Initial leg positions in Torso-local space. They remain the source of every future landing sample.
var _leg_initial_local_positions: Dictionary[RigidBody3D, Vector3] = {}
var _leg_initial_center_local: Vector3 = Vector3.ZERO
var _leg_adhesion_surface_normals: Dictionary[RigidBody3D, Vector3] = {}
var _support_anchors: Dictionary[RigidBody3D, Vector3] = {}
var _support_forces: Dictionary[RigidBody3D, Vector3] = {}
var _adhesion_forces: Dictionary = {}
var _ground_brake_force: Vector3 = Vector3.ZERO
var _character_body_cache: Array[RigidBody3D] = []
var _body_cache_root: Node
var _body_cache_dirty: bool = true
var _torso_parts_cache: Array[RigidBody3D] = []
var _torso_cache_frame: int = -1
var _turn_movement_multiplier: float = 1.0
var _facing_controller: Node
var _turn_planning_active: bool = false

func set_turn_planning_active(active: bool) -> void:
	if active == _turn_planning_active:
		return
	_turn_planning_active = active
	if active:
		if not _resource_turn_blending_enabled(): cancel_step(&"turn_planning_started")
	else:
		_turn_movement_multiplier = 1.0
		restore_base_hip_joint_limits()
		_fast_gait_anchor_valid = false

func set_turn_movement_multiplier(multiplier: float) -> void:
	_turn_movement_multiplier = clampf(multiplier, 0.0, 1.0)

func get_expected_horizontal_speed() -> float:
	return _get_expected_horizontal_speed() * _turn_movement_multiplier

var _last_input_direction: Vector3 = Vector3.ZERO
var _active_step_input_direction: Vector3:
	get: return _current_step.direction
	set(value): _current_step.direction = value
var _last_replan_time: float:
	get: return _current_step.last_replan_time
	set(value): _current_step.last_replan_time = value
var _last_fast_speed_active: bool = false
var _adhesion_release_time_remaining: float = 0.0
var _joint_spring_scale: float = 1.0
var _joint_base_springs: Dictionary[Generic6DOFJoint3D, Vector2] = {}
var _hip_joints_by_leg: Dictionary[RigidBody3D, Generic6DOFJoint3D] = {}
## lower X, upper X, lower Z, upper Z for every Leg joint.
var _hip_joint_base_limits: Dictionary[Generic6DOFJoint3D, Vector4] = {}
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
var _external_step_height: float:
	get: return _current_step.height
	set(value): _current_step.height = value
var _last_touchdown_leg: StringName = &""
var _last_touchdown_interval: float = -1.0
var _last_touchdown_time: float = -1.0
var _last_touchdown_times_by_leg: Dictionary[StringName, float] = {}
var _last_grounded_force_legs: Array[RigidBody3D] = []
var _last_ground_support_time: float = -1.0
var _performance_tracking_enabled: bool = false
var _performance_physics_frames: int = 0
var _performance_ray_queries: int = 0
var _performance_shape_queries: int = 0
var _performance_total_usec: int = 0
var _performance_max_usec: int = 0
var _leg_collision_shape_cache: Dictionary[RigidBody3D, CollisionShape3D] = {}
var _character_exclusion_rids: Array[RID] = []
var _ground_probe_cache: Dictionary[RigidBody3D, Dictionary] = {}
var _ground_probe_cache_physics_frame: int = -1
var _physics_query_cache_dirty: bool = true
var _diagnostic_elapsed: float = 0.0
var _diagnostic_last_event_times: Dictionary[String, float] = {}
var _last_landing_rejection_reason: StringName = &""

func _get_gait_data() -> GAIT_DATA:
	var data := fast_gait_data if is_fast_speed_active() else slow_gait_data
	return data if data != null and data.is_valid() else null

var _automatic_profiles: Dictionary = {}
var _automatic_profiles_frame: int = -1
var _automatic_next_steps: Dictionary = {}

func _automatic_motion_enabled() -> bool:
	var data := _get_gait_data()
	return data != null and data.automatic_motion

func _get_leg_reference_length(leg: RigidBody3D) -> float:
	return maxf(Vector3(_leg_initial_local_positions.get(leg, Vector3.ONE)).length(), 0.1)

func _get_leg_turn_radius(leg: RigidBody3D) -> float:
	return maxf(Vector3(_leg_initial_local_positions.get(leg, Vector3.ONE)).slide(Vector3.UP).length(), 0.1)

func get_leg_motion_profile(leg: RigidBody3D) -> Dictionary:
	if not _automatic_motion_enabled() or not is_instance_valid(leg): return {}
	if _automatic_profiles_frame != Engine.get_physics_frames():
		_automatic_profiles.clear()
		_automatic_profiles_frame = Engine.get_physics_frames()
	if not _automatic_profiles.has(leg):
		_automatic_profiles[leg] = _get_gait_data().calculate_motion_profile(_get_leg_reference_length(leg), _get_leg_turn_radius(leg), _legs.size(), _get_gait_reference_length())
	return _automatic_profiles[leg]

func get_automatic_motion_diagnostics() -> Dictionary:
	var legs: Array[Dictionary] = []
	for leg: RigidBody3D in _legs:
		var profile := get_leg_motion_profile(leg).duplicate()
		if not profile.is_empty(): profile["foot"] = leg.name; legs.append(profile)
	return {"enabled": _automatic_motion_enabled(), "requested_speed": _get_gait_data().target_speed if _automatic_motion_enabled() else get_expected_horizontal_speed(), "target_speed": get_expected_horizontal_speed(), "total_step_frequency": get_planned_step_frequency(), "legs": legs}

func _step_motion_setting(key: String, fallback: float) -> float:
	var profile: Dictionary = _current_step.extra.get("automatic_profile", {})
	return float(profile.get(key, fallback))

func _motion_setting(key: String, fallback: float, leg: RigidBody3D = null) -> float:
	if not _automatic_motion_enabled(): return fallback
	if leg == null: leg = _active_leg if is_instance_valid(_active_leg) else (_legs[0] if not _legs.is_empty() else null)
	return float(get_leg_motion_profile(leg).get(key, fallback))

func get_leg_step_distance(leg: RigidBody3D) -> float:
	return _motion_setting("stride", get_current_step_distance(), leg)

func _get_gait_reference_length() -> float:
	var shortest := INF
	for leg: RigidBody3D in _legs:
		shortest = minf(shortest, _get_leg_reference_length(leg))
	return maxf(shortest, 0.01) if is_finite(shortest) else 1.0

func _get_gait_step_distance() -> float:
	if _automatic_motion_enabled(): return _motion_setting("stride", minimum_step_distance)
	var data := _get_gait_data()
	var distance := data.stride_length_ratio * _get_gait_reference_length() if data.use_limb_length_ratios else data.step_distance
	return maxf(distance * sqrt(_get_configured_movement_scale()), minimum_step_distance)

func _get_gait_step_height() -> float:
	if _automatic_motion_enabled(): return _motion_setting("lift", 0.1)
	var data := _get_gait_data()
	var height := data.lift_length_ratio * _get_gait_reference_length() if data.use_limb_length_ratios else data.step_height
	return minf(height * sqrt(_get_configured_movement_scale()), maximum_scaled_step_height)

func get_maximum_stepping_feet() -> int:
	var data := _get_gait_data()
	if data == null: return 1
	if data.automatic_motion: return data.calculate_support_capacity(_legs.size())
	var count := mini(floori(_legs.size() * data.maximum_stepping_ratio), maxi(0, _legs.size() - data.minimum_support_feet))
	if data.maximum_simultaneous_steps > 0: count = mini(count, data.maximum_simultaneous_steps)
	return maxi(count, 0)

func get_planned_step_frequency() -> float:
	if _automatic_motion_enabled():
		var frequency := 0.0
		for foot: RigidBody3D in _legs: frequency += float(get_leg_motion_profile(foot).frequency)
		return frequency
	var data := _get_gait_data()
	if data == null: return get_fast_step_frequency() if is_fast_speed_active() else 1.0 / maxf(get_current_step_duration(), MIN_STEP_TIME)
	return minf(data.step_frequency * sqrt(_get_configured_movement_scale()), get_maximum_stepping_feet() / maxf(get_current_step_duration(), MIN_STEP_TIME))

func is_leg_stepping(leg: RigidBody3D) -> bool:
	if leg == null: return false
	for motion: StepMotion in _active_steps:
		if is_instance_valid(motion.leg) and motion.leg == leg and motion.state != StepState.IDLE: return true
	return leg == _active_leg and _step_state != StepState.IDLE

func get_leg_step_diagnostics(leg: RigidBody3D) -> Dictionary:
	for motion: StepMotion in _active_steps:
		if motion.leg == leg:
			return {"sequence": motion.sequence, "state": StepState.keys()[motion.state], "target": motion.target, "normal": motion.normal,
				"distance": (motion.target - leg.global_position).slide(Vector3.UP).length(),
				"timeout": maxf(float(motion.extra.get("landing_timeout", landing_timeout)) - motion.landing_elapsed, 0.0) if motion.state == StepState.LANDING else -1.0,
				"extra": motion.extra.duplicate()}
	return {"sequence": 0, "state": "IDLE", "target": Vector3.ZERO, "normal": Vector3.ZERO, "distance": 0.0, "timeout": -1.0, "extra": {}}

func _resource_turn_blending_enabled() -> bool:
	return false

func _has_resource_step_demand(direction: Vector3) -> bool:
	return not direction.is_zero_approx()

func _update_resource_gait(delta: float, direction: Vector3) -> void:
	# Each foot retains its own swing/landing timers and generated-drive data.
	_updating_steps = true
	for motion: StepMotion in _active_steps.duplicate():
		_current_step = motion
		if not is_instance_valid(motion.leg) or _is_body_broken(motion.leg) or not _legs.has(motion.leg):
			cancel_step(&"active_leg_invalid")
			continue
		if not motion.extra.get("generated_turn_step", false) and not direction.is_zero_approx() and _should_replan_active_step_direction(direction): replan_active_step(direction)
		_update_active_step(delta)
	_updating_steps = false
	var frequency := get_planned_step_frequency()
	if _has_resource_step_demand(direction) and _adhesion_release_time_remaining <= 0.0 and frequency > 0.0 and _physics_elapsed >= _next_resource_step_time and _active_steps.size() < get_maximum_stepping_feet():
		_current_step = StepMotion.new()
		var candidates := _legs.duplicate()
		if _automatic_motion_enabled() or not _walk_start_pending.is_empty():
			candidates.sort_custom(func(a,b):
				var a_rank := _walk_start_pending.find(a)
				var b_rank := _walk_start_pending.find(b)
				if a_rank>=0 or b_rank>=0: return a_rank<b_rank if a_rank>=0 and b_rank>=0 else a_rank>=0
				return float(_automatic_next_steps.get(a,0.0))<float(_automatic_next_steps.get(b,0.0)))
		for attempt: int in range(_legs.size()):
			if _automatic_motion_enabled() or not _walk_start_pending.is_empty():
				var candidate: RigidBody3D = candidates[attempt]
				if not _walk_start_pending.has(candidate) and _physics_elapsed < float(_automatic_next_steps.get(candidate, 0.0)): continue
				_next_leg_index = _legs.find(candidate)
			var started := try_start_step(direction)
			_next_leg_index = (_next_leg_index + 1) % maxi(_legs.size(), 1)
			if started:
				if _automatic_motion_enabled() and not _current_step.extra.get("generated_turn_step", false): _automatic_next_steps[_active_leg] = _physics_elapsed + float(get_leg_motion_profile(_active_leg).cycle)
				_updating_steps = true
				_update_active_step(delta)
				_updating_steps = false
				break
		# Never catch up missed events in a burst after a blocked support interval.
		_next_resource_step_time = _physics_elapsed + 1.0 / frequency
	_current_step = _active_steps[0] if not _active_steps.is_empty() else StepMotion.new()
	_last_input_direction = direction
	_last_fast_speed_active = is_fast_speed_active()

func _ready() -> void:
	_reset_contact_drive_diagnostics()
	_movement_perf.register(self)
	add_to_group(&"leg_step_movement_controllers")
	var runtime_console := get_tree().root.get_node_or_null("RuntimeConsole")
	if (
		runtime_console != null
		and runtime_console.has_method("is_npc_diagnostic_tracking_enabled")
		and bool(runtime_console.call("is_npc_diagnostic_tracking_enabled"))
		and get_parent().has_node("NPCStateMachine3D")
	):
		diagnostic_logging_enabled = true
	_torso = get_node_or_null(torso_path) as RigidBody3D
	_refresh_physics_query_cache()
	_capture_leg_initial_positions()
	_last_fast_speed_active = is_fast_speed_active()
	_active_movement_scale = _get_configured_movement_scale()
	_joint_spring_scale = _active_movement_scale
	_capture_joint_spring_settings()
	_capture_hip_joint_limits()
	_apply_joint_spring_scale(_joint_spring_scale)

func _physics_process(delta: float) -> void:
	var movement_started: int = _movement_perf.start()
	var started_usec := Time.get_ticks_usec() if _performance_tracking_enabled else 0
	_physics_elapsed += delta
	var selected_data := _get_gait_data()
	if selected_data != _last_scheduler_resource:
		cancel_step(&"gait_resource_changed")
		_last_scheduler_resource = selected_data
		_automatic_next_steps.clear()
	if _physics_query_cache_dirty:
		_refresh_physics_query_cache()
	_begin_ground_probe_frame()
	_current_fast_landing_force = Vector3.ZERO
	_reset_contact_drive_diagnostics()
	_adhesion_release_time_remaining = maxf(_adhesion_release_time_remaining - delta, 0.0)
	_update_joint_spring_scale(delta)
	if input_enabled and is_burst_requested():
		try_surface_burst()

	var input_direction := get_input_movement_direction() if input_enabled else Vector3.ZERO
	_update_walk_start_stagger(delta,input_direction)
	var fast_speed_active := is_fast_speed_active() if input_enabled and not _turn_planning_active else false
	_refresh_torso_force_support()
	_update_fast_velocity_gait(delta, input_direction, fast_speed_active)
	if _get_gait_data() != null and (not _turn_planning_active or _resource_turn_blending_enabled()):
		_update_resource_gait(delta, input_direction)
	else:
		if (
			not _turn_planning_active
			and _adhesion_release_time_remaining <= 0.0
			and not input_direction.is_zero_approx()
			and _step_state != StepState.IDLE
			and _should_replan_active_step_direction(input_direction)
		):
			replan_active_step(input_direction)
		elif (
			not _turn_planning_active
			and fast_speed_active != _last_fast_speed_active
			and not input_direction.is_zero_approx()
			and _step_state != StepState.IDLE
		):
			replan_active_step(input_direction)
		_last_input_direction = input_direction
		_last_fast_speed_active = fast_speed_active
	
		if fast_speed_active:
			_update_fast_gait_clock(input_direction)
		elif not _turn_planning_active and _step_state == StepState.IDLE and _adhesion_release_time_remaining <= 0.0:
			if not input_direction.is_zero_approx():
				for attempt: int in range(maxi(_walk_start_pending.size(),1)):
					if try_start_step(input_direction): break
					if not _legs.is_empty(): _next_leg_index = (_next_leg_index+1)%_legs.size()
		if _step_state != StepState.IDLE:
			_update_active_step(delta)
	_update_fast_float_lift(delta, input_direction, fast_speed_active)
	update_leg_surface_adhesion()
	_ground_brake_force = Vector3.ZERO
	if _adhesion_release_time_remaining <= 0.0:
		var response_started: int = _movement_perf.start()
		_apply_torso_response()
		_movement_perf.finish(&"torso_response", response_started)
		# Contact velocity demand includes braking; do not stack legacy velocity drives.
	if _performance_tracking_enabled:
		var elapsed_usec := Time.get_ticks_usec() - started_usec
		_performance_physics_frames += 1
		_performance_total_usec += elapsed_usec
		_performance_max_usec = maxi(_performance_max_usec, elapsed_usec)
	_update_diagnostic_log(delta)
	_movement_perf.finish(&"movement_base", movement_started)

func set_diagnostic_logging_enabled(enabled: bool) -> void:
	diagnostic_logging_enabled = enabled
	_diagnostic_elapsed = diagnostic_log_interval if enabled else 0.0
	_diagnostic_last_event_times.clear()

func set_performance_tracking_enabled(enabled: bool) -> void:
	_performance_tracking_enabled = enabled
	_reset_performance_stats()

func is_performance_tracking_enabled() -> bool:
	return _performance_tracking_enabled

func consume_performance_stats() -> Dictionary:
	var result := {
		&"physics_frames": _performance_physics_frames,
		&"ray_queries": _performance_ray_queries,
		&"shape_queries": _performance_shape_queries,
		&"total_usec": _performance_total_usec,
		&"max_usec": _performance_max_usec,
	}
	_reset_performance_stats()
	return result

func _reset_performance_stats() -> void:
	_performance_physics_frames = 0
	_performance_ray_queries = 0
	_performance_shape_queries = 0
	_performance_total_usec = 0
	_performance_max_usec = 0

func _update_fast_velocity_gait(
	delta: float,
	input_direction: Vector3,
	fast_speed_active: bool
) -> void:
	var scale := _get_fast_movement_scale()
	_fast_step_frequency = _calculate_fast_step_frequency()
	_fast_step_interval = 1.0 / maxf(_fast_step_frequency, MIN_STEP_TIME)
	var planned_speed := _get_gait_step_distance() * get_planned_step_frequency() if _get_gait_data() != null else fast_target_speed * scale
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
	cancel_step(&"fast_phase_replaced")

func _apply_fast_torso_velocity_drive() -> void:
	if (
		not fast_torso_velocity_drive_enabled
		or not is_instance_valid(_torso)
		or not has_torso_movement_force_support(true)
	):
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
var _last_shared_step_start: float = -INF
func _automatic_step_cadence_allows() -> bool:
	if not _walk_start_pending.is_empty() and not is_finite(_walk_start_last_start): return true
	if not _automatic_motion_enabled() or _get_gait_data().maximum_step_frequency <= 0.0: return true
	return _physics_elapsed + 0.000001 >= _last_shared_step_start + 1.0 / _get_gait_data().maximum_step_frequency

func try_start_step(movement_direction: Vector3 = Vector3.RIGHT) -> bool:
	if not _automatic_step_cadence_allows(): return false
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
	if not _walk_start_stagger_allows(candidate): return false
	if is_leg_stepping(candidate) or not _can_start_step_with_support(candidate):
		_log_gait_event(&"step_rejected", candidate, &"no_support", movement_direction)
		return false
	var landing := find_landing_point(candidate, movement_direction)
	if landing.is_empty():
		var rejection_reason := (
			_last_landing_rejection_reason
			if not _last_landing_rejection_reason.is_empty()
			else &"no_landing_point"
		)
		_log_gait_event(&"step_rejected", candidate, rejection_reason, movement_direction)
		return false
	_begin_leg_motion(
		candidate,
		_body_position_for_ground_contact(candidate, landing[&"position"]),
		landing[&"normal"],
		movement_direction
	)
	return true

## Shares landing validation, swing tracking and contact confirmation with walking.
func try_start_turn_step(leg: RigidBody3D, sample_position: Vector3, duration: float, height: float) -> bool:
	_last_landing_rejection_reason = &""
	if not _automatic_step_cadence_allows():
		_last_landing_rejection_reason = &"cadence_wait"
		return false
	if _step_state != StepState.IDLE or not is_instance_valid(leg) or _is_body_broken(leg):
		_last_landing_rejection_reason = &"step_busy_or_invalid_leg"
		return false
	if not _can_start_step_with_support(leg):
		_last_landing_rejection_reason = &"insufficient_support"
		return false
	var foot := _get_foot_world_position(leg)
	var ray_from := Vector3(sample_position.x, foot.y + ray_start_height, sample_position.z)
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_from + Vector3.DOWN * ray_length, terrain_collision_mask, _get_character_exclusion_rids())
	query.collide_with_areas = false
	var hit := _intersect_ray(query)
	if not _is_landing_point_valid(leg, foot, hit):
		return false
	_begin_leg_motion(leg, _body_position_for_ground_contact(leg, hit[&"position"]), hit[&"normal"])
	if _automatic_motion_enabled() and _get_gait_data().maximum_step_frequency > 0.0:
		_next_resource_step_time = _physics_elapsed + 1.0 / _get_gait_data().maximum_step_frequency
	_active_step_duration = maxf(duration, MIN_STEP_TIME)
	_external_step_height = maxf(height, 0.0)
	if _automatic_motion_enabled():
		var profile: Dictionary = _current_step.extra.automatic_profile
		var gain := clampf(16.0 / (_active_step_duration * _active_step_duration), 20.0, 4000.0)
		profile.position_gain = gain
		profile.velocity_gain = 2.0 * sqrt(gain)
		profile.step_acceleration = clampf(8.0 * maxf((_step_target - leg.global_position).length(), height) / (_active_step_duration * _active_step_duration) + 9.8, 30.0, 2000.0)
	return true

func get_turn_step_rejection_reason() -> StringName:
	return _last_landing_rejection_reason

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
		var rejection_reason := StringName("replan_%s" % (
			_last_landing_rejection_reason
			if not _last_landing_rejection_reason.is_empty()
			else &"no_landing_point"
		))
		_log_gait_event(&"step_rejected", _active_leg, rejection_reason, new_direction)
		return false
	_log_gait_event(
		&"step_replanned",
		_active_leg,
		&"input_changed",
		new_direction,
		_body_position_for_ground_contact(_active_leg, landing[&"position"])
	)
	_begin_leg_motion(
		_active_leg,
		_body_position_for_ground_contact(_active_leg, landing[&"position"]),
		landing[&"normal"],
		new_direction
	)
	_last_replan_time = _physics_elapsed
	return true

func _should_replan_active_step_direction(new_direction: Vector3) -> bool:
	new_direction.y = 0.0
	if new_direction.is_zero_approx():
		return false
	new_direction = new_direction.normalized()
	var planned_direction := _active_step_input_direction
	planned_direction.y = 0.0
	if planned_direction.is_zero_approx():
		return true
	planned_direction = planned_direction.normalized()
	var direction_dot := clampf(planned_direction.dot(new_direction), -1.0, 1.0)
	# A reversal must react immediately even if the ordinary replan cooldown is active.
	if direction_dot < 0.0:
		return true
	if _physics_elapsed - _last_replan_time < _motion_setting("replan_cooldown", replan_cooldown):
		return false
	var minimum_dot := cos(deg_to_rad(replan_direction_angle_degrees))
	return direction_dot < minimum_dot

## Searches from the preferred stride back toward the leg and returns the first legal hit.
func find_landing_point(leg: RigidBody3D, movement_direction: Vector3 = Vector3.RIGHT) -> Dictionary:
	_last_landing_rejection_reason = &""
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
		var forward_distance := lerpf(get_leg_step_distance(leg), minf(minimum_step_distance, get_leg_step_distance(leg)), ratio)
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
		var hit: Dictionary = _intersect_ray(query)
		if _is_landing_point_valid(leg, foot_position, hit):
			return hit
	return {}

func get_leg_parts() -> Array[RigidBody3D]:
	_remove_invalid_legs()
	return _legs.duplicate()

func _discover_leg_parts() -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	var parts_root := get_node_or_null(parts_root_path)
	if parts_root == null:
		return result
	for node: Node in parts_root.find_children("*", "RigidBody3D", true, false):
		var body := node as RigidBody3D
		if _has_leg_tag(body) and not _is_body_broken(body):
			result.append(body)
	return result

func get_active_leg() -> RigidBody3D:
	return _active_leg

## Input seam implemented by player, AI, replay, or network-controlled subclasses.
func get_player_command_source() -> Node:
	if is_instance_valid(command_source): return command_source
	var source := PLAYER_CONTEXT.controller(self)
	return source if source != null and source.get_controlled_character() == get_parent() else null

func get_input_movement_direction() -> Vector3:
	return Vector3.ZERO

func is_burst_requested() -> bool:
	return false

func is_fast_speed_active() -> bool:
	return false

func get_current_speed_preset_name() -> String:
	return "FAST" if is_fast_speed_active() else "SLOW"

func get_current_step_distance() -> float:
	if _get_gait_data() != null: return _get_gait_step_distance()
	if is_fast_speed_active():
		return maxf(
			fast_target_speed * _get_fast_movement_scale() / _calculate_fast_step_frequency(),
			minimum_step_distance
		)
	return slow_step_distance * sqrt(_get_configured_movement_scale())

func get_current_step_duration() -> float:
	if _automatic_motion_enabled(): return _motion_setting("swing_duration", 0.35)
	if _get_gait_data() != null: return _get_gait_data().swing_duration / sqrt(_get_configured_movement_scale())
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
	return 1.0 / maxf(_calculate_fast_step_frequency(), MIN_STEP_TIME)

func _get_fast_movement_scale() -> float:
	return maxf(fast_movement_scale, 0.1) if use_fast_movement_scale else 1.0

func _calculate_fast_step_frequency() -> float:
	if _get_gait_data() != null: return get_planned_step_frequency()
	return clampf(
		fast_base_step_frequency * sqrt(_get_fast_movement_scale()),
		fast_minimum_step_frequency,
		maxf(fast_maximum_step_frequency, fast_minimum_step_frequency)
	)

func _get_configured_movement_scale() -> float:
	if _automatic_motion_enabled(): return 1.0
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

func cancel_step(reason: StringName = &"unspecified") -> void:
	if reason in [&"flight",&"landed",&"recovery",&"character_disabled",&"generated_parts_refreshed",&"physics_test_mode_changed"]: _reset_walk_start_stagger(reason)
	if reason != &"completed":
		if _updating_steps:
			if is_instance_valid(_active_leg): _log_gait_event(&"step_cancelled", _active_leg, reason, _last_input_direction, _step_target)
		else:
			for motion: StepMotion in _active_steps:
				if is_instance_valid(motion.leg): _log_gait_event(&"step_cancelled", motion.leg, reason, _last_input_direction, motion.target)
	if _updating_steps:
		_active_steps.erase(_current_step)
	else:
		_active_steps.clear()
		_next_resource_step_time = _physics_elapsed
	_active_leg = null
	_active_step_input_direction = Vector3.ZERO
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
	_adhesion_forces.clear()
	_remove_invalid_legs()
	_support_forces.clear()
	for previous_leg in _support_pins.keys():
		if not is_instance_valid(previous_leg) or not _legs.has(previous_leg):
			_release_support_pin(previous_leg)
	if _adhesion_release_time_remaining > 0.0:
		_clear_leg_adhesion_surface_normals()
		release_all_support_pins()
		return
	for leg: RigidBody3D in _legs:
		if _is_leg_action_controlled(leg): continue
		if is_leg_stepping(leg):
			if _keep_touchdown_support_pin(leg):
				continue
			_release_support_pin(leg)
			_leg_adhesion_surface_normals[leg] = Vector3.ZERO
			continue
		var hit := _get_surface_below_leg(leg, surface_adhesion_probe_distance)
		if hit.is_empty():
			_release_support_pin(leg)
			_leg_adhesion_surface_normals[leg] = Vector3.ZERO
			continue
		var surface_normal: Vector3 = hit[&"normal"].normalized()
		_leg_adhesion_surface_normals[leg] = surface_normal
		_update_support_foot_lock(leg, surface_normal)
		var adhesion_multiplier := fast_lift_adhesion_multiplier if _fast_lift_time_remaining > 0.0 else 1.0
		if surface_adhesion_enabled and not _support_pins.has(leg):
			var force := _calculate_leg_adhesion_force(leg, hit, adhesion_multiplier)
			_adhesion_forces[leg] = force
			if not force.is_zero_approx():
				leg.sleeping = false
				leg.apply_central_force(force)

func _calculate_leg_adhesion_force(_leg: RigidBody3D, hit: Dictionary, multiplier: float) -> Vector3:
	return -Vector3(hit.normal).normalized() * surface_adhesion_force * _get_configured_movement_scale() * multiplier

var _support_pins: Dictionary = {}

func is_leg_slipping(leg: RigidBody3D) -> bool:
	return is_instance_valid(leg) and leg.get("is_slipping") == true

func set_leg_slipping(leg: RigidBody3D, slipping: bool) -> void:
	if not is_instance_valid(leg) or not leg.has_signal("slipping_changed"): return
	leg.set("is_slipping", slipping)
	if slipping: _release_support_pin(leg)

func _on_foot_slipping_changed(slipping: bool, leg: RigidBody3D) -> void:
	if slipping: _release_support_pin(leg)

func _on_pinned_foot_exiting(leg: RigidBody3D) -> void:
	_release_support_pin(leg)

func _on_pinned_foot_broken(_source: Node, leg: RigidBody3D) -> void:
	_release_support_pin(leg)

func _release_support_pin(leg) -> void:
	if _support_pins.has(leg):
		var pin: Generic6DOFJoint3D = _support_pins[leg].joint
		if is_instance_valid(pin): pin.free()
		_support_pins.erase(leg)
	_support_anchors.erase(leg)

func release_all_support_pins() -> void:
	for leg in _support_pins.keys(): _release_support_pin(leg)
	_support_anchors.clear()

## External attacks release stance pins without adding the jump's own impulse.
func release_support_for_impact(duration: float) -> void:
	release_all_support_pins()
	cancel_step(&"external_impact")
	_fast_lift_time_remaining = 0.0
	_current_fast_lift_force = 0.0
	_adhesion_release_time_remaining = maxf(_adhesion_release_time_remaining,maxf(duration,0.0))
	_clear_leg_adhesion_surface_normals()

func _exit_tree() -> void:
	release_all_support_pins()

func _support_pin_z_free() -> bool:
	return false

## Generated landing phases may retain a real-contact pin before finishing a step.
func _keep_touchdown_support_pin(_leg: RigidBody3D) -> bool:
	return false

func _is_leg_action_controlled(_leg: RigidBody3D) -> bool:
	return false

func _update_support_foot_lock(leg: RigidBody3D, normal: Vector3) -> void:
	if _adhesion_release_time_remaining > 0.0 or not support_foot_lock_enabled or not surface_adhesion_enabled or leg.freeze or _is_body_broken(leg) or is_leg_slipping(leg) or not is_leg_grounded(leg):
		_release_support_pin(leg)
		return
	var hit := _get_surface_below_leg(leg, surface_adhesion_probe_distance)
	if hit.is_empty():
		_release_support_pin(leg)
		return
	# A broad ground ray alone is insufficient: never pin a foot while still falling.
	if absf((_get_foot_world_position(leg) - Vector3(hit.position)).dot(normal)) > 0.08:
		_release_support_pin(leg)
		return
	var terrain := hit.get("collider") as PhysicsBody3D
	if _support_pins.has(leg):
		var entry: Dictionary = _support_pins[leg]
		if not is_instance_valid(entry.joint) or (entry.terrain != null and not is_instance_valid(entry.terrain)) or entry.terrain != terrain:
			_release_support_pin(leg)
		else:
			_support_anchors[leg] = terrain.to_global(entry.local_anchor) if terrain != null else entry.local_anchor
			return
	var pin := Generic6DOFJoint3D.new()
	pin.name = "FootGroundPin_" + str(leg.get_instance_id())
	pin.exclude_nodes_from_collision = false
	pin.set_meta(&"foot_ground_pin", true)
	for axis: String in ["x", "y", "z"]:
		pin.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, not (axis == "z" and _support_pin_z_free()))
		pin.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
		pin.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
		pin.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
		pin.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, false)
		pin.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)
	add_child(pin)
	pin.global_position = leg.global_position
	pin.node_a = pin.get_path_to(leg)
	if terrain != null: pin.node_b = pin.get_path_to(terrain)
	_support_pins[leg] = {"joint": pin, "terrain": terrain, "local_anchor": terrain.to_local(leg.global_position) if terrain != null else leg.global_position}
	_support_anchors[leg] = leg.global_position
	if leg.has_signal("slipping_changed"):
		var callback := _on_foot_slipping_changed.bind(leg)
		if not leg.is_connected("slipping_changed", callback): leg.connect("slipping_changed", callback)
	if leg.has_signal("broken"):
		var callback := _on_pinned_foot_broken.bind(leg)
		if not leg.is_connected("broken", callback): leg.connect("broken", callback)
	var exiting_callback := _on_pinned_foot_exiting.bind(leg)
	if not leg.tree_exiting.is_connected(exiting_callback): leg.tree_exiting.connect(exiting_callback)

func get_support_foot_diagnostics(leg: RigidBody3D) -> Dictionary:
	return {
		"locked": _support_pins.has(leg), "slipping": is_leg_slipping(leg), "pin_kind": "linear_constraint" if _support_pins.has(leg) else "none",
		"adhesion_force": _adhesion_forces.get(leg, Vector3.ZERO),
		"anchor": _support_anchors.get(leg, leg.global_position),
		"drift": absf(leg.global_position.x - Vector3(_support_anchors.get(leg,leg.global_position)).x) if _support_pin_z_free() else (leg.global_position - _support_anchors.get(leg, leg.global_position)).slide(Vector3.UP).length(),
		"z_free": _support_pin_z_free(),
		"speed": leg.linear_velocity.slide(Vector3.UP).length(),
		"force": _support_forces.get(leg, Vector3.ZERO),
		"brake_force": _ground_brake_force,
		"expected_speed": get_expected_horizontal_speed() if input_enabled and not get_input_movement_direction().is_zero_approx() else 0.0,
	}

func _apply_ground_movement_brake(direction: Vector3) -> void:
	if not ground_movement_brake_enabled or not is_instance_valid(_torso) or _is_body_broken(_torso):
		return
	if not has_torso_movement_force_support(is_fast_speed_active()):
		return
	var velocity := _torso.linear_velocity.slide(Vector3.UP)
	var correction := -velocity
	if not direction.is_zero_approx():
		var forward := direction.slide(Vector3.UP).normalized()
		var along := velocity.dot(forward)
		# Do not propel the Torso: Leg displacement remains the movement source.
		correction = -velocity.slide(forward) - forward * maxf(along - get_expected_horizontal_speed(), 0.0)
	var controlled_mass := 0.0
	for body: RigidBody3D in _character_body_cache:
		if is_instance_valid(body) and not _is_body_broken(body):
			controlled_mass += body.mass
	_ground_brake_force = (correction * maxf(controlled_mass, _torso.mass) * ground_brake_gain).limit_length(maximum_ground_brake_force)
	_torso.apply_central_force(_ground_brake_force)


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
	release_all_support_pins()
	for torso: RigidBody3D in torsos:
		torso.sleeping = false
		torso.apply_central_impulse(burst_direction * surface_burst_impulse)
	cancel_step(&"surface_burst")
	_fast_lift_time_remaining = 0.0
	_current_fast_lift_force = 0.0
	_adhesion_release_time_remaining = adhesion_release_duration
	_clear_leg_adhesion_surface_normals()
	return true

func get_torso_parts() -> Array[RigidBody3D]:
	var started: int = _movement_perf.start()
	var result := _get_cached_torso_parts()
	_movement_perf.finish(&"torso_lookup", started)
	return result

func _get_cached_torso_parts() -> Array[RigidBody3D]:
	var parts_root := get_node_or_null(parts_root_path)
	if _body_cache_dirty or parts_root != _body_cache_root:
		_rebuild_character_exclusion_rids()
	var frame := Engine.get_physics_frames()
	if _torso_cache_frame != frame:
		_torso_parts_cache.clear()
		for body: RigidBody3D in _character_body_cache:
			if is_instance_valid(body) and body.is_inside_tree() and _has_body_tag(body, TORSO_TAG):
				_torso_parts_cache.append(body)
		_torso_cache_frame = frame
		_movement_perf.count(&"torso_cache_refreshes")
	# Broken/removed parts must stop receiving forces immediately, even within a cached frame.
	var result: Array[RigidBody3D] = []
	for body: RigidBody3D in _torso_parts_cache:
		if is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion() and not _is_body_broken(body):
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
		if is_leg_stepping(leg):
			_leg_adhesion_surface_normals[leg] = Vector3.ZERO
			continue
		var hit := _get_surface_below_leg(leg, surface_adhesion_probe_distance)
		_leg_adhesion_surface_normals[leg] = (
			Vector3.ZERO if hit.is_empty() else (hit[&"normal"] as Vector3).normalized()
		)

func _clear_leg_adhesion_surface_normals() -> void:
	for leg: RigidBody3D in _legs:
		_leg_adhesion_surface_normals[leg] = Vector3.ZERO

func _update_diagnostic_log(delta: float) -> void:
	if not diagnostic_logging_enabled:
		return
	_diagnostic_elapsed += delta
	if _diagnostic_elapsed < diagnostic_log_interval:
		return
	_diagnostic_elapsed = 0.0
	var active_leg_name: StringName = _active_leg.name if is_instance_valid(_active_leg) else &""
	var target_error := Vector3.ZERO
	var active_grounded := false
	var hip_limits := Vector4.ZERO
	if is_instance_valid(_active_leg):
		target_error = _step_target - _active_leg.global_position
		active_grounded = is_leg_grounded(_active_leg)
		hip_limits = _get_current_hip_limits(_active_leg)
	var support_legs := get_torso_movement_force_legs(is_fast_speed_active())
	var torso_force := calculate_torso_force()
	print(
		"[npc_gait] npc=", get_parent().name,
		" state=", get_step_state_name(),
		" sequence=", _step_sequence,
		" active_leg=", active_leg_name,
		" active_grounded=", active_grounded,
		" support_count=", support_legs.size(),
		" input=", _last_input_direction,
		" target=", _step_target,
		" target_error=", target_error,
		" target_error_horizontal=", Vector2(target_error.x, target_error.z).length(),
		" step_elapsed=", _step_elapsed,
		" landing_elapsed=", _landing_elapsed,
		" hip_limits_xz=", hip_limits,
		" torso_force=", torso_force,
		" torso_position=", _torso.global_position if is_instance_valid(_torso) else Vector3.ZERO,
		" torso_velocity=", _torso.linear_velocity if is_instance_valid(_torso) else Vector3.ZERO
	)

func _log_gait_event(
	event: StringName,
	leg: RigidBody3D,
	reason: StringName,
	movement_direction: Vector3 = Vector3.ZERO,
	target: Vector3 = Vector3.INF
) -> void:
	if not diagnostic_logging_enabled:
		return
	var leg_name: StringName = leg.name if is_instance_valid(leg) else &""
	if event == &"step_rejected" or event == &"step_replanned":
		var throttle_key := "%s:%s:%s" % [event, leg_name, reason]
		var last_time := float(_diagnostic_last_event_times.get(throttle_key, -INF))
		if _physics_elapsed - last_time < diagnostic_rejection_interval:
			return
		_diagnostic_last_event_times[throttle_key] = _physics_elapsed
	var actual_target := _step_target if target == Vector3.INF else target
	var hip_limits := _get_current_hip_limits(leg)
	print(
		"[npc_gait_event] event=", event,
		" npc=", get_parent().name,
		" leg=", leg_name,
		" reason=", reason,
		" sequence=", _step_sequence,
		" direction=", movement_direction,
		" target=", actual_target,
		" hip_limits_xz=", hip_limits,
		" grounded=", is_leg_grounded(leg) if is_instance_valid(leg) else false,
		" torso_force=", calculate_torso_force(),
		" torso_velocity=", _torso.linear_velocity if is_instance_valid(_torso) else Vector3.ZERO
	)

func _get_current_hip_limits(leg: RigidBody3D) -> Vector4:
	var joint := _hip_joints_by_leg.get(leg) as Generic6DOFJoint3D
	if not is_instance_valid(joint):
		return Vector4.ZERO
	return Vector4(
		joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT),
		joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT),
		joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT),
		joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
	)

func _get_surface_below_leg(leg: RigidBody3D, probe_distance: float) -> Dictionary:
	if not is_instance_valid(leg) or not is_inside_tree():
		return {}
	var foot_position := _get_foot_world_position(leg)
	var physics_frame := Engine.get_physics_frames()
	if _ground_probe_cache_physics_frame != physics_frame:
		_begin_ground_probe_frame()
	var cached: Dictionary = _ground_probe_cache.get(leg, {})
	var maximum_probe_distance := maxf(
		maxf(ground_probe_distance, surface_adhesion_probe_distance),
		maxf(probe_distance, 0.001)
	)
	if (
		not cached.is_empty()
		and (cached.get(&"foot_position", Vector3.INF) as Vector3).is_equal_approx(foot_position)
		and float(cached.get(&"probe_distance", 0.0)) >= maximum_probe_distance
	):
		return _filter_cached_ground_hit(cached.get(&"hit", {}) as Dictionary, foot_position, probe_distance)
	var query := PhysicsRayQueryParameters3D.create(
		foot_position + Vector3.UP * ground_probe_start_offset,
		foot_position + Vector3.DOWN * maximum_probe_distance,
		terrain_collision_mask,
		_get_character_exclusion_rids()
	)
	query.collide_with_areas = false
	var hit := _intersect_ray(query)
	_ground_probe_cache[leg] = {
		&"foot_position": foot_position,
		&"probe_distance": maximum_probe_distance,
		&"hit": hit,
	}
	return _filter_cached_ground_hit(hit, foot_position, probe_distance)

func _begin_ground_probe_frame() -> void:
	_ground_probe_cache_physics_frame = Engine.get_physics_frames()
	_ground_probe_cache.clear()

func _filter_cached_ground_hit(
	hit: Dictionary,
	foot_position: Vector3,
	probe_distance: float
) -> Dictionary:
	if hit.is_empty():
		return {}
	var hit_position: Vector3 = hit.get(&"position", foot_position)
	var vertical_drop := foot_position.y - hit_position.y
	if vertical_drop > maxf(probe_distance, 0.001) + 0.0001:
		return {}
	return hit

func get_combined_leg_offset() -> Vector3:
	if not is_instance_valid(_torso):
		return Vector3.ZERO
	var combined_offset := Vector3.ZERO
	for leg: RigidBody3D in get_torso_movement_force_legs(is_fast_speed_active()):
		var rest_world_position := _get_leg_rest_world_position(leg)
		combined_offset += leg.global_position - rest_world_position
	return combined_offset

## Returns Legs currently allowed to transfer movement force into the Torso.
func get_torso_movement_force_legs(_fast_mode_active: bool = false) -> Array[RigidBody3D]:
	return _contact_drive_supports(get_leg_parts())

func has_torso_movement_force_support(fast_mode_active: bool = false) -> bool:
	return not get_torso_movement_force_legs(fast_mode_active).is_empty()

func get_fast_airborne_force_grace_remaining() -> float:
	# Kept for log/API compatibility. Airborne legs no longer provide contact drive.
	return 0.0

func _refresh_torso_force_support() -> Array[RigidBody3D]:
	var grounded_legs: Array[RigidBody3D] = []
	for leg: RigidBody3D in get_leg_parts():
		if is_leg_grounded(leg):
			grounded_legs.append(leg)
	if not grounded_legs.is_empty():
		_last_grounded_force_legs = grounded_legs.duplicate()
		_last_ground_support_time = _physics_elapsed
	return grounded_legs

func set_contact_force_request(force: Vector3) -> void:
	_contact_extra_force = force if force.is_finite() else Vector3.ZERO

func clear_contact_force_request() -> void:
	_contact_extra_force = Vector3.ZERO

func _reset_contact_drive_diagnostics() -> void:
	_contact_drive_frame = Engine.get_physics_frames()
	_contact_drive_rows.clear()
	_contact_drive_diagnostics = {"mode": "contact_velocity", "frame": _contact_drive_frame,
		"requested_force": Vector3.ZERO, "applied_force": Vector3.ZERO, "supports": 0,
		"extra_force": _contact_extra_force, "legs": _contact_drive_rows}

func get_contact_drive_diagnostics() -> Dictionary:
	var result := _contact_drive_diagnostics.duplicate(true)
	result["age_frames"] = Engine.get_physics_frames() - _contact_drive_frame
	result["unmet_force"] = Vector3(result.get("requested_force", Vector3.ZERO)) - Vector3(result.get("applied_force", Vector3.ZERO))
	result["enabled"] = torso_response_enabled
	return result

func _get_contact_drive_body(foot: RigidBody3D) -> RigidBody3D:
	return foot

func _contact_drive_supports(feet: Array) -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	if _adhesion_release_time_remaining > 0.0: return result
	for foot: RigidBody3D in feet:
		if not is_instance_valid(foot) or foot.freeze or _is_body_broken(foot) or is_leg_stepping(foot): continue
		if is_leg_grounded(foot): result.append(foot)
	return result

func _contact_velocity_force(velocity: Vector3, mass: float, up: Vector3) -> Vector3:
	var direction := get_input_movement_direction().slide(up) if input_enabled else Vector3.ZERO
	var target := direction.limit_length(1.0) * get_expected_horizontal_speed() * _walk_start_drive_scale()
	_contact_drive_diagnostics["target_velocity"] = target
	_contact_drive_diagnostics["actual_velocity"] = velocity.slide(up)
	return ((target - velocity.slide(up)) * _motion_setting("contact_gain", contact_velocity_gain)).limit_length(_motion_setting("contact_acceleration", contact_maximum_acceleration)) * mass

func calculate_torso_force() -> Vector3:
	if not torso_response_enabled or not is_instance_valid(_torso): return Vector3.ZERO
	if _adhesion_release_time_remaining > 0.0 or _contact_drive_supports(get_leg_parts()).is_empty(): return Vector3.ZERO
	var mass := 0.0
	for body: RigidBody3D in _character_body_cache:
		if is_instance_valid(body) and not _is_body_broken(body): mass += body.mass
	return (_contact_velocity_force(_torso.linear_velocity, maxf(mass, _torso.mass), Vector3.UP) + _contact_extra_force).limit_length(maximum_contact_drive_force)

## Allocate one region's demand to stance legs. No offset enters the demand calculation.
func _apply_contact_drive(feet: Array, requested: Vector3, carried_mass: float, up: Vector3) -> Vector3:
	if _contact_drive_frame != Engine.get_physics_frames(): _reset_contact_drive_diagnostics()
	var supports := _contact_drive_supports(feet)
	_contact_drive_diagnostics.requested_force += requested
	if supports.is_empty(): return Vector3.ZERO
	var applied := Vector3.ZERO
	var load := carried_mass * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)) / float(supports.size())
	for foot: RigidBody3D in supports:
		var driver := _get_contact_drive_body(foot)
		if not is_instance_valid(driver) or driver.freeze or _is_body_broken(driver): continue
		var hit := _get_surface_below_leg(foot, ground_probe_distance)
		if hit.is_empty(): continue
		var normal: Vector3 = Vector3(hit.normal).normalized()
		var share := requested / float(supports.size())
		var normal_force := clampf(share.dot(normal), -surface_adhesion_force, load * 2.0)
		var tangent_limit := load * contact_traction_coefficient
		var force := share.slide(normal).limit_length(tangent_limit) + normal * normal_force
		force = force.limit_length(maximum_contact_drive_force / float(supports.size()))
		driver.apply_central_force(force)
		applied += force
		var row: Dictionary = {}
		for existing: Dictionary in _contact_drive_rows:
			if existing.foot == foot.name: row = existing; break
		if row.is_empty():
			row = {"foot": foot.name, "driver": driver.name, "normal": normal,
				"requested": Vector3.ZERO, "applied": Vector3.ZERO, "limited": false,
				"traction_limit": tangent_limit, "carried_mass": carried_mass,
				"segment": int(foot.get_meta(&"body_segment_id", -1))}
			_contact_drive_rows.append(row)
		row.requested += share
		row.applied += force
		row.limited = row.limited or not force.is_equal_approx(share)
	_contact_drive_diagnostics.supports = _contact_drive_rows.size()
	_contact_drive_diagnostics.applied_force += applied
	return applied

func _begin_leg_motion(
	leg: RigidBody3D,
	target: Vector3,
	target_normal: Vector3 = Vector3.UP,
	input_direction: Vector3 = Vector3.ZERO
) -> void:
	_external_step_height = -1.0
	var starts_new_step := _step_state == StepState.IDLE or leg != _active_leg
	_active_leg = leg
	if not _active_steps.has(_current_step): _active_steps.append(_current_step)
	_current_step.extra["resource_step"] = _get_gait_data() != null
	_release_support_pin(leg)
	_active_movement_scale = _get_configured_movement_scale()
	_step_start = leg.global_position
	_step_target = target
	_step_target_normal = target_normal.normalized() if not target_normal.is_zero_approx() else Vector3.UP
	input_direction.y = 0.0
	if not input_direction.is_zero_approx():
		_active_step_input_direction = input_direction.normalized()
	elif starts_new_step:
		var target_direction := target - leg.global_position
		target_direction.y = 0.0
		_active_step_input_direction = (
			target_direction.normalized()
			if not target_direction.is_zero_approx()
			else Vector3.ZERO
		)
	_step_elapsed = 0.0
	_landing_elapsed = 0.0
	_grounded_confirmation_elapsed = 0.0
	_active_step_duration = maxf(get_current_step_duration(), MIN_STEP_TIME)
	if _get_gait_data() != null:
		_external_step_height = _get_gait_step_height()
		_current_step.extra["landing_tolerance"] = _motion_setting("landing_tolerance", _get_gait_data().landing_tolerance, leg)
		_current_step.extra["landing_timeout"] = _motion_setting("landing_timeout", _get_gait_data().landing_timeout, leg)
		_current_step.extra["automatic_profile"] = get_leg_motion_profile(leg).duplicate()
	_expand_hip_joint_for_step(leg, target)
	_step_state = StepState.MOVING
	_active_leg.sleeping = false
	if starts_new_step:
		if not input_direction.is_zero_approx(): _record_walk_start(leg)
		_last_shared_step_start = _physics_elapsed
		_last_replan_time = _physics_elapsed
		_step_sequence += 1
		_current_step.sequence = _step_sequence
		_log_gait_event(&"step_started", leg, &"", target - leg.global_position, target)
		if is_fast_speed_active() and not _turn_planning_active:
			_start_fast_float_lift()

func _update_active_step(delta: float) -> void:
	if not is_instance_valid(_active_leg):
		cancel_step(&"active_leg_invalid")
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
		if grounded and _is_step_target_reached(close_enough):
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
			and _accept_grounded_step_timeout()
		):
			_finish_current_step()
		if _step_state == StepState.LANDING and _landing_elapsed >= _get_effective_landing_timeout():
			_handle_step_timeout(grounded)

## Generated chains can require actual lift and arrival rather than contact alone.
func _is_step_target_reached(close_enough: bool) -> bool:
	return close_enough

func _accept_grounded_step_timeout() -> bool:
	return true

func _handle_step_timeout(grounded: bool) -> void:
	if grounded and _accept_grounded_step_timeout():
		_finish_current_step()
	else:
		cancel_step(&"landing_timeout_airborne")

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
	var effective_stiffness := _step_motion_setting("position_gain", leg_move_stiffness / maxf(_active_leg.mass, 0.001)) * _active_leg.mass * _active_movement_scale
	var effective_damping := _step_motion_setting("velocity_gain", leg_move_damping / maxf(_active_leg.mass, 0.001)) * _active_leg.mass * root_scale
	var effective_maximum_force := _step_motion_setting("step_acceleration", maximum_leg_force / maxf(_active_leg.mass, 0.001)) * _active_leg.mass * pow(_active_movement_scale, 1.5)
	var force := position_error * effective_stiffness + velocity_error * effective_damping
	if effective_maximum_force > 0.0:
		force = force.limit_length(effective_maximum_force)
	_active_leg.apply_central_force(force)

func _apply_fast_landing_assist(progress: float) -> void:
	if _automatic_motion_enabled(): return
	if (
		not fast_landing_assist_enabled
		or not is_fast_speed_active()
		or _turn_planning_active
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
	if _external_step_height >= 0.0:
		return _external_step_height
	if _get_gait_data() != null: return _get_gait_step_height()
	var base_height := fast_step_height if is_fast_speed_active() else step_height
	return minf(base_height * sqrt(_active_movement_scale), maximum_scaled_step_height)

func _get_effective_landing_tolerance() -> float:
	var tolerance := float(_current_step.extra.get("landing_tolerance", landing_tolerance)) * sqrt(_active_movement_scale)
	if is_fast_speed_active():
		tolerance *= fast_landing_tolerance_multiplier
	return tolerance

func _get_effective_landing_velocity_limit() -> float:
	if _automatic_motion_enabled(): return maxf(0.2, _step_motion_setting("stride", 0.2) / maxf(_active_step_duration, MIN_STEP_TIME) * 0.25)
	return landing_velocity_limit * _active_movement_scale

func _get_effective_landing_timeout() -> float:
	return maxf(float(_current_step.extra.get("landing_timeout", landing_timeout)) / sqrt(_active_movement_scale), minimum_scaled_landing_timeout)

func _finish_current_step() -> void:
	_log_gait_event(&"step_finished", _active_leg, &"grounded", _last_input_direction, _step_target)
	_record_touchdown()
	if not _legs.is_empty() and not _current_step.extra.get("resource_step", false):
		_next_leg_index = (_next_leg_index + 1) % _legs.size()
	cancel_step(&"completed")

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
	if _automatic_motion_enabled(): return
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
		or not has_torso_movement_force_support(true)
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
		_current_fast_lift_force = _apply_contact_drive(get_leg_parts(), Vector3.UP * lift_force, _torso.mass, Vector3.UP).dot(Vector3.UP)
	_fast_lift_time_remaining = maxf(_fast_lift_time_remaining - delta, 0.0)

func _has_enough_support(moving_leg: RigidBody3D) -> bool:
	if _legs.size() <= 1:
		return true
	var supported_count := 0
	for leg: RigidBody3D in _legs:
		if leg != moving_leg and not is_leg_stepping(leg) and is_leg_grounded(leg):
			supported_count += 1
	var required_count := maxi(1, ceili(float(_legs.size() - 1) * 0.5))
	if _get_gait_data() != null: required_count = _get_gait_data().minimum_support_feet
	return supported_count >= required_count

## Keeps the strict support rule in slow mode and optionally bypasses it in fast mode.
func _can_start_step_with_support(moving_leg: RigidBody3D) -> bool:
	if _get_gait_data() != null:
		return not is_leg_stepping(moving_leg) and _active_steps.size() < get_maximum_stepping_feet() and _has_enough_support(moving_leg)
	if fast_mode_ignores_leg_support and is_fast_speed_active():
		return true
	return _has_enough_support(moving_leg)

func _is_landing_point_valid(leg: RigidBody3D, current_foot: Vector3, hit: Dictionary) -> bool:
	if hit.is_empty():
		_last_landing_rejection_reason = &"landing_ray_missed"
		return false
	if not _surface_is_walkable(hit[&"normal"]):
		_last_landing_rejection_reason = &"slope_invalid"
		return false
	var ground_position: Vector3 = hit[&"position"]
	var height_difference := ground_position.y - current_foot.y
	if height_difference > maximum_step_up or height_difference < -maximum_step_down:
		_last_landing_rejection_reason = &"height_invalid"
		return false
	if is_instance_valid(_torso) and maximum_horizontal_leg_reach > 0.0:
		var horizontal_reach := ground_position - _torso.global_position
		horizontal_reach.y = 0.0
		if horizontal_reach.length() > maximum_horizontal_leg_reach:
			_last_landing_rejection_reason = &"horizontal_reach_exceeded"
			return false
	var body_target := _body_position_for_ground_contact(leg, ground_position)
	if not _has_leg_clearance(leg, body_target, hit.get(&"rid", RID())):
		_last_landing_rejection_reason = &"leg_clearance_blocked"
		return false
	_last_landing_rejection_reason = &""
	return true

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
	for overlap: Dictionary in _intersect_shape(query, 16):
		if overlap.get(&"rid", RID()) != landing_rid:
			return false
	return true

func _intersect_ray(query: PhysicsRayQueryParameters3D) -> Dictionary:
	if _performance_tracking_enabled:
		_performance_ray_queries += 1
	return _get_space_state().intersect_ray(query)

func _intersect_shape(query: PhysicsShapeQueryParameters3D, max_results: int) -> Array[Dictionary]:
	if _performance_tracking_enabled:
		_performance_shape_queries += 1
	return _get_space_state().intersect_shape(query, max_results)

func _body_position_for_ground_contact(leg: RigidBody3D, ground_position: Vector3) -> Vector3:
	return leg.global_position + ground_position - _get_foot_world_position(leg) + Vector3.UP * foot_ground_offset

func _get_foot_world_position(leg: RigidBody3D) -> Vector3:
	var collision := _find_leg_collision_shape(leg)
	if collision == null:
		return leg.global_position
	var box := collision.shape as BoxShape3D
	if collision.shape is ConvexPolygonShape3D:
		# Imported paper feet use an offset polygon, not a centered box.
		var points := (collision.shape as ConvexPolygonShape3D).points
		var lowest := INF
		for point: Vector3 in points:
			lowest = minf(lowest,(collision.global_transform * point).y)
		var sole := Vector3.ZERO
		var count := 0
		for point: Vector3 in points:
			var world_point := collision.global_transform * point
			if world_point.y <= lowest + 0.001:
				sole += world_point
				count += 1
		return sole / float(count) if count > 0 else collision.global_position
	if box == null:
		return collision.global_position
	return collision.global_transform * Vector3(0.0, -box.size.y * 0.5, 0.0)

func _find_leg_collision_shape(leg: RigidBody3D) -> CollisionShape3D:
	var cached := _leg_collision_shape_cache.get(leg) as CollisionShape3D
	if (
		is_instance_valid(cached)
		and cached.is_inside_tree()
		and not cached.disabled
		and cached.shape != null
	):
		return cached
	for node: Node in leg.find_children("*", "CollisionShape3D", true, false):
		var collision := node as CollisionShape3D
		if not collision.disabled and collision.shape != null:
			_leg_collision_shape_cache[leg] = collision
			return collision
	_leg_collision_shape_cache.erase(leg)
	return null

func _get_character_exclusion_rids() -> Array[RID]:
	if _physics_query_cache_dirty or _character_exclusion_rids.is_empty():
		_rebuild_character_exclusion_rids()
	return _character_exclusion_rids

func _rebuild_character_exclusion_rids() -> void:
	_body_cache_dirty = false
	_torso_cache_frame = -1
	_torso_parts_cache.clear()
	_movement_perf.count(&"body_cache_rebuilds")
	_character_exclusion_rids.clear()
	_character_body_cache.clear()
	var parts_root := get_node_or_null(parts_root_path)
	_body_cache_root = parts_root
	if parts_root == null:
		return
	if not parts_root.child_entered_tree.is_connected(_on_parts_tree_changed):
		parts_root.child_entered_tree.connect(_on_parts_tree_changed)
	if not parts_root.child_exiting_tree.is_connected(_on_parts_tree_changed):
		parts_root.child_exiting_tree.connect(_on_parts_tree_changed)
	for node: Node in parts_root.find_children("*", "CollisionObject3D", true, false):
		_character_exclusion_rids.append((node as CollisionObject3D).get_rid())
		if node is RigidBody3D:
			_character_body_cache.append(node as RigidBody3D)

func refresh_physics_query_cache() -> void:
	_reset_walk_start_stagger(&"structure_changed")
	release_all_support_pins()
	_refresh_physics_query_cache()

func _refresh_physics_query_cache() -> void:
	_physics_query_cache_dirty = false
	_leg_collision_shape_cache.clear()
	_ground_probe_cache.clear()
	_refresh_leg_order()
	_rebuild_character_exclusion_rids()

func _on_parts_tree_changed(_node: Node) -> void:
	_physics_query_cache_dirty = true
	_body_cache_dirty = true
	_torso_cache_frame = -1

func _get_space_state() -> PhysicsDirectSpaceState3D:
	var parts_root := get_node_or_null(parts_root_path) as Node3D
	if parts_root == null:
		return null
	return parts_root.get_world_3d().direct_space_state

func _refresh_leg_order() -> void:
	_legs = _discover_leg_parts()
	_legs.sort_custom(func(a: RigidBody3D, b: RigidBody3D) -> bool:
		if not is_equal_approx(a.global_position.x, b.global_position.x):
			return a.global_position.x < b.global_position.x
		return String(a.get_path()) < String(b.get_path())
	)
	_next_leg_index = 0

func _remove_invalid_legs() -> void:
	for index: int in range(_legs.size() - 1, -1, -1):
		if not is_instance_valid(_legs[index]) or _is_body_broken(_legs[index]):
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

var _hip_reference_frames: Dictionary = {}

func _capture_hip_joint_limits() -> void:
	_hip_joints_by_leg.clear()
	_hip_reference_frames.clear()
	_hip_joint_base_limits.clear()
	var parts_root := get_node_or_null(parts_root_path)
	if parts_root == null:
		return
	for node: Node in parts_root.find_children("*", "Generic6DOFJoint3D", true, false):
		var joint := node as Generic6DOFJoint3D
		var body_b := joint.get_node_or_null(joint.node_b) as RigidBody3D
		if not is_instance_valid(body_b) or not _has_leg_tag(body_b):
			continue
		_hip_joints_by_leg[body_b] = joint
		var body_a := joint.get_node_or_null(joint.node_a) as RigidBody3D
		if is_instance_valid(body_a):
			_hip_reference_frames[joint] = {"a": body_a.to_local(joint.global_position), "b": body_b.to_local(joint.global_position), "basis_a": body_a.global_basis.inverse() * joint.global_basis}
		_hip_joint_base_limits[joint] = Vector4(
			joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT),
			joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT),
			joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT),
			joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
		)

## Read-only diagnostics. Submitted forces are not measured solver reaction forces.
func get_npc_motion_execution_diagnostics() -> Dictionary:
	var rows: Array[Dictionary] = []
	for foot: RigidBody3D in get_leg_parts():
		if not is_instance_valid(foot): continue
		var driver := _get_contact_drive_body(foot)
		var row := {"foot": foot.name, "driver": driver.name if is_instance_valid(driver) else &"none",
			"stepping": is_leg_stepping(foot), "grounded": is_leg_grounded(foot),
			"foot_position": foot.global_position, "foot_velocity": foot.linear_velocity,
			"driver_is_torso": driver == _torso, "pin_active": _support_pins.has(foot)}
		if is_instance_valid(driver):
			row.driver_frozen = driver.freeze
			row.driver_linear_locks = Vector3i(int(driver.axis_lock_linear_x), int(driver.axis_lock_linear_y), int(driver.axis_lock_linear_z))
		if _support_pins.has(foot):
			var pin := _support_pins[foot].joint as Generic6DOFJoint3D
			if is_instance_valid(pin):
				row.pin_basis = pin.global_basis
				row.pin_linear_locks = Vector3i(int(pin.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)), int(pin.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)), int(pin.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)))
		var joint := _hip_joints_by_leg.get(foot) as Generic6DOFJoint3D
		if is_instance_valid(joint) and _hip_reference_frames.has(joint):
			var a := joint.get_node_or_null(joint.node_a) as RigidBody3D
			var ref: Dictionary = _hip_reference_frames[joint]
			if is_instance_valid(a):
				var frame: Basis = a.global_basis * ref.basis_a
				row.hip_anchor_offset = frame.inverse() * (foot.to_global(ref.b) - a.to_global(ref.a))
				row.hip_joint = joint.name
				row.hip_limits_xz = _get_current_hip_limits(foot)
				row.hip_limits_y = Vector2(joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT), joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT))
				row.hip_spring_z = Vector2(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS), joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING))
		rows.append(row)
	return {"frame": Engine.get_physics_frames(), "input": get_last_input_direction(),
		"contact_gain": _motion_setting("contact_gain", contact_velocity_gain), "acceleration_cap": _motion_setting("contact_acceleration", contact_maximum_acceleration),
		"force_meaning": "submitted_to_body_not_measured_solver_force", "legs": rows}

func _expand_hip_joint_for_step(leg: RigidBody3D, target: Vector3) -> void:
	if (
		not auto_expand_hip_limits
		or (is_fast_speed_active() and not expand_hip_limits_in_fast_mode)
	):
		return
	var joint := _hip_joints_by_leg.get(leg) as Generic6DOFJoint3D
	if not is_instance_valid(joint) or not _hip_joint_base_limits.has(joint):
		return
	var base_limits: Vector4 = _hip_joint_base_limits[joint]
	var world_step := target - leg.global_position
	world_step.y = 0.0
	var local_step := joint.global_basis.inverse() * world_step
	var x_extent := maxf(absf(base_limits.x), absf(base_limits.y))
	var z_extent := maxf(absf(base_limits.z), absf(base_limits.w))
	if absf(local_step.x) > 0.0001:
		x_extent = maxf(
			x_extent,
			minf(
				x_extent + absf(local_step.x) * hip_limit_stride_ratio + hip_limit_margin,
				maximum_dynamic_hip_limit
			)
		)
	if absf(local_step.z) > 0.0001:
		z_extent = maxf(
			z_extent,
			minf(
				z_extent + absf(local_step.z) * hip_limit_stride_ratio + hip_limit_margin,
				maximum_dynamic_hip_limit
			)
		)
	joint.set_param_x(
		Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,
		minf(base_limits.x, -x_extent)
	)
	joint.set_param_x(
		Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,
		maxf(base_limits.y, x_extent)
	)
	joint.set_param_z(
		Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,
		minf(base_limits.z, -z_extent)
	)
	joint.set_param_z(
		Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,
		maxf(base_limits.w, z_extent)
	)

## Restores the authored limits. Call only when every Leg is already inside those limits.
func restore_base_hip_joint_limits() -> void:
	for joint: Generic6DOFJoint3D in _hip_joint_base_limits:
		if not is_instance_valid(joint):
			continue
		var limits: Vector4 = _hip_joint_base_limits[joint]
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, limits.x)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, limits.y)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, limits.z)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, limits.w)

func _update_joint_spring_scale(delta: float) -> void:
	if not scale_joint_angular_springs or _joint_base_springs.is_empty():
		return
	var target_scale := _get_configured_movement_scale()
	if is_equal_approx(_joint_spring_scale, target_scale):
		return
	var weight := clampf(delta / maxf(joint_scale_transition_duration, 0.001), 0.0, 1.0)
	var next_scale := lerpf(_joint_spring_scale, target_scale, weight)
	if absf(next_scale - target_scale) <= 0.001:
		next_scale = target_scale
	if is_equal_approx(next_scale, _joint_spring_scale):
		return
	_joint_spring_scale = next_scale
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
	if not torso_response_enabled or not is_instance_valid(_torso): return
	var mass := 0.0
	for body: RigidBody3D in _character_body_cache:
		if is_instance_valid(body) and not _is_body_broken(body): mass += body.mass
	mass = maxf(mass, _torso.mass)
	var requested := (_contact_velocity_force(_torso.linear_velocity, mass, Vector3.UP) + _contact_extra_force).limit_length(maximum_contact_drive_force)
	_contact_drive_diagnostics["target_velocity"] = (get_input_movement_direction() if input_enabled else Vector3.ZERO).limit_length(1.0) * get_expected_horizontal_speed()
	_apply_contact_drive(get_leg_parts(), requested, mass, Vector3.UP)

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
	if not is_instance_valid(_facing_controller):
		_facing_controller = get_parent().get_node_or_null("PhysicalFacingController3D")
	if is_instance_valid(_facing_controller) and not _turn_planning_active:
		var correction: float = _facing_controller.call("get_walking_heading_correction")
		rest_position = _torso.global_position + (rest_position - _torso.global_position).rotated(Vector3.UP, correction)
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
	if _automatic_motion_enabled():
		var speed := _get_gait_data().target_speed
		for leg: RigidBody3D in _legs: speed = minf(speed, float(get_leg_motion_profile(leg).reachable_speed))
		return speed
	if _get_gait_data() != null: return _get_gait_step_distance() * get_planned_step_frequency()
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
	if not is_instance_valid(body): return false
	_movement_perf.count(&"tag_checks")
	if body is PhysicalBodyPart3D:
		return required_tag in (body as PhysicalBodyPart3D).tags
	# Compatibility for custom RigidBody3D parts; Object.get returns null when tags is absent.
	var tags: Variant = body.get(&"tags")
	return tags is Array and required_tag in tags

func _is_body_broken(body: RigidBody3D) -> bool:
	return body is PhysicalBodyPart3D and (body as PhysicalBodyPart3D).is_broken

func set_control_performance_tracking_enabled(enabled: bool) -> void:
	_movement_perf.set_enabled(enabled)

func consume_control_performance_stats() -> Dictionary:
	return _movement_perf.consume()

func _walk_start_stagger_ready() -> bool:
	return input_enabled and _adhesion_release_time_remaining <= 0.0

func _walk_start_leg_available(leg: RigidBody3D) -> bool:
	return is_instance_valid(leg) and not leg.is_queued_for_deletion() and not leg.freeze and not _is_body_broken(leg)

func _walk_start_priority(leg: RigidBody3D, direction: Vector3) -> float:
	return (leg.global_position-_torso.global_position).dot(direction) if is_instance_valid(_torso) else 0.0

func _walk_start_emergency(leg: RigidBody3D) -> bool:
	if not is_instance_valid(_torso) or not is_instance_valid(leg) or maximum_horizontal_leg_reach<=0.0: return false
	var relative := (leg.global_position-_torso.global_position).slide(Vector3.UP)
	var approach := (_torso.linear_velocity-leg.linear_velocity).dot(_walk_start_direction)
	return approach>0.05 and relative.dot(_walk_start_direction)<0.0 and relative.length()>=maximum_horizontal_leg_reach*0.95

func _reset_walk_start_stagger(reason: StringName = &"idle") -> void:
	_walk_start_pending.clear()
	_walk_start_due.clear()
	_walk_start_input_active = false
	_walk_start_stop_elapsed = 0.0
	_walk_start_last_start = -INF
	_walk_start_last_frame = -1
	_walk_start_status = reason

func _sort_walk_start_pending(direction: Vector3) -> void:
	_walk_start_pending.sort_custom(func(a,b):
		var difference := _walk_start_priority(a,direction)-_walk_start_priority(b,direction)
		return difference<0.0 if absf(difference)>0.001 else str(a.name)<str(b.name))
	# Keep urgency first, but alternate equally urgent sides of the support center.
	var center := Vector3.ZERO
	for leg: RigidBody3D in _walk_start_pending: center += leg.global_position
	center /= maxf(_walk_start_pending.size(),1)
	var side_axis := direction.cross(Vector3.UP)
	for index: int in range(1,_walk_start_pending.size()):
		var previous := _walk_start_pending[index-1]
		var next := _walk_start_pending[index]
		if (previous.global_position-center).dot(side_axis)*(next.global_position-center).dot(side_axis)<=0.0: continue
		for candidate: int in range(index+1,_walk_start_pending.size()):
			var other := _walk_start_pending[candidate]
			if absf(_walk_start_priority(other,direction)-_walk_start_priority(next,direction))>0.001: break
			if (previous.global_position-center).dot(side_axis)*(other.global_position-center).dot(side_axis)<0.0:
				_walk_start_pending[index] = other
				_walk_start_pending[candidate] = next
				break

func _schedule_walk_start_pending() -> void:
	_walk_start_due.clear()
	for index: int in range(_walk_start_pending.size()):
		_walk_start_due[_walk_start_pending[index]] = _walk_start_last_start+(index+1)*_walk_start_interval if is_finite(_walk_start_last_start) else _physics_elapsed

func _update_walk_start_stagger(delta: float, direction: Vector3) -> void:
	if not walk_start_stagger_enabled or not _walk_start_stagger_ready():
		_reset_walk_start_stagger(&"disabled_or_suspended")
		return
	var old_count := _walk_start_pending.size()
	_walk_start_pending = _walk_start_pending.filter(func(leg): return _walk_start_leg_available(leg) and _legs.has(leg))
	if old_count != _walk_start_pending.size(): _schedule_walk_start_pending()
	var speed := _torso.linear_velocity.slide(Vector3.UP).length() if is_instance_valid(_torso) else 0.0
	if direction.is_zero_approx():
		_walk_start_stop_elapsed = _walk_start_stop_elapsed+delta if speed<=walk_start_stop_speed else 0.0
		if _walk_start_stop_elapsed>=walk_start_stop_confirmation: _reset_walk_start_stagger()
		return
	_walk_start_stop_elapsed = 0.0
	var travel := direction.slide(Vector3.UP).normalized()
	if not _walk_start_input_active:
		_walk_start_input_active = true
		_walk_start_direction = travel
		_walk_start_bypasses = 0
		if speed>walk_start_speed_threshold:
			_walk_start_status = &"already_moving"
			return
		for leg: RigidBody3D in _legs:
			if _walk_start_leg_available(leg) and not is_leg_stepping(leg): _walk_start_pending.append(leg)
		_walk_start_interval = clampf(walk_start_interval_ratio/maxf(get_planned_step_frequency(),0.01),0.01,maxf(walk_start_maximum_interval,0.01))
		_sort_walk_start_pending(travel)
		_schedule_walk_start_pending()
		_next_resource_step_time = _physics_elapsed
		_next_fast_step_start_time = _physics_elapsed
		if _active_steps.is_empty(): _automatic_next_steps.clear()
		_walk_start_status = &"staggering"
		if not _walk_start_pending.is_empty(): _next_leg_index = _legs.find(_walk_start_pending[0])
	elif not _walk_start_pending.is_empty() and travel.dot(_walk_start_direction)<0.5:
		# Reorder only unstarted legs; keep all running swings and elapsed eligibility.
		_walk_start_direction = travel
		_sort_walk_start_pending(travel)
		_schedule_walk_start_pending()
	if _walk_start_pending.is_empty(): _walk_start_status = &"complete"

func _walk_start_stagger_allows(leg: RigidBody3D) -> bool:
	if not walk_start_stagger_enabled: return true
	# At most one launch in a frame during startup, including emergency overrides.
	if _walk_start_last_frame == Engine.get_physics_frames(): return false
	if not _walk_start_pending.has(leg): return true
	if _walk_start_emergency(leg): return true
	return _physics_elapsed>=float(_walk_start_due.get(leg,_physics_elapsed))

func _record_walk_start(leg: RigidBody3D) -> void:
	if not _walk_start_pending.has(leg): return
	if _walk_start_emergency(leg) and _physics_elapsed<float(_walk_start_due.get(leg,_physics_elapsed)): _walk_start_bypasses += 1
	_walk_start_pending.erase(leg)
	_walk_start_last_start = _physics_elapsed
	_walk_start_last_frame = Engine.get_physics_frames()
	_schedule_walk_start_pending()
	_walk_start_status = &"complete" if _walk_start_pending.is_empty() else &"staggering"

func _walk_start_drive_scale() -> float:
	# Reduce only commanded walking speed, never static support or zero-input braking.
	for leg: RigidBody3D in _walk_start_pending:
		if _walk_start_leg_available(leg) and _walk_start_emergency(leg) and not _can_start_step_with_support(leg): return 0.35
	return 1.0

func get_walk_start_stagger_diagnostics() -> Dictionary:
	var pending: Array[Dictionary] = []
	for leg: RigidBody3D in _walk_start_pending:
		if not is_instance_valid(leg): continue
		pending.append({"foot":str(leg.name),"remaining_delay":maxf(float(_walk_start_due.get(leg,_physics_elapsed))-_physics_elapsed,0.0),"emergency":_walk_start_emergency(leg)})
	return {"enabled":walk_start_stagger_enabled,"status":_walk_start_status,"interval":_walk_start_interval,"direction":_walk_start_direction,"stop_elapsed":_walk_start_stop_elapsed,"emergency_bypasses":_walk_start_bypasses,"pending":pending}
