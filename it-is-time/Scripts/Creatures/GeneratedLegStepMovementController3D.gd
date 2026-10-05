extends "res://Scripts/Creatures/LegStepMovementControllerBase3D.gd"

const FORELEG_TAG: int = 4
const LEG_LIMB_TAG: int = 5
const SUB_TORSO_TAG: int = 6

var simplified_physics_mode: bool = false
@export_group("Zero Gravity Pose")
@export_range(0.0, 50.0, 0.1) var simple_pose_strength: float = 8.0
@export_range(0.0, 30.0, 0.1) var simple_pose_damping: float = 6.0
@export_range(0.0, 100.0, 0.1) var simple_pose_acceleration_limit: float = 20.0
@export_range(0.0, 10000.0, 1.0) var simple_pose_torque_limit: float = 500.0

@export_group("Planar Movement")
## Independent physical stepping; no inter-part Joint3D transmits force.
@export_range(0.0, 2.0, 0.01) var planar_step_height: float = 0.15
@export_range(0.0, 2.0, 0.01) var planar_step_stride: float = 0.25
@export_range(0.1, 10.0, 0.1) var planar_step_frequency: float = 2.0
@export_range(0.01, 5.0, 0.01) var planar_ground_tolerance: float = 0.3
@export_range(0.0, 200.0, 0.1) var planar_support_gain: float = 80.0
@export_range(0.0, 100.0, 0.1) var planar_support_damping: float = 18.0
@export_range(0.0, 100.0, 0.1) var planar_move_gain: float = 12.0
@export_range(0.0, 200.0, 0.1) var planar_pose_gain: float = 40.0
@export_range(0.0, 200.0, 0.1) var planar_balance_gain: float = 60.0
@export_range(0.0, 100.0, 0.1) var planar_balance_damping: float = 15.0
@export_range(1.0, 500.0, 0.1) var planar_maximum_acceleration: float = 100.0
@export_range(1.0, 100000.0, 1.0) var planar_maximum_torque: float = 5000.0

@export_group("Generated Player Input")
@export var right_action: StringName = &"Right"
@export var left_action: StringName = &"Left"
@export var up_action: StringName = &"Up"
@export var down_action: StringName = &"Down"
@export var burst_action: StringName = &"Space"
@export var forelegs_participate_in_walking: bool = true

@export_group("Generated Gait")
## Derives stride, lift and probe range from the shortest attached limb chain.
@export var auto_size_gait: bool = true
@export_range(0.01, 0.5, 0.01) var stride_length_ratio: float = 0.12
@export_range(0.01, 0.5, 0.01) var lift_length_ratio: float = 0.1
## Leaves a little slack in the straight-line reach test. This is not a full IK solver.
@export_range(0.8, 1.0, 0.005) var chain_reach_ratio: float = 0.995
@export_range(0.0, 90.0, 0.5) var walking_joint_angular_limit_degrees: float = 60.0
## Normalizes feedback by foot count, then scales by total living Torso mass.
@export var scale_response_by_torso_mass: bool = true
@export_range(0.01, 100.0, 0.01, "or_greater") var response_reference_mass: float = 1.0
## Preserve the configured cap for light bodies, but give heavy Torso assemblies
## enough feedback force to oppose their weight. This does not alter ground gating.
@export var mass_scaled_torso_force_limit: bool = true
@export_range(1.0, 3.0, 0.05) var torso_force_weight_margin: float = 1.5
@export_range(0.0, 100000.0, 1.0, "or_greater") var maximum_mass_scaled_torso_force: float = 20000.0
@export_range(0.0, 30.0, 0.1) var torso_vertical_response_damping: float = 6.0

@export_group("Generated Vertical Feedback")
@export_range(0.0, 100.0, 0.1) var vertical_response_gain: float = 12.0
@export_range(0.0, 2.0, 0.05) var vertical_response_damping_ratio: float = 1.0
@export_range(0.0, 2.0, 0.05) var upward_response_weight_limit: float = 1.0
@export_range(0.0, 2.0, 0.05) var downward_response_weight_limit: float = 0.25

@export_group("SubTorso Support")
@export var sub_torso_support_enabled: bool = true
@export_range(0.0, 1.0, 0.05) var sub_torso_weight_share: float = 0.5
@export_range(0.0, 100.0, 0.1) var sub_torso_height_gain: float = 12.0
@export_range(0.0, 2.0, 0.05) var sub_torso_damping_ratio: float = 1.0
@export_range(0.0, 2.0, 0.05) var sub_torso_maximum_weight_share: float = 1.2
@export_range(0.0, 1.0, 0.01) var sub_torso_force_smoothing_time: float = 0.15
@export_range(0.0, 1.0, 0.01) var sub_torso_support_ramp_time: float = 0.2
## Keep some downward load on the feet even while correcting body height.
@export_range(0.0, 0.95, 0.05) var auxiliary_support_weight_limit: float = 0.85
@export_range(0.8, 1.0, 0.005) var standing_chain_reach_ratio: float = 0.98
@export_group("Grounded Movement Feedback")
@export_range(0.0, 30.0, 0.1) var maximum_grounded_drive_acceleration: float = 4.0
@export var grounded_directional_feedback: bool = true
@export_range(0.0, 1.0, 0.05) var unbalanced_movement_multiplier: float = 0.25

@export_group("Generated Ground Contact")
## Sole clearance hysteresis; the broad ray range is only for finding terrain.
@export_range(0.001, 0.5, 0.001) var support_contact_enter_distance: float = 0.03
@export_range(0.001, 0.5, 0.001) var support_contact_exit_distance: float = 0.08
@export_range(0.0, 1.0, 0.01) var support_load_smoothing_time: float = 0.15
var _contact_states: Dictionary = {}

@export_group("Generated Foot Heading")
## Feet face the measured torso +X heading, independently of movement input.
## Correct yaw with torque, then lock it; turning/recovery/broken chains release the lock.
@export var foot_heading_lock_enabled: bool = true
@export_range(0.05, 5.0, 0.05) var foot_heading_lock_tolerance_degrees: float = 0.5
@export_range(0.1, 10.0, 0.1) var foot_heading_unlock_tolerance_degrees: float = 2.0
@export_range(0.0, 500.0, 0.1) var foot_heading_strength: float = 60.0
@export_range(0.0, 100.0, 0.1) var foot_heading_damping: float = 16.0
@export_range(0.0, 500.0, 0.1) var foot_heading_maximum_acceleration: float = 120.0
@export_range(0.0, 100000.0, 1.0) var foot_heading_maximum_torque: float = 2000.0
var _foot_heading_previous_locks: Dictionary = {}
var _foot_heading_diagnostics: Dictionary = {}

@export_group("Generated Step Drive")
## PD gains are acceleration gains; effective mass includes the foot and distal limb chain.
@export var mass_scaled_step_drive: bool = true
@export_range(0.0, 1.0, 0.05) var stepping_chain_mass_ratio: float = 0.35
@export_range(0.0, 500.0, 0.1) var step_position_gain: float = 60.0
@export_range(0.0, 100.0, 0.1) var step_velocity_gain: float = 14.0
@export_range(0.0, 500.0, 0.1) var maximum_step_acceleration: float = 100.0
@export_range(0.0, 100000.0, 1.0) var maximum_mass_scaled_step_force: float = 5000.0
@export var step_gravity_compensation: bool = true
## Actual sole clearance, not the broad ground-probe distance used by adhesion.
@export_range(0.001, 1.0, 0.001) var minimum_step_lift_clearance: float = 0.02

var _tracking_force: Vector3:
	get: return _current_step.extra.get("_tracking_force", Vector3.ZERO)
	set(value): _current_step.extra["_tracking_force"] = value
var _tracking_gravity_force: Vector3:
	get: return _current_step.extra.get("_tracking_gravity_force", Vector3.ZERO)
	set(value): _current_step.extra["_tracking_gravity_force"] = value
var _tracking_mass: float:
	get: return _current_step.extra.get("_tracking_mass", 0.0)
	set(value): _current_step.extra["_tracking_mass"] = value
var _tracking_force_limit: float:
	get: return _current_step.extra.get("_tracking_force_limit", 0.0)
	set(value): _current_step.extra["_tracking_force_limit"] = value
var _tracking_force_limited: bool:
	get: return _current_step.extra.get("_tracking_force_limited", false)
	set(value): _current_step.extra["_tracking_force_limited"] = value
var _tracking_position_error: Vector3:
	get: return _current_step.extra.get("_tracking_position_error", Vector3.ZERO)
	set(value): _current_step.extra["_tracking_position_error"] = value
var _step_has_lifted: bool:
	get: return _current_step.extra.get("_step_has_lifted", false)
	set(value): _current_step.extra["_step_has_lifted"] = value
var _step_start_clearance: float:
	get: return _current_step.extra.get("_step_start_clearance", 0.0)
	set(value): _current_step.extra["_step_start_clearance"] = value
var _failed_step_count: int = 0
var _last_step_failure: StringName = &""

@export_group("Generated Foot Adhesion")
@export_range(0.0, 200.0, 0.1) var foot_adhesion_strength: float = 40.0
@export_range(0.0, 50.0, 0.1) var foot_adhesion_damping: float = 8.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var maximum_foot_adhesion_force: float = 400.0
@export var align_support_feet_to_surface: bool = true
@export_range(0.0, 200.0, 0.1) var foot_alignment_strength: float = 20.0
@export_range(0.0, 50.0, 0.1) var foot_alignment_damping: float = 8.0
@export_range(0.0, 500.0, 0.1) var maximum_foot_alignment_acceleration: float = 60.0
@export_range(0.0, 5000.0, 1.0, "or_greater") var maximum_foot_alignment_torque: float = 150.0

@export_group("Generated Balance")
## Generated bodies have no separate TorsoBalanceController. Apply tilt stabilization without yaw steering.
@export var stabilize_torso_tilt: bool = true
@export_range(0.0, 500.0, 0.1, "or_greater") var tilt_strength: float = 25.0
@export_range(0.0, 100.0, 0.1, "or_greater") var tilt_damping: float = 6.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var maximum_tilt_acceleration: float = 80.0

@export_group("Segment Layout")
@export var segment_layout_enabled: bool = true
@export_range(0.1, 5.0, 0.05) var segment_layout_frequency: float = 1.0
@export_range(0.0, 2.0, 0.05) var segment_layout_damping_ratio: float = 1.0
@export_range(0.0, 100.0, 0.1) var segment_layout_maximum_acceleration: float = 12.0
@export_range(1.0, 180.0, 1.0) var segment_layout_turn_speed_degrees: float = 45.0
@export_range(0.0, 90.0, 1.0) var segment_layout_heading_lead_degrees: float = 12.0
@export var segment_layout_turn_steps_enabled: bool = true
@export_range(1.0, 30.0, 0.5) var segment_layout_heading_tolerance_degrees: float = 10.0
@export_range(1.0, 45.0, 1.0) var segment_layout_step_angle_degrees: float = 10.0
@export_range(0.0, 30.0, 0.1) var turn_leg_traction_gain: float = 8.0
@export_range(0.0, 20.0, 0.1) var turn_leg_traction_damping: float = 4.0
@export_range(0.0, 20.0, 0.1) var turn_leg_traction_maximum_acceleration: float = 4.0
@export_range(0.0, 30.0, 0.1) var turn_leg_yaw_gain: float = 16.0
@export_range(0.0, 20.0, 0.1) var turn_leg_yaw_damping: float = 5.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var turn_leg_yaw_torque_limit: float = 1500.0
@export_range(0.0, 20.0, 0.1) var turn_leg_yaw_maximum_acceleration: float = 8.0
@export_range(0.1, 1.0, 0.05) var turn_minimum_grounded_ratio: float = 0.5
var _turn_leg_forces: Dictionary = {}
var _speed_plan_frame: int = -1
var _speed_plan_cache: Dictionary = {}
var _landing_time_estimates: Dictionary = {}
var _extension_start_times: Array[float] = []
var _extension_rearm: Dictionary = {}
var _extension_admission: Dictionary = {}
var _gallop_reach_released: Dictionary = {}
var _planar_slide_integral: float = 0.0
var _planar_slide_frame: int = -1
var _planar_slide_last_target: float = 0.0
var _planar_slide_diagnostics: Dictionary = {}
var _speed_smoothed_velocity: Vector3 = Vector3.ZERO
var _speed_velocity_frame: int = -1
var _gallop_contacts: Dictionary = {}
var _gallop_launch_time: float = -1000.0
var _gallop_landed_feet: Dictionary = {}
var _gallop_updating_group: bool = false
var _gallop_starting_batch: bool = false
var _gallop_group_scheduler_active: bool = false
var _gallop_next_group_time: float = 0.0
var _gallop_group_sequence: int = 0
var _gallop_next_takeoff: float = 0.0
var _gallop_pin_release_until: float = 0.0
var _gallop_takeoffs: int = 0
var _gallop_diagnostics: Dictionary = {}
var _turn_drive_diagnostics: Dictionary = {}
var _turn_landing_rejections: Dictionary = {}
@export_range(0.1, 2.0, 0.05) var segment_layout_step_duration: float = 0.4
@export_range(1.0, 60.0, 1.0) var segment_layout_turn_timeout: float = 30.0
var _layout_turn_elapsed: float = 0.0
var _layout_turn_stagnant: float = 0.0
var _layout_turn_best_error: float = INF
var _layout_turn_goal_yaw: float = 0.0
var _layout_turn_retry: float = 0.0
var _layout_turn_status: StringName = &"idle"
var _layout_turn_owned: bool = false
var _layout_turn_cursor: int = 0
var _layout_turn_target := Vector3.ZERO
var _segment_layout_yaw: float = 0.0
var _segment_layout_initialized: bool = false

@export_group("Segment Balance")
@export var segment_balance_enabled: bool = true
## Restore pitch as well as damping it; central-force springs do not constrain orientation.
@export_range(0.0, 500.0, 0.1) var segment_z_balance_strength: float = 300.0
@export_range(0.0, 100.0, 0.1) var segment_z_angular_damping: float = 40.0
@export_range(0.0, 500.0, 0.1) var segment_x_balance_strength: float = 80.0
@export_range(0.0, 500.0, 0.1) var segment_y_balance_strength: float = 80.0
@export_range(0.0, 2.0, 0.05) var segment_balance_damping_ratio: float = 1.0
@export_range(0.0, 500.0, 0.1) var segment_balance_acceleration_limit: float = 400.0
@export_range(0.0, 100000.0, 1.0) var segment_balance_torque_limit: float = 30000.0
@export_range(1.0, 720.0, 1.0) var segment_heading_speed_degrees: float = 180.0
var _segment_target_yaw: float = 0.0
var _segment_goal_yaw: float = 0.0
var _segment_heading_initialized: bool = false

@export_group("Generated Stance Stability")
## Restores the generated relative joint pose only on grounded, non-stepping chains.
@export var stabilize_stance_limbs: bool = true
## One contact per chain; intermediate blocks never become independent stepping feet.
@export var leg_limbs_can_support: bool = true
@export_range(0.0, 500.0, 0.1, "or_greater") var stance_strength: float = 16.0
@export_range(0.0, 100.0, 0.1, "or_greater") var stance_damping: float = 6.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var maximum_stance_acceleration: float = 400.0
## Final torque cap per joint, after accounting for both bodies' inertia.
@export_range(0.0, 10000.0, 0.1, "or_greater") var maximum_stance_torque: float = 10000.0
@export_range(0.0, 2.0, 0.01) var stance_recovery_duration: float = 0.2

@export_group("Automatic Stance Allocation")
@export var auto_allocate_stance_torque: bool = true
@export_range(0.5, 30.0, 0.1) var stance_allowed_deformation_degrees: float = 5.0
@export_range(0.0, 2.0, 0.01) var stance_damping_ratio: float = 1.0
@export_range(1.0, 5.0, 0.05) var stance_load_safety_factor: float = 1.5
@export_range(0.0, 1000.0, 0.1, "or_greater") var minimum_stance_torque: float = 5.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var stance_dynamic_torque_reserve: float = 100.0
## Keep allocation away from the angular servo's per-frame update cost.
@export_range(0.02, 1.0, 0.01) var stance_allocation_interval: float = 0.1
## World-space COM projection error above which support is considered unbalanced.
@export_range(0.01, 10.0, 0.01, "or_greater") var stance_balance_tolerance: float = 0.25
## Retain at least a quarter of allocated load even in older scenes storing zero.
@export_range(0.25, 1.0, 0.05) var unbalanced_stance_multiplier: float = 1.0

var _stance_support_weights: Dictionary = {}
var _stance_joint_loads: Dictionary = {}
var _stance_allocation_elapsed: float = 0.0
var _stance_support_signature: Array[int] = []
var _stance_total_mass: float = 0.0
var _stance_center_of_mass: Vector3 = Vector3.ZERO
var _stance_balance_error: float = 0.0
var _stance_support_balanced: bool = false
var _last_torso_response_force: Vector3 = Vector3.ZERO
var _segments: Dictionary = {}
var _segment_links: Array[Dictionary] = []
var _last_auxiliary_support_force: Vector3 = Vector3.ZERO
var _support_delta: float = 1.0 / 60.0
var _stance_last_applied_frame: int = -1
var _stance_last_allocation_frame: int = -1

var _foot_alignment_torques: Dictionary = {}

var recovery_control_active: bool = false

var _chains: Dictionary = {}
var _chains_ready: bool = false
var _generated_diagnostic_elapsed: float = 0.0

func _ready() -> void:
	parts_root_path = NodePath("../GeneratedParts")
	auto_expand_hip_limits = false
	scale_joint_angular_springs = false
	directional_projection_correction_enabled = false
	super._ready()
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	if console != null and console.has_method("is_generated_motion_tracking_enabled") and console.call("is_generated_motion_tracking_enabled"):
		set_diagnostic_logging_enabled(true)
	refresh_physics_query_cache()

func _planar_mode_active() -> bool:
	var actor := get_parent()
	return actor != null and actor.has_method("is_planar_mode_active") and actor.is_planar_mode_active()

func _support_pin_z_free() -> bool:
	return _planar_mode_active()

func prepare_planar_mode_change() -> void:
	_reset_planar_slide_control()
	cancel_step(&"planar_mode_changed")
	release_all_support_pins()
	_release_all_foot_heading_locks()
	set_turn_planning_active(false)
	_layout_turn_owned = false
	_gallop_contacts.clear()
	_gallop_reach_released.clear()
	_gallop_group_scheduler_active = false

func set_turn_planning_active(active: bool) -> void:
	super.set_turn_planning_active(active and not _planar_mode_active())

func get_input_movement_direction() -> Vector3:
	var source := get_player_command_source()
	if source != null: return source.get_movement_direction()
	if PLAYER_CONTEXT.controller(self) != null: return Vector3.ZERO
	var direction := Vector3(
		Input.get_action_strength(right_action) - Input.get_action_strength(left_action),
		0.0,
		Input.get_action_strength(down_action) - Input.get_action_strength(up_action)
	)
	return direction.normalized() if not direction.is_zero_approx() else Vector3.ZERO

func is_burst_requested() -> bool:
	var source := get_player_command_source()
	if source != null: return source.is_jump_requested()
	return PLAYER_CONTEXT.controller(self) == null and Input.is_action_just_pressed(burst_action)

func is_fast_speed_active() -> bool:
	return false

func _has_leg_tag(body: RigidBody3D) -> bool:
	return _has_body_tag(body, LEG_TAG) or (forelegs_participate_in_walking and _has_body_tag(body, FORELEG_TAG))

func _discover_leg_parts() -> Array[RigidBody3D]:
	var feet := super._discover_leg_parts()
	if _chains_ready:
		for index: int in range(feet.size() - 1, -1, -1):
			if not _chain_is_intact(feet[index]):
				feet.remove_at(index)
	return feet

func refresh_physics_query_cache() -> void:
	_release_all_foot_heading_locks()
	_body_cache_dirty = true
	_torso_cache_frame = -1
	cancel_step(&"generated_parts_refreshed")
	_step_has_lifted = false
	_failed_step_count = 0
	_last_step_failure = &""
	_clear_leg_adhesion_surface_normals()
	_leg_adhesion_surface_normals.clear()
	_joint_base_springs.clear()
	_hip_joints_by_leg.clear()
	_hip_joint_base_limits.clear()
	_support_anchors.clear()
	_support_forces.clear()
	_adhesion_forces.clear()
	_foot_alignment_torques.clear()
	_last_grounded_force_legs.clear()
	_last_ground_support_time = -1.0
	_adhesion_release_time_remaining = 0.0
	_external_step_height = -1.0
	_fast_gait_anchor_valid = false
	_last_touchdown_times_by_leg.clear()
	_last_touchdown_time = -1.0
	_last_touchdown_leg = &""
	_stance_support_weights.clear()
	_stance_joint_loads.clear()
	_stance_support_signature.clear()
	_stance_allocation_elapsed = 0.0
	_stance_total_mass = 0.0
	_stance_balance_error = 0.0
	_stance_support_balanced = false
	_contact_states.clear()
	_chains.clear()
	_chains_ready = false
	_torso = null
	var torsos := get_torso_parts()
	for body: RigidBody3D in torsos:
		if _torso == null or body.mass > _torso.mass:
			_torso = body
	if _torso != null:
		torso_path = get_path_to(_torso)
	super.refresh_physics_query_cache()
	_capture_chains()
	_capture_body_segments()
	_chains_ready = true
	_refresh_leg_order()
	_capture_leg_initial_positions()
	if auto_size_gait and not _legs.is_empty():
		var shortest := INF
		for foot: RigidBody3D in _legs:
			shortest = minf(shortest, float(_chains[foot].length))
		slow_step_distance = maxf(0.02, shortest * stride_length_ratio)
		minimum_step_distance = slow_step_distance * 0.25
		step_height = shortest * lift_length_ratio
		ray_start_height = maxf(0.5, shortest * 0.5)
		ray_length = maxf(2.0, shortest * 2.0)
	# Reach is checked relative to each attachment, not a single central Torso.
	maximum_horizontal_leg_reach = 0.0
	set_physics_process(_torso != null and not _legs.is_empty())
	if diagnostic_logging_enabled:
		print("[generated_gait] initialized ", get_generated_movement_diagnostics())

