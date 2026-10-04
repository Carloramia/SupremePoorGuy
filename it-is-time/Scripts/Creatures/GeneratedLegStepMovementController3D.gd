extends "res://Scripts/Creatures/LegStepMovementControllerBase3D.gd"

const FORELEG_TAG: int = 4
const LEG_LIMB_TAG: int = 5
const SUB_TORSO_TAG: int = 6

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
@export_range(0.0, 100.0, 0.1) var sub_torso_height_gain: float = 20.0
@export_range(0.0, 2.0, 0.05) var sub_torso_damping_ratio: float = 1.0
@export_range(0.0, 2.0, 0.05) var sub_torso_maximum_weight_share: float = 1.2
@export_range(0.0, 1.0, 0.01) var sub_torso_support_ramp_time: float = 0.2
@export_group("Grounded Movement Feedback")
@export var grounded_directional_feedback: bool = true
@export_range(0.0, 1.0, 0.05) var unbalanced_movement_multiplier: float = 0.25

@export_group("Generated Ground Contact")
## Sole clearance hysteresis; the broad ray range is only for finding terrain.
@export_range(0.001, 0.5, 0.001) var support_contact_enter_distance: float = 0.03
@export_range(0.001, 0.5, 0.001) var support_contact_exit_distance: float = 0.08
@export_range(0.0, 1.0, 0.01) var support_load_smoothing_time: float = 0.15
var _contact_states: Dictionary = {}

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
				var locked := limb_hinge and axis != "z"
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

func try_start_step(direction: Vector3 = Vector3.RIGHT) -> bool:
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
	_segments.clear()
	_segment_links.clear()
	var parts := get_node_or_null(parts_root_path)
	if parts != null:
		for node: Node in parts.find_children("*", "Generic6DOFJoint3D", true, false):
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
	for id: int in _segments:
		var segment: Dictionary = _segments[id]
		var floor_height := 0.0
		for foot: RigidBody3D in segment.feet: floor_height += _get_foot_world_position(foot).y
		if not segment.feet.is_empty(): floor_height /= float(segment.feet.size())
		var reference: RigidBody3D = segment.bodies[0]
		if not reference.has_meta(&"generated_segment_rest_height"):
			reference.set_meta(&"generated_segment_rest_height", maxf(0.1, Vector3(segment.torso_center).y - floor_height))
		segment.reference_height = reference.get_meta(&"generated_segment_rest_height")

func _connected_body_segments(start: int) -> Array[int]:
	var result: Array[int] = [start]
	var cursor := 0
	while cursor < result.size():
		var current := result[cursor]
		cursor += 1
		for link: Dictionary in _segment_links:
			if not is_instance_valid(link.joint) or link.joint.is_queued_for_deletion(): continue
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

## No airborne grace: only intact, non-stepping soles touching terrain drive Torso.
func get_torso_movement_force_legs(_fast_mode_active: bool = false) -> Array[RigidBody3D]:
	var feet: Array[RigidBody3D] = []
	for foot: RigidBody3D in _legs:
		if _chain_is_intact(foot) and not is_leg_stepping(foot) and is_leg_grounded(foot): feet.append(foot)
	return feet

