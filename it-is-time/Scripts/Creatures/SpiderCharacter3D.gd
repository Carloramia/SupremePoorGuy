@tool
extends "res://Scripts/Creatures/GeneratedCreatureCharacter3D.gd"

## Long lower legs bend with the chain rather than behaving as upright feet.
@export_range(0.0, 90.0, 0.5) var spider_leg_bend_limit_degrees: float = 75.0
var _spider_angle_joints: Array[Generic6DOFJoint3D] = []

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	for joint: Generic6DOFJoint3D in _spider_angle_joints:
		if is_instance_valid(joint): _update_spider_world_limits(joint)

func _update_spider_world_limits(joint: Generic6DOFJoint3D) -> void:
	var data: Dictionary = joint.get_meta(&"spider_world_angle")
	var parent_body := joint.get_node_or_null(data.parent_path) as RigidBody3D
	if parent_body == null: return
	var rotation := (parent_body.global_basis.orthonormalized() * Basis(data.parent_rest_basis).inverse()).get_rotation_quaternion()
	var axis := joint.global_basis.z.normalized()
	var delta := wrapf(2.0 * atan2(Vector3(rotation.x, rotation.y, rotation.z).dot(axis), rotation.w), -PI, PI)
	var center := float(data.initial_angle) + delta
	var bound := deg_to_rad(spider_leg_bend_limit_degrees)
	# Godot's Z limit is A relative to B; the child endpoint changes at the knee.
	var low := -bound - center if data.child_is_a else center - bound
	var high := bound - center if data.child_is_a else center + bound
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, maxf(low, -PI))
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, minf(high, PI))

func _capture_spider_world_limits(joint: Generic6DOFJoint3D) -> void:
	var a := joint.get_node(joint.node_a) as PhysicalBodyPart3D
	var b := joint.get_node(joint.node_b) as PhysicalBodyPart3D
	var knee := BODY_PART.BodyPartTag.Leg in b.tags
	var child := b if knee else a
	var parent_body := a if knee else b
	var sign_up := 1.0 if child.global_basis.y.dot(Vector3.UP) >= 0.0 else -1.0
	child.set_meta(&"spider_up_axis_sign", sign_up)
	child.set_meta(&"spider_world_bend_limit", deg_to_rad(spider_leg_bend_limit_degrees))
	var up_axis := child.global_basis.y.normalized() * sign_up
	var angle := atan2(joint.global_basis.z.normalized().dot(Vector3.UP.cross(up_axis)), Vector3.UP.dot(up_axis))
	joint.set_meta(&"spider_world_angle", {"child_is_a": not knee, "initial_angle": angle, "parent_path": joint.get_path_to(parent_body), "parent_rest_basis": parent_body.global_basis.orthonormalized()})
	_spider_angle_joints.append(joint)
	_update_spider_world_limits(joint)
@export_range(0.0, 10000.0, 1.0, "or_greater") var spider_leg_spring_stiffness: float = 300.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var spider_leg_spring_damping: float = 30.0
## Spring values are specified per unit of effective hinge inertia (kg m²).
@export var spider_scale_joint_springs: bool = true
@export_group("Spider Independent Torso Support")
## Root joints retain angular limits, but cannot transmit linear load to Torso.
@export var spider_independent_torso_support: bool = true
@export_group("Spider Axial Sliding")
@export var spider_axial_sliding_enabled: bool = true
## One-sided travel at each connection, as a fraction of upper-limb length.
@export_range(0.0, 0.1, 0.005) var spider_root_slide_ratio: float = 0.02
@export_range(0.0, 0.1, 0.005) var spider_knee_slide_ratio: float = 0.03
@export_range(0.1, 30.0, 0.1) var spider_axial_spring_frequency: float = 8.0
@export_range(0.1, 3.0, 0.05) var spider_axial_damping_ratio: float = 1.0

