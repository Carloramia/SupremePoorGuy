@tool
extends RefCounted

var action_joint_limits: Dictionary = {}
var _standing_blends: Dictionary = {}
var _standing_pose_rows: Array[Dictionary] = []
var _standing_pose_frame: int = -1

func reset_standing() -> void:
	_standing_blends.clear()
	_standing_pose_rows.clear()

func restore_action_limits() -> void:
	for joint: Variant in action_joint_limits:
		if is_instance_valid(joint) and not joint.is_queued_for_deletion():
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -float(action_joint_limits[joint]))
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, float(action_joint_limits[joint]))
	action_joint_limits.clear()

func expand_action_limits(movement: Node, feet: Array[RigidBody3D], degrees: float, protected_metadata: Array[StringName] = []) -> void:
	for foot: RigidBody3D in feet:
		if not movement._chain_is_intact(foot): continue
		var chain: Dictionary = movement._chains.get(foot, {})
		for joint: Variant in chain.get("joints", []):
			if not is_instance_valid(joint) or joint.is_queued_for_deletion(): continue
			var protected_bend := false
			for key: StringName in protected_metadata:
				if joint.has_meta(key): protected_bend = true; break
			if protected_bend or not joint.has_meta(&"authored_walk_limits"): continue
			var limits: Vector3 = joint.get_meta(&"authored_walk_limits")
			action_joint_limits[joint] = limits.z
			var angle := maxf(limits.z, deg_to_rad(degrees))
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -angle)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, angle)

func apply_standing(movement: Node, physics: Resource, scale: float, delta: float, blocked: bool) -> void:
	_standing_pose_rows.clear()
	_standing_pose_frame = Engine.get_physics_frames()
	if blocked:
		_standing_blends.clear()
		return
	var torque_limit: float = physics.standing_maximum_torque * pow(scale, 5.0)
	for foot: Variant in movement._chains:
		var eligible: bool = movement._chain_is_intact(foot) and not foot.freeze and movement.is_leg_grounded(foot) and not movement.is_leg_stepping(foot) and not movement.is_leg_slipping(foot) and movement._support_pins.has(foot)
		if not eligible:
			_standing_blends.erase(foot)
			continue
		var blend: float = minf(float(_standing_blends.get(foot, 0.0)) + delta / maxf(physics.standing_blend_time, 0.001), 1.0)
		_standing_blends[foot] = blend
		var chain: Dictionary = movement._chains[foot]
		# Keep the pinned foot/ankle out of the standing servo.
		for index: int in range(1, chain.bodies.size() - 1):
			var child: RigidBody3D = chain.bodies[index]
			var parent_body: RigidBody3D = chain.bodies[index + 1]
			var joint: Generic6DOFJoint3D = chain.joints[index]
			if child.freeze or parent_body.freeze or not joint.has_meta(&"passive_hinge_axis_parent"): continue
			var axis: Vector3 = (parent_body.global_basis * Vector3(joint.get_meta(&"passive_hinge_axis_parent"))).normalized()
			var error: float = movement._stance_rotation_error(child, parent_body, chain.rest_rotations[index]).dot(axis)
			var controlled_error := signf(error) * maxf(absf(error) - deg_to_rad(physics.standing_dead_zone_degrees), 0.0)
			var rate := (child.angular_velocity - parent_body.angular_velocity).dot(axis)
			var acceleration := clampf(controlled_error * physics.standing_strength - rate * physics.standing_damping, -physics.standing_maximum_acceleration, physics.standing_maximum_acceleration)
			var child_inverse: Basis = movement._stance_inverse_inertia(child)
			var parent_inverse: Basis = movement._stance_inverse_inertia(parent_body)
			var inverse: float = axis.dot(child_inverse * axis) + axis.dot(parent_inverse * axis)
			var scalar := clampf(acceleration / maxf(inverse, 0.000001), -torque_limit, torque_limit) * blend
			var torque := axis * scalar
			child.apply_torque(torque)
			parent_body.apply_torque(-torque)
			_standing_pose_rows.append({"foot":foot.name, "joint":joint.name, "error_degrees":rad_to_deg(error), "blend":blend, "torque":torque, "limit":torque_limit})

func get_standing_pose_diagnostics() -> Array[Dictionary]:
	if Engine.get_physics_frames() - _standing_pose_frame > 1: return []
	return _standing_pose_rows
