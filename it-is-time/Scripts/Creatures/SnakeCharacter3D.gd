@tool
extends "res://Scripts/Creatures/GeneratedCreatureCharacter3D.gd"

const TAIL_DAMAGE_TRANSFER_RATIO := 0.9

## Incoming damage has already passed the struck part's resilience and armor.
func distribute_part_damage(target: PhysicalBodyPart3D, amount: float, source: Node = null) -> float:
	if PhysicalBodyPart3D.BodyPartTag.Torso not in target.tags:
		return target.apply_local_damage(amount, source)
	var tailward: Dictionary = {}
	for node: Node in get_body_connections():
		if not node is Joint3D or node.get_meta(&"generated_connection_kind", "") != "SnakeSpine": continue
		# SnakeSpine is generated from tail (A) to head (B); never infer direction from world X.
		var rear := node.get_node_or_null(node.node_a) as PhysicalBodyPart3D
		var front := node.get_node_or_null(node.node_b) as PhysicalBodyPart3D
		if is_instance_valid(rear) and is_instance_valid(front): tailward[front] = rear
	var current := target
	var remaining := amount
	var applied := 0.0
	var visited: Dictionary = {}
	while is_instance_valid(current) and not current.is_queued_for_deletion() and not current.is_broken:
		visited[current] = true
		var next := tailward.get(current) as PhysicalBodyPart3D
		var transfer := is_instance_valid(next) and not next.is_queued_for_deletion() and not next.is_broken and not visited.has(next) and PhysicalBodyPart3D.BodyPartTag.Torso in next.tags
		var forwarded := remaining * TAIL_DAMAGE_TRANSFER_RATIO if transfer else 0.0
		var local := remaining - forwarded
		applied += current.apply_local_damage(local, source)
		if current.damage_logging_enabled:
			print("[snake_damage_share] character=%s part=%s incoming=%.3f local=%.3f forwarded=%.3f next=%s" % [name,current.name,remaining,local,forwarded,next.name if transfer else &"None"])
		if not transfer: break
		current = next
		remaining = forwarded
	return applied

@export_group("Snake Passive Joints")
## Relative Z bending around the generated pose.
@export_range(0.0, 90.0, 0.1) var snake_bend_limit_degrees: float = 25.0
## Allow passive horizontal twist while the movement controller restores the shared heading.
@export_range(0.0, 90.0, 0.1) var snake_yaw_slack_degrees: float = 30.0
## Symmetric local sliding, relative to the shorter neighboring part's actual X length.
@export_range(0.0, 0.25, 0.005) var snake_joint_x_slack_ratio: float = 0.15
@export_range(0.0, 0.25, 0.005) var snake_joint_y_slack_ratio: float = 0.05

func _init() -> void:
	planar_constraints_enabled = false
	segmented_torso_enabled = false
	segment_rotation_constraints_enabled = false
	segment_transverse_constraints_enabled = false
	segment_translation_springs_enabled = false

func _valid_settings(generator: Node3D) -> bool:
	return super._valid_settings(generator) and is_finite(snake_bend_limit_degrees) and snake_bend_limit_degrees >= 0.0 and snake_bend_limit_degrees <= 90.0 \
		and is_finite(snake_yaw_slack_degrees) and snake_yaw_slack_degrees >= 0.0 and snake_yaw_slack_degrees <= 90.0 \
		and is_finite(snake_joint_x_slack_ratio) and snake_joint_x_slack_ratio >= 0.0 and snake_joint_x_slack_ratio <= 0.25 \
		and is_finite(snake_joint_y_slack_ratio) and snake_joint_y_slack_ratio >= 0.0 and snake_joint_y_slack_ratio <= 0.25

func _instantiate_blueprint(blueprint: Dictionary, generator_transform: Transform3D) -> Node3D:
	var container := super._instantiate_blueprint(blueprint, generator_transform)
	if container == null: return null
	for node: Node in container.get_node("Joints").get_children():
		var joint := node as Generic6DOFJoint3D
		if joint == null: continue
		for axis: String in ["x", "y", "z"]:
			var angle := deg_to_rad(snake_bend_limit_degrees if axis == "z" else snake_yaw_slack_degrees if axis == "y" and joint.get_meta(&"generated_connection_kind", "") in ["SnakeSpine", "SnakeHead"] else 0.0)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -angle)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, angle)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, false)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, false)
	_configure_slide_joints(container)
	return container

func _configure_slide_joints(container: Node) -> void:
	for joint: Generic6DOFJoint3D in container.get_node("Joints").get_children():
		if joint.get_meta(&"generated_connection_kind", "") == "SnakeJaw":
			# Hold the generated closed pose even when the optional attack component is disabled.
			# Bite attacks temporarily widen this limit, then restore it on completion/cancellation.
			joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, 0.0)
			joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, 0.0)
			continue
		if joint.get_meta(&"generated_connection_kind", "") not in ["SnakeSpine", "SnakeHead"]: continue
		var a := joint.get_node_or_null(joint.node_a) as RigidBody3D
		var b := joint.get_node_or_null(joint.node_b) as RigidBody3D
		if a == null or b == null: continue
		var size_a := preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd").bounds(a).size
		var size_b := preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd").bounds(b).size
		var width := minf(size_a.z, size_b.z)
		var length := minf(size_a.x, size_b.x)
		joint.remove_meta(&"snake_slide_xy")
		for axis: String in ["x", "y"]:
			var slack := length * (snake_joint_x_slack_ratio if axis == "x" else snake_joint_y_slack_ratio)
			joint.set_meta(StringName("snake_slide_" + axis), slack)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -slack)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, slack)
		# Preserve the old two-width total stroke, centered on the generated pose.
		joint.remove_meta(&"snake_slide_inward")
		joint.set_meta(&"snake_slide_width", width)
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -width)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, width)

func _activate_parts(container: Node) -> void:
	# Skip leg caches, body-segment migration, planar guides and HeadPositionSupport3D.
	_apply_physics_test_mode()
	_configure_slide_joints(container)
	for node: Node in container.get_children():
		if node is RigidBody3D: node.freeze = false
	preload("res://Scripts/Debug/JointMotionDiagnostics3D.gd").capture_activation(container)
	var movement := get_node_or_null("SnakeMovementController3D")
	if movement != null: movement.refresh_parts()
	var attacks := get_node_or_null("SnakeBiteAttackController3D")
	if attacks != null: attacks.refresh_physics_query_cache()
