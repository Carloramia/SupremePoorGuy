@tool
extends "res://Scripts/Creatures/GeneratedCreatureCharacter3D.gd"

const LIMB_VISUAL_STRETCH = preload("res://Scripts/Creatures/SpiderLimbVisualStretch3D.gd")
const LIMB_HOLE_ALIGNMENT = preload("res://Scripts/Creatures/SpiderLimbHoleAlignment.gd")
var _spider_root_anchors: Dictionary = {}
var _spider_stretch_rows: Array = []
var _spider_stretch_container_id: int = 0
var _spider_stretch_dirty := true

@export_group("Spider Limb Visual Stretch")
## Connect the rendered upper-limb holes to Torso/Leg anchors without changing physics.
@export var spider_limb_visual_stretch_enabled: bool = false:
	set(value):
		spider_limb_visual_stretch_enabled = value
		_spider_stretch_dirty = true
## Each end retains its original size; only the middle changes length.
@export_range(0.05, 0.3, 0.01) var spider_limb_visual_end_ratio: float = 0.15:
	set(value):
		spider_limb_visual_end_ratio = value
		_spider_stretch_dirty = true
@export_group("")

func _process(_delta: float) -> void:
	_update_spider_limb_visuals()

func _exit_tree() -> void:
	_restore_spider_limb_visuals()
	_clear_spider_root_anchors()

func _restore_spider_limb_visuals() -> void:
	for row: RefCounted in _spider_stretch_rows: row.restore()
	_spider_stretch_rows.clear()
	_spider_stretch_container_id = 0

func _update_spider_limb_visuals() -> void:
	var container := get_node_or_null("GeneratedParts")
	var container_id := container.get_instance_id() if container != null else 0
	if Engine.is_editor_hint():
		for row: RefCounted in _spider_stretch_rows:
			if not row.geometry_is_current(): _spider_stretch_dirty = true
	if _spider_stretch_dirty or container_id != _spider_stretch_container_id:
		_restore_spider_limb_visuals()
		_spider_stretch_container_id = container_id
		_spider_stretch_dirty = false
		if spider_limb_visual_stretch_enabled and container != null:
			var connections: Dictionary = {}
			for joint: Generic6DOFJoint3D in container.find_children("*", "Generic6DOFJoint3D", true, false):
				if joint.node_a.is_empty() or joint.node_b.is_empty(): continue
				var a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
				var b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
				if a == null or b == null: continue
				var upper := a if BODY_PART.BodyPartTag.LegLimb in a.tags else b
				if BODY_PART.BodyPartTag.LegLimb not in upper.tags: continue
				var other := b if upper == a else a
				if not connections.has(upper): connections[upper] = {}
				if BODY_PART.BodyPartTag.Leg in other.tags: connections[upper].tip = joint
				elif BODY_PART.BodyPartTag.Torso in other.tags: connections[upper].root = joint
			for upper: PhysicalBodyPart3D in connections:
				var pair: Dictionary = connections[upper]
				if not pair.has("root") or not pair.has("tip"): continue
				var row := LIMB_VISUAL_STRETCH.new()
				if row.configure(upper, pair.root, pair.tip, spider_limb_visual_end_ratio): _spider_stretch_rows.append(row)
	for row: RefCounted in _spider_stretch_rows: row.update()

## Long lower legs bend with the chain rather than behaving as upright feet.
@export_range(0.0, 90.0, 0.5) var spider_leg_bend_limit_degrees: float = 75.0
var _spider_angle_joints: Array[Generic6DOFJoint3D] = []

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	_update_spider_root_anchors(_delta)
	for joint: Generic6DOFJoint3D in _spider_angle_joints:
		if is_instance_valid(joint): _update_spider_world_limits(joint)