func _capture_chains() -> void:
	var parts := get_node_or_null(parts_root_path)
	if parts == null:
		return
	var graph: Dictionary = {}
	for node: Node in parts.find_children("*", "Generic6DOFJoint3D", true, false):
		var joint := node as Generic6DOFJoint3D
		var a := joint.get_node_or_null(joint.node_a) as RigidBody3D
		var b := joint.get_node_or_null(joint.node_b) as RigidBody3D
		if a == null or b == null or joint.is_queued_for_deletion():
			continue
		if not graph.has(a): graph[a] = []
		if not graph.has(b): graph[b] = []
		graph[a].append({"body": b, "joint": joint})
		graph[b].append({"body": a, "joint": joint})
	for foot: RigidBody3D in _legs:
		var bodies: Array[RigidBody3D] = [foot]
		var joints: Array[Generic6DOFJoint3D] = []
		var current := foot
		var seen: Array[RigidBody3D] = [foot]
		while not _has_body_tag(current, TORSO_TAG):
			var next: Dictionary = {}
			for edge: Dictionary in graph.get(current, []):
				var body: RigidBody3D = edge.body
				if body not in seen and not _is_body_broken(body) and (_has_body_tag(body, LEG_LIMB_TAG) or body.get_meta(&"generated_role", "") == "Limb" or _has_body_tag(body, TORSO_TAG)):
					next = edge
					break
			if next.is_empty(): break
			current = next.body
			seen.append(current)
			bodies.append(current)
			joints.append(next.joint)
		if not _has_body_tag(current, TORSO_TAG) or joints.is_empty():
			continue
		var length := 0.0
		var previous := foot.global_position
		for joint: Generic6DOFJoint3D in joints:
			length += previous.distance_to(joint.global_position)
			previous = joint.global_position
			var angle := deg_to_rad(walking_joint_angular_limit_degrees)
			var body_a := joint.get_node_or_null(joint.node_a) as RigidBody3D
			var body_b := joint.get_node_or_null(joint.node_b) as RigidBody3D
			var limb_hinge := body_a != null and body_b != null and _has_body_tag(body_a, LEG_LIMB_TAG) and _has_body_tag(body_b, LEG_LIMB_TAG)
			for axis: String in ["x", "y", "z"]:
				var root_yaw_lock := body_a != null and body_b != null and ((_has_body_tag(body_a, LEG_LIMB_TAG) and _has_body_tag(body_b, SUB_TORSO_TAG)) or (_has_body_tag(body_b, LEG_LIMB_TAG) and _has_body_tag(body_a, SUB_TORSO_TAG)))
				var locked := (limb_hinge and axis != "z") or (root_yaw_lock and axis == "y")
				var axis_angle := 0.0 if locked else angle
				joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
				joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -axis_angle)
				joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, axis_angle)
				if locked: joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, false)
		var rest_rotations: Array[Quaternion] = []
		for index: int in range(joints.size()):
			var child_rotation := bodies[index].global_basis.orthonormalized().get_rotation_quaternion()
			var parent_rotation := bodies[index + 1].global_basis.orthonormalized().get_rotation_quaternion()
			var rest := parent_rotation.inverse() * child_rotation
			if joints[index].has_meta(&"generated_rest_b_relative_a"):
				rest = joints[index].get_meta(&"generated_rest_b_relative_a")
				if joints[index].get_node_or_null(joints[index].node_a) == bodies[index]: rest = rest.inverse()
			rest_rotations.append(rest)
		_chains[foot] = {"bodies": bodies, "joints": joints, "root": current, "anchor": current.to_local(previous), "length": length, "rest_rotations": rest_rotations, "stance_weight": 0.0, "stance_torques": []}

func _chain_is_intact(foot: RigidBody3D) -> bool:
	if not _chains.has(foot): return false
	for body in _chains[foot].bodies:
		if not is_instance_valid(body) or _is_body_broken(body): return false
	for joint in _chains[foot].joints:
		if not is_instance_valid(joint) or joint.is_queued_for_deletion(): return false
	return true

func _remove_invalid_legs() -> void:
	super._remove_invalid_legs()
	if not _chains_ready: return
	for index: int in range(_legs.size() - 1, -1, -1):
		if not _chain_is_intact(_legs[index]):
			if _legs[index] == _active_leg: cancel_step(&"limb_chain_broken")
			_legs.remove_at(index)
	if not _legs.is_empty(): _next_leg_index %= _legs.size()

func _refresh_leg_order() -> void:
	super._refresh_leg_order()
	if _legs.size() < 3: return
	# Choose a distant support region next instead of marching adjacent feet in scene order.
	var pending := _legs.duplicate()
	var ordered: Array[RigidBody3D] = [pending.pop_front()]
	while not pending.is_empty():
		var farthest := 0
		for index: int in range(1, pending.size()):
			if ordered[-1].global_position.distance_squared_to(pending[index].global_position) > ordered[-1].global_position.distance_squared_to(pending[farthest].global_position):
				farthest = index
		ordered.append(pending[farthest])
		pending.remove_at(farthest)
	_legs = ordered

func _get_gait_reference_length() -> float:
	var shortest := INF
	for foot: RigidBody3D in _legs:
		if _chain_is_intact(foot): shortest = minf(shortest, float(_chains[foot].length))
	return shortest if is_finite(shortest) else 1.0

func _get_leg_reference_length(leg: RigidBody3D) -> float:
	return maxf(float(_chains[leg].length), 0.1) if _chains.has(leg) else super._get_leg_reference_length(leg)

func _get_leg_turn_radius(leg: RigidBody3D) -> float:
	return Vector3(leg.get_meta(&"generated_layout_foot_offset", Vector3.ONE)).slide(Vector3.UP).length()

func _try_start_walk_step(direction: Vector3 = Vector3.RIGHT) -> bool:
	if _automatic_motion_enabled(): return super.try_start_step(direction)
	if _step_state != StepState.IDLE: return false
	_remove_invalid_legs()
	for attempt: int in range(_legs.size()):
		if super.try_start_step(direction): return true
		_next_leg_index = (_next_leg_index + 1) % _legs.size()
	return false

func _is_landing_point_valid(leg: RigidBody3D, current_foot: Vector3, hit: Dictionary) -> bool:
	if not super._is_landing_point_valid(leg, current_foot, hit): return false
	if not _chain_is_intact(leg):
		_last_landing_rejection_reason = &"limb_chain_broken"
		return false
	var chain: Dictionary = _chains[leg]
	var root_body: RigidBody3D = chain.root
	var attachment := root_body.to_global(chain.anchor)
	var target := _body_position_for_ground_contact(leg, hit.position)
	if _gallop_active() and _get_gait_data().speed_based_gait:
		var plan := _get_speed_leg_plan(leg)
		if not plan.is_empty(): attachment += Vector3(plan.predicted_travel)
	if target.distance_to(attachment) > float(chain.length) * chain_reach_ratio:
		_last_landing_rejection_reason = &"limb_chain_reach_exceeded"
		return false
	return true

func _capture_hip_joint_limits() -> void:
	# The foot reaches its Torso through several rotational joints; never stretch their linear limits.
	_hip_joints_by_leg.clear()
	_hip_joint_base_limits.clear()

func _expand_hip_joint_for_step(_leg: RigidBody3D, _target: Vector3) -> void:
	pass

func _capture_body_segments() -> void:
	_reset_planar_slide_control()
	_gallop_reach_released.clear()
	_speed_plan_cache.clear()
	_landing_time_estimates.clear()
	_extension_start_times.clear()
	_extension_rearm.clear()
	_extension_admission.clear()
	_speed_plan_frame = -1
	_speed_smoothed_velocity = Vector3.ZERO
	_speed_velocity_frame = -1
	_gallop_contacts.clear()
	_gallop_landed_feet.clear()
	_gallop_launch_time = -1000.0
	_gallop_group_scheduler_active = false
	_gallop_next_group_time = 0.0
	_gallop_group_sequence = 0
	_gallop_next_takeoff = 0.0
	_gallop_pin_release_until = 0.0
	_gallop_takeoffs = 0
	_gallop_diagnostics.clear()
	_turn_drive_diagnostics.clear()
	_turn_landing_rejections.clear()
	_segments.clear()
	_segment_heading_initialized = false
	_segment_layout_initialized = false
	_layout_turn_owned = false
	_layout_turn_cursor = 0
	_layout_turn_elapsed = 0.0
	_layout_turn_retry = 0.0
	_layout_turn_stagnant = 0.0
	_segment_links.clear()
	var parts := get_node_or_null(parts_root_path)
	if parts != null:
		for node: Node in parts.find_children("*", "Node", true, false):
			if not node is Generic6DOFJoint3D and not node.has_method("is_segment_spring"): continue
			var a := node.get_node_or_null(node.node_a) as RigidBody3D
			var b := node.get_node_or_null(node.node_b) as RigidBody3D
			if a == null or b == null or not a.has_meta(&"body_segment_id") or not b.has_meta(&"body_segment_id"): continue
			var first := int(a.get_meta(&"body_segment_id"))
			var second := int(b.get_meta(&"body_segment_id"))
			if first != second: _segment_links.append({"a": first, "b": second, "joint": node, "body_a": a, "body_b": b})
	for body: RigidBody3D in get_torso_parts():
		var id := int(body.get_meta(&"body_segment_id", 0))
		if not _segments.has(id): _segments[id] = {"bodies": [], "feet": [], "mass": 0.0, "center": Vector3.ZERO, "torso_center": Vector3.ZERO, "reference_height": 0.0, "support_blend": 0.0, "auxiliary_force": 0.0, "balanced": true}
		_segments[id].bodies.append(body)
	for foot: RigidBody3D in _legs:
		if not _chains.has(foot): continue
		var attachment: RigidBody3D = _chains[foot].root
		var id := int(attachment.get_meta(&"body_segment_id", 0))
		_segments[id].feet.append(foot)
		var yaw := Basis(Vector3.UP, attachment.global_rotation.y)
		if not foot.has_meta(&"generated_attachment_rest_offset"):
			foot.set_meta(&"generated_attachment_rest_offset", yaw.inverse() * (foot.global_position - attachment.global_position))
	_update_segment_metrics()
	var layout_center := Vector3.ZERO
	var layout_mass := 0.0
	for body: RigidBody3D in get_torso_parts():
		layout_center += body.global_position * body.mass
		layout_mass += body.mass
	layout_center /= maxf(layout_mass, 0.001)
	for foot: RigidBody3D in _legs:
		if not foot.has_meta(&"generated_layout_foot_offset"):
			foot.set_meta(&"generated_layout_foot_offset", Basis(Vector3.UP, _torso.global_rotation.y).inverse() * (foot.global_position - layout_center))
	for id: int in _segments:
		var segment: Dictionary = _segments[id]
		var floor_height := 0.0
		for foot: RigidBody3D in segment.feet: floor_height += _get_foot_world_position(foot).y
		if not segment.feet.is_empty(): floor_height /= float(segment.feet.size())
		var reference: RigidBody3D = segment.bodies[0]
		if not reference.has_meta(&"generated_segment_rest_height"):
			reference.set_meta(&"generated_segment_rest_height", maxf(0.1, Vector3(segment.torso_center).y - floor_height))
		segment.reference_height = reference.get_meta(&"generated_segment_rest_height")
		if not reference.has_meta(&"generated_segment_rest_offset"):
			reference.set_meta(&"generated_segment_rest_offset", Basis(Vector3.UP, _torso.global_rotation.y).inverse() * (Vector3(segment.torso_center) - layout_center))
		segment.rest_offset = reference.get_meta(&"generated_segment_rest_offset")

func _connected_body_segments(start: int) -> Array[int]:
	var result: Array[int] = [start]
	var cursor := 0
	while cursor < result.size():
		var current := result[cursor]
		cursor += 1
		for link: Dictionary in _segment_links:
			if not is_instance_valid(link.joint) or link.joint.is_queued_for_deletion(): continue
			if link.joint.has_method("is_segment_spring") and not link.joint.enabled: continue
			if not is_instance_valid(link.body_a) or not is_instance_valid(link.body_b) or _is_body_broken(link.body_a) or _is_body_broken(link.body_b): continue
			var other: int = link.b if link.a == current else (link.a if link.b == current else -1)
			if other >= 0 and other not in result: result.append(other)
	return result

func _update_segment_metrics() -> void:
	for id: int in _segments:
		var segment: Dictionary = _segments[id]
		segment.mass = 0.0
		segment.center = Vector3.ZERO
		segment.torso_center = Vector3.ZERO
		var torso_mass := 0.0
		for body: RigidBody3D in segment.bodies:
			if not is_instance_valid(body) or _is_body_broken(body): continue
			segment.mass += body.mass
			segment.center += _stance_body_center(body) * body.mass
			segment.torso_center += _stance_body_center(body) * body.mass
			torso_mass += body.mass
		if torso_mass > 0.0: segment.torso_center /= torso_mass
		for foot: RigidBody3D in segment.feet:
			if not _chain_is_intact(foot): continue
			for body: RigidBody3D in _chains[foot].bodies:
				if _has_body_tag(body, TORSO_TAG): continue
				segment.mass += body.mass
				segment.center += _stance_body_center(body) * body.mass
		if segment.mass > 0.0: segment.center /= segment.mass

func _get_leg_rest_world_position(leg: RigidBody3D) -> Vector3:
	if not _chains.has(leg) or not leg.has_meta(&"generated_attachment_rest_offset"):
		return super._get_leg_rest_world_position(leg)
	var attachment: RigidBody3D = _chains[leg].root
	return attachment.global_position + Basis(Vector3.UP, attachment.global_rotation.y) * Vector3(leg.get_meta(&"generated_attachment_rest_offset"))

func _get_speed_leg_plan(leg: RigidBody3D) -> Dictionary:
	if not _automatic_motion_enabled() or not _get_gait_data().speed_based_gait or not _chain_is_intact(leg): return {}
	var frame := Engine.get_physics_frames()
	if _speed_plan_frame != frame:
		_speed_plan_frame = frame
		_speed_plan_cache.clear()
	if _speed_plan_cache.has(leg): return _speed_plan_cache[leg]
	if _speed_velocity_frame != frame:
		_speed_velocity_frame = frame
		var velocity := Vector3.ZERO
		var mass := 0.0
		for torso: RigidBody3D in get_torso_parts():
			if _is_body_broken(torso): continue
			velocity += torso.linear_velocity * torso.mass
			mass += torso.mass
		var blend := 1.0-exp(-maxf(_support_delta,1.0/60.0)/0.15)
		_speed_smoothed_velocity = _speed_smoothed_velocity.lerp(velocity/maxf(mass,0.001),blend)
	var direction := get_input_movement_direction().slide(Vector3.UP).normalized()
	if _planar_mode_active(): direction = Vector3(signf(direction.x),0,0)
	if direction.is_zero_approx(): direction = Vector3.RIGHT
	# Build geometry once per frame using the common reference cadence.
	# Landing delays no longer modify either cadence or swing duration.
	var capacity := _legs.size() if _get_gait_data().gallop_allow_all_feet_airborne else maxi(_legs.size()-1,0)
	var reference := _get_gait_reference_length()
	var actual_speed := maxf(_speed_smoothed_velocity.dot(direction),0.0)
	var geometry: Dictionary = {}
	for foot: RigidBody3D in _legs:
		if not _chain_is_intact(foot): continue
		var chain: Dictionary = _chains[foot]
		var attachment: Vector3 = chain.root.to_global(chain.anchor)
		var relative := foot.global_position-attachment
		var sideways := relative.slide(Vector3.UP)-direction*relative.dot(direction)
		var radius := float(chain.length)*chain_reach_ratio*0.95
		var forward_reach := sqrt(maxf(radius*radius-relative.y*relative.y-sideways.length_squared(),0.0))
		var margin := maxf(float(chain.length)*0.05,0.05)
		var distance := maxf(relative.dot(direction)+forward_reach-margin,0.0)
		geometry[foot] = {"distance": distance,"reach": maxf(forward_reach-margin,0.05)}
	for foot: RigidBody3D in geometry:
		var plan := _get_gait_data().calculate_adaptive_flight_profile(reference,_legs.size(),actual_speed,float(geometry[foot].distance),capacity,float(_landing_time_estimates.get(foot,0.0)))
		if not plan.get("enabled",false): continue
		plan["forward_reach"] = geometry[foot].reach
		plan["direction"] = direction
		plan["predicted_travel"] = direction*float(plan.planning_speed)*float(plan.air_duration)
		_speed_plan_cache[foot] = plan
	return _speed_plan_cache.get(leg,{})

func get_automatic_motion_diagnostics() -> Dictionary:
	var result := super.get_automatic_motion_diagnostics()
	result["step_start_policy"] = "extension" if _extension_gait_enabled() else "cadence"
	result["actual_starts_last_second"] = _extension_start_times.filter(func(time): return _physics_elapsed-time < 1.0).size()
	result["speed_based_gait"] = _automatic_motion_enabled() and _get_gait_data().speed_based_gait and _get_gait_data().gallop_enabled
	for profile: Dictionary in result.legs:
		for leg: RigidBody3D in _legs:
			if profile.foot == leg.name:
				profile["speed_gait"] = _get_speed_leg_plan(leg) if result.speed_based_gait else {}
				break
	return result

func get_leg_step_distance(leg: RigidBody3D) -> float:
	if _gallop_active() and _get_gait_data().speed_based_gait:
		var plan := _get_speed_leg_plan(leg)
		if not plan.is_empty(): return minf(float(plan.required_stride)*0.5,float(plan.forward_reach)*0.8)
	return super.get_leg_step_distance(leg)

func _gallop_flight_available() -> bool:
	return _gallop_active() and (_physics_elapsed < _gallop_pin_release_until or _gallop_support(_legs).weight > 0.0)

func get_maximum_stepping_feet() -> int:
	if not _gallop_active():
		var normal_capacity := super.get_maximum_stepping_feet()
		# Mode changes must let already airborne gait steps land. Shared admission
		# sees a full budget until the extra motions finish; no new excess starts.
		for motion: StepMotion in _active_steps:
			if motion.extra.get("gallop_step",false): return maxi(normal_capacity,_active_steps.size())
		return normal_capacity
	var capacity := _automatic_flight_capacity() if _get_gait_data().speed_based_gait else _get_gait_data().calculate_gallop_capacity(_legs.size(),_gallop_flight_available())
	# Let an already launched group land when its launch window expires; no new
	# group can exceed the configured budget simply because old motions exist.
	return maxi(capacity,_active_steps.size())

func _automatic_flight_capacity() -> int:
	# Admission is a support safety budget, independent of reference frequency.
	var intact := 0
	for foot: RigidBody3D in _legs:
		if _chain_is_intact(foot): intact += 1
	return intact if _get_gait_data().gallop_allow_all_feet_airborne else maxi(intact-1,0)

func _extension_gait_enabled() -> bool:
	var data := _get_gait_data()
	return data != null and data.automatic_motion and data.speed_based_gait and data.target_speed > 0.0 and input_enabled and not get_input_movement_direction().is_zero_approx() and not _planar_mode_active() and not recovery_control_active and not simplified_physics_mode and _adhesion_release_time_remaining <= 0.0

func _automatic_step_cadence_allows() -> bool:
	return true if _extension_gait_enabled() or _gallop_starting_batch else super._automatic_step_cadence_allows()

