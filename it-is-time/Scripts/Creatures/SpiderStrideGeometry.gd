extends RefCounted

## Solve flat-ground contact using the captured root/knee frames. Root follow
## stretch and knee spring compression are deliberately not spent as stride.
static func build(root_joint: Generic6DOFJoint3D, knee: Generic6DOFJoint3D, upper: RigidBody3D, foot: RigidBody3D, torso: RigidBody3D, toe: Vector3, reserve: float) -> Dictionary:
	var root_a: Transform3D = root_joint.get_meta(&"generated_joint_frame_a")
	var root_b: Transform3D = root_joint.get_meta(&"generated_joint_frame_b")
	var knee_a: Transform3D = knee.get_meta(&"generated_joint_frame_a")
	var knee_b: Transform3D = knee.get_meta(&"generated_joint_frame_b")
	var anchor := torso.to_global(root_b.origin)
	var frame := (torso.global_basis * root_b.basis).orthonormalized()
	var toe_local := foot.to_local(toe)
	var plane_height := toe.y
	var height := plane_height - anchor.y
	var root_min := root_joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT) + reserve
	var root_max := root_joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT) - reserve
	var knee_min := knee.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT) + reserve
	var knee_max := knee.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT) - reserve
	var world_limits := root_joint.has_meta(&"spider_world_angle")
	if world_limits:
		# The knee's relative range changes with the upper limb's world angle;
		# sample it broadly and filter both bodies against the absolute envelope.
		knee_min = -PI
		knee_max = PI
	if root_min >= root_max or knee_min >= knee_max: return {"valid": false, "reason": "no_angular_clearance"}
	var collision := foot.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or not collision.shape is BoxShape3D: return {"valid": false, "reason": "unsupported_foot_shape"}
	var corners := PackedVector3Array()
	var half: Vector3 = collision.shape.size * 0.5
	for x: float in [-1.0, 1.0]:
		for y: float in [-1.0, 1.0]:
			for z: float in [-1.0, 1.0]: corners.append(collision.transform * (half * Vector3(x, y, z)))
	var points := PackedVector3Array()
	var samples: Array[Dictionary] = []
	var root_inverse := root_a.basis.inverse()
	var upper_offset := root_inverse * (knee_a.origin - root_a.origin)
	var tolerance := maxf(half.length() * 0.0001, 0.00001)
	# For each knee bend, solve the two root angles which put the toe exactly
	# on the ground: A*cos(root)+B*sin(root)=ground height.
	for index: int in 81:
		var knee_angle := lerpf(knee_min, knee_max, float(index) / 80.0)
		var foot_relative := root_inverse * knee_a.basis * Basis(Vector3.BACK, knee_angle) * knee_b.basis.inverse()
		var vector := upper_offset + foot_relative * (toe_local - knee_b.origin)
		var a := (frame * vector).y
		var b := (frame * Vector3.BACK.cross(vector)).y
		var radius := Vector2(a, b).length()
		if radius <= 0.000001 or absf(height) > radius: continue
		var phase := atan2(b, a)
		var angle := acos(clampf(height / radius, -1.0, 1.0))
		for candidate: float in [phase - angle, phase + angle]:
			var root_angle := wrapf(candidate, -PI, PI)
			if root_angle < root_min or root_angle > root_max: continue
			var rotation := Basis(Vector3.BACK, root_angle)
			var foot_basis := frame * rotation * foot_relative
			if world_limits:
				var upper_basis := frame * rotation * root_a.basis.inverse()
				var bound := float(foot.get_meta(&"spider_world_bend_limit")) - reserve
				var upper_axis := upper_basis.y * float(upper.get_meta(&"spider_up_axis_sign"))
				var foot_axis := foot_basis.y * float(foot.get_meta(&"spider_up_axis_sign"))
				if upper_axis.dot(Vector3.UP) < cos(bound) or foot_axis.dot(Vector3.UP) < cos(bound): continue
			var foot_origin := anchor + frame * rotation * upper_offset - foot_basis * knee_b.origin
			var legal := true
			for corner: Vector3 in corners:
				if (foot_origin + foot_basis * corner).y < plane_height - tolerance:
					legal = false
					break
			if not legal: continue
			var point := torso.to_local(foot_origin + foot_basis * toe_local)
			points.append(point)
			samples.append({"point": point, "root_angle": root_angle, "knee_angle": knee_angle})
	return {"valid": points.size() >= 2, "reason": "joint_geometry" if points.size() >= 2 else "no_ground_contact_solution", "points": points, "samples": samples, "reference": torso.to_local(toe), "capture_transform": torso.global_transform, "root_range": Vector2(root_min, root_max), "knee_range": Vector2(knee_min, knee_max), "ground_height": plane_height}

static func interval(geometry: Dictionary, local_direction: Vector3, safety: float) -> Dictionary:
	if not geometry.get("valid", false): return {"valid": false, "reason": geometry.get("reason", "uncaptured")}
	var minimum := INF
	var maximum := -INF
	var reference: Vector3 = geometry.reference
	for point: Vector3 in geometry.points:
		var projection := (point - reference).dot(local_direction)
		minimum = minf(minimum, projection)
		maximum = maxf(maximum, projection)
	# Both forward and rearward travel must be feasible from the rest stance.
	var half_travel := minf(-minimum, maximum) * safety
	return {"valid": half_travel > 0.01, "reason": "joint_geometry" if half_travel > 0.01 else "no_bidirectional_reach", "raw_backward": -minimum, "raw_forward": maximum, "half_travel": maxf(half_travel, 0.0), "stride_limit": maxf(half_travel * 2.0, 0.0), "safety_ratio": safety, "samples": geometry.points.size()}
