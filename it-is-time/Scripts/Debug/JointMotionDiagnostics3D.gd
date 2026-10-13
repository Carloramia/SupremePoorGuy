extends RefCounted
## Captured reference frames are public-node observations, not private solver state.
static func capture_activation(container: Node) -> void:
	for joint: Generic6DOFJoint3D in container.find_children("*", "Generic6DOFJoint3D", true, false):
		var a := joint.get_node_or_null(joint.node_a) as RigidBody3D
		var b := joint.get_node_or_null(joint.node_b) as RigidBody3D
		if a == null or b == null: continue
		joint.set_meta(&"diagnostic_activation_frames", {"a_id": a.get_instance_id(), "b_id": b.get_instance_id(), "frame": Engine.get_physics_frames(), "a": a.global_transform.affine_inverse() * joint.global_transform, "b": b.global_transform.affine_inverse() * joint.global_transform})

static func collect(joint: Generic6DOFJoint3D) -> Dictionary:
	var a := joint.get_node_or_null(joint.node_a) as RigidBody3D
	var b := joint.get_node_or_null(joint.node_b) as RigidBody3D
	var row := {"joint": str(joint.get_path()), "node_a": str(joint.node_a), "node_b": str(joint.node_b), "physics_frame": Engine.get_physics_frames(), "time_ms": Time.get_ticks_msec(), "valid_endpoints": a != null and b != null}
	if a == null or b == null: return row
	row["a"] = _body(a)
	row["b"] = _body(b)
	row["joint_world_transform"] = joint.global_transform
	var reference: Dictionary = joint.get_meta(&"diagnostic_activation_frames", {})
	var valid_reference: bool = reference.get("a_id", 0) == a.get_instance_id() and reference.get("b_id", 0) == b.get_instance_id()
	row["reference_source"] = "activation_snapshot" if valid_reference else "saved_generated_frames"
	row["reference_frame"] = reference.get("frame", -1) if valid_reference else -1
	row["solver_angles_available"] = false
	if not valid_reference and (not joint.has_meta(&"generated_joint_frame_a") or not joint.has_meta(&"generated_joint_frame_b")):
		row["reference_source"] = "unavailable"
		return row
	var fa: Transform3D = reference.a if valid_reference else joint.get_meta(&"generated_joint_frame_a")
	var fb: Transform3D = reference.b if valid_reference else joint.get_meta(&"generated_joint_frame_b")
	row["local_frame_a"] = fa
	row["local_frame_b"] = fb
	var wa := a.global_transform * fa
	var wb := b.global_transform * fb
	var ba := wa.basis.orthonormalized()
	var bb := wb.basis.orthonormalized()
	var relative := ba.inverse() * bb
	row["relative_basis"] = relative
	row["relative_quaternion"] = relative.get_rotation_quaternion()
	row["relative_euler_xyz_degrees"] = relative.get_euler(EULER_ORDER_XYZ) * (180.0 / PI)
	row["relative_euler_yxz_degrees"] = relative.get_euler(EULER_ORDER_YXZ) * (180.0 / PI)
	row["relative_angular_velocity_joint_a"] = ba.inverse() * (b.angular_velocity - a.angular_velocity)
	row["plane_normal_angle_degrees"] = rad_to_deg(ba.z.angle_to(bb.z))
	row["anchor_gap"] = wa.origin.distance_to(wb.origin)
	row["relative_anchor_offset_joint_a"] = ba.inverse() * (wb.origin - wa.origin)
	var limits: Dictionary = {}
	for axis: String in ["x", "y", "z"]:
		limits[axis] = {"angular_enabled": joint.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT), "angular_lower_degrees": rad_to_deg(joint.call("get_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)), "angular_upper_degrees": rad_to_deg(joint.call("get_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)), "angular_spring": joint.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING), "angular_motor": joint.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR), "linear_enabled": joint.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT), "linear_lower": joint.call("get_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT), "linear_upper": joint.call("get_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)}
	row["limits"] = limits
	if joint.has_meta(&"generated_joint_frame_a") and joint.has_meta(&"generated_joint_frame_b"):
		var saved_a: Transform3D = joint.get_meta(&"generated_joint_frame_a")
		var saved_b: Transform3D = joint.get_meta(&"generated_joint_frame_b")
		row["saved_vs_activation_a"] = _frame_difference(saved_a, fa)
		row["saved_vs_activation_b"] = _frame_difference(saved_b, fb)
		row["saved_relative_euler_xyz_degrees"] = ((a.global_basis * saved_a.basis).orthonormalized().inverse() * (b.global_basis * saved_b.basis).orthonormalized()).get_euler(EULER_ORDER_XYZ) * (180.0 / PI)
	return row

static func _frame_difference(saved: Transform3D, actual: Transform3D) -> Dictionary:
	return {"position": saved.origin.distance_to(actual.origin), "rotation_degrees": rad_to_deg(saved.basis.orthonormalized().get_rotation_quaternion().angle_to(actual.basis.orthonormalized().get_rotation_quaternion()))}

static func _body(body: RigidBody3D) -> Dictionary:
	return {"path": str(body.get_path()), "id": body.get_instance_id(), "mass": body.mass, "frozen": body.freeze, "broken": body.get("is_broken") == true, "world_transform": body.global_transform, "angular_velocity": body.angular_velocity, "world_angular_locks": Vector3i(int(body.axis_lock_angular_x), int(body.axis_lock_angular_y), int(body.axis_lock_angular_z))}
