@tool
extends "res://Scripts/Creatures/GeneratedCreatureCharacter3D.gd"
const PHYSICS_DATA = preload("res://Scripts/Creatures/WolfPhysicsData.gd")
const LIMB_CONTROL = preload("res://Scripts/Creatures/GeneratedLimbControl3D.gd")
var _limb_control = LIMB_CONTROL.new()
@export_group("Wolf Physics")
@export var wolf_physics: PHYSICS_DATA = preload("res://Resources/Creatures/WolfPhysics.tres")
func _instantiate_blueprint(blueprint: Dictionary, generator_transform: Transform3D) -> Node3D:
	_limb_control.reset_standing()
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
		if joint.has_meta(&"module_joint_settings"): continue
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
		if joint.has_meta(&"module_joint_settings"): continue
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
	
var _action_joint_limits: Dictionary:
	get: return _limb_control.action_joint_limits

func set_limb_action_limits(feet: Array[RigidBody3D], active: bool) -> void:
	if not active:
		_limb_control.restore_action_limits()
		return
	if wolf_physics == null or not wolf_physics.enabled: return
	var protected_metadata: Array[StringName] = []
	if wolf_physics.foreleg_anti_reverse_enabled: protected_metadata.append(&"wolf_elbow_z_limits")
	if wolf_physics.hind_lower_angle_limit_enabled: protected_metadata.append(&"wolf_hind_lower_z_limits")
	_limb_control.expand_action_limits(get_node("GeneratedLegStepMovementController3D"), feet, wolf_physics.action_z_limit, protected_metadata)

func apply_grounded_standing_pose(movement: Node, delta: float) -> void:
	var action: Node = movement.get_creature_action_controller()
	var charge: Node = get_node_or_null("ChargeAttackController3D")
	var blocked: bool = wolf_physics == null or not wolf_physics.enabled or wolf_physics.independent_torso_support or not wolf_physics.standing_pose_enabled or movement.recovery_control_active or movement._foot_heading_turn_active()
	blocked = blocked or (action != null and action.get_action_diagnostics().active)
	blocked = blocked or (charge != null and charge.is_active())
	var scale: float = 1.0 if blocked else get_node(generator_path).overall_scale
	_limb_control.apply_standing(movement, wolf_physics, scale, delta, blocked)

func get_standing_pose_diagnostics() -> Array[Dictionary]:
	return _limb_control.get_standing_pose_diagnostics()