## Distance to the rear reach boundary, measured in the requested travel direction.
## Use actual attachment/foot relative velocity, never target speed, to avoid
## repeatedly lifting a stationary, already stretched foot.
func _get_extension_step_demand(foot: RigidBody3D, direction: Vector3) -> Dictionary:
	var result := {"policy": "extension", "requested": false, "reason": "inactive", "remaining_distance": 0.0, "approach_speed": 0.0, "time_to_limit": -1.0}
	if not _extension_gait_enabled() or direction.is_zero_approx() or not _chain_is_intact(foot): return result
	if is_leg_stepping(foot):
		result.reason = "already_stepping"
		return result
	if not is_leg_grounded(foot):
		result.reason = "not_grounded"
		return result
	var chain: Dictionary = _chains[foot]
	var root_body: RigidBody3D = chain.root
	var attachment: Vector3 = root_body.to_global(chain.anchor)
	var attachment_velocity := root_body.linear_velocity + root_body.angular_velocity.cross(attachment-root_body.global_position)
	var travel := direction.slide(Vector3.UP).normalized()
	var relative := foot.global_position-attachment
	var sideways := relative.slide(Vector3.UP)-travel*relative.dot(travel)
	var length := float(chain.length)
	var radius := length*chain_reach_ratio*0.95
	var reach := sqrt(maxf(radius*radius-relative.y*relative.y-sideways.length_squared(),0.0))
	var raw_remaining := relative.dot(travel)+reach-maxf(length*0.05,0.05)
	var remaining := maxf(raw_remaining,0.0)
	var approach := (attachment_velocity-foot.linear_velocity).dot(travel)
	var plan := _get_speed_leg_plan(foot)
	var lead := clampf(float(plan.get("air_duration",get_leg_motion_profile(foot).swing_duration))*0.15,0.06,0.18)
	var threshold := maxf(length*0.12,0.03)
	result.remaining_distance = remaining
	result.approach_speed = approach
	result.time_to_limit = remaining/approach if approach > 0.05 else -1.0
	result["distance_threshold"] = threshold
	result["lead_time"] = lead
	result["reference_frequency"] = get_planned_step_frequency()
	result["overextension"] = maxf(-raw_remaining,0.0)
	result["rearm_progress"] = 0.0
	result["rearm_required_progress"] = length*0.15
	var emergency := remaining <= maxf(length*0.02,0.02)
	var actually_moving := approach > 0.05 or (attachment_velocity.dot(travel)>0.1 and foot.linear_velocity.slide(Vector3.UP).length()>0.35)
	result["emergency"] = emergency and actually_moving
	if result.emergency:
		if _extension_rearm.has(foot): result.rearm_progress = (attachment-Vector3(_extension_rearm[foot].origin)).dot(travel)
		result.requested = true
		result.reason = "extension_emergency"
		return result
	result.requested = approach > 0.05 and (remaining <= threshold or remaining/approach <= lead)
	# Rearm through geometry/progress, not a timer or cadence credit. If a
	# landing leaves the foot behind, allow a slower recovery after actual
	# stance travel instead of rapid repeated normal swings.
	if _extension_rearm.has(foot):
		var stance: Dictionary = _extension_rearm[foot]
		var progress := (attachment-Vector3(stance.origin)).dot(travel)
		result.rearm_progress = progress
		if remaining >= length*0.22 or travel.dot(Vector3(stance.direction)) < 0.5:
			_extension_rearm.erase(foot)
		elif progress < length*0.15:
			result.requested = false
			result.reason = "rearming_stance"
			return result
		elif result.requested:
			result.reason = "reach_recovery"
			return result
	result.reason = "distance_limit" if result.requested and remaining <= threshold else ("predicted_limit" if result.requested else "holding")
	return result

func _update_extension_gait(delta: float, direction: Vector3) -> void:
	_extension_start_times = _extension_start_times.filter(func(time): return _physics_elapsed-time < 1.0)
	# Shared code still updates and finishes existing motions. Admission below
	# ignores all shared/per-foot deadlines and the old cadence gates.
	_gallop_updating_group = true
	super._update_resource_gait(delta,direction)
	_gallop_updating_group = false
	var candidates := _legs.duplicate()
	var demands: Dictionary = {}
	for foot: RigidBody3D in candidates: demands[foot] = _get_extension_step_demand(foot,direction)
	candidates.sort_custom(func(a,b): return float(demands[a].remaining_distance) < float(demands[b].remaining_distance))
	var started := 0
	for foot: RigidBody3D in candidates:
		_extension_admission[foot] = {"time": _physics_elapsed,"reason": demands[foot].reason,"requested": demands[foot].requested}
		if not demands[foot].requested: continue
		if not _can_start_step_with_support(foot):
			_extension_admission[foot].reason = "support_budget_or_ground_lease"
			continue
		_current_step = StepMotion.new()
		_next_leg_index = _legs.find(foot)
		if not try_start_step(direction):
			_extension_admission[foot].reason = "landing_rejected"
			_extension_admission[foot]["landing_rejection"] = _last_landing_rejection_reason
			continue
		_extension_admission[foot].reason = "started"
		_extension_start_times.append(_physics_elapsed)
		_current_step.extra["extension_trigger"] = demands[foot].duplicate()
		if demands[foot].reason in ["reach_recovery","extension_emergency"] and _current_step.extra.has("speed_gait"):
			_active_step_duration = maxf(_active_step_duration,0.55)
			_current_step.extra.speed_gait.air_duration = _active_step_duration
		_current_step.extra["gallop_group"] = _gallop_group_sequence+1
		started += 1
	if started > 0: _gallop_group_sequence += 1
	_gallop_group_scheduler_active = false
	_current_step = _active_steps[0] if not _active_steps.is_empty() else StepMotion.new()


func _update_resource_gait(delta: float, direction: Vector3) -> void:
	if _extension_gait_enabled():
		_update_extension_gait(delta,direction)
		return
	if _planar_mode_active():
		direction = Vector3(signf(direction.x),0,0)
		if direction.is_zero_approx():
			if not _active_steps.is_empty(): cancel_step(&"planar_side_slide")
			_gallop_reach_released.clear()
			_gallop_group_scheduler_active = false
			return
	if not _gallop_active():
		_gallop_group_scheduler_active = false
		super._update_resource_gait(delta,direction)
		return
	if not _gallop_group_scheduler_active:
		_gallop_group_scheduler_active = true
		_gallop_next_group_time = _physics_elapsed
		_automatic_next_steps.clear()
	# Reuse all shared tracking, invalid-body cleanup and input replanning. Only
	# the start policy changes from individual starts to explicitly budgeted groups.
	_gallop_updating_group = true
	super._update_resource_gait(delta,direction)
	_gallop_updating_group = false
	var frequency := get_planned_step_frequency()
	if frequency <= 0.0: return
	# Legacy/manual gallop retains its timed group policy. Automatic speed-based
	# walking was handled by extension events above.
	if _physics_elapsed < _gallop_next_group_time: return
	var started := 0
	var group_size := mini(_get_gait_data().gallop_step_group_size,_legs.size())
	_gallop_starting_batch = true
	for foot: RigidBody3D in _legs:
		if started >= group_size: break
		if is_leg_stepping(foot): continue
		_current_step = StepMotion.new()
		_next_leg_index = _legs.find(foot)
		if not try_start_step(direction): continue
		_current_step.extra["gallop_group"] = _gallop_group_sequence+1
		started += 1
	_gallop_starting_batch = false
	if started > 0: _gallop_group_sequence += 1
	_gallop_next_group_time = _physics_elapsed+maxf(started,1)/frequency
	_next_resource_step_time = _gallop_next_group_time
	_current_step = _active_steps[0] if not _active_steps.is_empty() else StepMotion.new()

func _gallop_intensity() -> float:
	if not _automatic_motion_enabled() or _legs.is_empty(): return 0.0
	var walking_speed := _get_gait_data().target_speed
	for foot: RigidBody3D in _legs: walking_speed = minf(walking_speed,float(get_leg_motion_profile(foot).reachable_speed))
	return clampf(_get_gait_data().target_speed / maxf(walking_speed,0.01) - 1.0,0.0,1.0)

func _gallop_window() -> float:
	if _automatic_motion_enabled() and _get_gait_data().speed_based_gait and not _legs.is_empty():
		return float(_get_speed_leg_plan(_legs[0]).get("air_duration",0.15))
	return _get_gait_data().gallop_airborne_duration * lerpf(0.5,1.0,_gallop_intensity())

func _gallop_active() -> bool:
	var data := _get_gait_data()
	if data == null or not data.automatic_motion or not data.gallop_enabled or not input_enabled or recovery_control_active or simplified_physics_mode or (_turn_planning_active and not data.speed_based_gait) or _adhesion_release_time_remaining > 0.0: return false
	if get_input_movement_direction().is_zero_approx() or _legs.is_empty(): return false
	if data.speed_based_gait: return data.target_speed > 0.0
	for foot: RigidBody3D in _legs:
		if data.target_speed > float(get_leg_motion_profile(foot).reachable_speed) + 0.001: return true
	return false

func _try_gallop_takeoff(foot: RigidBody3D) -> void:
	# Automatic gait lifts selected feet through tracking; never unpin waiting feet.
	if _automatic_motion_enabled() and _get_gait_data().speed_based_gait: return
	if not _gallop_active() or _physics_elapsed < _gallop_next_takeoff or _get_gait_data().gallop_takeoff_velocity <= 0.0: return
	var supports := _contact_drive_supports(_legs)
	if supports.size() < maxi(_get_gait_data().minimum_support_feet,1): return
	# Record actual stance before releasing pins; future step commands cannot renew this lease.
	_update_gallop_contacts()
	var up := -_gravity_acceleration().normalized()
	if up.is_zero_approx(): return
	var velocity := Vector3.ZERO
	var mass := 0.0
	for body: RigidBody3D in get_torso_parts():
		if _is_body_broken(body) or body.freeze: continue
		velocity += body.linear_velocity * body.mass
		mass += body.mass
	if mass <= 0.0: return
	var takeoff_speed := _get_gait_data().gallop_takeoff_velocity * sqrt(_gallop_intensity())
	var correction := clampf(takeoff_speed - (velocity / mass).dot(up),0.0,takeoff_speed)
	if correction <= 0.0: return
	var launch_bodies := get_torso_parts()
	launch_bodies.append_array(_legs)
	for body: RigidBody3D in launch_bodies:
		if not _is_body_broken(body) and not body.freeze: body.apply_central_impulse(up * body.mass * correction)
	release_all_support_pins()
	_gallop_landed_feet.clear()
	_gallop_launch_time = _physics_elapsed
	_gallop_pin_release_until = _physics_elapsed + _gallop_window()
	_gallop_next_takeoff = _physics_elapsed + maxf(float(get_leg_motion_profile(foot).cycle) * 0.5,_get_gait_data().gallop_airborne_duration)
	_gallop_takeoffs += 1

func _update_gallop_contacts() -> void:
	if not _gallop_active():
		_gallop_contacts.clear()
		_gallop_reach_released.clear()
		_gallop_diagnostics = {"active": false}
		return
	for foot: RigidBody3D in _legs:
		if not _chain_is_intact(foot) or is_leg_stepping(foot) or _gallop_reach_released.has(foot) or not is_leg_grounded(foot): continue
		var hit := _get_surface_below_leg(foot, ground_probe_distance)
		if not hit.is_empty():
			var duration := _gallop_window()
			var plan := _get_speed_leg_plan(foot)
			if not plan.is_empty(): duration = float(plan.get("lease_duration",clampf(float(plan.air_duration)+float(plan.landing_reserve),duration,_get_gait_data().gallop_maximum_airborne_duration)))
			_gallop_contacts[foot] = {"time": _physics_elapsed, "position": hit.position, "normal": hit.normal, "duration": duration}
	for foot in _gallop_contacts.keys():
		if not is_instance_valid(foot) or not _chain_is_intact(foot) or _physics_elapsed - float(_gallop_contacts[foot].time) >= _gallop_contact_duration(foot):
			_gallop_contacts.erase(foot)
	_gallop_diagnostics = {"active": true, "target_speed": _get_gait_data().target_speed, "window": _gallop_window(), "maximum_lease_duration": float(_get_speed_leg_plan(_legs[0]).get("lease_duration",_get_gait_data().gallop_maximum_airborne_duration)), "intensity": _gallop_intensity(), "walking_speed_limit": float(get_leg_motion_profile(_legs[0]).reachable_speed), "total_step_frequency": get_planned_step_frequency(), "remembered_contacts": _gallop_contacts.size(), "takeoffs": _gallop_takeoffs, "group_sequence": _gallop_group_sequence, "group_size": get_maximum_stepping_feet() if _get_gait_data().speed_based_gait else _get_gait_data().gallop_step_group_size, "stepping_capacity": get_maximum_stepping_feet(), "cadence_controls_admission": not _extension_gait_enabled(), "actual_starts_last_second": _extension_start_times.filter(func(time): return _physics_elapsed-time < 1.0).size(), "next_group_in": maxf(_gallop_next_group_time-_physics_elapsed,0.0), "phase": "flight" if _physics_elapsed < _gallop_pin_release_until else "landing_or_support", "pin_release_remaining": maxf(_gallop_pin_release_until - _physics_elapsed,0.0), "airborne_force": Vector3.ZERO, "airborne_support": Vector3.ZERO, "segments": []}

func _gallop_contact_duration(foot: RigidBody3D) -> float:
	return float(_gallop_contacts.get(foot,{}).get("duration",_gallop_window()))

func _gallop_contact_weight(foot: RigidBody3D) -> float:
	if not _gallop_contacts.has(foot): return 0.0
	var duration := _gallop_contact_duration(foot)
	var age := _physics_elapsed-float(_gallop_contacts[foot].time)
	# Speed gait retains traction through the planned swing, then fades out.
	# Only a real non-stepping ground contact can renew this bounded lease.
	var hold := duration*0.75 if _get_gait_data().speed_based_gait else 0.0
	return clampf((duration-age)/maxf(duration-hold,0.001),0.0,1.0)

func _contact_drive_supports(feet: Array) -> Array[RigidBody3D]:
	var result := super._contact_drive_supports(feet)
	for motion: StepMotion in _active_steps:
		if not feet.has(motion.leg) or motion.state != StepState.LANDING or not motion.extra.get("gallop_touchdown_braking",false): continue
		if motion.leg.freeze or _is_body_broken(motion.leg) or is_leg_slipping(motion.leg) or not is_leg_grounded(motion.leg) or motion.leg.linear_velocity.length() > 1.5: continue
		if not result.has(motion.leg): result.append(motion.leg)
	if _gallop_active():
		for index: int in range(result.size()-1,-1,-1):
			if _gallop_reach_released.has(result[index]): result.remove_at(index)
	return result

func _gallop_support(feet: Array, up: Vector3 = Vector3.UP) -> Dictionary:
	var result := {"weight": 0.0, "height": 0.0, "feet": 0}
	if not _gallop_active(): return result
	var total := 0.0
	for foot in feet:
		if not _gallop_contacts.has(foot) or not _chain_is_intact(foot) or foot.freeze: continue
		var weight := _gallop_contact_weight(foot)
		result.weight = maxf(result.weight,weight)
		result.height += Vector3(_gallop_contacts[foot].position).dot(up) * weight
		total += weight
		if weight > 0.0: result.feet += 1
	if total > 0.0: result.height /= total
	return result

func _apply_contact_drive(feet: Array, requested: Vector3, carried_mass: float, up: Vector3) -> Vector3:
	# The contact allocator still owns ground drive; airborne assistance is a single
	# bounded replacement, never an extra full-strength force per remembered foot.
	if not _gallop_active() or not _contact_drive_supports(feet).is_empty(): return super._apply_contact_drive(feet,requested,carried_mass,up)
	var support := _gallop_support(feet,up)
	if support.weight <= 0.0: return super._apply_contact_drive(feet,requested,carried_mass,up)
	var bodies: Array[RigidBody3D] = []
	var mass := 0.0
	for foot in feet:
		if not _chain_is_intact(foot): continue
		var driver: RigidBody3D = _chains[foot].root
		if driver in bodies or driver.freeze or _is_body_broken(driver): continue
		bodies.append(driver)
		mass += driver.mass
	if mass <= 0.0: return Vector3.ZERO
	var force: Vector3 = requested.slide(up).limit_length(maximum_contact_drive_force) * support.weight * (0.65 if _get_gait_data().speed_based_gait else _get_gait_data().gallop_airborne_drive_ratio) * _gallop_intensity()
	for body: RigidBody3D in bodies: body.apply_central_force(force * body.mass / mass)
	_contact_drive_diagnostics.requested_force += requested
	_contact_drive_diagnostics.applied_force += force
	_contact_drive_diagnostics["airborne_assist"] = true
	_gallop_diagnostics.airborne_force += force
	return force

func _get_projected_landing_rest_position(leg: RigidBody3D, movement_direction: Vector3) -> Vector3:
	var rest := super._get_projected_landing_rest_position(leg,movement_direction)
	if not _gallop_active(): return rest
	if _get_gait_data().speed_based_gait:
		var plan := _get_speed_leg_plan(leg)
		if not plan.is_empty(): return rest + Vector3(plan.predicted_travel)
	var duration := _motion_setting("swing_duration",slow_step_duration,leg)
	return rest + movement_direction * get_expected_horizontal_speed() * duration * _get_gait_data().gallop_landing_prediction_ratio

## Ground contacts remain the source of diagnostics; airborne assistance is reported separately.
func get_torso_movement_force_legs(_fast_mode_active: bool = false) -> Array[RigidBody3D]:
	var feet: Array[RigidBody3D] = []
	for foot: RigidBody3D in _contact_drive_supports(_legs):
		if _chain_is_intact(foot): feet.append(foot)
	return feet

func _reset_planar_slide_control() -> void:
	_planar_slide_integral = 0.0
	_planar_slide_frame = -1
	_planar_slide_last_target = 0.0
	_planar_slide_diagnostics = {}

func _planar_target_velocity() -> Vector3:
	var direction := get_input_movement_direction() if input_enabled else Vector3.ZERO
	var data := _get_gait_data()
	var speed := maxf(data.target_speed,0.0) if data != null else get_expected_horizontal_speed()
	return direction * speed

func _update_planar_motion(delta: float) -> void:
	var performance_started: int = _movement_perf.start()
	var started_usec := Time.get_ticks_usec() if _performance_tracking_enabled else 0
	# Bypass all physical gait, adhesion, ground pins, balance and Torso drive.
	if _physics_query_cache_dirty: _refresh_physics_query_cache()
	_support_delta = delta
	_physics_elapsed += delta
	var target := _planar_target_velocity()
	var planar := get_parent().get_node_or_null("PlanarConstraints")
	if planar == null: return
	_planar_slide_diagnostics = planar.apply_independent_motion(self,target,delta)
	var actual: Vector3 = _planar_slide_diagnostics.actual_velocity
	_last_torso_response_force = Vector3.ZERO
	_last_auxiliary_support_force = Vector3.ZERO
	_ground_brake_force = Vector3.ZERO
	_reset_contact_drive_diagnostics()
	_contact_drive_diagnostics["target_velocity"] = target
	_contact_drive_diagnostics["actual_velocity"] = actual
	_contact_drive_diagnostics["independent_parts"] = _planar_slide_diagnostics
	if _performance_tracking_enabled:
		var elapsed_usec := Time.get_ticks_usec()-started_usec
		_performance_physics_frames += 1
		_performance_total_usec += elapsed_usec
		_performance_max_usec = maxi(_performance_max_usec,elapsed_usec)
	_movement_perf.finish(&"movement_planar_independent",performance_started)
	_update_diagnostic_log(delta)

func _update_planar_slide_control(target: Vector3, gain: float, cap: float) -> void:
	var frame := Engine.get_physics_frames()
	if _planar_slide_frame == frame: return
	_planar_slide_frame = frame
	var velocity := 0.0
	var mass := 0.0
	for body: RigidBody3D in get_torso_parts():
		if _is_body_broken(body): continue
		velocity += body.linear_velocity.z*body.mass
		mass += body.mass
	velocity /= maxf(mass,0.001)
	var authorized := not _contact_drive_supports(_legs).is_empty() or float(_gallop_support(_legs).weight) > 0.0
	if is_zero_approx(target.z) or signf(target.z) != signf(_planar_slide_last_target): _planar_slide_integral = 0.0
	if not is_zero_approx(target.z) and authorized:
		# Critically damped PI response. Its bounded integral compensates terrain
		# friction; it cannot create propulsion without real/recent ground support.
		_planar_slide_integral = clampf(_planar_slide_integral+(target.z-velocity)*gain*gain*0.25*_support_delta,-cap*0.5,cap*0.5)
	_planar_slide_last_target = target.z
	_planar_slide_diagnostics = {"target_z": target.z,"actual_z": velocity,"integral_acceleration": _planar_slide_integral,"authorized": authorized}

func _contact_velocity_force(velocity: Vector3, mass: float, up: Vector3) -> Vector3:
	if not _planar_mode_active():
		if _planar_slide_frame >= 0: _reset_planar_slide_control()
		return super._contact_velocity_force(velocity,mass,up)
	var target := _planar_target_velocity()
	var gain := _motion_setting("contact_gain",contact_velocity_gain)
	var cap := _motion_setting("contact_acceleration",contact_maximum_acceleration)
	_update_planar_slide_control(target,gain,cap)
	var acceleration := (target-velocity.slide(up))*gain
	acceleration.z += _planar_slide_integral
	_contact_drive_diagnostics["target_velocity"] = target
	_contact_drive_diagnostics["actual_velocity"] = velocity.slide(up)
	_contact_drive_diagnostics["planar_slide"] = _planar_slide_diagnostics
	return acceleration.limit_length(cap)*mass