func _update_spider_world_limits(joint: Generic6DOFJoint3D) -> void:
	if joint.is_queued_for_deletion() or joint.node_a.is_empty() or joint.node_b.is_empty(): return
	if joint.get_meta(&"spider_attack_knee", false): return
	var data: Dictionary = joint.get_meta(&"spider_world_angle")
	var parent_body := joint.get_node_or_null(data.parent_path) as RigidBody3D
	if parent_body == null: return
	# Measure in the parent's live sheet: quaternion twist about a fixed world
	# Z axis becomes singular when the creature turns through 180 degrees of yaw.
	var current := parent_body.global_basis.orthonormalized()
	var rest := Basis(data.parent_rest_basis).orthonormalized()
	var current_angle := atan2(current.z.dot(Vector3.UP.cross(current.y)), Vector3.UP.dot(current.y))
	var rest_angle := atan2(rest.z.dot(Vector3.UP.cross(rest.y)), Vector3.UP.dot(rest.y))
	var delta := wrapf(current_angle - rest_angle, -PI, PI)
	var center := float(data.initial_angle) + delta
	var bound := deg_to_rad(spider_leg_bend_limit_degrees)
	# Godot's Z limit is A relative to B; the child endpoint changes at the knee.
	var low := -bound - center if data.child_is_a else center - bound
	var high := bound - center if data.child_is_a else center + bound
	var previous_low := joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)
	var previous_high := joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)
	var a := joint.get_node_or_null(joint.node_a) as RigidBody3D
	var b := joint.get_node_or_null(joint.node_b) as RigidBody3D
	if a == null or b == null: return
	var frame_a: Transform3D = joint.get_meta(&"generated_joint_frame_a", Transform3D.IDENTITY)
	var frame_b: Transform3D = joint.get_meta(&"generated_joint_frame_b", Transform3D.IDENTITY)
	var relative := (b.global_basis * frame_b.basis).orthonormalized().inverse() * (a.global_basis * frame_a.basis).orthonormalized()
	var angle := atan2(relative.x.y, relative.x.x)
	var guard := deg_to_rad(5.0)
	# Changing a Jolt angular bound rebuilds its entire constraint. Keep the
	# warm start while both old and desired bounds safely contain the hinge.
	if joint.get_meta(&"spider_world_limits_initialized", false) and previous_low < previous_high and angle > maxf(previous_low, low) + guard and angle < minf(previous_high, high) - guard: return
	joint.set_meta(&"spider_world_limits_initialized", true)
	if not is_equal_approx(previous_low, maxf(low, -PI)): joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, maxf(low, -PI))
	if not is_equal_approx(previous_high, minf(high, PI)): joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, minf(high, PI))

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
	joint.set_meta(&"spider_world_limits_initialized", false)
	_update_spider_world_limits(joint)
@export_range(0.0, 10000.0, 1.0, "or_greater") var spider_leg_spring_stiffness: float = 300.0
@export_range(0.0, 1000.0, 1.0, "or_greater") var spider_leg_spring_damping: float = 30.0
## Spring values are specified per unit of effective hinge inertia (kg m²).
@export var spider_scale_joint_springs: bool = true
@export_group("Spider Independent Torso Support")
## Torso supports its own weight; bounded root joints keep the limbs attached.
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
	# A ring-to-ring knee is a pivot, so axial sliding would separate its holes.
	var locked_hole: bool = knee and bool(joint.get_meta(&"spider_hole_aligned", false))
	var slack := length * ratio if spider_axial_sliding_enabled and not locked_hole else 0.0
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

func _instantiate_blueprint(blueprint: Dictionary, generator_transform: Transform3D) -> Node3D:
	var container := super._instantiate_blueprint(blueprint, generator_transform)
	if container == null: return null
	for part: Node in container.get_children():
		if not part is PhysicalBodyPart3D: continue
		if part.get_meta(&"generated_role", "") == "Leg" and part.geometry_mode == part.GeometryMode.CUSTOM_MODEL and not part.get_meta(&"generated_layout", {}).has("internal_snapshot"):
			# Imported feet point +Y toward the knee; the original box frame points +Y toward the toe.
			var flip := Transform3D(Basis(Vector3.BACK, PI), Vector3.ZERO)
			for child: Node in part.get_children():
				if child is Node3D and not child.has_meta(&"generated_connection_port"):
					child.transform = flip * child.transform
		# Collision follows the original frame, independently of the imported visual silhouette.
		var size: Vector3 = part.get_meta(&"generated_framework_size")
		var shape := BoxShape3D.new()
		shape.resource_local_to_scene = true
		shape.size = size
		var collision := part.get_node("CollisionShape3D") as CollisionShape3D
		collision.transform = Transform3D.IDENTITY
		collision.shape = shape
		part.left_distance = size.x * 0.5
		part.right_distance = size.x * 0.5
		part.top_distance = size.y * 0.5
		part.bottom_distance = size.y * 0.5
		part.collision_thickness = size.z
		part.set_meta(&"generated_size", size)
	LIMB_HOLE_ALIGNMENT.align(container)
	return container