func _apply_torso_response() -> void:
	_last_torso_response_force = Vector3.ZERO
	_last_auxiliary_support_force = Vector3.ZERO
	if _segments.is_empty(): return
	_update_segment_metrics()
	var gravity := _gravity_acceleration()
	var up := -gravity.normalized() if not gravity.is_zero_approx() else Vector3.UP
	var direction := get_input_movement_direction().slide(up).normalized() if input_enabled else Vector3.ZERO
	var eligible := get_torso_movement_force_legs()
	var contact_heights: Dictionary = {}
	for foot: RigidBody3D in _legs:
		var contact := _get_stance_chain_contact(foot)
		if not contact.is_empty():
			var id := int(_chains[foot].root.get_meta(&"body_segment_id", 0))
			if not contact_heights.has(id): contact_heights[id] = []
			contact_heights[id].append(Vector3(contact.position).dot(up))
	var total_torso_mass := 0.0
	for body: RigidBody3D in get_torso_parts(): total_torso_mass += body.mass
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
		var offset := Vector3.ZERO
		var grounded := 0
		var floor_height := 0.0
		for foot: RigidBody3D in segment.feet:
			if foot not in eligible: continue
			grounded += 1
			offset += foot.global_position - _get_leg_rest_world_position(foot)
			floor_height += _support_surface_contact(foot).position.dot(up)
		var denominator := maxf(1.0, float(segment.feet.size()))
		var force := Vector3.ZERO
		if torso_response_enabled and grounded > 0:
			force = offset.slide(up) * torso_force_per_unit * sqrt(_get_configured_movement_scale()) / denominator
			if scale_response_by_torso_mass: force *= torso_mass / maxf(response_reference_mass, 0.01)
			if grounded_directional_feedback:
				force = direction * maxf(0.0, force.dot(direction))
			if not bool(segment.balanced): force *= unbalanced_movement_multiplier
		segment.auxiliary_force = 0.0
		var supported := contact_count > 0 and _adhesion_release_time_remaining <= 0.0
		var target_blend := 1.0 if supported else 0.0
		segment.support_blend = move_toward(float(segment.support_blend), target_blend, _support_delta / maxf(sub_torso_support_ramp_time, 0.001))
		if sub_torso_support_enabled and not sub_torsos.is_empty():
			# Remove support immediately in air; ramp only its return after contact.
			if supported:
				var height_error: float = (floor_height / float(grounded) if grounded > 0 else support_floor) + segment.reference_height - Vector3(segment.torso_center).dot(up)
				var damping := 2.0 * sub_torso_damping_ratio * sqrt(sub_torso_height_gain)
				var lift: float = segment.mass * (gravity.length() * sub_torso_weight_share + height_error * sub_torso_height_gain - vertical_speed / torso_mass * damping)
				lift = clampf(lift, 0.0, segment.mass * gravity.length() * sub_torso_maximum_weight_share) * segment.support_blend
				# Nonnegative weights make off-center supports carry the segment COM.
				var points: Array[Vector3] = []
				for body: RigidBody3D in sub_torsos: points.append(_stance_body_center(body))
				var weights := _solve_stance_support_weights(points, segment.center, up)
				for index: int in range(sub_torsos.size()): sub_torsos[index].apply_central_force(up * lift * weights[index])
				segment.auxiliary_force = lift
				_last_auxiliary_support_force += up * lift
		elif torso_response_enabled and supported and grounded > 0:
			var damping := maxf(torso_vertical_response_damping, 2.0 * vertical_response_damping_ratio * sqrt(vertical_response_gain))
			var vertical: float = offset.dot(up) / denominator * vertical_response_gain * torso_mass - vertical_speed * damping
			force += up * clampf(vertical, -torso_mass * gravity.length() * downward_response_weight_limit, torso_mass * gravity.length() * upward_response_weight_limit)
		if maximum_torso_force > 0.0: force = force.limit_length(_get_torso_response_force_limit(total_torso_mass) * torso_mass / maxf(total_torso_mass, 0.01))
		_last_torso_response_force += force
		for body: RigidBody3D in torsos: body.apply_central_force(force * body.mass / torso_mass)

func get_body_segment_diagnostics() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: int in _segments:
		var segment: Dictionary = _segments[id]
		result.append({"segment": id, "torso_count": segment.bodies.size(), "foot_count": segment.feet.size(), "mass": segment.mass, "center": segment.center, "reference_height": segment.reference_height, "balanced": segment.balanced, "support_blend": segment.support_blend, "auxiliary_force": segment.auxiliary_force})
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
	if not direction.is_zero_approx():
		var forward := direction.slide(Vector3.UP).normalized()
		correction = -velocity.slide(forward) - forward * maxf(velocity.dot(forward) - get_expected_horizontal_speed(), 0.0)
	var controlled_mass := 0.0
	for body: RigidBody3D in _character_body_cache:
		if is_instance_valid(body) and not _is_body_broken(body): controlled_mass += body.mass
	_ground_brake_force = (correction * maxf(controlled_mass, mass) * ground_brake_gain).limit_length(maximum_ground_brake_force)
	# A force intended to brake a whole body must not act only on an off-center reference Torso.
	for body: RigidBody3D in torsos:
		body.apply_central_force(_ground_brake_force * body.mass / mass)