func _segment_movement_scale(segment: Dictionary, up: Vector3) -> float:
	if bool(segment.balanced): return 1.0
	# A sparse flight/support phase is not a fallen body. Retain the normal
	# protection when the segment actually tilts, or recovery/turning owns control.
	if _gallop_active() or (_planar_mode_active() and not is_zero_approx(get_input_movement_direction().z)):
		var upright := true
		for body: RigidBody3D in segment.bodies:
			if body.global_basis.y.normalized().angle_to(up) > deg_to_rad(20.0): upright = false
		if upright: return 1.0
	return unbalanced_movement_multiplier

func _apply_torso_response() -> void:
	_last_torso_response_force = Vector3.ZERO
	_last_auxiliary_support_force = Vector3.ZERO
	if _segments.is_empty(): return
	_update_segment_metrics()
	_update_gallop_contacts()
	var gravity := _gravity_acceleration()
	var up := -gravity.normalized() if not gravity.is_zero_approx() else Vector3.UP
	var eligible := _contact_drive_supports(get_leg_parts())
	var contact_heights: Dictionary = {}
	for foot: RigidBody3D in _legs:
		var contact := _get_stance_chain_contact(foot)
		if not contact.is_empty():
			var id := int(_chains[foot].root.get_meta(&"body_segment_id", 0))
			if not contact_heights.has(id): contact_heights[id] = []
			contact_heights[id].append(Vector3(contact.position).dot(up))
	var total_torso_mass := 0.0
	for body: RigidBody3D in get_torso_parts():
		if not _is_body_broken(body): total_torso_mass += body.mass
	for id: int in _segments:
		var segment: Dictionary = _segments[id]
		var support_floor := 0.0
		var contact_count := 0
		for connected: int in _connected_body_segments(id):
			for height: float in contact_heights.get(connected, []):
				support_floor += height
				contact_count += 1
		if contact_count > 0: support_floor /= float(contact_count)
		var torsos: Array[RigidBody3D] = []
		var sub_torsos: Array[RigidBody3D] = []
		var torso_mass := 0.0
		var vertical_speed := 0.0
		for body: RigidBody3D in segment.bodies:
			if not is_instance_valid(body) or _is_body_broken(body) or body.freeze: continue
			torsos.append(body)
			torso_mass += body.mass
			vertical_speed += body.linear_velocity.dot(up) * body.mass
			if _has_body_tag(body, SUB_TORSO_TAG): sub_torsos.append(body)
		if torso_mass <= 0.0: continue
		var grounded := 0
		var floor_height := 0.0
		for foot: RigidBody3D in segment.feet:
			if foot not in eligible: continue
			grounded += 1
			floor_height += _support_surface_contact(foot).position.dot(up)
		var velocity := Vector3.ZERO
		for body: RigidBody3D in torsos: velocity += body.linear_velocity * body.mass / torso_mass
		var force := Vector3.ZERO
		if torso_response_enabled:
			var requested := _contact_velocity_force(velocity, float(segment.mass), up)
			requested += _contact_extra_force * torso_mass / maxf(total_torso_mass, 0.001)
			var drive_scale := _segment_movement_scale(segment,up)
			segment["movement_scale"] = drive_scale
			requested *= drive_scale
			requested = requested.limit_length(minf(maximum_contact_drive_force * torso_mass / maxf(total_torso_mass, 0.001), float(segment.mass) * _motion_setting("contact_acceleration", maximum_grounded_drive_acceleration)))
			force = _apply_contact_drive(segment.feet, requested, float(segment.mass), up)
		_last_torso_response_force += force
		var air_support := _gallop_support(segment.feet,up)
		var previous_lift := float(segment.auxiliary_force)
		segment.auxiliary_force = 0.0
		var grounded_support := contact_count > 0 and _adhesion_release_time_remaining <= 0.0
		var supported: bool = grounded_support or air_support.weight > 0.0
		var target_blend := 1.0 if supported else 0.0
		segment.support_blend = move_toward(float(segment.support_blend), target_blend, _support_delta / maxf(sub_torso_support_ramp_time, 0.001))
		if not simplified_physics_mode and sub_torso_support_enabled and not sub_torsos.is_empty():
			# Bounded airborne support remembers the last real floor; it never samples a new floor in air.
			if supported:
				var target_height: float = (floor_height / float(grounded) if grounded > 0 else (support_floor if grounded_support else float(air_support.height))) + segment.reference_height
				target_height = _limit_supported_torso_height(segment, target_height, up)
				var height_error: float = target_height - Vector3(segment.torso_center).dot(up)
				var damping := 2.0 * sub_torso_damping_ratio * sqrt(sub_torso_height_gain)
				var lift: float = segment.mass * (gravity.length() * sub_torso_weight_share + height_error * sub_torso_height_gain - vertical_speed / torso_mass * damping)
				var support_limit := minf(sub_torso_maximum_weight_share, auxiliary_support_weight_limit)
				if not grounded_support: support_limit = minf(support_limit,(0.45 if _get_gait_data().speed_based_gait else _get_gait_data().gallop_airborne_support_ratio) * float(air_support.weight) * _gallop_intensity())
				lift = clampf(lift, 0.0, segment.mass * gravity.length() * support_limit) * segment.support_blend
				var blend := 1.0 if sub_torso_force_smoothing_time <= 0.0 else 1.0 - exp(-_support_delta / sub_torso_force_smoothing_time)
				lift = minf(lerpf(previous_lift, lift, blend),segment.mass * gravity.length() * support_limit)
				# Nonnegative weights make off-center supports carry the segment COM.
				var points: Array[Vector3] = []
				for body: RigidBody3D in sub_torsos: points.append(_stance_body_center(body))
				var weights := _solve_stance_support_weights(points, segment.center, up)
				for index: int in range(sub_torsos.size()): sub_torsos[index].apply_central_force(up * lift * weights[index])
				segment.auxiliary_force = lift
				if not grounded_support: _gallop_diagnostics.airborne_support += up * lift
				_last_auxiliary_support_force += up * lift
		elif not simplified_physics_mode and torso_response_enabled and supported and grounded > 0:
			# Height demand comes from body height, never sole displacement.
			var damping := maxf(torso_vertical_response_damping, 2.0 * vertical_response_damping_ratio * sqrt(vertical_response_gain))
			var height_error := floor_height / float(grounded) + float(segment.reference_height) - Vector3(segment.torso_center).dot(up)
			var vertical := height_error * vertical_response_gain * torso_mass - vertical_speed * damping
			var lift := up * clampf(vertical, -torso_mass * gravity.length() * downward_response_weight_limit, torso_mass * gravity.length() * upward_response_weight_limit)
			_apply_contact_drive(segment.feet, lift, float(segment.mass), up)
		if _gallop_diagnostics.get("active",false):
			_gallop_diagnostics.segments.append({"id": id,"ground_support": grounded_support,"air_weight": air_support.weight,"drive": force,"support": segment.auxiliary_force})

func _get_contact_drive_body(foot: RigidBody3D) -> RigidBody3D:
	if not _chain_is_intact(foot): return null
	var bodies: Array = _chains[foot].bodies
	return _chains[foot].root

func calculate_torso_force() -> Vector3:
	# Diagnostics expose the actual distributed force, not the legacy displacement formula.
	return _last_torso_response_force

## Do not raise a torso beyond the reach of its non-stepping feet to the terrain.
func _limit_supported_torso_height(segment: Dictionary, requested: float, up: Vector3) -> float:
	var limit := requested
	for foot: RigidBody3D in segment.feet:
		if not _chain_is_intact(foot) or is_leg_stepping(foot): continue
		var hit := _get_surface_below_leg(foot, maxf(ray_length, surface_adhesion_probe_distance))
		if hit.is_empty(): continue
		var chain: Dictionary = _chains[foot]
		var attachment: Vector3 = chain.root.to_global(chain.anchor)
		var center_target := _body_position_for_ground_contact(foot, hit.position)
		var horizontal := (attachment - center_target).slide(up).length()
		var reach: float = chain.length * standing_chain_reach_ratio
		var vertical := sqrt(maxf(0.0, reach * reach - horizontal * horizontal))
		limit = minf(limit, Vector3(segment.torso_center).dot(up) + center_target.dot(up) + vertical - attachment.dot(up))
	# A transient sideways stretch must not command a standing segment to collapse.
	return maxf(limit, requested - float(segment.reference_height) * 0.15)

func _get_segment_spring_diagnostics() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for link: Dictionary in _segment_links:
		if is_instance_valid(link.joint) and link.joint.has_method("get_spring_diagnostics"):
			result.append(link.joint.get_spring_diagnostics())
	return result

func get_body_segment_diagnostics() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: int in _segments:
		var segment: Dictionary = _segments[id]
		result.append({"segment": id, "torso_count": segment.bodies.size(), "foot_count": segment.feet.size(), "mass": segment.mass, "center": segment.center, "reference_height": segment.reference_height, "balanced": segment.balanced, "movement_scale": segment.get("movement_scale",1.0), "support_blend": segment.support_blend, "auxiliary_force": segment.auxiliary_force, "balance_torque": segment.get("balance_torque", Vector3.ZERO), "balance_error_xy": segment.get("balance_error", Vector2.ZERO), "balance_error_z": segment.get("balance_error_z", 0.0), "balance_torque_limited": segment.get("balance_torque_limited", false)})
	return result

func _apply_ground_movement_brake(direction: Vector3) -> void:
	if not ground_movement_brake_enabled or not has_torso_movement_force_support(false): return
	var torsos := get_torso_parts()
	var mass := 0.0
	var velocity := Vector3.ZERO
	for body: RigidBody3D in torsos:
		mass += body.mass
		velocity += body.linear_velocity * body.mass
	if mass <= 0.0: return
	velocity = (velocity / mass).slide(Vector3.UP)
	var correction := -velocity
	if _planar_mode_active():
		var target := _planar_target_velocity()
		for axis: int in [0,2]:
			if not is_zero_approx(target[axis]): correction[axis] = -signf(target[axis])*maxf(velocity[axis]*signf(target[axis])-absf(target[axis]),0.0)
	elif not direction.is_zero_approx():
		var forward := direction.slide(Vector3.UP).normalized()
		correction = -velocity.slide(forward) - forward * maxf(velocity.dot(forward) - get_expected_horizontal_speed(), 0.0)
	var controlled_mass := 0.0
	for body: RigidBody3D in _character_body_cache:
		if is_instance_valid(body) and not _is_body_broken(body): controlled_mass += body.mass
	_ground_brake_force = (correction * maxf(controlled_mass, mass) * ground_brake_gain).limit_length(maximum_ground_brake_force)
	# A force intended to brake a whole body must not act only on an off-center reference Torso.
	for body: RigidBody3D in torsos:
		body.apply_central_force(_ground_brake_force * body.mass / mass)

func set_simplified_physics_mode(active: bool) -> void:
	if simplified_physics_mode == active: return
	simplified_physics_mode = active
	cancel_step(&"physics_test_mode_changed")
	_reset_contact_drive_diagnostics()
	for id: int in _segments:
		_segments[id].balance_torque = Vector3.ZERO
		_segments[id].auxiliary_force = 0.0
		_segments[id].support_blend = 0.0
	_last_auxiliary_support_force = Vector3.ZERO
	if active: set_recovery_control_active(false)

func set_recovery_control_active(active: bool) -> void:
	if recovery_control_active == active: return
	recovery_control_active = active
	if active:
		_reset_planar_slide_control()
		release_all_support_pins()
		_gallop_contacts.clear()
		_gallop_reach_released.clear()
		_gallop_diagnostics = {"active": false,"blocked": "recovery"}
	_turn_leg_forces.clear()
	_reset_contact_drive_diagnostics()
	_last_auxiliary_support_force = Vector3.ZERO
	for id: int in _segments:
		_segments[id].auxiliary_force = 0.0
		_segments[id].support_blend = 0.0
	cancel_step(&"physical_recovery")
	_support_anchors.clear()
	_support_forces.clear()
	_clear_leg_adhesion_surface_normals()
	_adhesion_forces.clear()
	_foot_alignment_torques.clear()
	_last_torso_response_force = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if _planar_mode_active():
		_update_planar_motion(delta)
		return
	_apply_passive_limb_damping()
	if recovery_control_active:
		_release_all_foot_heading_locks()
		_reset_contact_drive_diagnostics()
		_contact_drive_diagnostics["blocked"] = "recovery"
		_begin_ground_probe_frame()
		_remove_invalid_legs()
		_update_segment_metrics()
		if segment_balance_enabled and not simplified_physics_mode: _apply_segment_balance(delta)
		else: _update_segment_layout(delta)
		return
	_support_delta = delta
	var full_started := Time.get_ticks_usec() if _performance_tracking_enabled else 0
	var full_control_started: int = _movement_perf.start()
	var prior_total := _performance_total_usec
	if not is_instance_valid(_torso) or _is_body_broken(_torso):
		refresh_physics_query_cache()
		if _torso == null: return
	super._physics_process(delta)
	var stance_started: int = _movement_perf.start()
	_apply_stance_stabilization(delta)
	_movement_perf.finish(&"limb_stance", stance_started)
	if segment_balance_enabled and not simplified_physics_mode:
		_apply_segment_balance(delta)
	elif stabilize_torso_tilt and not simplified_physics_mode:
		var tilt_started: int = _movement_perf.start()
		_apply_torso_tilt_stabilization()
		_movement_perf.finish(&"torso_tilt", tilt_started)
	if simplified_physics_mode:
		# No active global attitude servo; preserve gait and contact-based turning commands.
		var source := get_player_command_source()
		if source != null and source.has_method("get_generated_facing_direction"):
			var direction: Vector3 = source.get_generated_facing_direction(delta)
			if not direction.is_zero_approx():
				_segment_goal_yaw = atan2(-direction.z, direction.x)
				_segment_target_yaw = _segment_goal_yaw
				_segment_heading_initialized = true
		_update_segment_layout(delta)
	elif not segment_balance_enabled: _update_segment_layout(delta)
	_update_foot_heading_constraints()
	if diagnostic_logging_enabled:
		_generated_diagnostic_elapsed += delta
		if _generated_diagnostic_elapsed >= diagnostic_log_interval:
			_generated_diagnostic_elapsed = 0.0
			print("[generated_gait] ", get_generated_movement_diagnostics())

	# Replace the parent's elapsed time with the inclusive generated update; keep its frame count.
	if _performance_tracking_enabled:
		var full_elapsed := Time.get_ticks_usec() - full_started
		_performance_total_usec = prior_total + full_elapsed
		_performance_max_usec = maxi(_performance_max_usec, full_elapsed)
	_movement_perf.finish(&"movement_generated_full", full_control_started)

func _exit_tree() -> void:
	_release_all_foot_heading_locks()
	super._exit_tree()

func _release_foot_heading_lock(foot: Variant) -> void:
	if not _foot_heading_previous_locks.has(foot): return
	if is_instance_valid(foot): foot.axis_lock_angular_y = bool(_foot_heading_previous_locks[foot])
	_foot_heading_previous_locks.erase(foot)

func _release_all_foot_heading_locks() -> void:
	for foot: Variant in _foot_heading_previous_locks.keys():
		_release_foot_heading_lock(foot)
	_foot_heading_diagnostics.clear()

func _foot_heading_turn_active() -> bool:
	if _turn_planning_active or _layout_turn_owned: return true
	var facing := get_parent().get_node_or_null("PhysicalFacingController3D")
	if facing != null and facing.has_method("is_turning") and facing.is_turning(): return true
	# Release as soon as a new heading is requested, before a turn step is scheduled.
	return _segment_heading_initialized and absf(wrapf(_segment_goal_yaw - _get_physical_heading_yaw(), -PI, PI)) > deg_to_rad(maxf(foot_heading_unlock_tolerance_degrees, foot_heading_lock_tolerance_degrees))

func _update_foot_heading_constraints() -> void:
	if _planar_mode_active():
		_foot_heading_diagnostics.clear()
		return
	_foot_heading_diagnostics.clear()
	for foot: Variant in _foot_heading_previous_locks.keys():
		if not is_instance_valid(foot) or not _legs.has(foot) or not _chain_is_intact(foot):
			_release_foot_heading_lock(foot)
	if not foot_heading_lock_enabled or recovery_control_active or _foot_heading_turn_active():
		_release_all_foot_heading_locks()
		return
	var target := _get_physical_heading_yaw()
	for foot: RigidBody3D in _legs:
		if not _chain_is_intact(foot) or foot.freeze or _is_body_broken(foot):
			_release_foot_heading_lock(foot)
			continue
		var forward := foot.global_basis.x.slide(Vector3.UP)
		if forward.is_zero_approx(): continue
		var yaw := atan2(-forward.z, forward.x)
		var error := wrapf(target - yaw, -PI, PI)
		var tolerance := deg_to_rad(foot_heading_lock_tolerance_degrees)
		var release_tolerance := deg_to_rad(maxf(foot_heading_unlock_tolerance_degrees, foot_heading_lock_tolerance_degrees))
		if not _foot_heading_previous_locks.has(foot):
			_foot_heading_previous_locks[foot] = foot.axis_lock_angular_y
		# Respect any independently configured Y lock.
		if bool(_foot_heading_previous_locks[foot]): continue
		var locked := (foot.axis_lock_angular_y and absf(error) <= release_tolerance) or (absf(error) <= tolerance and absf(foot.angular_velocity.y) <= deg_to_rad(2.0))
		foot.axis_lock_angular_y = locked
		var torque := Vector3.ZERO
		if not locked:
			var inverse := _stance_inverse_inertia(foot)
			var inverse_y := Vector3.UP.dot(inverse * Vector3.UP)
			if inverse_y > 0.000001:
				var acceleration := clampf(error * foot_heading_strength - foot.angular_velocity.y * foot_heading_damping, -foot_heading_maximum_acceleration, foot_heading_maximum_acceleration)
				torque = Vector3.UP * clampf(acceleration / inverse_y, -foot_heading_maximum_torque, foot_heading_maximum_torque)
				if not torque.is_zero_approx():
					foot.sleeping = false
					foot.apply_torque(torque)
		_foot_heading_diagnostics[foot] = {"state": &"locked" if locked else &"aligning", "target_degrees": rad_to_deg(target), "error_degrees": rad_to_deg(error), "torque": torque}

func _support_surface_contact(body: RigidBody3D) -> Dictionary:
	var hit := _get_surface_below_leg(body, ground_probe_distance)
	if hit.is_empty() or not _surface_is_walkable(hit.normal):
		_contact_states.erase(body)
		return {}
	var gap := (_get_foot_world_position(body) - Vector3(hit.position)).dot(Vector3(hit.normal))
	var threshold := maxf(support_contact_enter_distance, support_contact_exit_distance) if _contact_states.get(body, false) else support_contact_enter_distance
	if gap > threshold:
		_contact_states.erase(body)
		return {}
	_contact_states[body] = true
	return hit

func is_leg_grounded(leg: RigidBody3D) -> bool:
	return is_instance_valid(leg) and is_inside_tree() and not _support_surface_contact(leg).is_empty()

func _get_stance_chain_contact(foot: RigidBody3D) -> Dictionary:
	if not _chain_is_intact(foot): return {}
	var hit := _support_surface_contact(foot)
	if hit.is_empty(): return {}
	return {"body": foot, "index": 0, "position": hit.position, "normal": hit.normal}

func _stance_chain_can_support(foot: RigidBody3D) -> bool:
	return _adhesion_release_time_remaining <= 0.0 and not is_leg_stepping(foot) and _chain_is_intact(foot) and not _get_stance_chain_contact(foot).is_empty()

func _apply_stance_stabilization(delta: float) -> void:
	# Keep contact/load diagnostics, but intermediate links are entirely passive.
	_stance_last_applied_frame = Engine.get_physics_frames()
	_update_stance_allocation(delta)
	for foot: RigidBody3D in _chains:
		_chains[foot].stance_weight = 0.0
		_chains[foot].stance_torques = []
		_chains[foot].stance_torque_vectors = []

var _passive_hinge_rows: Array[Dictionary] = []
func _apply_passive_limb_damping() -> void:
	_passive_hinge_rows.clear()
	var configured: Variant = get_parent().get("limb_hinge_damping")
	var damping := maxf(float(configured) if configured != null else 3.0, 0.0)
	var seen: Array[RigidBody3D] = []
	for foot: RigidBody3D in _chains:
		if not _chain_is_intact(foot): continue
		var chain: Dictionary = _chains[foot]
		for index: int in range(1, chain.bodies.size() - 1):
			var body: RigidBody3D = chain.bodies[index]
			if body in seen or body.freeze or not _has_body_tag(body, LEG_LIMB_TAG): continue
			seen.append(body)
			var parent_body: RigidBody3D = chain.bodies[index + 1]
			var joint: Generic6DOFJoint3D = chain.joints[index]
			if not joint.has_meta(&"passive_hinge_axis_parent"):
				joint.set_meta(&"passive_hinge_axis_parent", parent_body.global_basis.inverse() * joint.global_basis.z.normalized())
			var axis: Vector3 = (parent_body.global_basis * Vector3(joint.get_meta(&"passive_hinge_axis_parent"))).normalized()
			var rate := (body.angular_velocity - parent_body.angular_velocity).dot(axis)
			var inverse := axis.dot(_stance_inverse_inertia(body) * axis)
			var torque := -axis * rate * damping / maxf(inverse, 0.000001)
			body.apply_torque(torque)
			_passive_hinge_rows.append({"body": body.name, "parent": parent_body.name, "relative_hinge_speed": rate, "damping": damping, "self_torque": torque, "other_part_commanded_torque": Vector3.ZERO})

