@tool
extends Generic6DOFJoint3D
## Angular and transverse constraint audit. Axial translation remains spring-driven.
func _ready() -> void:
	capture_reference()

func capture_reference() -> void:
	var a := get_node_or_null(node_a) as RigidBody3D
	var b := get_node_or_null(node_b) as RigidBody3D
	if a == null or b == null: return
	if not has_meta(&"constraint_frame_a"):
		set_meta(&"constraint_frame_a", a.global_transform.affine_inverse() * global_transform)
		set_meta(&"constraint_frame_b", b.global_transform.affine_inverse() * global_transform)

func get_constraint_diagnostics() -> Dictionary:
	var a := get_node_or_null(node_a) as RigidBody3D
	var b := get_node_or_null(node_b) as RigidBody3D
	if a == null or b == null: return {"name": name, "valid": false}
	capture_reference()
	var frame_a: Transform3D = a.global_transform * Transform3D(get_meta(&"constraint_frame_a"))
	var frame_b: Transform3D = b.global_transform * Transform3D(get_meta(&"constraint_frame_b"))
	var local_gap := frame_a.basis.orthonormalized().inverse() * (frame_b.origin - frame_a.origin)
	var relative := frame_a.basis.orthonormalized().inverse() * frame_b.basis.orthonormalized()
	var angles := relative.get_euler() * (180.0 / PI)
	var linear_excess := Vector2(maxf(0.0, absf(local_gap.y) - get_param_y(PARAM_LINEAR_UPPER_LIMIT)), maxf(0.0, absf(local_gap.z) - get_param_z(PARAM_LINEAR_UPPER_LIMIT)))
	return {"name": name, "valid": true, "a": a.name, "b": b.name,
		"segment_a": int(a.get_meta(&"body_segment_id", -1)), "segment_b": int(b.get_meta(&"body_segment_id", -1)),
		"linear_free": not get_flag_x(FLAG_ENABLE_LINEAR_LIMIT) and not get_flag_y(FLAG_ENABLE_LINEAR_LIMIT) and not get_flag_z(FLAG_ENABLE_LINEAR_LIMIT),
		"axial_free": not get_flag_x(FLAG_ENABLE_LINEAR_LIMIT), "transverse_locked": get_flag_y(FLAG_ENABLE_LINEAR_LIMIT) and get_flag_z(FLAG_ENABLE_LINEAR_LIMIT),
		"locked_xy": get_flag_x(FLAG_ENABLE_ANGULAR_LIMIT) and get_flag_y(FLAG_ENABLE_ANGULAR_LIMIT), "z_free": not get_flag_z(FLAG_ENABLE_ANGULAR_LIMIT),
		"angular_lower_degrees": Vector3(get_param_x(PARAM_ANGULAR_LOWER_LIMIT), get_param_y(PARAM_ANGULAR_LOWER_LIMIT), get_param_z(PARAM_ANGULAR_LOWER_LIMIT)) * (180.0 / PI),
		"angular_upper_degrees": Vector3(get_param_x(PARAM_ANGULAR_UPPER_LIMIT), get_param_y(PARAM_ANGULAR_UPPER_LIMIT), get_param_z(PARAM_ANGULAR_UPPER_LIMIT)) * (180.0 / PI),
		"relative_frame_rotation_degrees": angles, "relative_frame_quaternion": relative.get_rotation_quaternion(),
		"locked_xy_error_degrees": Vector2(angles.x, angles.y), "relative_angular_velocity_local": frame_a.basis.inverse() * (b.angular_velocity - a.angular_velocity),
		"anchor_gap_local": local_gap, "transverse_limit": get_param_y(PARAM_LINEAR_UPPER_LIMIT), "transverse_excess": linear_excess,
		"relative_linear_velocity_local": frame_a.basis.inverse() * (b.linear_velocity - a.linear_velocity), "axis_global": frame_a.basis.x,
		"broken_endpoints": a.get("is_broken") == true or b.get("is_broken") == true}