func set_recovery_control_active(active: bool) -> void:
	if recovery_control_active == active: return
	recovery_control_active = active
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
	if recovery_control_active:
		_begin_ground_probe_frame()
		_remove_invalid_legs()
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
	if stabilize_torso_tilt:
		var tilt_started: int = _movement_perf.start()
		_apply_torso_tilt_stabilization()
		_movement_perf.finish(&"torso_tilt", tilt_started)
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
	var chain: Dictionary = _chains[foot]
	# Prefer the sole, then the most distal grounded limb. Never count both.
	for index: int in range(chain.bodies.size() - 1):
		var body: RigidBody3D = chain.bodies[index]
		if index > 0 and (not leg_limbs_can_support or not _has_body_tag(body, LEG_LIMB_TAG)): continue
		var hit := _support_surface_contact(body)
		if not hit.is_empty() and _surface_is_walkable(hit.normal):
			return {"body": body, "index": index, "position": hit.position, "normal": hit.normal}
	return {}

func _stance_chain_can_support(foot: RigidBody3D) -> bool:
	return stabilize_stance_limbs and _adhesion_release_time_remaining <= 0.0 and not is_leg_stepping(foot) and _chain_is_intact(foot) and not _get_stance_chain_contact(foot).is_empty()

func _apply_stance_stabilization(delta: float) -> void:
	_stance_last_applied_frame = Engine.get_physics_frames()
	_update_stance_allocation(delta)
	for foot: RigidBody3D in _legs:
		if not _chains.has(foot): continue
		var chain: Dictionary = _chains[foot]
		if not _stance_chain_can_support(foot):
			chain.stance_weight = 0.0
			chain.stance_torques = []
			chain.stance_torque_vectors = []
			continue
		chain.stance_torques = []
		chain.stance_torque_vectors = []
		chain.stance_weight = minf(1.0, float(chain.stance_weight) + delta / maxf(stance_recovery_duration, 0.0001))
		for index: int in range(chain.joints.size()):
			var child: RigidBody3D = chain.bodies[index]
			var parent_body: RigidBody3D = chain.bodies[index + 1]
			var joint: Generic6DOFJoint3D = chain.joints[index]
			var weight: float = chain.stance_weight
			var torque: Vector3
			if auto_allocate_stance_torque:
				var load: Vector3 = _stance_joint_loads.get(joint, Vector3.ZERO)
				var balance_scale := 1.0 if _stance_support_balanced else maxf(unbalanced_stance_multiplier, 0.25)
				torque = _calculate_allocated_stance_torque(child, parent_body, chain.rest_rotations[index], load * balance_scale, weight)
			else:
				torque = (_calculate_stance_torque(child, parent_body, chain.rest_rotations[index]) * weight).limit_length(maximum_stance_torque)
			chain.stance_torques.append(torque.length())
			chain.stance_torque_vectors.append(torque)
			_apply_stance_joint_torque(child, parent_body, torque)

func _stance_leg_side_released(body: RigidBody3D, other: RigidBody3D) -> bool:
	return (_has_body_tag(body, LEG_TAG) or _has_body_tag(body, FORELEG_TAG)) and _has_body_tag(other, LEG_LIMB_TAG)

func _apply_stance_joint_torque(child: RigidBody3D, parent_body: RigidBody3D, torque: Vector3) -> void:
	# Leg and ForeLeg soles are oriented by their surface-alignment controller. The limb
	# still receives support torque; ordinary joints retain paired torques.
	if not child.freeze and not _stance_leg_side_released(child, parent_body):
		child.apply_torque(torque)
	if not parent_body.freeze and not _stance_leg_side_released(parent_body, child):
		parent_body.apply_torque(-torque)

func _stance_body_center(body: RigidBody3D) -> Vector3:
	return body.to_global(body.center_of_mass) if body.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM else body.global_position