func uses_passive_limb_links() -> bool:
	return true

func _calculate_simple_pose_torque(child: RigidBody3D, parent_body: RigidBody3D, rest: Quaternion, joint: Generic6DOFJoint3D) -> Vector3:
	var error := _stance_rotation_error(child, parent_body, rest)
	var velocity := child.angular_velocity - parent_body.angular_velocity
	var acceleration := error * simple_pose_strength - velocity * simple_pose_damping
	if _has_body_tag(child, LEG_LIMB_TAG) and _has_body_tag(parent_body, LEG_LIMB_TAG):
		var axis := joint.global_basis.z.normalized()
		acceleration = axis * acceleration.dot(axis)
	acceleration = acceleration.limit_length(simple_pose_acceleration_limit)
	var a := _stance_inverse_inertia(child)
	var b := _stance_inverse_inertia(parent_body)
	var inverse := Basis(a.x + b.x, a.y + b.y, a.z + b.z)
	return (inverse.inverse() * acceleration).limit_length(simple_pose_torque_limit) if absf(inverse.determinant()) > 1e-18 else Vector3.ZERO

func _stance_leg_side_released(body: RigidBody3D, other: RigidBody3D) -> bool:
	return (_has_body_tag(body, LEG_TAG) or _has_body_tag(body, FORELEG_TAG)) and _has_body_tag(other, LEG_LIMB_TAG)

func _apply_stance_joint_torque(_child: RigidBody3D, _parent_body: RigidBody3D, _torque: Vector3) -> void:
	# Compatibility entry point: never reactivate the removed cross-part servo.
	pass

func _stance_body_center(body: RigidBody3D) -> Vector3:
	return body.to_global(body.center_of_mass) if body.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM else body.global_position

func _gravity_acceleration() -> Vector3:
	if simplified_physics_mode: return Vector3.ZERO
	var direction: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
	return direction.normalized() * float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))

func _update_stance_allocation(delta: float) -> void:
	if not auto_allocate_stance_torque:
		_stance_support_weights.clear()
		_stance_joint_loads.clear()
		_stance_support_signature.clear()
		_stance_total_mass = 0.0
		_stance_center_of_mass = Vector3.ZERO
		_stance_support_balanced = false
		_stance_balance_error = 0.0
		return
	var supports: Array[RigidBody3D] = []
	var signature: Array[int] = []
	for foot: RigidBody3D in _legs:
		if _stance_chain_can_support(foot):
			supports.append(foot)
			signature.append(int(_get_stance_chain_contact(foot).body.get_instance_id()))
	_stance_allocation_elapsed += delta
	if signature == _stance_support_signature and _stance_allocation_elapsed < stance_allocation_interval: return
	var allocation_delta := _stance_allocation_elapsed
	var previous_loads := _stance_joint_loads.duplicate()
	_stance_allocation_elapsed = 0.0
	_stance_last_allocation_frame = Engine.get_physics_frames()
	_stance_support_signature = signature
	_stance_support_weights.clear()
	_stance_joint_loads.clear()
	_stance_total_mass = 0.0
	_stance_center_of_mass = Vector3.ZERO
	# Include equipped bodies underneath the character, but not frozen inventory items.
	for node: Node in get_parent().find_children("*", "RigidBody3D", true, false):
		var body := node as RigidBody3D
		if body.freeze or body.is_queued_for_deletion() or _is_body_broken(body): continue
		_stance_total_mass += body.mass
		_stance_center_of_mass += _stance_body_center(body) * body.mass
	if _stance_total_mass > 0.0: _stance_center_of_mass /= _stance_total_mass
	_stance_support_balanced = false
	_stance_balance_error = 0.0
	for id: int in _segments: _segments[id].balanced = false
	if supports.is_empty(): return
	var gravity := _gravity_acceleration()
	var up := -gravity.normalized() if not gravity.is_zero_approx() else Vector3.UP
	var contacts: Array[Vector3] = []
	for foot: RigidBody3D in supports:
		var contact := _get_stance_chain_contact(foot)
		contacts.append(contact.position)
	var weights := PackedFloat64Array()
	weights.resize(supports.size())
	weights.fill(0.0)
	var groups: Dictionary = {}
	for index: int in range(supports.size()):
		var foot: RigidBody3D = supports[index]
		var id := int(_chains[foot].root.get_meta(&"body_segment_id", 0))
		id = _connected_body_segments(id).min()
		if not groups.has(id): groups[id] = {"indices": [], "mass": 0.0, "center": Vector3.ZERO, "auxiliary": 0.0}
		groups[id].indices.append(index)
	# Pool the support polygon only across live, connected segment links.
	for id: int in _segments:
		var segment: Dictionary = _segments[id]
		var owner: int = _connected_body_segments(id).min()
		if not groups.has(owner): continue
		groups[owner].mass += segment.mass
		groups[owner].center += Vector3(segment.center) * float(segment.mass)
		groups[owner].auxiliary += segment.auxiliary_force
	var known_mass := 0.0
	for id: int in groups: known_mass += groups[id].mass
	var total_reaction := maxf(0.0, _stance_total_mass * gravity.length() - (_last_torso_response_force + _last_auxiliary_support_force).dot(up))
	var reaction_sum := 0.0
	_stance_support_balanced = true
	for id: int in groups:
		var group: Dictionary = groups[id]
		var center: Vector3 = group.center / maxf(group.mass, 0.01)
		var local_contacts: Array[Vector3] = []
		for index: int in group.indices: local_contacts.append(contacts[index])
		var local_weights := _solve_stance_support_weights(local_contacts, center, up)
		var projected := Vector3.ZERO
		for index: int in range(local_contacts.size()): projected += local_contacts[index] * local_weights[index]
		var error := (projected - center).slide(up).length()
		var balanced := error <= stance_balance_tolerance
		for member: int in _connected_body_segments(id): _segments[member].balanced = balanced
		_stance_support_balanced = _stance_support_balanced and balanced
		_stance_balance_error = maxf(_stance_balance_error, error)
		var reaction: float = maxf(0.0, _stance_total_mass * gravity.length() * group.mass / maxf(known_mass, 0.01) - group.auxiliary)
		reaction_sum += reaction
		for index: int in range(group.indices.size()): weights[group.indices[index]] = local_weights[index] * reaction
	for index: int in range(weights.size()): weights[index] /= maxf(reaction_sum, 0.01)
	for index: int in range(supports.size()):
		var foot: RigidBody3D = supports[index]
		_stance_support_weights[foot] = weights[index]
		# Torso feedback already carries part of the body's weight. Estimating
		# full weight again would command excessive ankle/hip compensation.
		var reaction := total_reaction
		var force := up * reaction * weights[index]
		var chain: Dictionary = _chains[foot]
		for joint_index: int in range(chain.joints.size()):
			var joint: Generic6DOFJoint3D = chain.joints[joint_index]
			var contact_index: int = _get_stance_chain_contact(foot).index
			# Only joints between the contact and Torso carry the ground reaction.
			var external := (contacts[index] - joint.global_position).cross(force) if joint_index >= contact_index else Vector3.ZERO
			for body_index: int in range(joint_index + 1):
				var body: RigidBody3D = chain.bodies[body_index]
				external += (_stance_body_center(body) - joint.global_position).cross(gravity * body.mass)
			var desired_load := -external
			var blend := 1.0 if support_load_smoothing_time <= 0.0 else 1.0 - exp(-allocation_delta / support_load_smoothing_time)
			_stance_joint_loads[joint] = Vector3(previous_loads.get(joint, desired_load)).lerp(desired_load, blend)

## Constrained least-squares COM projection; weights stay nonnegative and sum to one.
## Vertical reactions approximate standable terrain, not a full friction-cone solver.
func _solve_stance_support_weights(contacts: Array[Vector3], center: Vector3, up: Vector3) -> PackedFloat64Array:
	var weights := PackedFloat64Array()
	if contacts.is_empty(): return weights
	weights.resize(contacts.size())
	weights.fill(1.0 / float(contacts.size()))
	var offsets: Array[Vector3] = []
	var bound := 0.0
	for contact: Vector3 in contacts:
		var offset := (contact - center).slide(up)
		offsets.append(offset)
		bound += offset.length_squared()
	var regularization := maxf(bound * 0.00001, 0.000001)
	var rate := 0.5 / maxf(bound + regularization, 0.000001)
	for iteration: int in range(64):
		var residual := Vector3.ZERO
		for index: int in range(weights.size()): residual += offsets[index] * weights[index]
		var next := weights.duplicate()
		for index: int in range(weights.size()):
			next[index] -= rate * (offsets[index].dot(residual) + regularization * (weights[index] - 1.0 / float(weights.size())))
		weights = _project_stance_weights(next)
	return weights

func _project_stance_weights(values: PackedFloat64Array) -> PackedFloat64Array:
	var ordered := values.duplicate()
	ordered.sort()
	ordered.reverse()
	var sum := 0.0
	var threshold := 0.0
	for index: int in range(ordered.size()):
		sum += ordered[index]
		var candidate := (sum - 1.0) / float(index + 1)
		if ordered[index] > candidate: threshold = candidate
	var result := values.duplicate()
	for index: int in range(values.size()): result[index] = maxf(values[index] - threshold, 0.0)
	return result

func _calculate_allocated_stance_torque(child: RigidBody3D, parent_body: RigidBody3D, rest: Quaternion, load: Vector3, weight: float) -> Vector3:
	var child_inverse := _stance_inverse_inertia(child)
	var parent_inverse := _stance_inverse_inertia(parent_body)
	var inverse := Basis(child_inverse.x + parent_inverse.x, child_inverse.y + parent_inverse.y, child_inverse.z + parent_inverse.z)
	if absf(inverse.determinant()) < 1e-18: return Vector3.ZERO
	var inertia := inverse.inverse()
	var axes := parent_body.global_basis.orthonormalized()
	var rotation_error := _stance_rotation_error(child, parent_body, rest)
	var relative_velocity := child.angular_velocity - parent_body.angular_velocity
	var correction := Vector3.ZERO
	var allowance := deg_to_rad(maxf(stance_allowed_deformation_degrees, 0.5))
	for axis: Vector3 in [axes.x, axes.y, axes.z]:
		var effective_inertia := maxf(axis.dot(inertia * axis), 0.000001)
		var stiffness := maxf(effective_inertia * stance_strength, absf(load.dot(axis)) / allowance)
		var damping := maxf(effective_inertia * stance_damping, 2.0 * stance_damping_ratio * sqrt(stiffness * effective_inertia))
		correction += axis * (stiffness * rotation_error.dot(axis) - damping * relative_velocity.dot(axis))
	# Limit pose correction separately: static weight compensation must not be
	# attenuated by an angular acceleration limit intended for pose recovery.
	var acceleration := (inverse * correction).limit_length(maximum_stance_acceleration)
	var raw := (load + inertia * acceleration) * weight
	var allocated_limit := maxf(minimum_stance_torque, load.length() * stance_load_safety_factor + stance_dynamic_torque_reserve)
	return raw.limit_length(minf(maximum_stance_torque, allocated_limit))

func _stance_rotation_error(child: RigidBody3D, parent_body: RigidBody3D, rest: Quaternion) -> Vector3:
	var child_rotation := child.global_basis.orthonormalized().get_rotation_quaternion()
	var parent_rotation := parent_body.global_basis.orthonormalized().get_rotation_quaternion()
	var error := (parent_rotation * rest * child_rotation.inverse()).normalized()
	if error.w < 0.0: error = -error
	var vector := Vector3(error.x, error.y, error.z)
	return vector.normalized() * (2.0 * atan2(vector.length(), error.w))

func _calculate_stance_torque(child: RigidBody3D, parent_body: RigidBody3D, rest: Quaternion) -> Vector3:
	var rotation_error := _stance_rotation_error(child, parent_body, rest)
	var relative_velocity := child.angular_velocity - parent_body.angular_velocity
	var acceleration := (rotation_error * stance_strength - relative_velocity * stance_damping).limit_length(maximum_stance_acceleration)
	var child_inverse := _stance_inverse_inertia(child)
	var parent_inverse := _stance_inverse_inertia(parent_body)
	var inverse_inertia := Basis(child_inverse.x + parent_inverse.x, child_inverse.y + parent_inverse.y, child_inverse.z + parent_inverse.z)
	if absf(inverse_inertia.determinant()) < 1e-18: return Vector3.ZERO
	return (inverse_inertia.inverse() * acceleration).limit_length(maximum_stance_torque)

func _stance_inverse_inertia(body: RigidBody3D) -> Basis:
	if body.freeze: return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var size: Vector3 = body.get_meta(&"generated_size", Vector3.ONE)
	var inertia := Vector3(size.y * size.y + size.z * size.z, size.x * size.x + size.z * size.z, size.x * size.x + size.y * size.y) * body.mass / 12.0
	var inverse := Vector3(1.0 / maxf(inertia.x, 0.000001), 1.0 / maxf(inertia.y, 0.000001), 1.0 / maxf(inertia.z, 0.000001))
	var axes := body.global_basis.orthonormalized()
	return axes * Basis(Vector3(inverse.x, 0, 0), Vector3(0, inverse.y, 0), Vector3(0, 0, inverse.z)) * axes.transposed()

## Optional command source for generated characters without PhysicalFacingController3D.
func set_segment_facing_direction(direction: Vector3) -> void:
	if direction.slide(Vector3.UP).is_zero_approx(): return
	_segment_goal_yaw = atan2(-direction.z, direction.x)

## Share one heading frame across all links; cap its advance during a turn.
func _update_segment_layout(delta: float) -> void:
	var direction := Vector3.ZERO
	for body: RigidBody3D in get_torso_parts():
		if not _is_body_broken(body): direction += body.global_basis.x.slide(Vector3.UP).normalized() * body.mass
	var actual_yaw := atan2(-direction.z, direction.x) if not direction.is_zero_approx() else _segment_layout_yaw
	if not _segment_layout_initialized:
		_segment_layout_yaw = actual_yaw
		_segment_layout_initialized = true
	if segment_layout_enabled: actual_yaw = _get_actual_layout_yaw(actual_yaw)
	var target_yaw := _segment_target_yaw if _segment_heading_initialized else actual_yaw
	var lead := deg_to_rad(_motion_setting("turn_lead", segment_layout_heading_lead_degrees))
	var advance := clampf(wrapf(target_yaw - actual_yaw, -PI, PI), -lead, lead)
	var turn_sign := signf(advance)
	for body: RigidBody3D in get_torso_parts():
		if _is_body_broken(body): continue
		var body_yaw := atan2(-body.global_basis.x.z, body.global_basis.x.x)
		var allowance := maxf(0.0, turn_sign * wrapf(body_yaw - actual_yaw, -PI, PI) + lead)
		advance = turn_sign * minf(absf(advance), allowance)
	var goal := actual_yaw + advance
	var change := clampf(wrapf(goal - _segment_layout_yaw, -PI, PI), -deg_to_rad(_motion_setting("turning_speed_degrees", segment_layout_turn_speed_degrees)) * delta, deg_to_rad(_motion_setting("turning_speed_degrees", segment_layout_turn_speed_degrees)) * delta)
	_segment_layout_yaw = wrapf(_segment_layout_yaw + change, -PI, PI)
	for link: Dictionary in _segment_links:
		if is_instance_valid(link.joint) and link.joint.has_method("set_layout_reference"):
			link.joint.set_layout_reference(actual_yaw, 0.0, false, segment_layout_frequency, segment_layout_damping_ratio, segment_layout_maximum_acceleration)
	_update_layout_turn_steps(delta)

func _get_physical_heading_yaw() -> float:
	var direction := Vector3.ZERO
	for body: RigidBody3D in get_torso_parts():
		if not _is_body_broken(body): direction += body.global_basis.x.slide(Vector3.UP).normalized() * body.mass
	return atan2(-direction.z, direction.x) if not direction.is_zero_approx() else _segment_layout_yaw

func _get_physical_yaw_rate() -> float:
	var mass := 0.0
	var weighted := 0.0
	for body: RigidBody3D in get_torso_parts():
		if _is_body_broken(body): continue
		mass += body.mass
		weighted += body.angular_velocity.y * body.mass
	return weighted / maxf(mass, 0.001)

func _get_maximum_heading_error(target: float) -> float:
	var error := 0.0
	for body: RigidBody3D in get_torso_parts():
		if _is_body_broken(body): continue
		var actual := atan2(-body.global_basis.x.z, body.global_basis.x.x)
		error = maxf(error, absf(wrapf(target - actual, -PI, PI)))
	return error

func _get_actual_layout_yaw(fallback: float) -> float:
	var cosine := 0.0
	var sine := 0.0
	for link: Dictionary in _get_segment_spring_diagnostics():
		if not link.valid or link.distance <= 0.0: continue
		var rest: Vector3 = link.rest_offset
		var current: Vector3 = link.layout_error + Basis(Vector3.UP, deg_to_rad(link.layout_yaw_degrees)) * rest
		cosine += rest.x * current.x + rest.z * current.z
		sine += rest.z * current.x - rest.x * current.z
	return atan2(sine, cosine) if absf(cosine) + absf(sine) > 0.000001 else fallback

