@tool
extends "res://Scripts/Creatures/Generators/BaseCreatureGenerator.gd"

const PART_GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const MAX_BODY_SEGMENTS := 128

@export_group("Snake Materials")
## Repeat one body design to keep the skin continuous. Exact Part Scene Rules can override it.
@export var torso_part_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/Snake/Torso/Snake2BodyFront.tscn")
@export var snake_head_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/Snake/Head/Snake3UpperJaw.tscn")
## 独立下颚，以双方的JointIn连接；使用完整头部素材时可留空。
@export var snake_jaw_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/Snake/Mouth/Snake3LowerJaw.tscn")
## 绕上下颚连接孔的局部Z轴闭合角；不缩放素材，重新生成后生效。
@export_range(-90.0, 90.0, 0.1) var jaw_closed_angle_degrees: float = 32.0

@export_group("Snake Torso Scaling")
## 横轴：沿身体路径从尾端0到头端1；纵轴：Torso的XY等比尺寸倍率（1为素材原始尺寸）。
## 厚度仍由Part Width控制。曲线为空时使用1倍；修改后重新生成，段数随总长自动调整。
@export var segment_size_curve: Curve = _make_torso_curve([[Vector2(0, 1), 0.0, 0.0, 0, 0], [Vector2(1, 1), 0.0, 0.0, 0, 0]], 0.1, 2.0)

@export_group("Snake Raised Front")
## Fraction of body segments forming the raised S, excluding Head; at least three are needed.
@export_range(0.1, 0.9, 0.01) var raised_body_ratio: float = 0.35
## Preferred rise relative to the raised chain's length. Curve is fitted to the available length.
@export_range(0.1, 1.0, 0.01) var raised_height_ratio: float = 0.8
## Controls the forward/backward bend in XY; neither segment geometry nor UVs are warped.
@export_range(0.1, 1.0, 0.01) var s_bend_ratio: float = 0.45
@export_range(0.0, 0.4, 0.01) var head_overlap_ratio: float = 0.15

func _init() -> void:
	_apply_default_preset()

func _get_defaults_path() -> String:
	return "res://Resources/Generators/SnakeGeneratorDefaults.tres"

func _validate_property(property: Dictionary) -> void:
	# Snake has no feet, limbs, SubTorso, network or separate neck; hide those inherited controls.
	if property.name in ["unsymmetrie", "inhomogeneity", "base_foot_size", "minimum_foot_size", "maximum_foot_size", "minimum_feet_distance", "torso_count", "torso_upper_curve", "torso_lower_curve", "torso_height_offset_curve", "sub_torso_size", "sub_torso_x_offset", "sub_torso_height_curve", "torso_minimum_height", "torso_maximum_height", "torso_connection_distance", "base_limb_length", "minimum_segment_height", "maximum_segment_height", "minimum_bend_offset", "maximum_bend_offset", "limb_minimum_size", "limb_maximum_size", "limb_y_matches_segment", "limb_endpoint_merge_distance", "network_extra_endpoint_count", "network_extra_endpoint_padding", "network_center_bias", "network_core_extra_connections", "neck_number", "neck_minimum_length", "neck_maximum_length", "neck_segment_count", "neck_maximum_angle", "neck_block_thickness", "max_neck_overlap_diameter", "head_minimum_size", "head_maximum_size"]:
		property.usage &= ~PROPERTY_USAGE_EDITOR
	if property.name == "body_length":
		property.hint_string = "1,200,0.1,or_greater"
	if property.name == "torso_overlap_percent":
		property.hint_string = "5,35,0.1"

func _source_rule(type: String, node_name: String, key: String = "") -> PART_SCENE_RULE:
	var rule := super.get_part_scene_rule(type, node_name, key)
	if rule != null: return rule
	rule = PART_SCENE_RULE.new()
	rule.part_type = type
	match type:
		"Head": rule.part_scene = snake_head_scene
		"Jaw": rule.part_scene = snake_jaw_scene
		_: rule.part_scene = torso_part_scene
	return rule

func get_part_scene_rule(type: String, node_name: String, key: String = "") -> PART_SCENE_RULE:
	var rule: PART_SCENE_RULE = _copy_default_value(_source_rule(type, node_name, key))
	# The frame already includes the source multiplier. Fit proportionally once, including Overall Scale.
	rule.size_mode = PART_SCENE_RULE.SizeMode.FIT_UNIFORM
	rule.size_multiplier = 1.0
	rule.use_joint_markers = false
	rule.align_connectors_to_frame = false
	return rule