func _configure_spider_axial_joint(joint: Generic6DOFJoint3D, a: PhysicalBodyPart3D, b: PhysicalBodyPart3D) -> void:
	var upper := a if BODY_PART.BodyPartTag.LegLimb in a.tags else b
	var other := b if upper == a else a
	var collision := upper.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or not collision.shape is BoxShape3D: return
	# The solver's linear reference is endpoint A. Make it the upper limb,
	# with joint Y along that limb, so the slide axis follows its rotation.
	# Rebuild after changing the frame; moving the Joint node alone does not
	# update the physics server's captured local frames.
	joint.node_a = NodePath("")
	joint.node_b = NodePath("")
	joint.global_basis = upper.global_basis.orthonormalized()
	joint.node_a = joint.get_path_to(upper)
	joint.node_b = joint.get_path_to(other)
	joint.set_meta(&"generated_joint_frame_a", upper.global_transform.affine_inverse() * joint.global_transform)
	joint.set_meta(&"generated_joint_frame_b", other.global_transform.affine_inverse() * joint.global_transform)
	joint.set_meta(&"generated_rest_b_relative_a", upper.global_basis.orthonormalized().get_rotation_quaternion().inverse() * other.global_basis.orthonormalized().get_rotation_quaternion())
	var length: float = collision.shape.size.y * collision.global_basis.y.length()
	var knee := BODY_PART.BodyPartTag.Leg in other.tags
	var ratio := spider_knee_slide_ratio if knee else spider_root_slide_ratio
	var slack := length * ratio if spider_axial_sliding_enabled else 0.0
	var mass := upper.mass * other.mass / maxf(upper.mass + other.mass, 0.000001)
	var omega := TAU * spider_axial_spring_frequency
	var stiffness := mass * omega * omega
	var damping := 2.0 * spider_axial_damping_ratio * mass * omega
	for axis: String in ["x", "y", "z"]:
		var travel := slack if axis == "y" else 0.0
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -travel)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, travel)
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_MOTOR, false)
		joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING, travel > 0.0)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_SPRING_STIFFNESS, stiffness if travel > 0.0 else 0.0)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_SPRING_DAMPING, damping if travel > 0.0 else 0.0)
		joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_SPRING_EQUILIBRIUM_POINT, 0.0)
	joint.set_meta(&"spider_axial_slide", {"upper": upper.name, "connection": "knee" if knee else "root", "half_travel": slack, "upper_length": length, "effective_mass": mass, "stiffness": stiffness, "damping": damping})
	if spider_independent_torso_support and not knee:
		for axis: String in ["x", "y", "z"]:
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, false)
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING, false)
	joint.set_meta(&"spider_independent_root", spider_independent_torso_support and not knee)

func get_spider_joint_spring(joint: Generic6DOFJoint3D) -> Vector2:
	var inertia := 1.0
	if spider_scale_joint_springs:
		# Cache geometry, not a world-axis inertia: yaw/hinge motion must not
		# change the tuning. Regeneration creates new joints and new caches.
		if not joint.has_meta(&"spider_effective_inertia"):
			var a := joint.get_node_or_null(joint.node_a) as RigidBody3D
			var b := joint.get_node_or_null(joint.node_b) as RigidBody3D
			var ia := _spider_hinge_inertia(a, joint)
			var ib := _spider_hinge_inertia(b, joint)
			joint.set_meta(&"spider_effective_inertia", ia * ib / maxf(ia + ib, 0.000001))
		inertia = float(joint.get_meta(&"spider_effective_inertia"))
	return Vector2(spider_leg_spring_stiffness, spider_leg_spring_damping) * inertia

func _spider_hinge_inertia(body: RigidBody3D, joint: Generic6DOFJoint3D) -> float:
	if body == null: return 1.0
	var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var intrinsic := 0.001
	var axis := joint.global_basis.z.normalized()
	if collision != null and collision.shape is BoxShape3D:
		var size: Vector3 = collision.shape.size * collision.global_basis.get_scale().abs()
		var local_axis := collision.global_basis.orthonormalized().inverse() * axis
		var diagonal := Vector3(size.y * size.y + size.z * size.z, size.x * size.x + size.z * size.z, size.x * size.x + size.y * size.y) * body.mass / 12.0
		intrinsic = diagonal.dot(local_axis * local_axis)
	var center := body.to_global(body.center_of_mass) if body.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM else (collision.global_position if collision != null else body.global_position)
	return maxf(intrinsic + body.mass * (center - joint.global_position).slide(axis).length_squared(), 0.000001)

func _activate_parts(container: Node) -> void:
	_spider_angle_joints.clear()
	for part: Node in container.get_children():
		if part is PhysicalBodyPart3D and BODY_PART.BodyPartTag.Leg in part.tags:
			part.lock_foot_pitch_roll = false
	for node: Node in container.find_children("*", "Generic6DOFJoint3D", true, false):
		var joint := node as Generic6DOFJoint3D
		var a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
		var b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
		if a == null or b == null: continue
		if BODY_PART.BodyPartTag.LegLimb not in a.tags and BODY_PART.BodyPartTag.LegLimb not in b.tags: continue
		_configure_spider_axial_joint(joint, a, b)
		# Joint frames follow the generated XY sheets; only their Z hinge bends.
		var limits := Vector3(0.0, 0.0, deg_to_rad(spider_leg_bend_limit_degrees))
		joint.set_meta(&"authored_walk_limits", limits)
		for axis: String in ["x", "y", "z"]:
			var angle := limits[["x", "y", "z"].find(axis)]
			joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -angle)
			joint.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, angle)
		_capture_spider_world_limits(joint)
	super._activate_parts(container)
	# The generic activation intentionally disables limb springs. These long
	# legs need an explicit resting bend instead of the generic upright-foot lock.
	for node: Node in container.find_children("*", "Generic6DOFJoint3D", true, false):
		var joint := node as Generic6DOFJoint3D
		if not joint.has_meta(&"authored_walk_limits"): continue
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, true)
		var spring := get_spider_joint_spring(joint)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS, spring.x)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING, spring.y)
