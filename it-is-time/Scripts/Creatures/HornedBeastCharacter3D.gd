@tool
extends "res://Scripts/Creatures/GeneratedCreatureCharacter3D.gd"
const PHYSICS_DATA = preload("res://Scripts/Creatures/HornedBeastPhysicsData.gd")
const LIMB_CONTROL = preload("res://Scripts/Creatures/GeneratedLimbControl3D.gd")
var _limb_control = LIMB_CONTROL.new()
@export_group("Horned Beast Physics")
@export var horned_physics: PHYSICS_DATA = preload("res://Resources/Creatures/HornedBeastPhysics.tres")
func _instantiate_blueprint(blueprint: Dictionary, generator_transform: Transform3D) -> Node3D:
	_limb_control.reset_standing()
	var container := super._instantiate_blueprint(blueprint,generator_transform)
	if container == null or horned_physics == null or not horned_physics.enabled: return container
	var generator := get_node(generator_path)
	var multiplier: float = pow(float(generator.overall_scale),3.0)
	for body: Node in container.get_children():
		if body is PhysicalBodyPart3D and PhysicalBodyPart3D.BodyPartTag.LegLimb in body.tags:
			var mass: float = maxf(body.mass,horned_physics.minimum_limb_mass*multiplier)
			body.mass = minf(mass,maximum_part_mass) if mass_limits_enabled else mass
	# The container is not in the SceneTree yet; resolve relative endpoints directly.
	for joint: Node in container.get_node("Joints").get_children():
		if not joint is Generic6DOFJoint3D: continue
		var a := container.get_node(NodePath(str(joint.node_a).get_file())) as PhysicalBodyPart3D
		var b := container.get_node(NodePath(str(joint.node_b).get_file())) as PhysicalBodyPart3D
		var a_limb := PhysicalBodyPart3D.BodyPartTag.LegLimb in a.tags
		var b_limb := PhysicalBodyPart3D.BodyPartTag.LegLimb in b.tags
		var z_limit := -1.0
		var x_limit := 0.0
		if a_limb and b_limb: z_limit = horned_physics.knee_z_limit
		elif (a_limb or b_limb) and (PhysicalBodyPart3D.BodyPartTag.SubTorso in a.tags or PhysicalBodyPart3D.BodyPartTag.SubTorso in b.tags):
			z_limit = horned_physics.hip_z_limit
			x_limit = horned_physics.hip_x_limit
		elif (a_limb or b_limb) and (PhysicalBodyPart3D.BodyPartTag.Leg in a.tags or PhysicalBodyPart3D.BodyPartTag.ForeLeg in a.tags or PhysicalBodyPart3D.BodyPartTag.Leg in b.tags or PhysicalBodyPart3D.BodyPartTag.ForeLeg in b.tags): z_limit = horned_physics.ankle_z_limit
		if z_limit < 0.0: continue
		joint.set_meta(&"authored_walk_limits",Vector3(deg_to_rad(x_limit),0.0,deg_to_rad(z_limit)))
		for axis: String in ["x","y","z"]:
			var limit := deg_to_rad(z_limit if axis == "z" else x_limit if axis == "x" else 0.0)
			joint.call("set_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,true)
			joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,-limit)
			joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,limit)
	return container

var _action_joint_limits: Dictionary:
	get: return _limb_control.action_joint_limits

func set_limb_action_limits(feet: Array[RigidBody3D], active: bool) -> void:
	if not active:
		_limb_control.restore_action_limits()
		return
	if horned_physics == null or not horned_physics.enabled: return
	_limb_control.expand_action_limits(get_node("GeneratedLegStepMovementController3D"), feet, horned_physics.action_z_limit)

func apply_grounded_standing_pose(movement: Node, delta: float) -> void:
	var action: Node = movement.get_creature_action_controller()
	var charge: Node = get_node_or_null("ChargeAttackController3D")
	var blocked: bool = horned_physics == null or not horned_physics.enabled or not horned_physics.standing_pose_enabled or movement.recovery_control_active or movement._foot_heading_turn_active()
	blocked = blocked or (action != null and action.get_action_diagnostics().active)
	blocked = blocked or (charge != null and charge.is_active())
	var scale: float = 1.0 if blocked else get_node(generator_path).overall_scale
	_limb_control.apply_standing(movement, horned_physics, scale, delta, blocked)

func get_standing_pose_diagnostics() -> Array[Dictionary]:
	return _limb_control.get_standing_pose_diagnostics()