func _piece(node_name: String, role: String, uniform_size: float, dimensions: Dictionary) -> Dictionary:
	var rule := _source_rule(role, node_name, node_name)
	if rule.part_scene == null or not is_finite(rule.size_multiplier) or rule.size_multiplier <= 0.0: return {}
	if not dimensions.has(rule.part_scene):
		var instance := rule.part_scene.instantiate()
		var part := instance as PhysicalBodyPart3D
		if part == null:
			instance.free()
			return {}
		part.prepare_generated_geometry()
		var bounds: AABB = PART_GEOMETRY.bounds(part, false)
		var inlet := part.get_node_or_null("JointIn") as Marker3D
		dimensions[rule.part_scene] = {"size": bounds.size, "inlet": (inlet.position if inlet != null else Vector3.ZERO) - bounds.get_center(), "has_inlet": inlet != null}
		part.free()
	var source: Dictionary = dimensions[rule.part_scene]
	var factor := uniform_size * rule.size_multiplier
	var size: Vector3 = source.size * factor
	if not size.is_finite() or minf(size.x, minf(size.y, size.z)) <= 0.0: return {}
	size.z = part_width
	var piece := {"name": node_name, "part_key": node_name, "role": role, "size": size, "transform": Transform3D.IDENTITY, "segment_id": 0}
	if role in ["Head", "Jaw"]:
		if not source.has_inlet: return {}
		# Uniform fitting recenters the model; the mouth hinge must receive the same transform.
		piece.mouth_hinge_offset = source.inlet * factor
	return piece

func _build_snake_blueprint() -> Dictionary:
	for value: float in [body_length, part_width, torso_overlap_percent, raised_body_ratio, raised_height_ratio, s_bend_ratio, head_overlap_ratio, jaw_closed_angle_degrees]:
		if not is_finite(value): return {}
	if absf(jaw_closed_angle_degrees) > 90.0: return {}
	if body_length <= 0.0 or part_width < 0.01 or torso_overlap_percent < 5.0 or torso_overlap_percent > 35.0: return {}
	if raised_body_ratio < 0.1 or raised_body_ratio > 0.9 or raised_height_ratio < 0.1 or raised_height_ratio > 1.0 or s_bend_ratio < 0.1 or s_bend_ratio > 1.0 or head_overlap_ratio < 0.0 or head_overlap_ratio > 0.4: return {}
	var parts: Array[Dictionary] = []
	var advances: Array[float] = []
	var dimensions := {}
	var length := 0.0
	while length < body_length or parts.size() < 4:
		if parts.size() == MAX_BODY_SEGMENTS: return {}
		var progress := clampf(length / body_length, 0.0, 1.0)
		var factor := segment_size_curve.sample_baked(progress) if segment_size_curve != null and segment_size_curve.point_count > 0 else 1.0
		if not is_finite(factor) or factor < 0.1: return {}
		var piece := _piece("Torso_%03d" % [parts.size() + 1], "Torso", factor, dimensions)
		if piece.is_empty(): return {}
		var advance: float = piece.size.x * (1.0 - torso_overlap_percent / 100.0)
		parts.append(piece)
		advances.append(advance)
		length += advance
	var raised_count := clampi(roundi(parts.size() * raised_body_ratio), 3, parts.size() - 1)
	var grounded_count := parts.size() - raised_count
	var cursor := 0.0
	var endpoints := PackedVector3Array()
	for index: int in grounded_count:
		var part: Dictionary = parts[index]
		var center := Vector3(cursor + advances[index] * 0.5, part.size.y * 0.5, 0)
		part.transform.origin = center
		endpoints.append(Vector3(cursor + advances[index], center.y, 0))
		cursor += advances[index]
	var raised_length := 0.0
	for index: int in range(grounded_count, parts.size()): raised_length += advances[index]
	var curve := _raised_curve(raised_length)
	var curve_origin := endpoints[-1]
	var distance := 0.0
	var start := curve_origin
	for index: int in range(grounded_count, parts.size()):
		distance += advances[index]
		var end := curve_origin + _point_on_curve(curve, distance)
		var direction := end - start
		if direction.length() < 0.001: return {}
		var angle := atan2(direction.y, direction.x)
		parts[index].transform = Transform3D(Basis(Vector3.BACK, angle), (start + end) * 0.5)
		endpoints.append(end)
		start = end
	# Keep the rear soles at Y=0, and lift only the curved chain if its first overhang dips below ground.
	var lowest := 0.0
	for index: int in range(grounded_count, parts.size()):
		var part: Dictionary = parts[index]
		var bounds: AABB = part.transform * AABB(-part.size * 0.5, part.size)
		lowest = minf(lowest, bounds.position.y)
	for index: int in range(grounded_count, parts.size()):
		parts[index].transform.origin.y -= lowest
		endpoints[index].y -= lowest
	var edges: Array[Dictionary] = []
	for index: int in parts.size():
		parts[index]["snake_grounded"] = index < grounded_count
		parts[index].transform.origin.z = 0.0
		if index > 0:
			var anchor := endpoints[index - 1]
			if index == grounded_count: anchor.y -= lowest * 0.5
			edges.append({"a": index - 1, "b": index, "anchor": anchor, "basis": Basis.IDENTITY, "kind": "SnakeSpine"})
	var head := _piece("Head", "Head", 1.0, dimensions)
	if head.is_empty(): return {}
	var tip := endpoints[-1]
	# All rigid body centers share the character's local XY plane.
	head.transform.origin = tip + Vector3(head.size.x * (0.5 - head_overlap_ratio), 0, 0)
	head.transform.origin.z = 0.0
	edges.append({"a": parts.size() - 1, "b": parts.size(), "anchor": tip, "basis": Basis.IDENTITY, "kind": "SnakeHead"})
	parts.append(head)
	if _source_rule("Jaw", "Jaw", "Jaw").part_scene != null:
		var jaw := _piece("Jaw", "Jaw", 1.0, dimensions)
		if jaw.is_empty(): return {}
		var hinge: Vector3 = head.transform * head.mouth_hinge_offset
		hinge.z = 0.0
		# The source artwork is open; rotate around the shared hinge instead of the body center.
		jaw.transform.basis = Basis(Vector3.BACK, deg_to_rad(jaw_closed_angle_degrees))
		jaw.transform.origin = hinge - jaw.transform.basis * jaw.mouth_hinge_offset
		jaw.transform.origin.z = 0.0
		edges.append({"a": parts.size() - 1, "b": parts.size(), "anchor": hinge, "basis": Basis.IDENTITY, "kind": "SnakeJaw"})
		parts.append(jaw)
	return {"parts": parts, "connections": edges, "generator_type": "snake", "paper_depth": part_width, "grounded_count": grounded_count, "raised_count": raised_count, "body_path_length": length}