func _activate_parts(container: Node) -> void:
	_clear_spider_root_anchors()
	_restore_spider_limb_visuals()
	LIMB_HOLE_ALIGNMENT.align(container)
	_spider_stretch_dirty = true
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

	_bind_spider_root_anchors()

func _bind_spider_root_anchors() -> void:
	if not Engine.is_editor_hint() and spider_independent_torso_support and not planar_constraints_enabled:
		for joint: Generic6DOFJoint3D in _spider_angle_joints:
			if not is_instance_valid(joint) or joint.is_queued_for_deletion() or joint.node_a.is_empty() or joint.node_b.is_empty(): continue
			if not joint.get_meta(&"spider_independent_root", false): continue
			var torso := joint.get_node(joint.node_b) as RigidBody3D
			if torso.is_broken: continue
			if not _spider_root_anchors.has(torso):
				var anchor := PhysicsServer3D.body_create()
				PhysicsServer3D.body_set_mode(anchor, PhysicsServer3D.BODY_MODE_KINEMATIC)
				PhysicsServer3D.body_set_collision_layer(anchor, 0)
				PhysicsServer3D.body_set_collision_mask(anchor, 0)
				PhysicsServer3D.body_set_state(anchor, PhysicsServer3D.BODY_STATE_TRANSFORM, torso.global_transform)
				PhysicsServer3D.body_set_space(anchor, get_world_3d().space)
				_spider_root_anchors[torso] = anchor
			var upper := joint.get_node(joint.node_a) as RigidBody3D
			# Keep logical NodePaths for damage/chain discovery; the physical parent
			# follows Torso without feeding foot-pin constraint forces back into it.
			PhysicsServer3D.joint_make_generic_6dof(joint.get_rid(), upper.get_rid(), joint.get_meta(&"generated_joint_frame_a"), _spider_root_anchors[torso], joint.get_meta(&"generated_joint_frame_b"))
			for axis: int in 3:
				var suffix: String = ["x", "y", "z"][axis]
				for param: int in Generic6DOFJoint3D.PARAM_MAX:
					PhysicsServer3D.generic_6dof_joint_set_param(joint.get_rid(), axis, param, joint.call("get_param_" + suffix, param))
				for flag: int in Generic6DOFJoint3D.FLAG_MAX:
					PhysicsServer3D.generic_6dof_joint_set_flag(joint.get_rid(), axis, flag, joint.call("get_flag_" + suffix, flag))
			joint.set_meta(&"spider_root_anchor", true)

func _update_spider_root_anchors(delta: float) -> void:
	for torso: Variant in _spider_root_anchors.keys():
		if not is_instance_valid(torso) or torso.is_broken:
			PhysicsServer3D.free_rid(_spider_root_anchors[torso])
			_spider_root_anchors.erase(torso)
			continue
		var target: Transform3D = torso.global_transform
		target.origin += torso.linear_velocity * delta
		if not torso.angular_velocity.is_zero_approx(): target.basis = Basis(torso.angular_velocity.normalized(), torso.angular_velocity.length() * delta) * target.basis
		PhysicsServer3D.body_set_state(_spider_root_anchors[torso], PhysicsServer3D.BODY_STATE_TRANSFORM, target)

func _clear_spider_root_anchors() -> void:
	for anchor: RID in _spider_root_anchors.values(): PhysicsServer3D.free_rid(anchor)
	_spider_root_anchors.clear()

func _sync_planar_constraints() -> void:
	super._sync_planar_constraints()
	if planar_constraints_enabled: _clear_spider_root_anchors()
	else: _bind_spider_root_anchors()
