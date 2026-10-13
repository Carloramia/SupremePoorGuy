@tool
extends RefCounted

## Fit the intact upper limb between its root anchor and the lower leg's actual
## connector hole. All calculations use GeneratedParts space, including staging.
static func align(container: Node3D) -> int:
	var pairs := _pairs(container)
	var count := 0
	for upper: PhysicalBodyPart3D in pairs:
		var pair: Dictionary = pairs[upper]
		if not pair.has("root") or not pair.has("knee"): continue
		if _align_pair(upper, pair.foot, pair.root, pair.knee): count += 1
	return count

static func _pairs(container: Node3D) -> Dictionary:
	var pairs: Dictionary = {}
	for joint: Generic6DOFJoint3D in container.find_children("*", "Generic6DOFJoint3D", true, false):
		if joint.node_a.is_empty() or joint.node_b.is_empty(): continue
		var a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
		var b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
		if a == null or b == null: continue
		var upper := a if PhysicalBodyPart3D.BodyPartTag.LegLimb in a.tags else b
		if PhysicalBodyPart3D.BodyPartTag.LegLimb not in upper.tags: continue
		var other := b if upper == a else a
		if not pairs.has(upper): pairs[upper] = {}
		if PhysicalBodyPart3D.BodyPartTag.Leg in other.tags:
			pairs[upper].knee = joint
			pairs[upper].foot = other
		elif PhysicalBodyPart3D.BodyPartTag.Torso in other.tags:
			pairs[upper].root = joint
	return pairs

static func _nearest_hole(body: PhysicalBodyPart3D, point: Vector3) -> Node3D:
	var best: Node3D
	var distance := INF
	for key: String in ["JointIn", "JointOut"]:
		var marker := body.get_node_or_null(key) as Node3D
		if marker == null: continue
		var candidate := body.transform * marker.position
		var delta := Vector2(candidate.x - point.x, candidate.y - point.y).length_squared()
		if delta < distance:
			distance = delta
			best = marker
	return best

static func _align_pair(upper: PhysicalBodyPart3D, foot: PhysicalBodyPart3D, root_joint: Generic6DOFJoint3D, knee: Generic6DOFJoint3D) -> bool:
	if upper.is_broken or foot.is_broken: return false
	var model := upper.get_node_or_null("Model") as Node3D
	var root_hole := _nearest_hole(upper, root_joint.position)
	var knee_hole := _nearest_hole(upper, knee.position)
	var foot_hole := _nearest_hole(foot, knee.position)
	if model == null or root_hole == null or knee_hole == null or foot_hole == null or root_hole == knee_hole: return false
	var local_root := model.transform.affine_inverse() * root_hole.transform
	var local_tip := model.transform.affine_inverse() * knee_hole.transform
	var source_delta := local_tip.origin - local_root.origin
	var inverse := upper.transform.affine_inverse()
	var desired_root := inverse * root_joint.position
	var foot_point := foot.transform * foot_hole.position
	var desired_tip := inverse * foot_point
	# Adjacent paper sheets keep their separate Z layers and PartWidth depth.
	# Their holes share XY and the joint lies halfway between their middle planes.
	desired_root.z = root_hole.position.z
	desired_tip.z = knee_hole.position.z
	var desired_delta := desired_tip - desired_root
	var source_length := Vector2(source_delta.x, source_delta.y).length()
	var desired_length := Vector2(desired_delta.x, desired_delta.y).length()
	if minf(source_length, desired_length) < 0.0001: return false
	var orientation := model.basis.orthonormalized()
	var rotated_source := orientation * source_delta
	var angle := atan2(desired_delta.y, desired_delta.x) - atan2(rotated_source.y, rotated_source.x)
	var factor := desired_length / source_length
	var basis := Basis(Vector3.BACK, angle) * orientation * Basis.from_scale(Vector3(factor, factor, model.basis.z.length()))
	model.transform = Transform3D(basis, desired_root - basis * local_root.origin)
	root_hole.transform = model.transform * local_root
	knee_hole.transform = model.transform * local_tip
	var upper_point := upper.transform * knee_hole.position
	var anchor := (upper_point + foot_point) * 0.5
	if not knee.position.is_equal_approx(anchor) and knee.has_meta(&"spider_effective_inertia"):
		knee.remove_meta(&"spider_effective_inertia")
	knee.position = anchor
	knee.set_meta(&"spider_hole_aligned", true)
	knee.set_meta(&"spider_upper_hole", str(knee_hole.name))
	knee.set_meta(&"spider_foot_hole", str(foot_hole.name))
	if knee.has_meta(&"spider_axial_slide"):
		var slide: Dictionary = knee.get_meta(&"spider_axial_slide").duplicate()
		slide.half_travel = 0.0
		knee.set_meta(&"spider_axial_slide", slide)
	upper.set_meta(&"spider_visual_uniform_scale", factor)
	_capture_frame(knee)
	# Saved editor previews need the same positional lock as runtime activation.
	for axis: String in ["x", "y", "z"]:
		knee.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
		knee.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
		knee.call("set_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
		knee.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING, false)
	return true

static func _capture_frame(joint: Generic6DOFJoint3D) -> void:
	for endpoint: String in ["a", "b"]:
		var body := joint.get_node(NodePath(joint.get("node_" + endpoint))) as Node3D
		var frame := body.transform.affine_inverse() * joint.transform
		joint.set_meta(StringName("generated_joint_frame_" + endpoint), frame)
		for marker: Node in body.get_children():
			if marker is Marker3D and marker.get_meta(&"joint_name", "") == str(joint.name):
				marker.position = frame.origin
