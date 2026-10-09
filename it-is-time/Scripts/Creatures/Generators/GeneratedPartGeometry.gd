@tool
extends RefCounted

const RULE = preload("res://Scripts/Creatures/Generators/GeneratedPartSceneRule.gd")

## Return actual local collision bounds, including the collider transform.
static func bounds(part: PhysicalBodyPart3D) -> AABB:
	var collider := part.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider == null or collider.disabled: return AABB()
	var points := PackedVector3Array()
	if collider.shape is ConvexPolygonShape3D:
		points = collider.shape.points
	elif collider.shape is BoxShape3D:
		var half: Vector3 = collider.shape.size * 0.5
		for x: float in [-half.x, half.x]:
			for y: float in [-half.y, half.y]:
				for z: float in [-half.z, half.z]: points.append(Vector3(x,y,z))
	if points.is_empty(): return AABB()
	var result := AABB(collider.transform * points[0], Vector3.ZERO)
	for point: Vector3 in points: result = result.expand(collider.transform * point)
	return result

static func fit(part: PhysicalBodyPart3D, target: Vector3, rule: RULE, role: String = "", paper_depth: float = -1.0) -> AABB:
	if part.get_node_or_null("Sprite3D") == null: return AABB()
	if part.geometry_mode == part.GeometryMode.CUSTOM_MODEL:
		var model := part.get_node_or_null(part.custom_model_path) as Node3D
		if model == null or model == part or not part.is_ancestor_of(model): return AABB()
	part.prepare_generated_geometry()
	var original := bounds(part)
	if not original.size.is_finite() or original.size.x <= 0.0 or original.size.y <= 0.0 or original.size.z <= 0.0:
		return AABB()
	var multiplier := rule.size_multiplier
	if not is_finite(multiplier) or multiplier <= 0.0: return AABB()
	if part.geometry_mode == part.GeometryMode.BOX_FIT:
		target *= multiplier
		var sprite := part.get_node("Sprite3D") as Sprite3D
		var dimensions := target
		if sprite.axis == Vector3.AXIS_X: dimensions = Vector3(target.z,target.y,target.x)
		elif sprite.axis == Vector3.AXIS_Y: dimensions = Vector3(target.x,target.z,target.y)
		part.left_distance = dimensions.x * 0.5
		part.right_distance = dimensions.x * 0.5
		part.top_distance = dimensions.y * 0.5
		part.bottom_distance = dimensions.y * 0.5
		part.collision_thickness = dimensions.z
		part.prepare_generated_geometry()
		if role == "Tail":
			# A box tail grows toward -X from the center of its front shell.
			var tail_bounds := bounds(part)
			var inlet := part.get_node_or_null("JointIn") as Marker3D
			var outlet := part.get_node_or_null("JointOut") as Marker3D
			if inlet != null: inlet.position = tail_bounds.get_center() + Vector3(tail_bounds.size.x * 0.5, 0, 0)
			if outlet != null: outlet.position = tail_bounds.get_center() - Vector3(tail_bounds.size.x * 0.5, 0, 0)
		return bounds(part)
	var ratio := Vector3.ONE
	# Paper depth is fitted separately so source thickness never constrains XY.
	var source_paper_depth := part.paper_volume_enabled
	var final_paper_depth := target.z if paper_depth < 0.0 else paper_depth
	if source_paper_depth and (not is_finite(final_paper_depth) or final_paper_depth <= 0.0): return AABB()
	if rule.size_mode != RULE.SizeMode.KEEP_SIZE:
		ratio = target / original.size
		if rule.size_mode == RULE.SizeMode.FIT_UNIFORM:
			var factor := minf(ratio.x, ratio.y) if source_paper_depth else minf(ratio.x, minf(ratio.y, ratio.z))
			ratio = Vector3.ONE * factor
	ratio *= multiplier
	if source_paper_depth: ratio.z = final_paper_depth / original.size.z
	var scale_basis := Basis.from_scale(ratio)
	var shift := -(scale_basis * original.get_center())
	if rule.align_connectors_to_frame:
		var joint_in := part.get_node_or_null("JointIn") as Marker3D
		if joint_in == null: return AABB()
		if role == "Limb":
			var joint_out := part.get_node_or_null("JointOut") as Marker3D
			if joint_out == null: return AABB()
			var span := joint_in.position - joint_out.position
			if span.length() < 0.001: return AABB()
			var rotation := Basis(Quaternion(span.normalized(), Vector3.UP))
			var factor := target.y / span.length()
			var depth_factor := final_paper_depth / original.size.z if source_paper_depth else target.z * multiplier / original.size.z
			scale_basis = Basis.from_scale(Vector3(factor, factor, depth_factor)) * rotation
			shift = -(scale_basis * (joint_in.position + joint_out.position) * 0.5)
		elif role in ["Leg", "ForeLeg", "Head"]:
			var anchor := Vector3(-target.x * 0.5,0,0) if role == "Head" else Vector3(0,target.y * 0.5,0)
			shift = anchor - scale_basis * joint_in.position
	var collider := part.get_node("CollisionShape3D") as CollisionShape3D
	# Bake collider scaling into a unique convex resource; the rigid body stays unit scale.
	var shape := ConvexPolygonShape3D.new()
	var source := PackedVector3Array()
	if collider.shape is ConvexPolygonShape3D:
		source = collider.shape.points
	else:
		var half: Vector3 = collider.shape.size * 0.5
		for x: float in [-half.x, half.x]:
			for y: float in [-half.y, half.y]:
				for z: float in [-half.z, half.z]: source.append(Vector3(x,y,z))
	var points := PackedVector3Array()
	for point: Vector3 in source: points.append(scale_basis * (collider.transform * point) + shift)
	shape.points = points
	for child: Node in part.get_children():
		if child is Node3D and child != collider:
			var node := child as Node3D
			node.transform = Transform3D(scale_basis * node.basis, scale_basis * node.position + shift)
	collider.transform = Transform3D.IDENTITY
	collider.shape = shape
	part.prepare_generated_geometry()
	return bounds(part)

static func connection_marker(part: PhysicalBodyPart3D, planned: Vector3) -> Vector3:
	var result := planned
	var best := INF
	for key: String in ["JointIn", "JointOut"]:
		var marker := part.get_node_or_null(key) as Marker3D
		if marker == null: continue
		var point := part.transform * marker.position
		var distance := point.distance_squared_to(planned)
		if distance < best:
			best = distance
			result = point
	return result
