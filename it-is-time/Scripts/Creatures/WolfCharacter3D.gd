@tool
extends "res://Scripts/Creatures/GeneratedCreatureCharacter3D.gd"
const PHYSICS_DATA = preload("res://Scripts/Creatures/WolfPhysicsData.gd")
@export_group("Wolf Physics")
@export var wolf_physics: PHYSICS_DATA = preload("res://Resources/Creatures/WolfPhysics.tres")
func _instantiate_blueprint(blueprint: Dictionary, generator_transform: Transform3D) -> Node3D:
	_standing_blends.clear()
	_standing_pose_rows.clear()
	_action_joint_limits.clear()
	var container := super._instantiate_blueprint(blueprint, generator_transform)
	if container != null: _configure_wolf_physics(container)
	return container

func _activate_parts(container: Node) -> void:
	# Saved previews also need the preset before movement caches their joint limits.
	_configure_wolf_physics(container)
	super._activate_parts(container)
	_configure_independent_support(container)

func _configure_independent_support(container: Node) -> void:
	if wolf_physics == null or not wolf_physics.enabled or not wolf_physics.independent_torso_support: return
	var movement := get_node("GeneratedLegStepMovementController3D")
	movement.independent_torso_height_support = true
	movement.sub_torso_support_enabled = true
	movement.sub_torso_weight_share = 1.0
	movement.sub_torso_maximum_weight_share = wolf_physics.torso_support_weight_limit
	movement.auxiliary_support_weight_limit = wolf_physics.torso_support_weight_limit
	for foot: RigidBody3D in movement._chains:
		var chain: Dictionary = movement._chains[foot]
		if chain.joints.is_empty(): continue
		var joint: Generic6DOFJoint3D = chain.joints.back()
		for axis: String in ["x", "y", "z"]:
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING, false)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_MOTOR, false)

func _configure_wolf_physics(container: Node) -> void:
	if wolf_physics == null or not wolf_physics.enabled: return
	var torso_mass := 0.0
	for body: Node in container.get_children():
		if body is PhysicalBodyPart3D and BODY_PART.BodyPartTag.Torso in body.tags and BODY_PART.BodyPartTag.SubTorso not in body.tags:
			torso_mass += body.mass
	var scale: float = get_node(generator_path).overall_scale
	for body: Node in container.get_children():
		if body is PhysicalBodyPart3D and BODY_PART.BodyPartTag.SubTorso in body.tags:
			var mass := maxf(body.mass, maxf(wolf_physics.minimum_subtorso_mass * pow(scale, 3.0), torso_mass * wolf_physics.subtorso_torso_mass_ratio))
			body.mass = minf(mass, maximum_part_mass) if mass_limits_enabled else mass
	var generator := get_node(generator_path)
	var multiplier: float = pow(float(generator.overall_scale),3.0)
	for body: Node in container.get_children():
		if body is PhysicalBodyPart3D and PhysicalBodyPart3D.BodyPartTag.LegLimb in body.tags:
			body.ignore_limb_terrain = not wolf_physics.limb_terrain_collisions_enabled
			var mass: float = maxf(body.mass,wolf_physics.minimum_limb_mass*multiplier)
			body.mass = minf(mass,maximum_part_mass) if mass_limits_enabled else mass
	# Also runs before the generated container enters the tree.
	for joint: Node in container.get_node("Joints").get_children():
		if not joint is Generic6DOFJoint3D: continue
		var a := container.get_node(NodePath(str(joint.node_a).get_file())) as PhysicalBodyPart3D
		var b := container.get_node(NodePath(str(joint.node_b).get_file())) as PhysicalBodyPart3D
		if a == null or b == null: continue
		var a_limb := PhysicalBodyPart3D.BodyPartTag.LegLimb in a.tags
		var b_limb := PhysicalBodyPart3D.BodyPartTag.LegLimb in b.tags
		var z_limit := -1.0
		var x_limit := 0.0
		if a_limb and b_limb: z_limit = wolf_physics.knee_z_limit
		elif (a_limb or b_limb) and (PhysicalBodyPart3D.BodyPartTag.SubTorso in a.tags or PhysicalBodyPart3D.BodyPartTag.SubTorso in b.tags):
			z_limit = wolf_physics.hip_z_limit
			x_limit = wolf_physics.hip_x_limit
		elif (a_limb or b_limb) and (PhysicalBodyPart3D.BodyPartTag.Leg in a.tags or PhysicalBodyPart3D.BodyPartTag.ForeLeg in a.tags or PhysicalBodyPart3D.BodyPartTag.Leg in b.tags or PhysicalBodyPart3D.BodyPartTag.ForeLeg in b.tags): z_limit = wolf_physics.ankle_z_limit
		if z_limit < 0.0: continue
		joint.set_meta(&"authored_walk_limits",Vector3(deg_to_rad(x_limit),0.0,deg_to_rad(z_limit)))
		for axis: String in ["x","y","z"]:
			var protected_bend: bool = (wolf_physics.foreleg_anti_reverse_enabled and joint.has_meta(&"wolf_elbow_z_limits")) or (wolf_physics.hind_lower_angle_limit_enabled and joint.has_meta(&"wolf_hind_lower_z_limits"))
			if axis == "z" and protected_bend:
				var elbow_limits: Vector2 = joint.get_meta(&"wolf_bend_z_limits")
				joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,true)
				joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,elbow_limits.x)
				joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,elbow_limits.y)
				continue
			var limit := deg_to_rad(z_limit if axis == "z" else x_limit if axis == "x" else 0.0)
			var unlimited: bool = axis == "z" and wolf_physics.foreleg_z_rotation_unlimited and joint.get_meta(&"wolf_foreleg_joint",false)
			joint.call("set_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,not unlimited)
			joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,-limit)
			joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,limit)
	