func _gravity_acceleration() -> Vector3:
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
		if not groups.has(id): groups[id] = {"indices": [], "mass": 0.0, "center": Vector3.ZERO, "auxiliary": 0.0}
		groups[id].indices.append(index)
	# Unsupported segments transfer their load through the segment joints.
	for id: int in _segments:
		var segment: Dictionary = _segments[id]
		var owner := id
		var connected := _connected_body_segments(id)
		if not groups.has(owner):
			var nearest := INF
			for candidate: int in groups:
				if candidate not in connected: continue
				var distance: float = Vector3(segment.center).distance_squared_to(_segments[candidate].center)
				if distance < nearest:
					nearest = distance
					owner = candidate
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
		_segments[id].balanced = error <= stance_balance_tolerance
		_stance_support_balanced = _stance_support_balanced and bool(_segments[id].balanced)
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
	return {"character": get_parent().name, "torso": _torso.name if is_instance_valid(_torso) else &"", "foot_count": feet.size(), "support_count": support_count, "feet": feet, "state": get_step_state_name(), "stride": get_current_step_distance(), "lift": _get_effective_step_height(), "target_error": get_active_leg_horizontal_target_distance(), "total_mass": _stance_total_mass, "center_of_mass": _stance_center_of_mass, "support_balanced": _stance_support_balanced, "balance_error": _stance_balance_error, "torso_response_force": _last_torso_response_force, "recovery": recovery.get_recovery_diagnostics() if recovery != null else {}}

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
			var estimate_valid := auto_allocate_stance_torque and allocation_age >= 0 and eligible and _stance_joint_loads.has(joint)
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
				"angular_spring_enabled": [joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING), joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING), joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING)],
				"angular_spring_stiffness": Vector3(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS), joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS), joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS)),
				"angular_spring_damping": Vector3(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING), joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING), joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING)),
				"leg_side_released": _stance_leg_side_released(child, parent_body) or _stance_leg_side_released(parent_body, child),
				"child_applied_vector": commanded if not child.freeze and not _stance_leg_side_released(child, parent_body) else Vector3.ZERO,
				"parent_applied_vector": -commanded if not parent_body.freeze and not _stance_leg_side_released(parent_body, child) else Vector3.ZERO,
				"eligible": eligible, "chain_intact": _chain_is_intact(foot), "grounded": is_leg_grounded(foot), "stepping": is_leg_stepping(foot),
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
	return {"normal_control": normal_control, "recovery_active": recovery_control_active, "auto_allocation": auto_allocate_stance_torque,
		"contact_enter_distance": support_contact_enter_distance, "contact_exit_distance": maxf(support_contact_enter_distance, support_contact_exit_distance), "load_smoothing_time": support_load_smoothing_time,
		"vertical_response_gain": vertical_response_gain, "vertical_damping_ratio": vertical_response_damping_ratio,
		"stance_enabled": stabilize_stance_limbs, "total_mass": _stance_total_mass, "torso_mass": torso_mass,
		"total_weight": _stance_total_mass * gravity.length(), "estimated_ground_reaction": maxf(0.0, _stance_total_mass * gravity.length() - (_last_torso_response_force + _last_auxiliary_support_force).dot(-gravity.normalized())), "torso_weight": torso_mass * gravity.length(), "torso_response_force": _last_torso_response_force, "torso_response_force_limit": _get_torso_response_force_limit(torso_mass),
		"supporting_feet": supporting_feet, "foot_count": _legs.size(), "center_of_mass": _stance_center_of_mass,
		"support_balanced": _stance_support_balanced, "balance_error": _stance_balance_error, "balance_tolerance": stance_balance_tolerance,
		"segments": get_body_segment_diagnostics(), "auxiliary_support_force": _last_auxiliary_support_force, "unbalanced_compensation": maxf(unbalanced_stance_multiplier, 0.25), "applied_age_frames": applied_age,
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
	var new_step := _step_state == StepState.IDLE or leg != _active_leg
	if new_step:
		_step_has_lifted = false
		var hit := _get_surface_below_leg(leg, surface_adhesion_probe_distance)
		_step_start_clearance = maxf(0.0, (_get_foot_world_position(leg) - Vector3(hit.position)).dot(Vector3(hit.normal))) if not hit.is_empty() else 0.0
	super._begin_leg_motion(leg, target, target_normal, input_direction)

func _apply_leg_tracking_force(desired_position: Vector3, desired_velocity: Vector3) -> void:
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
	_tracking_position_error = desired_position - _active_leg.global_position
	var velocity_error := desired_velocity - _active_leg.linear_velocity
	var acceleration := _tracking_position_error * step_position_gain * _active_movement_scale + velocity_error * step_velocity_gain * sqrt(_active_movement_scale)
	acceleration = acceleration.limit_length(maximum_step_acceleration * pow(_active_movement_scale, 1.5))
	# Remove the weight feedforward on touchdown, so the foot can settle instead of hovering.
	var gravity_weight := 1.0 if _step_state == StepState.MOVING else clampf(gap / minimum_step_lift_clearance, 0.0, 1.0)
	_tracking_gravity_force = -_gravity_acceleration() * gravity_mass * gravity_weight if step_gravity_compensation else Vector3.ZERO
	var requested := acceleration * _tracking_mass + _tracking_gravity_force
	_tracking_force_limit = minf(maximum_mass_scaled_step_force, _tracking_mass * maximum_step_acceleration * pow(_active_movement_scale, 1.5) + _tracking_gravity_force.length())
	_tracking_force_limited = requested.length() > _tracking_force_limit
	_tracking_force = requested.limit_length(_tracking_force_limit)
	_active_leg.apply_central_force(_tracking_force)

func _is_step_target_reached(close_enough: bool) -> bool:
	return close_enough and (_step_has_lifted or not mass_scaled_step_drive)

func _accept_grounded_step_timeout() -> bool:
	return false

func _handle_step_timeout(grounded: bool) -> void:
	_failed_step_count += 1
	_last_step_failure = &"landing_timeout_unreached" if grounded else &"landing_timeout_airborne"
	if not _step_has_lifted and mass_scaled_step_drive: _last_step_failure = &"step_never_lifted"
	# Try another chain after failure, without recording a successful touchdown.
	if not _legs.is_empty() and not _current_step.extra.get("resource_step", false): _next_leg_index = (_next_leg_index + 1) % _legs.size()
	cancel_step(_last_step_failure)

func _calculate_leg_adhesion_force(leg: RigidBody3D, hit: Dictionary, multiplier: float) -> Vector3:
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
	var acceleration := (error * foot_alignment_strength - leg.angular_velocity.slide(normal) * foot_alignment_damping).limit_length(maximum_foot_alignment_acceleration)
	var inverse := _stance_inverse_inertia(leg)
	if absf(inverse.determinant()) < 1e-18: return Vector3.ZERO
	return (inverse.inverse() * acceleration).limit_length(maximum_foot_alignment_torque)

func update_leg_surface_adhesion() -> void:
	super.update_leg_surface_adhesion()
	_foot_alignment_torques.clear()
	if not surface_adhesion_enabled or not align_support_feet_to_surface or _adhesion_release_time_remaining > 0.0: return
	for foot: RigidBody3D in _legs:
		if is_leg_stepping(foot) or not _chain_is_intact(foot): continue
		var normal := get_leg_adhesion_surface_normal(foot)
		if normal.is_zero_approx() or not _surface_is_walkable(normal) or not is_leg_grounded(foot): continue
		var torque := _calculate_foot_alignment_torque(foot, normal)
		_foot_alignment_torques[foot] = torque
		if not torque.is_zero_approx():
			foot.sleeping = false
			foot.apply_torque(torque)

func get_support_foot_diagnostics(leg: RigidBody3D) -> Dictionary:
	var result := super.get_support_foot_diagnostics(leg)
	var hit := _get_surface_below_leg(leg, surface_adhesion_probe_distance)
	result["ground_gap"] = (_get_foot_world_position(leg) - Vector3(hit.position)).dot(Vector3(hit.normal)) if not hit.is_empty() else -1.0
	result["alignment_torque"] = _foot_alignment_torques.get(leg, Vector3.ZERO)
	var extra: Dictionary = get_leg_step_diagnostics(leg).extra
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