## Turn via grounded leg actuation. The layout frame plans targets but never drives spring yaw.
func _update_layout_turn_steps(delta: float) -> void:
	if _planar_mode_active():
		_turn_leg_forces.clear()
		_turn_drive_diagnostics = {"blocked": &"planar_mode"}
		_layout_turn_owned = false
		_layout_turn_status = &"planar_mode"
		set_turn_planning_active(false)
		return
	_layout_turn_retry = maxf(0.0, _layout_turn_retry - delta)
	_turn_leg_forces.clear()
	_turn_drive_diagnostics = {"blocked": &"support_or_disabled"}
	var facing := get_parent().get_node_or_null("PhysicalFacingController3D")
	var external_turn: bool = facing != null and facing.has_method("is_turning") and facing.is_turning()
	if (_automatic_motion_enabled() and _get_gait_data().turning_speed_degrees <= 0.0) or not segment_layout_enabled or not segment_layout_turn_steps_enabled or recovery_control_active or external_turn:
		if _layout_turn_owned:
			if not external_turn: set_turn_planning_active(false)
			_layout_turn_owned = false
		_layout_turn_status = &"external_or_disabled"
		return
	var grounded_feet := 0
	for foot: RigidBody3D in _legs:
		if _chain_is_intact(foot) and is_leg_grounded(foot): grounded_feet += 1
	if grounded_feet == 0:
		if _layout_turn_owned:
			if not _resource_turn_blending_enabled(): cancel_step(&"turn_lost_ground")
			set_turn_planning_active(false)
			_layout_turn_owned = false
		_layout_turn_status = &"waiting_for_ground"
		return
	var supported_segments := true
	for id: int in _segments:
		if _segments[id].feet.is_empty(): continue
		var supported := false
		for foot: RigidBody3D in _segments[id].feet:
			if _chain_is_intact(foot) and is_leg_grounded(foot): supported = true
		if not supported: supported_segments = false
	if grounded_feet < maxi(1, ceili(_legs.size() * turn_minimum_grounded_ratio)) or not supported_segments:
		if _layout_turn_owned:
			if not _resource_turn_blending_enabled(): cancel_step(&"turn_support_insufficient")
			set_turn_planning_active(false)
			_layout_turn_owned = false
		_layout_turn_status = &"waiting_for_support"
		return
	# Continue stance-driven formation and heading support after releasing gait ownership.
	_apply_grounded_turn_traction()
	var actual_yaw := _get_actual_layout_yaw(_get_physical_heading_yaw())
	var error := wrapf(_segment_layout_yaw - actual_yaw, -PI, PI)
	var heading_error := _get_maximum_heading_error(_segment_target_yaw)
	var heading_tolerance := deg_to_rad(segment_layout_heading_tolerance_degrees * (1.0 if _layout_turn_owned else 1.5))
	if absf(error) < deg_to_rad(5.0) and heading_error < heading_tolerance:
		if _layout_turn_owned:
			set_turn_planning_active(false)
			_layout_turn_owned = false
		_layout_turn_status = &"aligned"
		return
	if _layout_turn_retry > 0.0: return
	if not _layout_turn_owned:
		_layout_turn_elapsed = 0.0
		_layout_turn_stagnant = 0.0
		_layout_turn_best_error = INF
		_layout_turn_goal_yaw = _segment_target_yaw
		set_turn_planning_active(true)
		_layout_turn_owned = true
	_layout_turn_elapsed += delta
	_layout_turn_stagnant += delta
	var goal_error := maxf(heading_error, absf(wrapf(_segment_target_yaw - actual_yaw, -PI, PI)))
	if absf(wrapf(_segment_target_yaw - _layout_turn_goal_yaw, -PI, PI)) > 0.0001:
		_layout_turn_goal_yaw = _segment_target_yaw
		_layout_turn_best_error = goal_error
		_layout_turn_stagnant = 0.0
	if goal_error < _layout_turn_best_error - deg_to_rad(1.0):
		_layout_turn_best_error = goal_error
		_layout_turn_stagnant = 0.0
	if _layout_turn_elapsed >= _motion_setting("turn_timeout", segment_layout_turn_timeout) or _layout_turn_stagnant >= 4.0:
		if not _resource_turn_blending_enabled(): cancel_step(&"layout_turn_stalled")
		set_turn_planning_active(false)
		_layout_turn_owned = false
		_layout_turn_retry = 1.0
		_layout_turn_status = &"stalled_retry"
		return
	_layout_turn_status = &"turning"
	if _resource_turn_blending_enabled(): return
	if get_step_state() != StepState.IDLE or _adhesion_release_time_remaining > 0.0 or _legs.is_empty(): return
	var center := Vector3.ZERO
	var mass := 0.0
	for body: RigidBody3D in get_torso_parts():
		center += body.global_position * body.mass
		mass += body.mass
	center /= maxf(mass, 0.001)
	var step_angle := clampf(error, -deg_to_rad(_motion_setting("turn_step_angle", segment_layout_step_angle_degrees)), deg_to_rad(_motion_setting("turn_step_angle", segment_layout_step_angle_degrees)))
	for offset: int in range(_legs.size()):
		var index := (_layout_turn_cursor + offset) % _legs.size()
		var foot: RigidBody3D = _legs[index]
		if not foot.has_meta(&"generated_layout_foot_offset") or not _chain_is_intact(foot): continue
		var desired := center + Basis(Vector3.UP, actual_yaw + step_angle) * Vector3(foot.get_meta(&"generated_layout_foot_offset"))
		var maximum_step: float = minf(float(_chains[foot].length) * 0.2, maxf(0.1, (foot.global_position - center).slide(Vector3.UP).length() * absf(step_angle)))
		var sample := foot.global_position + (desired - foot.global_position).slide(Vector3.UP).limit_length(maximum_step)
		var foot_yaw_error := absf(wrapf(_segment_layout_yaw - atan2(-foot.global_basis.x.z, foot.global_basis.x.x), -PI, PI))
		var root_body: RigidBody3D = _chains[foot].root
		var root_yaw_error := absf(wrapf(_segment_layout_yaw - atan2(-root_body.global_basis.x.z, root_body.global_basis.x.x), -PI, PI))
		if (sample - foot.global_position).slide(Vector3.UP).length() < 0.05 and foot_yaw_error < deg_to_rad(5.0) and root_yaw_error < deg_to_rad(5.0): continue
		var segment_id := int(_chains[foot].root.get_meta(&"body_segment_id", 0))
		var other_support := false
		for other: RigidBody3D in _segments[segment_id].feet:
			if other != foot and _chain_is_intact(other) and is_leg_grounded(other): other_support = true
		if _segments[segment_id].feet.size() > 1 and not other_support: continue
		if try_start_turn_step(foot, sample, _motion_setting("turn_step_duration", segment_layout_step_duration, foot), _motion_setting("turn_lift", _get_effective_step_height(), foot)):
			_layout_turn_cursor = (index + 1) % _legs.size()
			_layout_turn_target = sample
			return
	_layout_turn_status = &"landing_rejected"

## Grounded feet authorize force application at their Torso attachments.
## LegLimb links remain passive; release this drive as soon as the sole lifts.
func _apply_grounded_turn_traction() -> void:
	if _planar_mode_active(): return
	_turn_drive_diagnostics = {"blocked": &"no_stance_contact"}
	var bodies := get_torso_parts()
	var center := Vector3.ZERO
	var mass := 0.0
	for body: RigidBody3D in bodies:
		if _is_body_broken(body): continue
		center += body.global_position * body.mass
		mass += body.mass
	if mass <= 0.0: return
	center /= mass
	var feet: Array[RigidBody3D] = []
	var levers: Array[Vector3] = []
	var radius_sum := 0.0
	for foot: RigidBody3D in _legs:
		if not _chain_is_intact(foot) or is_leg_stepping(foot) or not is_leg_grounded(foot): continue
		var chain: Dictionary = _chains[foot]
		var lever: Vector3 = (chain.root.to_global(chain.anchor) - center).slide(Vector3.UP)
		feet.append(foot)
		levers.append(lever)
		radius_sum += lever.length_squared()
	if feet.is_empty() or radius_sum < 0.01: return
	var inertia := 0.0
	for body: RigidBody3D in bodies:
		if _is_body_broken(body): continue
		var inverse := _stance_inverse_inertia(body)
		if absf(inverse.determinant()) > 1e-18:
			inertia += Vector3.UP.dot(inverse.inverse() * Vector3.UP) + body.mass * (body.global_position - center).slide(Vector3.UP).length_squared()
	var error := wrapf(_segment_goal_yaw - _get_physical_heading_yaw(), -PI, PI)
	if absf(error) > deg_to_rad(175.0): error = -absf(error) if cos(_segment_goal_yaw) < 0.0 else absf(error)
	var limit_rate := deg_to_rad(_motion_setting("turning_speed_degrees", segment_heading_speed_degrees))
	var requested_rate := clampf(error * _motion_setting("turn_gain", turn_leg_yaw_gain), -limit_rate, limit_rate)
	var actual_rate := _get_physical_yaw_rate()
	var acceleration := clampf((requested_rate - actual_rate) * _motion_setting("turn_damping", turn_leg_yaw_damping), -maxf(limit_rate * 8.0,1.0), maxf(limit_rate * 8.0,1.0))
	var torque := inertia * acceleration
	if not _automatic_motion_enabled(): torque = clampf(torque,-turn_leg_yaw_torque_limit,turn_leg_yaw_torque_limit)
	var forces: Array[Vector3] = []
	var scale := 1.0
	var force_limit := mass * _motion_setting("turn_acceleration",turn_leg_yaw_maximum_acceleration) / feet.size()
	for lever: Vector3 in levers:
		var force := Vector3.UP.cross(lever) * torque / radius_sum
		forces.append(force)
		scale = minf(scale,force_limit / maxf(force.length(),0.000001))
	var net_force := Vector3.ZERO
	for index: int in range(feet.size()):
		var driver: RigidBody3D = _chains[feet[index]].root
		var force := forces[index] * scale
		var anchor: Vector3 = driver.to_global(_chains[feet[index]].anchor)
		driver.apply_force(force, anchor - driver.global_position)
		net_force += force
		_turn_leg_forces[feet[index]] = force
	# Contact-authorized yaw must not alter walking velocity. Mass-weighted cancellation
	# at the body centers has zero net moment about the shared center of mass.
	for body: RigidBody3D in bodies:
		if not _is_body_broken(body): body.apply_central_force(-net_force * body.mass / mass)
	_turn_drive_diagnostics = {"blocked": &"", "stance_feet": feet.size(), "requested_rate_degrees": rad_to_deg(requested_rate), "actual_rate_degrees": rad_to_deg(actual_rate), "yaw_inertia": inertia, "requested_torque": torque, "applied_torque": torque * scale, "force_scale": scale, "force_limited": scale < 0.999, "net_force_cancelled": net_force, "global_allocation": true}

func _resource_turn_blending_enabled() -> bool:
	return _get_gait_data() != null

func _has_resource_step_demand(direction: Vector3) -> bool:
	if _gallop_updating_group: return false
	return _layout_turn_owned or super._has_resource_step_demand(direction)

func _get_expected_horizontal_speed() -> float:
	if _planar_mode_active() and _get_gait_data() != null:
		var direction := get_input_movement_direction()
		if is_zero_approx(direction.x) and not is_zero_approx(direction.z): return maxf(_get_gait_data().target_speed,0.0)
	if _gallop_active(): return _get_gait_data().target_speed
	# Turning changes the shared event rate, not the configured walking speed.
	if _layout_turn_owned and _get_gait_data() != null and not _automatic_motion_enabled():
		return _get_gait_step_distance() * super.get_planned_step_frequency()
	return super._get_expected_horizontal_speed()

func get_planned_step_frequency() -> float:
	if _gallop_active() and _get_gait_data().speed_based_gait and not _legs.is_empty():
		var plan := _get_speed_leg_plan(_legs[0])
		if not plan.is_empty(): return float(plan.total_frequency)
	if not _layout_turn_owned: return super.get_planned_step_frequency()
	var duration := _motion_setting("turn_step_duration",segment_layout_step_duration)
	var frequency := get_maximum_stepping_feet() / maxf(duration + 0.04,0.01)
	var data := _get_gait_data()
	if data != null and data.automatic_motion and data.maximum_step_frequency > 0.0: frequency = minf(frequency,data.maximum_step_frequency)
	return frequency

func _can_start_step_with_support(leg: RigidBody3D) -> bool:
	if _gallop_active():
		var flight := _gallop_flight_available()
		var capacity := _automatic_flight_capacity() if _get_gait_data().speed_based_gait else _get_gait_data().calculate_gallop_capacity(_legs.size(),flight)
		if is_leg_stepping(leg) or _active_steps.size() >= capacity: return false
		var grounded := 0
		for other: RigidBody3D in _legs:
			if other != leg and not is_leg_stepping(other) and is_leg_grounded(other): grounded += 1
		# All-air starts require a lease from real ground. An expired lease never
		# authorizes a new launch, even with minimum_support_feet set to zero.
		return grounded >= (1 if _get_gait_data().speed_based_gait else maxi(_get_gait_data().gallop_minimum_support_feet,1)) or (_get_gait_data().gallop_allow_all_feet_airborne and (_get_gait_data().speed_based_gait or _get_gait_data().gallop_minimum_support_feet == 0) and flight)
	if not super._can_start_step_with_support(leg): return false
	if not _layout_turn_owned: return true
	var id := int(_chains[leg].root.get_meta(&"body_segment_id",0))
	for other: RigidBody3D in _segments[id].feet:
		if other != leg and _chain_is_intact(other) and not is_leg_stepping(other) and is_leg_grounded(other): return true
	return _segments[id].feet.size() <= 1

func try_start_step(movement_direction: Vector3 = Vector3.RIGHT) -> bool:
	if _gallop_active() or not _layout_turn_owned or not _resource_turn_blending_enabled(): return _try_start_walk_step(movement_direction)
	if _legs.is_empty(): return false
	var foot: RigidBody3D = _legs[_next_leg_index % _legs.size()]
	if is_leg_stepping(foot) or not _can_start_step_with_support(foot): return false
	var center := Vector3.ZERO
	var mass := 0.0
	for body: RigidBody3D in get_torso_parts():
		if _is_body_broken(body): continue
		center += body.global_position * body.mass
		mass += body.mass
	center /= maxf(mass,0.001)
	var yaw := _get_physical_heading_yaw()
	var error := wrapf(_segment_goal_yaw - yaw,-PI,PI)
	if absf(error) > deg_to_rad(175.0): error = -absf(error) if cos(_segment_goal_yaw) < 0.0 else absf(error)
	var rate := clampf(error * _motion_setting("turn_gain",turn_leg_yaw_gain),-deg_to_rad(_motion_setting("turning_speed_degrees",segment_heading_speed_degrees)),deg_to_rad(_motion_setting("turning_speed_degrees",segment_heading_speed_degrees)))
	var cycle := _legs.size() / maxf(get_planned_step_frequency(),0.01)
	var angle := clampf(rate * cycle,-deg_to_rad(40.0),deg_to_rad(40.0))
	var duration := _motion_setting("turn_step_duration",segment_layout_step_duration,foot)
	var lead := movement_direction.slide(Vector3.UP) * get_expected_horizontal_speed() * duration
	var desired := center + lead + Basis(Vector3.UP,yaw + angle) * Vector3(foot.get_meta(&"generated_layout_foot_offset",Vector3.ZERO))
	var maximum_step: float = float(_chains[foot].length) * 0.45
	var sample := foot.global_position + (desired - foot.global_position).slide(Vector3.UP).limit_length(maximum_step)
	if not try_start_turn_step(foot,sample,duration,_motion_setting("turn_lift",_get_effective_step_height(),foot)):
		_turn_landing_rejections[foot.name] = _last_landing_rejection_reason
		return false
	_current_step.extra["generated_turn_step"] = true
	_current_step.extra["turn_swing_yaw"] = yaw + angle
	_current_step.direction = movement_direction
	_automatic_next_steps[foot] = _physics_elapsed + cycle
	_layout_turn_target = sample
	_turn_landing_rejections.erase(foot.name)
	return true

## Apply one inertia-scaled attitude servo per rigid segment.
func _apply_segment_balance(delta: float) -> void:
	if not is_instance_valid(_torso): return
	var yaw := _segment_goal_yaw if _segment_heading_initialized else _torso.global_rotation.y
	var facing := get_parent().get_node_or_null("PhysicalFacingController3D")
	var source := get_player_command_source()
	if source != null and source.has_method("get_generated_facing_direction"):
		var command: Vector3 = source.get_generated_facing_direction(delta)
		if not command.is_zero_approx(): yaw = atan2(-command.z, command.x)
	if facing != null and facing.has_method("get_target_facing_direction"):
		var direction: Vector3 = facing.get_target_facing_direction()
		if not direction.slide(Vector3.UP).is_zero_approx(): yaw = atan2(-direction.z, direction.x)
	if not _segment_heading_initialized:
		_segment_target_yaw = _torso.global_rotation.y
		_segment_goal_yaw = yaw
		_segment_heading_initialized = true
	if _planar_mode_active(): yaw = _torso.global_rotation.y
	_segment_goal_yaw = yaw
	var heading_change := wrapf(yaw - _segment_target_yaw, -PI, PI)
	# A 180-degree request must not choose its turn side from tiny solver yaw noise.
	if absf(heading_change) > deg_to_rad(175.0): heading_change = -absf(heading_change) if cos(yaw) < 0.0 else absf(heading_change)
	_segment_target_yaw += clampf(heading_change, -deg_to_rad(_motion_setting("turning_speed_degrees", segment_heading_speed_degrees)) * delta, deg_to_rad(_motion_setting("turning_speed_degrees", segment_heading_speed_degrees)) * delta)
	_update_segment_layout(delta)
	# Roll/pitch balance follows the measured body frame, never the commanded yaw.
	var measured_forward := Vector3.ZERO
	for body: RigidBody3D in get_torso_parts():
		if not _is_body_broken(body): measured_forward += body.global_basis.x.slide(Vector3.UP).normalized() * body.mass
	var measured_yaw := atan2(-measured_forward.z, measured_forward.x) if not measured_forward.is_zero_approx() else 0.0
	var reference := Basis(Vector3.UP, measured_yaw)
	for id: int in _segments:
		var segment: Dictionary = _segments[id]
		var mass := 0.0
		var center := Vector3.ZERO
		var velocity := Vector3.ZERO
		var error := Vector3.ZERO
		var bodies: Array[RigidBody3D] = []
		for body: RigidBody3D in segment.bodies:
			if not is_instance_valid(body) or body.freeze or _is_body_broken(body): continue
			bodies.append(body)
			mass += body.mass
			center += _stance_body_center(body) * body.mass
			velocity += body.angular_velocity * body.mass
			var rotation := (reference.get_rotation_quaternion() * body.global_basis.orthonormalized().get_rotation_quaternion().inverse()).normalized()
			if rotation.w < 0.0: rotation = -rotation
			var vector := Vector3(rotation.x, rotation.y, rotation.z)
			error += vector.normalized() * (2.0 * atan2(vector.length(), rotation.w)) * body.mass
		if mass <= 0.0: continue
		center /= mass
		velocity /= mass
		error /= mass
		var acceleration := Vector3.ZERO
		for component: int in range(2):
			var axis: Vector3 = reference.x if component == 0 else reference.y
			# Heading is driven only by foot forces through the limb joints.
			if component == 1 or _planar_mode_active(): continue
			var gain := segment_x_balance_strength
			var damping := 2.0 * segment_balance_damping_ratio * sqrt(gain)
			acceleration += axis * (error.dot(axis) * gain - velocity.dot(axis) * damping)
		acceleration += reference.z * (error.dot(reference.z) * segment_z_balance_strength - velocity.dot(reference.z) * segment_z_angular_damping)
		acceleration = acceleration.slide(Vector3.UP).limit_length(segment_balance_acceleration_limit)
		var torques: Array[Vector3] = []
		var forces: Array[Vector3] = []
		var total := Vector3.ZERO
		for body: RigidBody3D in bodies:
			var size: Vector3 = body.get_meta(&"generated_size", Vector3.ONE)
			var diagonal := Vector3(size.y * size.y + size.z * size.z, size.x * size.x + size.z * size.z, size.x * size.x + size.y * size.y) * body.mass / 12.0
			var basis := body.global_basis.orthonormalized()
			var offset := _stance_body_center(body) - center
			# Parallel-axis inertia comes from tangential forces, not oversized local torques.
			# This produces the requested segment moment without twisting its internal joints.
			var torque := basis * (diagonal * (basis.inverse() * acceleration))
			var force := body.mass * acceleration.cross(offset)
			torques.append(torque)
			forces.append(force)
			total += torque + offset.cross(force)
		var scale := minf(1.0, segment_balance_torque_limit / maxf(total.length(), 0.0001))
		for index: int in range(bodies.size()):
			bodies[index].apply_torque(torques[index] * scale)
			bodies[index].apply_central_force(forces[index] * scale)
		segment.balance_torque = total * scale
		segment.balance_error = Vector2(error.dot(reference.x), error.dot(reference.y))
		segment.balance_error_z = error.dot(reference.z)
		segment.balance_torque_limited = scale < 1.0

func _apply_torso_tilt_stabilization() -> void:
	var gravity: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
	var up := -gravity.normalized() if not gravity.is_zero_approx() else Vector3.UP
	for body: RigidBody3D in get_torso_parts():
		var current_up := body.global_basis.y.normalized()
		var cross := current_up.cross(up)
		var error := cross.normalized() * atan2(cross.length(), current_up.dot(up))
		var acceleration := (error * tilt_strength - body.angular_velocity.slide(up) * tilt_damping).limit_length(maximum_tilt_acceleration)
		# Small boxes have much less inertia than large boxes of equal mass. Mass-only
		# torque scaling can make damping unstable on narrow procedurally generated Torso blocks.
		var size: Vector3 = body.get_meta(&"generated_size", Vector3.ONE)
		var inertia := Vector3(size.y * size.y + size.z * size.z, size.x * size.x + size.z * size.z, size.x * size.x + size.y * size.y) * body.mass / 12.0
		var local_acceleration := body.global_basis.inverse() * acceleration
		body.apply_torque(body.global_basis * (local_acceleration * inertia))

func get_generated_movement_diagnostics() -> Dictionary:
	var recovery := get_parent().get_node_or_null("CreatureRecoveryStateMachine3D")
	var feet: Array[Dictionary] = []
	var support_count := 0
	for foot: RigidBody3D in _legs:
		var chain: Dictionary = _chains.get(foot, {})
		if is_leg_grounded(foot): support_count += 1
		var required_torques: Array[float] = []
		var torque_limits: Array[float] = []
		for joint: Generic6DOFJoint3D in chain.get("joints", []):
			var load: Vector3 = _stance_joint_loads.get(joint, Vector3.ZERO)
			required_torques.append(load.length())
			torque_limits.append(minf(maximum_stance_torque, maxf(minimum_stance_torque, load.length() * stance_load_safety_factor + stance_dynamic_torque_reserve)))
		feet.append({"name": foot.name, "foreleg": _has_body_tag(foot, FORELEG_TAG), "joints": chain.get("joints", []).size(), "reach": chain.get("length", 0.0), "grounded": is_leg_grounded(foot), "moving": is_leg_stepping(foot), "stance_weight": chain.get("stance_weight", 0.0), "support_share": _stance_support_weights.get(foot, 0.0), "joint_torques": chain.get("stance_torques", []), "required_torques": required_torques, "torque_limits": torque_limits})
	return {"character": get_parent().name, "torso": _torso.name if is_instance_valid(_torso) else &"", "foot_count": feet.size(), "gallop": _gallop_diagnostics, "support_count": support_count, "feet": feet, "state": get_step_state_name(), "stride": get_current_step_distance(), "lift": _get_effective_step_height(), "target_error": get_active_leg_horizontal_target_distance(), "total_mass": _stance_total_mass, "center_of_mass": _stance_center_of_mass, "support_balanced": _stance_support_balanced, "balance_error": _stance_balance_error, "torso_response_force": _last_torso_response_force, "recovery": recovery.get_recovery_diagnostics() if recovery != null else {}}

