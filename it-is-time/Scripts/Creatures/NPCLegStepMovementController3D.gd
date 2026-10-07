extends "res://Scripts/Creatures/LegStepMovementControllerBase3D.gd"

@export_group("NPC Input")
@export var state_machine_path: NodePath = NodePath("../NPCStateMachine3D")

var _state_machine: Node

@export_group("Hip Reach Planning")
@export var extension_trigger_enabled: bool = true
@export_range(0.01, 0.5, 0.01) var hip_reach_margin: float = 0.15
@export_range(0.0, 0.5, 0.01) var extension_lead_time: float = 0.12
var _reach_diagnostics: Dictionary = {}
@export_range(0.0, 100.0, 0.5) var standing_height_gain: float = 25.0
@export_range(0.0, 30.0, 0.5) var standing_height_damping: float = 10.0
var _standing_height: float = 0.0
var _standing_force: Vector3 = Vector3.ZERO
var _hip_restore_pending := false

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _hip_restore_pending and not _turn_planning_active and _step_state == StepState.IDLE:
		restore_base_hip_joint_limits()

## Do not shrink a joint around a leg that has not returned to its authored range.
func restore_base_hip_joint_limits() -> void:
	_hip_restore_pending = false
	for leg: RigidBody3D in _hip_joints_by_leg:
		if not is_instance_valid(leg) or not leg.is_inside_tree() or _is_body_broken(leg):
			continue
		var joint := _hip_joints_by_leg[leg] as Generic6DOFJoint3D
		if not is_instance_valid(joint) or not joint.is_inside_tree() or not _hip_joint_base_limits.has(joint):
			continue
		var geometry := _hip_geometry(leg)
		if geometry.is_empty():
			continue
		var offset: Vector3 = geometry.offset
		var limits: Vector4 = _hip_joint_base_limits[joint]
		if offset.x < limits.x or offset.x > limits.y or offset.z < limits.z or offset.z > limits.w:
			_hip_restore_pending = true
			continue
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, limits.x)
		joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, limits.y)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, limits.z)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, limits.w)

func _apply_torso_response() -> void:
	super._apply_torso_response()
	_standing_force = Vector3.ZERO
	if not torso_response_enabled or not is_instance_valid(_torso) or _torso.freeze or _is_body_broken(_torso): return
	var supports := _contact_drive_supports(get_leg_parts())
	if supports.is_empty(): return
	var floor_height := 0.0
	var count := 0
	for leg: RigidBody3D in supports:
		var hit := _get_surface_below_leg(leg,ground_probe_distance)
		if not hit.is_empty(): floor_height += float(hit.position.y); count += 1
	if count == 0: return
	var mass := 0.0
	for body: RigidBody3D in _character_body_cache:
		if is_instance_valid(body) and not _is_body_broken(body) and not _has_leg_tag(body): mass += body.mass
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity",9.8)
	var error := floor_height/count+_standing_height-_torso.global_position.y
	var lift := clampf(mass*(gravity+error*standing_height_gain-_torso.linear_velocity.y*standing_height_damping),0.0,mass*gravity*1.5)
	_standing_force = Vector3.UP*lift
	_torso.apply_central_force(_standing_force)

## Stance feet authorize traction; the body receives it. Ground pins remain intact.
func _get_contact_drive_body(_foot: RigidBody3D) -> RigidBody3D:
	return _torso if is_instance_valid(_torso) and not _is_body_broken(_torso) else null

func _hip_geometry(leg: RigidBody3D) -> Dictionary:
	var joint := _hip_joints_by_leg.get(leg) as Generic6DOFJoint3D
	if not is_instance_valid(joint) or not _hip_reference_frames.has(joint): return {}
	var a := joint.get_node_or_null(joint.node_a) as RigidBody3D
	if not is_instance_valid(a): return {}
	var ref: Dictionary = _hip_reference_frames[joint]
	var frame: Basis = a.global_basis * ref.basis_a
	return {"joint": joint, "frame": frame, "offset": frame.inverse() * (leg.to_global(ref.b)-a.to_global(ref.a))}

func _hip_target_offset(leg: RigidBody3D, target: Vector3) -> Vector3:
	var geometry := _hip_geometry(leg)
	return Vector3.ZERO if geometry.is_empty() else Vector3(geometry.offset) + Basis(geometry.frame).inverse() * (target-leg.global_position)

func _is_landing_point_valid(leg: RigidBody3D, current_foot: Vector3, hit: Dictionary) -> bool:
	if not super._is_landing_point_valid(leg,current_foot,hit): return false
	var geometry := _hip_geometry(leg)
	if geometry.is_empty(): return true
	var offset := _hip_target_offset(leg,_body_position_for_ground_contact(leg,hit.position))
	var joint: Generic6DOFJoint3D = geometry.joint
	for i: int in range(3):
		var axis: String = ["x","y","z"][i]
		if not bool(joint.call("get_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)): continue
		var low: float = joint.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT)
		var high: float = joint.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
		var minimum := -maximum_dynamic_hip_limit if auto_expand_hip_limits else low
		var maximum := maximum_dynamic_hip_limit if auto_expand_hip_limits else high
		if offset[i] - hip_reach_margin < minimum or offset[i] + hip_reach_margin > maximum:
			_last_landing_rejection_reason = &"hip_target_out_of_reach"
			return false
	return true

func _expand_hip_joint_for_step(leg: RigidBody3D, target: Vector3) -> void:
	if not auto_expand_hip_limits: return
	var geometry := _hip_geometry(leg)
	if geometry.is_empty(): return
	var joint: Generic6DOFJoint3D = geometry.joint
	var offset := _hip_target_offset(leg,target)
	# Include the lift arc and current displacement; never tighten around an existing pose.
	var lift := _get_effective_step_height()
	for i: int in range(3):
		var axis: String = ["x","y","z"][i]
		if not bool(joint.call("get_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)): continue
		var low: float = joint.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT)
		var high: float = joint.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
		var excursion := absf((Basis(geometry.frame).inverse()*Vector3.UP)[i])*lift
		var needed := maxf(absf(Vector3(geometry.offset)[i]),absf(offset[i])) + excursion + hip_reach_margin
		var extent := maxf(maxf(absf(low),absf(high)),minf(needed,maximum_dynamic_hip_limit))
		joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,-extent)
		joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,extent)