func _raised_curve(length: float) -> Dictionary:
	# Horizontal end tangents, with the middle returning toward -X, form an upright S.
	var p1 := Vector3(s_bend_ratio, 0, 0)
	var p2 := Vector3(-s_bend_ratio, raised_height_ratio, 0)
	var p3 := Vector3(s_bend_ratio * 0.35, raised_height_ratio, 0)
	var points := PackedVector3Array([Vector3.ZERO])
	var distances := PackedFloat32Array([0.0])
	for index: int in range(1, 257):
		var t := float(index) / 256.0
		var point := 3.0 * (1-t) * (1-t) * t * p1 + 3.0 * (1-t) * t * t * p2 + t * t * t * p3
		distances.append(distances[-1] + points[-1].distance_to(point))
		points.append(point)
	var multiplier := length / distances[-1]
	for index: int in points.size():
		points[index] *= multiplier
		distances[index] *= multiplier
	return {"points": points, "distances": distances}

func _point_on_curve(curve: Dictionary, distance: float) -> Vector3:
	var distances: PackedFloat32Array = curve.distances
	var index := clampi(distances.bsearch(distance), 1, distances.size() - 1)
	var fraction := clampf((distance - distances[index-1]) / (distances[index] - distances[index-1]), 0.0, 1.0)
	return Vector3(curve.points[index-1]).lerp(curve.points[index], fraction)

func generate_torso() -> bool:
	if not is_inside_tree() or not is_finite(overall_scale) or overall_scale < 0.1: return false
	if use_manual_layout: return _generate_manual_framework()
	var blueprint := _build_snake_blueprint()
	if blueprint.is_empty():
		push_warning("[snake_generator] Invalid dimensions, body curve or Part scenes, or more than 128 Torso segments; previous layout retained.")
		return false
	var previous := manual_layout
	manual_layout = MANUAL_LAYOUT.new()
	manual_layout.blueprint = blueprint
	var succeeded := _generate_manual_framework()
	manual_layout = previous
	return succeeded