## Sampled by trackmotion only. These are controller-commanded torques, not the
## physics engine's constraint reaction torques or a guarantee of dynamic stability.
func get_stance_support_diagnostics() -> Dictionary:
	var torso_mass := 0.0
	for body: RigidBody3D in get_torso_parts(): torso_mass += body.mass
	var gravity := _gravity_acceleration()
	var rows: Array[Dictionary] = []
	var supporting_feet := 0
	var current_frame := Engine.get_physics_frames()
	var applied_age := current_frame - _stance_last_applied_frame if _stance_last_applied_frame >= 0 else -1
	var allocation_age := current_frame - _stance_last_allocation_frame if _stance_last_allocation_frame >= 0 else -1
	var normal_control := not recovery_control_active and is_physics_processing() and applied_age >= 0 and applied_age <= 1
	for foot: RigidBody3D in _chains.keys():
		if not is_instance_valid(foot) or not _chains.has(foot): continue
		var chain: Dictionary = _chains[foot]
		var eligible := normal_control and _stance_chain_can_support(foot)
		if eligible: supporting_feet += 1
		var share: float = _stance_support_weights.get(foot, 0.0)
		var vectors: Array = chain.get("stance_torque_vectors", [])
		for index: int in range(chain.joints.size()):
			if not is_instance_valid(chain.joints[index]) or not is_instance_valid(chain.bodies[index]) or not is_instance_valid(chain.bodies[index + 1]): continue
			var joint: Generic6DOFJoint3D = chain.joints[index]
			var child: RigidBody3D = chain.bodies[index]
			var parent_body: RigidBody3D = chain.bodies[index + 1]
			if not is_instance_valid(joint) or not is_instance_valid(child) or not is_instance_valid(parent_body): continue
			var load: Vector3 = _stance_joint_loads.get(joint, Vector3.ZERO)
			var estimate_valid := false
			var required := load.length()
			var limit := minf(maximum_stance_torque, maxf(minimum_stance_torque, required * stance_load_safety_factor + stance_dynamic_torque_reserve)) if auto_allocate_stance_torque else maximum_stance_torque
			var commanded: Vector3 = vectors[index] if eligible and index < vectors.size() else Vector3.ZERO
			var a := _stance_inverse_inertia(child)
			var b := _stance_inverse_inertia(parent_body)
			var inverse := Basis(a.x + b.x, a.y + b.y, a.z + b.z)
			var load_acceleration := (inverse * load).length()
			var along_load := commanded.dot(load / required) if required > 0.000001 else 0.0
			rows.append({"foot": foot.name, "joint": joint.name, "joint_path": get_parent().get_path_to(joint), "child": child.name, "parent": parent_body.name,
				"contact_body": _get_stance_chain_contact(foot).get("body", foot).name, "contact_is_limb": int(_get_stance_chain_contact(foot).get("index", 0)) > 0,
				"linear_slack": Vector3(joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)),
				"joint_y_rotation_locked": joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT) and is_zero_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)) and is_zero_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)),
				"angular_spring_enabled": [joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING), joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING), joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING)],
				"angular_spring_stiffness": Vector3(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS), joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS), joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS)),
				"angular_spring_damping": Vector3(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING), joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING), joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING)),
				"leg_side_released": _stance_leg_side_released(child, parent_body) or _stance_leg_side_released(parent_body, child),
				"child_applied_vector": commanded if not child.freeze and not _stance_leg_side_released(child, parent_body) else Vector3.ZERO,
				"parent_applied_vector": -commanded if not parent_body.freeze and not _stance_leg_side_released(parent_body, child) else Vector3.ZERO,
				"eligible": false, "contact_support": eligible, "chain_intact": _chain_is_intact(foot), "grounded": is_leg_grounded(foot), "stepping": is_leg_stepping(foot),
				"estimate_valid": estimate_valid, "support_share": share, "support_force": maxf(0.0, gravity.length() * _stance_total_mass - (_last_torso_response_force + _last_auxiliary_support_force).dot(-gravity.normalized())) * share,
				"required_torque": required, "required_vector": load, "commanded_torque": commanded.length(), "commanded_vector": commanded,
				"commanded_along_load": along_load, "torque_limit": limit, "hard_torque_limit": maximum_stance_torque,
				"capacity_ratio": limit / required if required > 0.000001 else -1.0,
				"capacity_shortfall": estimate_valid and required > limit,
				"torque_at_limit": eligible and commanded.length() >= limit * 0.99 and limit > 0.0,
				"load_angular_acceleration": load_acceleration, "acceleration_limit": maximum_stance_acceleration,
				"load_exceeds_pose_acceleration_limit": estimate_valid and load_acceleration > maximum_stance_acceleration,
				"load_compensation_acceleration_limited": false,
				"pose_error_degrees": rad_to_deg(_stance_rotation_error(child, parent_body, chain.rest_rotations[index]).length()),
				"relative_angular_speed": (child.angular_velocity - parent_body.angular_velocity).length(),
				"stance_ramp": chain.get("stance_weight", 0.0), "child_frozen": child.freeze, "parent_frozen": parent_body.freeze})
	var rotation_constraints: Array[Dictionary] = []
	var parts := get_node_or_null(parts_root_path)
	if parts != null:
		for node: Node in parts.find_children("*", "Generic6DOFJoint3D", true, false):
			if node.has_meta(&"segment_rotation_constraint"):
				if node.has_method("get_constraint_diagnostics"): rotation_constraints.append(node.get_constraint_diagnostics())
	var planar := get_parent().get_node_or_null("PlanarConstraints")
	return {"planar_constraints": planar.get_diagnostics() if planar != null else {}, "planar_slide": _planar_slide_diagnostics, "zero_gravity_test_mode": simplified_physics_mode, "segment_rotation_constraints": rotation_constraints, "normal_control": normal_control, "recovery_active": recovery_control_active, "auto_allocation": false, "passive_limb_links": true, "passive_hinges": _passive_hinge_rows,
		"contact_enter_distance": support_contact_enter_distance, "contact_exit_distance": maxf(support_contact_enter_distance, support_contact_exit_distance), "load_smoothing_time": support_load_smoothing_time,
		"vertical_response_gain": vertical_response_gain, "vertical_damping_ratio": vertical_response_damping_ratio,
		"stance_enabled": false, "total_mass": _stance_total_mass, "torso_mass": torso_mass,
		"total_weight": _stance_total_mass * gravity.length(), "estimated_ground_reaction": maxf(0.0, _stance_total_mass * gravity.length() - (_last_torso_response_force + _last_auxiliary_support_force).dot(-gravity.normalized())), "torso_weight": torso_mass * gravity.length(), "torso_response_force": _last_torso_response_force, "torso_response_force_limit": _get_torso_response_force_limit(torso_mass),
		"supporting_feet": supporting_feet, "foot_count": _legs.size(), "center_of_mass": _stance_center_of_mass,
		"support_balanced": _stance_support_balanced, "balance_error": _stance_balance_error, "balance_tolerance": stance_balance_tolerance,
		"segments": get_body_segment_diagnostics(), "auxiliary_support_force": _last_auxiliary_support_force, "auxiliary_weight_limit": auxiliary_support_weight_limit, "grounded_drive_acceleration_limit": maximum_grounded_drive_acceleration, "segment_springs": _get_segment_spring_diagnostics(), "turn_leg_forces": _turn_leg_forces.values(), "turn_drive_diagnostics": _turn_drive_diagnostics, "turn_landing_rejections": _turn_landing_rejections, "parallel_turn_steps": _resource_turn_blending_enabled(), "gallop": _gallop_diagnostics, "turn_minimum_grounded_ratio": turn_minimum_grounded_ratio, "physical_heading_degrees": rad_to_deg(_get_physical_heading_yaw()), "maximum_heading_error_degrees": rad_to_deg(_get_maximum_heading_error(_segment_goal_yaw)), "turn_drive": "grounded_foot_attachment_forces", "turn_rate_degrees": rad_to_deg(_get_physical_yaw_rate()), "requested_turn_rate_degrees": _motion_setting("turning_speed_degrees", segment_heading_speed_degrees), "layout_reference_lead_degrees": rad_to_deg(wrapf(_segment_layout_yaw - _get_physical_heading_yaw(), -PI, PI)), "direct_heading_torque_enabled": false, "heading_goal_degrees": rad_to_deg(_segment_goal_yaw), "heading_target_degrees": rad_to_deg(_segment_target_yaw), "layout_turn_active": _layout_turn_owned, "layout_turn_status": _layout_turn_status, "layout_turn_elapsed": _layout_turn_elapsed, "layout_turn_stagnant": _layout_turn_stagnant, "layout_turn_target": _layout_turn_target, "unbalanced_compensation": maxf(unbalanced_stance_multiplier, 0.25), "applied_age_frames": applied_age,
		"allocation_age_frames": allocation_age, "joints": rows}


## Generated feet can roll onto a side. Their original local bottom centre is
## then above the ground; use the gravity-facing extent of the current box.
func _get_foot_world_position(leg: RigidBody3D) -> Vector3:
	var collision := _find_leg_collision_shape(leg)
	if collision == null or not collision.shape is BoxShape3D: return super._get_foot_world_position(leg)
	var size: Vector3 = collision.shape.size
	var gravity := _gravity_acceleration()
	var up := -gravity.normalized() if not gravity.is_zero_approx() else Vector3.UP
	var axes := collision.global_basis
	var extent := (absf(axes.x.dot(up)) * size.x + absf(axes.y.dot(up)) * size.y + absf(axes.z.dot(up)) * size.z) * 0.5
	return collision.global_position - up * extent


func _get_torso_response_force_limit(torso_mass: float) -> float:
	var configured := maximum_torso_force * _get_configured_movement_scale()
	if not mass_scaled_torso_force_limit or not scale_response_by_torso_mass: return configured
	var weight_limit := torso_mass * _gravity_acceleration().length() * torso_force_weight_margin
	return maxf(configured, minf(weight_limit, maximum_mass_scaled_torso_force))

func _begin_leg_motion(leg: RigidBody3D, target: Vector3, target_normal: Vector3 = Vector3.UP, input_direction: Vector3 = Vector3.ZERO) -> void:
	_gallop_reach_released.erase(leg)
	var new_step := _step_state == StepState.IDLE or leg != _active_leg
	if new_step:
		_try_gallop_takeoff(leg)
		_step_has_lifted = false
		var hit := _get_surface_below_leg(leg, surface_adhesion_probe_distance)
		_step_start_clearance = maxf(0.0, (_get_foot_world_position(leg) - Vector3(hit.position)).dot(Vector3(hit.normal))) if not hit.is_empty() else 0.0
	super._begin_leg_motion(leg, target, target_normal, input_direction)
	if _layout_turn_owned: _current_step.extra["turn_swing_yaw"] = _segment_layout_yaw
	if _gallop_active():
		_current_step.extra["gallop_step"] = true
		var cycle := float(get_leg_motion_profile(leg).cycle)
		var interval := _get_gait_data().gallop_step_group_size / maxf(super.get_planned_step_frequency(),0.01)
		_active_step_duration = clampf(minf(interval*1.15,cycle*0.7),0.08,0.65)
		var timing := _get_speed_leg_plan(leg) if _get_gait_data().speed_based_gait else {}
		if not timing.is_empty():
			_current_step.extra["speed_gait"] = timing.duplicate()
			_active_step_duration = float(timing.air_duration)
			# Longer air phases need real clearance; do not merely slow a shallow
			# walking arc until it travels along the ground.
			_external_step_height = float(timing.get("lift",minf(float(_chains[leg].length)*0.15,_get_gait_step_height()+_gravity_acceleration().length()*_active_step_duration*_active_step_duration*0.04)))
			_current_step.extra.speed_gait["lift"] = _external_step_height
		_current_step.extra["landing_timeout"] = maxf(0.18,_get_gait_data().gallop_landing_confirmation*2.0)
		_current_step.extra["gallop_contact_confirmation"] = 0.0
		_current_step.extra["gallop_landing_confirmation"] = _get_gait_data().gallop_landing_confirmation
		_current_step.extra["gallop_freeze_progress"] = _get_gait_data().gallop_target_freeze_progress
		_current_step.extra["gallop_follow_limit"] = 0.0 if not timing.is_empty() else float(_chains[leg].length) * _get_gait_data().gallop_target_follow_length_ratio
		_current_step.extra["gallop_touchdown_speed_limit"] = _get_gait_data().gallop_touchdown_speed_limit
		if timing.get("automatic_flight",false):
			_current_step.extra["gallop_landing_confirmation"] = timing.landing_confirmation
			_current_step.extra["gallop_touchdown_speed_limit"] = timing.touchdown_speed_limit
			_current_step.extra["gallop_landing_started"] = -1.0
			_current_step.extra["gallop_retargets"] = 0
			_current_step.extra["gallop_rest_offset"] = target-_chains[leg].root.to_global(_chains[leg].anchor)-Vector3(timing.predicted_travel)
			_current_step.extra["gallop_follow_limit"] = Vector3(timing.predicted_travel).length()+float(_chains[leg].length)*2.0
			_current_step.extra["landing_timeout"] = maxf(0.5,float(timing.air_duration)*1.5)
		_current_step.extra["gallop_target_frozen"] = false
		_current_step.extra["gallop_target_shift"] = Vector3.ZERO
		_update_gallop_tracking_profile(leg,target)
		_current_step.extra["gallop_anchor_start"] = _chains[leg].root.global_position
		_current_step.extra["gallop_surface_start"] = target - (leg.global_position - _get_foot_world_position(leg)) - Vector3.UP * foot_ground_offset
	_current_step.extra["landing_surface_point"] = target - (leg.global_position - _get_foot_world_position(leg)) - Vector3.UP * foot_ground_offset

func _update_gallop_tracking_profile(leg: RigidBody3D, target: Vector3) -> void:
	var profile: Dictionary = _current_step.extra.get("automatic_profile",{})
	if profile.is_empty(): return
	var duration := maxf(_active_step_duration,0.35) if _current_step.extra.has("speed_gait") else maxf(_active_step_duration,0.08)
	var gain := clampf(16.0/(duration*duration),40.0,120.0) if _current_step.extra.has("speed_gait") else clampf(16.0/(duration*duration),20.0,4000.0)
	profile.position_gain = gain
	profile.velocity_gain = 2.0*sqrt(gain)
	profile.step_acceleration = clampf(8.0*maxf((target-leg.global_position).length(),_get_effective_step_height())/(duration*duration)+9.8,30.0,2000.0)
	if _current_step.extra.has("speed_gait"):
		profile["vertical_position_gain"] = maxf(gain,100.0)
		profile["vertical_velocity_gain"] = 2.0*sqrt(float(profile.vertical_position_gain))
		profile.step_acceleration = clampf(float(profile.step_acceleration),60.0,180.0)
		if _current_step.extra.get("extension_trigger",{}).get("reason","") in ["reach_recovery","extension_emergency"]:
			profile.position_gain = minf(float(profile.position_gain),80.0)
			profile.step_acceleration = minf(float(profile.step_acceleration),120.0)

# A smooth horizontal path has zero velocity at lift-off and touchdown. The
# vertical arch uses the full configured gallop lift at midpoint.
func _quadratic_step_position(progress: float) -> Vector3:
	if not _current_step.extra.get("gallop_step",false): return super._quadratic_step_position(progress)
	var t := smoothstep(0.0,1.0,progress)
	return _step_start.lerp(_step_target,t) + Vector3.UP * 4.0 * _get_effective_step_height() * progress * (1.0-progress)

func _quadratic_step_velocity(progress: float, duration: float) -> Vector3:
	if not _current_step.extra.get("gallop_step",false): return super._quadratic_step_velocity(progress,duration)
	return ((_step_target-_step_start)*6.0*progress*(1.0-progress) + Vector3.UP*4.0*_get_effective_step_height()*(1.0-2.0*progress))/maxf(duration,MIN_STEP_TIME)

func _update_active_step(delta: float) -> void:
	var gallop_step: bool = is_instance_valid(_active_leg) and _current_step.extra.get("gallop_step",false) and _chain_is_intact(_active_leg)
	if gallop_step and _current_step.extra.has("speed_gait") and _step_state == StepState.MOVING and not _current_step.extra.get("liftoff_complete",false):
		# Lift is a separate bounded phase: it must not consume the horizontal
		# swing clock and force the remaining travel into a catch-up burst.
		_current_step.extra["liftoff_elapsed"] = float(_current_step.extra.get("liftoff_elapsed",0.0))+delta
		_update_gallop_tracking_profile(_active_leg,_step_target)
		var lift_position := _active_leg.global_position
		lift_position.y = _step_start.y+maxf(_get_effective_step_height()*0.6,minimum_step_lift_clearance*2.0)
		_apply_leg_tracking_force(lift_position,Vector3.ZERO)
		if _step_has_lifted:
			_current_step.extra["liftoff_complete"] = true
			_step_start = _active_leg.global_position
			_step_elapsed = 0.0
		elif float(_current_step.extra.liftoff_elapsed) >= maxf(0.3,_active_step_duration*0.5):
			_handle_step_timeout(is_leg_grounded(_active_leg))
		return
	if gallop_step and _current_step.extra.get("speed_gait",{}).get("automatic_flight",false): _retarget_adaptive_landing(delta)
	if gallop_step and _step_state == StepState.MOVING:
		var progress := _step_elapsed / maxf(_active_step_duration,MIN_STEP_TIME)
		if progress >= float(_current_step.extra.gallop_freeze_progress) and not _current_step.extra.get("speed_gait",{}).get("automatic_flight",false): _current_step.extra.gallop_target_frozen = true
		if _gallop_active() and not _current_step.extra.gallop_target_frozen and not _current_step.extra.get("speed_gait",{}).get("automatic_flight",false):
			var root_body: RigidBody3D = _chains[_active_leg].root
			var offset: Vector3 = (root_body.global_position - Vector3(_current_step.extra.gallop_anchor_start)).slide(Vector3.UP)
			offset = offset.limit_length(float(_current_step.extra.gallop_follow_limit))
			var sample: Vector3 = _current_step.extra.gallop_surface_start + offset
			var query := PhysicsRayQueryParameters3D.create(sample + Vector3.UP * ray_start_height,sample + Vector3.DOWN * ray_length,terrain_collision_mask,_get_character_exclusion_rids())
			query.collide_with_areas = false
			var hit := _intersect_ray(query)
			if _is_landing_point_valid(_active_leg,_get_foot_world_position(_active_leg),hit):
				_current_step.extra.landing_surface_point = hit.position
				_current_step.extra.gallop_target_shift = Vector3(hit.position)-Vector3(_current_step.extra.gallop_surface_start)
				_step_target_normal = hit.normal
		# Once a foot has lifted, a real near-surface contact ends the swing
		# immediately, even early in the trajectory or during a contact bounce.
		# Landing below removes horizontal pursuit and brakes in this same tick.
		var contact := _support_surface_contact(_active_leg)
		if _step_has_lifted and not contact.is_empty():
			var gap := (_get_foot_world_position(_active_leg)-Vector3(contact.position)).dot(Vector3(contact.normal))
			if absf(gap) <= 0.04:
				_current_step.extra["touchdown_swing_progress"] = progress
				_step_state = StepState.LANDING
				_landing_elapsed = 0.0
	if is_instance_valid(_active_leg) and _current_step.extra.has("landing_surface_point"):
		_step_target = _body_position_for_ground_contact(_active_leg,_current_step.extra.landing_surface_point)
	if gallop_step:
		_update_gallop_tracking_profile(_active_leg,_step_target)
		if _step_state == StepState.LANDING:
			if _current_step.extra.get("speed_gait",{}).get("automatic_flight",false):
				if float(_current_step.extra.gallop_landing_started)<0: _current_step.extra.gallop_landing_started = _physics_elapsed
				var observed := _physics_elapsed-float(_current_step.extra.gallop_landing_started)
				_landing_time_estimates[_active_leg] = maxf(float(_landing_time_estimates.get(_active_leg,0)),minf(observed,2.0))
			var contact := _support_surface_contact(_active_leg)
			if not contact.is_empty():
				var normal: Vector3 = contact.normal
				var gap := (_get_foot_world_position(_active_leg)-Vector3(contact.position)).dot(normal)
				var contact_tolerance := minf(0.07,maxf(0.04,_get_effective_landing_tolerance())) if _current_step.extra.get("speed_gait",{}).get("automatic_flight",false) else 0.04
				if absf(gap) <= contact_tolerance and is_leg_grounded(_active_leg):
					if not _current_step.extra.has("gallop_touchdown_point"):
						_current_step.extra["gallop_contact_epoch"] = int(_current_step.extra.get("gallop_contact_epoch",0))+1
						_current_step.extra["gallop_touchdown_point"] = contact.position
						_current_step.extra["gallop_target_frozen"] = true
					# Remove pursuit: brake tangential motion at the actual contact,
					# with a normal correction only, then create the native ground pin.
					var desired := _active_leg.global_position + normal * (foot_ground_offset-gap)
					_current_step.extra["gallop_braking_velocity"] = _active_leg.linear_velocity.slide(normal)
					_current_step.extra["touchdown_normal"] = normal
					_current_step.extra["gallop_touchdown_braking"] = true
					_apply_leg_tracking_force(desired,Vector3.ZERO)
					var slow := _active_leg.linear_velocity.slide(normal).length() <= float(_current_step.extra.gallop_touchdown_speed_limit) and absf(_active_leg.linear_velocity.dot(normal)) <= 0.7
					_current_step.extra.gallop_contact_confirmation = float(_current_step.extra.gallop_contact_confirmation)+delta if slow else 0.0
					_landing_elapsed += delta
					if float(_current_step.extra.gallop_contact_confirmation) >= float(_current_step.extra.gallop_landing_confirmation):
						var landed := _active_leg
						_gallop_landed_feet[landed] = true
						_finish_current_step()
						_update_support_foot_lock(landed,normal)
					elif _landing_elapsed >= _get_effective_landing_timeout():
						# Keep braking real contact rather than treating an
						# obsolete positional error as an unsuccessful landing.
						if _landing_elapsed >= maxf(_get_effective_landing_timeout(),0.5) and not _current_step.extra.get("speed_gait",{}).get("automatic_flight",false): _handle_step_timeout(true)
					return
			# A lost real contact invalidates the frozen point. Do not drag the
			# foot back toward a point left behind by the moving torso.
			if _current_step.extra.get("speed_gait",{}).get("automatic_flight",false):
				_current_step.extra["gallop_target_frozen"] = false
				_current_step.extra.erase("gallop_touchdown_point")
			_current_step.extra["gallop_touchdown_braking"] = false
			_current_step.extra.gallop_contact_confirmation = 0.0
	super._update_active_step(delta)