func try_start_step(direction: Vector3 = Vector3.RIGHT) -> bool:
	if not extension_trigger_enabled or is_fast_speed_active() or _turn_planning_active: return super.try_start_step(direction)
	if _step_state != StepState.IDLE or direction.is_zero_approx() or not is_instance_valid(_torso): return false
	var legs := get_leg_parts()
	var selected := -1
	var smallest := INF
	var startup := _torso.linear_velocity.slide(Vector3.UP).length() < 0.2
	for index: int in range(legs.size()):
		var leg := legs[(_next_leg_index+index)%legs.size()]
		if not is_leg_grounded(leg) or not _can_start_step_with_support(leg): continue
		var geometry := _hip_geometry(leg)
		if geometry.is_empty(): continue
		var joint: Generic6DOFJoint3D = geometry.joint
		var travel := Basis(geometry.frame).inverse()*direction.slide(Vector3.UP).normalized()
		var remaining := INF
		for i: int in range(3):
			if absf(travel[i]) < 0.001: continue
			var axis: String = ["x","y","z"][i]
			if not bool(joint.call("get_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)): continue
			var boundary: float = joint.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT if travel[i]>0.0 else Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
			remaining = minf(remaining,(Vector3(geometry.offset)[i]-boundary)/travel[i])
		var threshold := hip_reach_margin + maxf(_torso.linear_velocity.dot(direction.normalized()),0.0)*(get_current_step_duration()+extension_lead_time)
		if (startup or remaining <= threshold) and remaining < smallest:
			smallest = remaining
			selected = legs.find(leg)
	_reach_diagnostics = {"startup": startup, "remaining": smallest, "selected": legs[selected].name if selected >= 0 else &"none"}
	if selected < 0: return false
	_next_leg_index = selected
	return super.try_start_step(direction)

func _begin_leg_motion(leg: RigidBody3D, target: Vector3, target_normal: Vector3 = Vector3.UP, input_direction: Vector3 = Vector3.ZERO) -> void:
	super._begin_leg_motion(leg, target, target_normal, input_direction)
	# StepMotion is reused. Contact evidence must belong to this swing only.
	_current_step.extra["npc_lifted"] = false

func _update_active_step(delta: float) -> void:
	if is_instance_valid(_active_leg):
		var hit := _get_surface_below_leg(_active_leg,surface_adhesion_probe_distance)
		if not hit.is_empty():
			var gap := (_get_foot_world_position(_active_leg)-Vector3(hit.position)).dot(Vector3(hit.normal))
			if gap > 0.06: _current_step.extra["npc_lifted"] = true
			if _current_step.extra.get("npc_lifted",false) and gap <= 0.025 and _active_leg.linear_velocity.dot(Vector3(hit.normal)) <= 0.0 and hit.collider in _active_leg.get_colliding_bodies():
				# End horizontal pursuit at real re-contact; the stance pin brakes the foot.
				var foot := _active_leg
				_finish_current_step()
				_update_support_foot_lock(foot,hit.normal)
				return
	super._update_active_step(delta)

func get_npc_motion_execution_diagnostics() -> Dictionary:
	var result := super.get_npc_motion_execution_diagnostics()
	result["reach_planning"] = _reach_diagnostics.duplicate()
	result["standing_height"] = _standing_height
	result["standing_force"] = _standing_force
	result["approach_speed_scale"] = _state_machine.get_npc_movement_speed_scale(super._get_expected_horizontal_speed()) if is_instance_valid(_state_machine) else 1.0
	result["desired_horizontal_speed"] = get_expected_horizontal_speed()
	return result

func _ready() -> void:
	_state_machine = get_node_or_null(state_machine_path)
	super()
	if is_instance_valid(_torso) and not _legs.is_empty():
		for leg: RigidBody3D in _legs: _standing_height += _torso.global_position.y-_get_foot_world_position(leg).y
		_standing_height /= _legs.size()

func get_input_movement_direction() -> Vector3:
	var source := get_player_command_source()
	if source != null: return source.get_movement_direction()
	if is_instance_valid(_state_machine) and _state_machine.has_method("get_movement_direction"):
		var requested_direction: Variant = _state_machine.call("get_movement_direction")
		if requested_direction is Vector3:
			return requested_direction
	return Vector3.ZERO

func _get_expected_horizontal_speed() -> float:
	var full_speed := super._get_expected_horizontal_speed()
	if get_player_command_source() == null and is_instance_valid(_state_machine):
		return full_speed * _state_machine.get_npc_movement_speed_scale(full_speed)
	return full_speed

func is_fast_speed_active() -> bool:
	if is_instance_valid(_state_machine) and _state_machine.has_method("is_fast_movement_requested"):
		return bool(_state_machine.call("is_fast_movement_requested"))
	return false

func is_burst_requested() -> bool:
	var source := get_player_command_source()
	return source != null and source.is_jump_requested()