var _action_joint_limits: Dictionary = {}
func set_limb_action_limits(feet: Array[RigidBody3D], active: bool) -> void:
	if not active:
		for joint: Variant in _action_joint_limits:
			if is_instance_valid(joint):
				joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,-float(_action_joint_limits[joint]))
				joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,float(_action_joint_limits[joint]))
		_action_joint_limits.clear()
		return
	if wolf_physics == null or not wolf_physics.enabled: return
	var movement := get_node("GeneratedLegStepMovementController3D")
	for foot: RigidBody3D in feet:
		var chain: Dictionary = movement._chains.get(foot,{})
		for joint: Generic6DOFJoint3D in chain.get("joints",[]):
			if wolf_physics.foreleg_anti_reverse_enabled and joint.has_meta(&"wolf_elbow_z_limits"): continue
			if wolf_physics.hind_lower_angle_limit_enabled and joint.has_meta(&"wolf_hind_lower_z_limits"): continue
			if not joint.has_meta(&"authored_walk_limits"): continue
			var limits: Vector3 = joint.get_meta(&"authored_walk_limits")
			_action_joint_limits[joint] = limits.z
			var angle := maxf(limits.z,deg_to_rad(wolf_physics.action_z_limit))
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,-angle)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,angle)

var _standing_blends: Dictionary = {}
var _standing_pose_rows: Array[Dictionary] = []
var _standing_pose_frame: int = -1

func apply_grounded_standing_pose(movement: Node, delta: float) -> void:
	_standing_pose_rows.clear()
	_standing_pose_frame = Engine.get_physics_frames()
	var action: Node = movement.get_creature_action_controller()
	var charge: Node = get_node_or_null("ChargeAttackController3D")
	var blocked: bool = wolf_physics == null or not wolf_physics.enabled or wolf_physics.independent_torso_support or not wolf_physics.standing_pose_enabled or movement.recovery_control_active or movement._foot_heading_turn_active()
	blocked = blocked or (action != null and action.get_action_diagnostics().active)
	blocked = blocked or (charge != null and charge.is_active())
	if blocked:
		_standing_blends.clear()
		return
	var scale: float = get_node(generator_path).overall_scale
	var torque_limit: float = wolf_physics.standing_maximum_torque * pow(scale, 5.0)
	for foot: RigidBody3D in movement._chains:
		var eligible: bool = movement._chain_is_intact(foot) and not foot.freeze and movement.is_leg_grounded(foot) and not movement.is_leg_stepping(foot) and not movement.is_leg_slipping(foot) and movement._support_pins.has(foot)
		if not eligible:
			_standing_blends.erase(foot)
			continue
		var blend: float = minf(float(_standing_blends.get(foot, 0.0)) + delta / maxf(wolf_physics.standing_blend_time, 0.001), 1.0)
		_standing_blends[foot] = blend
		var chain: Dictionary = movement._chains[foot]
		# Only the knee and hip participate; never command the pinned foot/ankle.
		for index: int in range(1, chain.bodies.size() - 1):
			var child: RigidBody3D = chain.bodies[index]
			var parent_body: RigidBody3D = chain.bodies[index + 1]
			var joint: Generic6DOFJoint3D = chain.joints[index]
			if child.freeze or parent_body.freeze or not joint.has_meta(&"passive_hinge_axis_parent"): continue
			var axis: Vector3 = (parent_body.global_basis * Vector3(joint.get_meta(&"passive_hinge_axis_parent"))).normalized()
			var error: float = movement._stance_rotation_error(child, parent_body, chain.rest_rotations[index]).dot(axis)
			var controlled_error := signf(error) * maxf(absf(error) - deg_to_rad(wolf_physics.standing_dead_zone_degrees), 0.0)
			var rate := (child.angular_velocity - parent_body.angular_velocity).dot(axis)
			var acceleration := clampf(controlled_error * wolf_physics.standing_strength - rate * wolf_physics.standing_damping, -wolf_physics.standing_maximum_acceleration, wolf_physics.standing_maximum_acceleration)
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