# Recompute the remaining root travel, rather than chasing a launch-time prediction.
# Keep terrain validation and a bounded correction speed; actual contact freezes the point.
func _retarget_adaptive_landing(delta: float) -> void:
	if _current_step.extra.get("gallop_target_frozen",false): return
	var remaining := maxf(_active_step_duration-_step_elapsed,0.0)
	var chain: Dictionary = _chains[_active_leg]
	var attachment: Vector3 = chain.root.to_global(chain.anchor)
	var predicted := attachment+_speed_smoothed_velocity.slide(Vector3.UP)*remaining
	var desired: Vector3 = _active_leg.global_position if _step_state==StepState.LANDING else predicted+Vector3(_current_step.extra.gallop_rest_offset)
	var current: Vector3 = _current_step.extra.landing_surface_point
	var foot_offset := _active_leg.global_position-_get_foot_world_position(_active_leg)+Vector3.UP*foot_ground_offset
	var correction := (desired-foot_offset-current).slide(Vector3.UP)
	var limit := maxf(float(_current_step.extra.speed_gait.budget_speed),float(chain.length))*delta
	var sample := current+correction.limit_length(limit)
	var query := PhysicsRayQueryParameters3D.create(sample+Vector3.UP*ray_start_height,sample+Vector3.DOWN*ray_length,terrain_collision_mask,_get_character_exclusion_rids())
	var hit := _intersect_ray(query)
	if not super._is_landing_point_valid(_active_leg,_get_foot_world_position(_active_leg),hit): return
	var body_target := _body_position_for_ground_contact(_active_leg,hit.position)
	if body_target.distance_to(predicted)>float(chain.length)*chain_reach_ratio: return
	_current_step.extra.landing_surface_point = hit.position
	_current_step.extra.gallop_target_shift = Vector3(hit.position)-Vector3(_current_step.extra.gallop_surface_start)
	_current_step.extra["gallop_predicted_attachment"] = predicted
	_current_step.extra["gallop_retargets"] += 1
	_step_target_normal = hit.normal

func _finish_current_step() -> void:
	if _current_step.extra.has("extension_trigger") and _current_step.extra.has("speed_gait") and _chain_is_intact(_active_leg):
		_extension_rearm[_active_leg] = {"origin": _chains[_active_leg].root.to_global(_chains[_active_leg].anchor), "direction": _active_step_input_direction.slide(Vector3.UP).normalized()}
	if _current_step.extra.get("speed_gait",{}).get("automatic_flight",false):
		var started := float(_current_step.extra.get("gallop_landing_started",-1.0))
		if started>=0:
			var observed := minf(_physics_elapsed-started,2.0)
			_landing_time_estimates[_active_leg] = lerpf(float(_landing_time_estimates.get(_active_leg,observed)),observed,0.25)
	super._finish_current_step()

func _apply_leg_tracking_force(desired_position: Vector3, desired_velocity: Vector3) -> void:
	_apply_turn_swing_orientation()
	if not mass_scaled_step_drive:
		super._apply_leg_tracking_force(desired_position, desired_velocity)
		return
	_tracking_mass = _active_leg.mass
	var gravity_mass := _active_leg.mass * _active_leg.gravity_scale
	var chain: Dictionary = _chains.get(_active_leg, {})
	if not chain.is_empty():
		# The last body is the Torso anchor; it is never lifted by the foot servo.
		for index: int in range(1, chain.bodies.size() - 1):
			var body = chain.bodies[index]
			if not is_instance_valid(body) or body.freeze: continue
			_tracking_mass += body.mass * stepping_chain_mass_ratio
			gravity_mass += body.mass * body.gravity_scale * stepping_chain_mass_ratio
	var hit := _get_surface_below_leg(_active_leg, surface_adhesion_probe_distance)
	var gap := INF if hit.is_empty() else (_get_foot_world_position(_active_leg) - Vector3(hit.position)).dot(Vector3(hit.normal))
	if gap >= _step_start_clearance + minimum_step_lift_clearance: _step_has_lifted = true
	var horizontal_weight := 1.0
	if _current_step.extra.has("speed_gait") and _step_state == StepState.MOVING:
		if not _step_has_lifted:
			horizontal_weight = 0.0
			desired_position.y = maxf(desired_position.y,_step_start.y+maxf(_get_effective_step_height()*0.6,minimum_step_lift_clearance*2.0))
			_current_step.extra["liftoff_phase"] = "lifting"
		else:
			if not _current_step.extra.has("horizontal_release_time"): _current_step.extra["horizontal_release_time"] = _physics_elapsed
			horizontal_weight = smoothstep(0.0,0.1,_physics_elapsed-float(_current_step.extra.horizontal_release_time))
			_current_step.extra["liftoff_phase"] = "travelling"
		_current_step.extra["horizontal_tracking_weight"] = horizontal_weight
	_tracking_position_error = desired_position - _active_leg.global_position
	var velocity_error := desired_velocity - _active_leg.linear_velocity
	var acceleration := _tracking_position_error * _step_motion_setting("position_gain", step_position_gain) * _active_movement_scale + velocity_error * _step_motion_setting("velocity_gain", step_velocity_gain) * sqrt(_active_movement_scale)
	if _current_step.extra.has("speed_gait") and not _current_step.extra.get("gallop_touchdown_braking",false):
		var vertical := _tracking_position_error.y * _step_motion_setting("vertical_position_gain",step_position_gain) + velocity_error.y * _step_motion_setting("vertical_velocity_gain",step_velocity_gain)
		acceleration.y = vertical
		if _step_state == StepState.MOVING:
			# Keep velocity damping while suppressing forward pursuit before lift.
			var damping := _step_motion_setting("velocity_gain",step_velocity_gain)*sqrt(_active_movement_scale)
			acceleration.x = (acceleration.x+_active_leg.linear_velocity.x*damping)*horizontal_weight-_active_leg.linear_velocity.x*damping
			acceleration.z = (acceleration.z+_active_leg.linear_velocity.z*damping)*horizontal_weight-_active_leg.linear_velocity.z*damping
	var acceleration_limit := _step_motion_setting("step_acceleration", maximum_step_acceleration)*pow(_active_movement_scale,1.5)
	var touchdown_braking: bool = _step_state == StepState.LANDING and _current_step.extra.get("gallop_touchdown_braking",false)
	if touchdown_braking:
		var data := _get_gait_data()
		var normal: Vector3 = _current_step.extra.touchdown_normal
		var stop_time := maxf(data.touchdown_stop_time,maxf(_support_delta,1.0/60.0))
		var tangent_velocity := _active_leg.linear_velocity.slide(normal)
		var requested_brake := -tangent_velocity/stop_time
		var braking_acceleration := requested_brake.limit_length(data.touchdown_maximum_braking_acceleration)
		# Keep normal correction bounded by the existing landing servo; replace
		# only tangential damping. This is one force application, not two servos.
		var normal_acceleration := clampf(acceleration.dot(normal),-acceleration_limit,acceleration_limit)
		acceleration = braking_acceleration+normal*normal_acceleration
		acceleration_limit = sqrt(data.touchdown_maximum_braking_acceleration*data.touchdown_maximum_braking_acceleration+acceleration_limit*acceleration_limit)
		_current_step.extra["touchdown_brake"] = {"stop_time": data.touchdown_stop_time,"effective_stop_time": stop_time,"maximum_acceleration": data.touchdown_maximum_braking_acceleration,"effective_mass": _tracking_mass,"speed": tangent_velocity.length(),"requested_force": requested_brake*_tracking_mass,"acceleration_limited": requested_brake.length()>data.touchdown_maximum_braking_acceleration}
	else:
		acceleration = acceleration.limit_length(acceleration_limit)
	# Fade weight feedforward during descent; landing applies no upward weight compensation.
	var progress := clampf(_step_elapsed / maxf(_active_step_duration, MIN_STEP_TIME), 0.0, 1.0)
	var gravity_weight := 1.0 - smoothstep(0.5, 1.0, progress) if _step_state == StepState.MOVING else 0.0
	_tracking_gravity_force = -_gravity_acceleration() * gravity_mass * gravity_weight if step_gravity_compensation else Vector3.ZERO
	var requested := acceleration * _tracking_mass + _tracking_gravity_force
	_tracking_force_limit = minf(maximum_mass_scaled_step_force, _tracking_mass*acceleration_limit+_tracking_gravity_force.length())
	_tracking_force_limited = requested.length() > _tracking_force_limit
	_tracking_force = requested.limit_length(_tracking_force_limit)
	if touchdown_braking:
		var normal: Vector3 = _current_step.extra.touchdown_normal
		_current_step.extra.touchdown_brake["applied_force"] = _tracking_force.slide(normal)
		_current_step.extra.touchdown_brake["force_limited"] = _tracking_force_limited
	_active_leg.apply_central_force(_tracking_force)

func _apply_turn_swing_orientation() -> void:
	if _planar_mode_active(): return
	if not is_instance_valid(_active_leg): return
	if _current_step.extra.has("turn_swing_yaw") and not recovery_control_active:
		var grounded := false
		for other: RigidBody3D in _legs:
			if other != _active_leg and _chain_is_intact(other) and is_leg_grounded(other): grounded = true
		if grounded:
			var inverse := _stance_inverse_inertia(_active_leg)
			if absf(inverse.determinant()) > 1e-18:
				var actual := atan2(-_active_leg.global_basis.x.z, _active_leg.global_basis.x.x)
				var error := wrapf(float(_current_step.extra.turn_swing_yaw) - actual, -PI, PI)
				var swing_acceleration := Vector3.UP * (error * _motion_setting("turn_gain", foot_alignment_strength) - _active_leg.angular_velocity.y * _motion_setting("turn_damping", foot_alignment_damping))
				_active_leg.apply_torque((inverse.inverse() * swing_acceleration).limit_length(maximum_foot_alignment_torque))

func _is_step_target_reached(close_enough: bool) -> bool:
	if _current_step.extra.get("gallop_step",false):
		var contact := _support_surface_contact(_active_leg)
		if contact.is_empty(): return false
		var normal: Vector3 = contact.normal
		var gap := (_get_foot_world_position(_active_leg)-Vector3(contact.position)).dot(normal)
		return _step_has_lifted and absf(gap) <= 0.04 and _active_leg.linear_velocity.slide(normal).length() <= float(_current_step.extra.gallop_touchdown_speed_limit) and absf(_active_leg.linear_velocity.dot(normal)) <= 0.5
	return close_enough and (_step_has_lifted or not mass_scaled_step_drive)

func _accept_grounded_step_timeout() -> bool:
	return false

func _handle_step_timeout(grounded: bool) -> void:
	_failed_step_count += 1
	_last_step_failure = &"landing_timeout_unreached" if grounded else &"landing_timeout_airborne"
	if _current_step.extra.get("gallop_touchdown_braking",false): _last_step_failure = &"touchdown_braking_timeout"
	elif not _step_has_lifted and mass_scaled_step_drive: _last_step_failure = &"step_never_lifted"
	# Try another chain after failure, without recording a successful touchdown.
	if not _legs.is_empty() and not _current_step.extra.get("resource_step", false): _next_leg_index = (_next_leg_index + 1) % _legs.size()
	cancel_step(_last_step_failure)

func _calculate_leg_adhesion_force(leg: RigidBody3D, hit: Dictionary, multiplier: float) -> Vector3:
	if _gallop_foot_launch_pending(leg,hit.normal): return Vector3.ZERO
	var normal: Vector3 = hit.normal.normalized()
	if not _surface_is_walkable(normal): return Vector3.ZERO
	var gap := maxf(0.0, (_get_foot_world_position(leg) - Vector3(hit.position)).dot(normal))
	var outward_speed := leg.linear_velocity.dot(normal)
	var pull := surface_adhesion_force * _get_configured_movement_scale() + leg.mass * (gap * foot_adhesion_strength + outward_speed * foot_adhesion_damping)
	# Pull only. A descending foot may reduce the pull, never receive an upward kick.
	return -normal * clampf(pull * multiplier, 0.0, maximum_foot_adhesion_force)

func _calculate_foot_alignment_torque(leg: RigidBody3D, normal: Vector3) -> Vector3:
	var current := leg.global_basis.y.normalized()
	var cross := current.cross(normal)
	var axis := cross.normalized() if cross.length_squared() > 0.000001 else leg.global_basis.x.normalized()
	var error := axis * acos(clampf(current.dot(normal), -1.0, 1.0))
	var requested := error * foot_alignment_strength - leg.angular_velocity.slide(normal) * foot_alignment_damping
	var acceleration := requested.limit_length(maximum_foot_alignment_acceleration)
	var inverse := _stance_inverse_inertia(leg)
	if absf(inverse.determinant()) < 1e-18: return Vector3.ZERO
	var torque := (inverse.inverse() * acceleration).limit_length(maximum_foot_alignment_torque)
	return torque

# Launch suppresses adhesion only until each foot has returned to a descending
# terrain contact. A shared flight timer must not release a foot that has landed.
func _gallop_foot_launch_pending(leg: RigidBody3D, normal: Vector3) -> bool:
	if _automatic_motion_enabled() and _get_gait_data().speed_based_gait: return false
	if not _gallop_active() or _physics_elapsed >= _gallop_pin_release_until or _gallop_landed_feet.has(leg): return false
	var contact := _support_surface_contact(leg)
	if not contact.is_empty() and _physics_elapsed-_gallop_launch_time >= 0.05 and leg.linear_velocity.dot(normal) <= 0.2:
		var gap := (_get_foot_world_position(leg)-Vector3(contact.position)).dot(normal)
		if absf(gap) <= 0.04:
			_gallop_landed_feet[leg] = true
			return false
	return true

func _update_support_foot_lock(leg: RigidBody3D, normal: Vector3) -> void:
	if (_gallop_active() and _gallop_reach_released.has(leg)) or _gallop_foot_launch_pending(leg,normal):
		_release_support_pin(leg)
		return
	super._update_support_foot_lock(leg,normal)

func update_leg_surface_adhesion() -> void:
	super.update_leg_surface_adhesion()
	_foot_alignment_torques.clear()
	if not surface_adhesion_enabled or not align_support_feet_to_surface or _adhesion_release_time_remaining > 0.0: return
	for foot: RigidBody3D in _legs:
		if is_leg_stepping(foot) or not _chain_is_intact(foot): continue
		var normal := get_leg_adhesion_surface_normal(foot)
		if _planar_mode_active(): continue
		if normal.is_zero_approx() or not _surface_is_walkable(normal) or not is_leg_grounded(foot): continue
		var torque := _calculate_foot_alignment_torque(foot, normal)
		_foot_alignment_torques[foot] = torque
		if not torque.is_zero_approx():
			foot.sleeping = false
			foot.apply_torque(torque)

func get_support_foot_diagnostics(leg: RigidBody3D) -> Dictionary:
	var result := super.get_support_foot_diagnostics(leg)
	var hit := _get_surface_below_leg(leg, surface_adhesion_probe_distance)
	result["reach_released"] = _gallop_active() and _gallop_reach_released.has(leg)
	result["airborne_lease_duration"] = _gallop_contact_duration(leg) if _gallop_contacts.has(leg) else 0.0
	result["ground_gap"] = (_get_foot_world_position(leg) - Vector3(hit.position)).dot(Vector3(hit.normal)) if not hit.is_empty() else -1.0
	result["foot_pitch_roll_locked"] = leg.axis_lock_angular_x and leg.axis_lock_angular_z
	result["foot_yaw_locked"] = leg.axis_lock_angular_y
	result["foot_heading"] = _foot_heading_diagnostics.get(leg, {"state": &"released", "torque": Vector3.ZERO})
	result["passive_limb_links"] = true
	var remembered: Dictionary = _gallop_contacts.get(leg,{})
	var age := _physics_elapsed - float(remembered.get("time", -1000.0))
	result["gallop"] = {"active": _gallop_active(), "reach_released": result.get("reach_released",false), "lease_duration": result.get("airborne_lease_duration",0.0), "contact_age": age if not remembered.is_empty() else -1.0, "grace_weight": _gallop_contact_weight(leg) if _gallop_active() else 0.0}
	result["turn_traction_force"] = _turn_leg_forces.get(leg, Vector3.ZERO)
	result["alignment_torque"] = _foot_alignment_torques.get(leg, Vector3.ZERO)
	var extra: Dictionary = get_leg_step_diagnostics(leg).extra
	result["speed_gait"] = extra.get("speed_gait",_get_speed_leg_plan(leg))
	result["extension_demand"] = _get_extension_step_demand(leg,get_input_movement_direction())
	result["extension_trigger"] = extra.get("extension_trigger",{})
	result["landing_time_estimate"] = _landing_time_estimates.get(leg,0.0)
	result["gallop"]["landing_time_estimate"] = result["landing_time_estimate"]
	result["gallop"]["retargets"] = extra.get("gallop_retargets",0)
	result["gallop"]["next_step_in"] = 0.0 if _extension_gait_enabled() else maxf(float(_automatic_next_steps.get(leg,_physics_elapsed))-_physics_elapsed,0.0)
	result["gallop"]["cadence_controls_admission"] = not _extension_gait_enabled()
	result["gallop"]["extension_demand"] = result["extension_demand"]
	result["gallop"]["extension_trigger"] = result["extension_trigger"]
	result["gallop"]["contact_epoch"] = extra.get("gallop_contact_epoch",0)
	result["gallop"]["tracking_profile"] = extra.get("automatic_profile",{})
	result["gallop"]["admission"] = _extension_admission.get(leg,{}).duplicate()
	if not result.gallop.admission.is_empty(): result.gallop.admission["age"] = _physics_elapsed-float(result.gallop.admission.time)
	result["gallop"]["touchdown_brake"] = extra.get("touchdown_brake",{})
	result["gallop"]["touchdown_swing_progress"] = extra.get("touchdown_swing_progress",-1.0)
	result["gallop"]["liftoff_phase"] = extra.get("liftoff_phase","")
	result["gallop"]["horizontal_tracking_weight"] = extra.get("horizontal_tracking_weight",1.0)
	result["gallop"]["predicted_attachment"] = extra.get("gallop_predicted_attachment",Vector3.ZERO)
	result["gallop"]["speed_gait"] = result["speed_gait"]
	result["gallop"]["group"] = extra.get("gallop_group",0)
	result["gallop"]["landing_confirmation"] = extra.get("gallop_contact_confirmation",0.0)
	result["gallop"]["target_shift"] = extra.get("gallop_target_shift",Vector3.ZERO)
	result["gallop"]["target_frozen"] = extra.get("gallop_target_frozen",false)
	result["gallop"]["touchdown_braking"] = extra.get("gallop_touchdown_braking",false)
	result["ground_tangential_speed"] = leg.linear_velocity.slide(Vector3(hit.normal)).length() if not hit.is_empty() else 0.0
	result["contact_sliding"] = is_leg_grounded(leg) and float(result["ground_tangential_speed"]) > 0.35
	result["gallop"]["ground_tangential_speed"] = result["ground_tangential_speed"]
	result["gallop"]["contact_sliding"] = result["contact_sliding"]
	result["step_tracking_force"] = extra.get("_tracking_force", Vector3.ZERO)
	result["step_gravity_force"] = extra.get("_tracking_gravity_force", Vector3.ZERO)
	result["step_effective_mass"] = extra.get("_tracking_mass", 0.0)
	result["step_force_limit"] = extra.get("_tracking_force_limit", 0.0)
	result["step_force_limited"] = extra.get("_tracking_force_limited", false)
	result["step_position_error"] = extra.get("_tracking_position_error", Vector3.ZERO)
	result["step_has_lifted"] = extra.get("_step_has_lifted", false)
	result["failed_steps"] = _failed_step_count
	result["last_step_failure"] = _last_step_failure
	return result
