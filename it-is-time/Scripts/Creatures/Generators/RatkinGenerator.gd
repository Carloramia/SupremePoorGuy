@tool
extends "res://Scripts/Creatures/Generators/BaseCreatureGenerator.gd"

const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const PART_ROOT := "res://Scenes/Creatures/Bodyparts/Ratkin/"

@export_group("Ratkin Standing Layout")
@export_range(0.1, 5.0, 0.01) var torso_height: float = 1.8
## Align the illustrated waist bands; a small depth offset avoids coplanar overlap.
@export var torso_pelvis_offset: Vector3 = Vector3(0.26, 0.0, 0.005)
@export_range(0.1, 3.0, 0.01) var pelvis_height: float = 0.7
@export_range(0.1, 3.0, 0.01) var head_height: float = 1.08
## Round left ear and pointed right ear heights, preserving each source image's proportions.
@export var ear_heights: Vector2 = Vector2(0.9, 0.8)
@export_range(0.1, 3.0, 0.01) var leg_pair_width: float = 0.16
## Hip to ankle: upper, lower. Feet are separate.
@export var leg_segment_lengths: Vector2 = Vector2(0.9, 0.7)
## Angles from vertical, positive toward +X. Mild alternating bends preserve standing reach.
@export var leg_bend_degrees: Vector2 = Vector2(12.0, -18.0)
@export_range(0.05, 1.0, 0.01) var foot_height: float = 0.32
@export_range(0.05, 1.0, 0.01) var hip_support_size: float = 0.16

@export_group("Ratkin Arms")
@export_range(0.1, 3.0, 0.01) var arm_pair_width: float = 0.16
@export var arm_segment_lengths: Vector2 = Vector2(0.8, 0.7)
@export var arm_bend_degrees: Vector2 = Vector2(5.0, 15.0)
@export_range(0.05, 1.0, 0.01) var hand_height: float = 0.35
@export_range(0.0, 1.0, 0.01) var shoulder_height_ratio: float = 0.8

@export_group("Ratkin Tail")
@export var tail_enabled: bool = true
@export_range(0.1, 5.0, 0.01) var tail_height: float = 1.25
## Direction from root to tip, relative to -X; positive angles raise the tip.
@export_range(-80.0, 80.0, 0.1) var tail_angle_degrees: float = -15.0
@export var tail_root_offset: Vector3 = Vector3.ZERO
@export_group("Ratkin Decorations")
@export var ears_enabled: bool = true
@export var neck_mane_enabled: bool = true

func _get_defaults_path() -> String:
	return "res://Resources/Generators/RatkinGeneratorDefaults.tres"

func get_part_scene_rule(part_type: String, part_name: String, part_key: String = "") -> PART_SCENE_RULE:
	var authored := super.get_part_scene_rule(part_type, part_name, part_key)
	if authored != null: return authored
	var path := ""
	match part_name:
		"Torso": path = "Torso/TorsoNoJointCaps"
		"Pelvis": path = "Torso/Pelvis"
		"Head": path = "Head/HeadMain"
		"Tail": path = "Tail/Tail"
		"NeckMane": path = "Torso/NeckMane"
		"EarLeft": path = "Head/EarRound"
		"EarRight": path = "Head/EarRound"
		"Leg_1": path = "Legs/Right/Foot"
		"Arm_1": path = "Arms/Right/Hand"
		"Arm_2": path = "Arms/Left/Hand"
		_:
			if part_name.begins_with("SubTorso_"): path = "Connectors/Rivet"
			elif part_name.begins_with("Leg_"):
				var side := "Left" if part_name.begins_with("Leg_1") else "Right"
				var piece := "Foot"
				if part_name.ends_with("_Limb_2"): piece = "UpperLeg"
				elif part_name.ends_with("_Limb_1"): piece = "LowerLeg"
				path = "Legs/" + side + "/" + piece
			elif part_name.begins_with("Arm_"):
				var side := "Left" if part_name.begins_with("Arm_1") else "Right"
				var piece := "Hand"
				if part_name.ends_with("_Limb_2"): piece = "UpperArm"
				elif part_name.ends_with("_Limb_1"): piece = "Forearm"
				path = "Arms/" + side + "/" + piece
	if path.is_empty(): return null
	var rule := PART_SCENE_RULE.new()
	rule.part_key = part_key if not part_key.is_empty() else part_name
	rule.part_type = part_type
	rule.part_scene = load(PART_ROOT + path + ".tscn") as PackedScene
	rule.size_mode = PART_SCENE_RULE.SizeMode.FIT_UNIFORM if part_name in ["Torso", "Head", "EarLeft", "EarRight"] else PART_SCENE_RULE.SizeMode.KEEP_SIZE
	return rule

func generate_torso() -> bool:
	if use_manual_layout: return _generate_manual_framework()
	if not is_inside_tree() or not is_finite(overall_scale) or overall_scale < 0.1: return false
	var blueprint := _build_ratkin_blueprint()
	if blueprint.is_empty():
		push_warning("[ratkin_generator] Invalid dimensions or Part connectors; previous layout retained.")
		return false
	var previous := manual_layout
	manual_layout = MANUAL_LAYOUT.new()
	manual_layout.blueprint = blueprint
	var succeeded := _generate_manual_framework()
	manual_layout = previous
	return succeeded

func _piece(node_name: String, role: String, height: float, span: float = -1.0, sub_torso: bool = false) -> Dictionary:
	var type := "SubTorso" if sub_torso else ("LegLimb" if role == "Limb" else role)
	var rule := get_part_scene_rule(type, node_name, node_name)
	if rule == null or rule.part_scene == null: return {}
	var part := rule.part_scene.instantiate() as PhysicalBodyPart3D
	if part == null: return {}
	var inlet := part.get_node_or_null("JointIn") as Marker3D
	var outlet := part.get_node_or_null("JointOut") as Marker3D
	var original := GEOMETRY.bounds(part)
	if inlet == null or outlet == null or original.size.y <= 0.0:
		part.free()
		return {}
	var factor := height / original.size.y
	if span > 0.0:
		var native_span := inlet.position.distance_to(outlet.position)
		if native_span < 0.001:
			part.free()
			return {}
		factor = span / native_span
	var target := original.size * factor
	target.z = part_width
	var actual := GEOMETRY.fit(part, target, rule, role, part_width)
	var layout := {"name":node_name, "part_key":node_name, "role":role, "size":actual.size,
		"transform":Transform3D.IDENTITY, "segment_id":0, "_in":inlet.position,
		"_out":outlet.position, "_bounds":actual}
	if sub_torso: layout["sub_torso"] = true
	part.free()
	return layout if actual.size != Vector3.ZERO else {}

func _place(piece: Dictionary, anchor: Vector3) -> void:
	piece.transform.origin = anchor - piece.transform.basis * Vector3(piece._in)

func _center(piece: Dictionary, center: Vector3) -> void:
	piece.transform.origin = center - piece.transform.basis * piece._bounds.get_center()

func _port(piece: Dictionary, outlet: bool = false) -> Vector3:
	return Transform3D(piece.transform) * Vector3(piece._out if outlet else piece._in)

func _direction(angle_degrees: float) -> Vector3:
	var angle := deg_to_rad(angle_degrees)
	return Vector3(sin(angle), -cos(angle), 0.0)

func _orient(piece: Dictionary, direction: Vector3) -> void:
	var native: Vector3 = piece._out - piece._in
	piece.transform.basis = Basis(Quaternion(native.normalized(), direction.normalized()))

func _join(edges: Array[Dictionary], a: int, b: int, anchor: Vector3, kind: String) -> void:
	edges.append({"a":a, "b":b, "anchor":anchor, "basis":Basis.IDENTITY, "kind":kind})

func _build_ratkin_blueprint() -> Dictionary:
	for value: float in [torso_height, pelvis_height, head_height, leg_pair_width, foot_height, hip_support_size, arm_pair_width, hand_height, tail_height, part_width]:
		if not is_finite(value) or value <= 0.0: return {}
	if not leg_segment_lengths.is_finite() or not arm_segment_lengths.is_finite() or not leg_bend_degrees.is_finite() or not arm_bend_degrees.is_finite() or not tail_root_offset.is_finite() or not torso_pelvis_offset.is_finite(): return {}
	if minf(leg_segment_lengths.x, leg_segment_lengths.y) <= 0.0 or minf(arm_segment_lengths.x, arm_segment_lengths.y) <= 0.0: return {}
	if not is_finite(tail_angle_degrees) or not is_finite(shoulder_height_ratio): return {}
	if not ear_heights.is_finite() or minf(ear_heights.x, ear_heights.y) <= 0.0: return {}
	for angle: float in [leg_bend_degrees.x, leg_bend_degrees.y, arm_bend_degrees.x, arm_bend_degrees.y]:
		if absf(angle) >= 75.0: return {}
	var parts: Array[Dictionary] = []
	var edges: Array[Dictionary] = []
	var torso := _piece("Torso", "Torso", torso_height)
	var pelvis := _piece("Pelvis", "Torso", pelvis_height)
	if torso.is_empty() or pelvis.is_empty(): return {}
	parts.append(torso)
	parts.append(pelvis)
	var hip_height := 0.0
	for side: int in 2:
		var prefix := "Leg_%d" % [side + 1]
		var z := leg_pair_width * (-0.5 if side == 0 else 0.5)
		var foot := _piece(prefix, "Leg", foot_height)
		var support := _piece("SubTorso_" + prefix, "Torso", hip_support_size, -1.0, true)
		if foot.is_empty() or support.is_empty(): return {}
		var ankle_y: float = foot._in.y - foot._bounds.position.y
		var hip := Vector3(0.0, ankle_y, z)
		var limbs: Array[Dictionary] = []
		for link: int in 2:
			var limb := _piece(prefix + "_Limb_%d" % [2-link], "Limb", 1.0, leg_segment_lengths[link])
			if limb.is_empty(): return {}
			_orient(limb, _direction(leg_bend_degrees[link]))
			# KEEP_SIZE preserves authored connector spans, not the requested frame length.
			hip -= limb.transform.basis * (Vector3(limb._out) - Vector3(limb._in))
			limbs.append(limb)
		hip_height += hip.y * 0.5
		_center(support, hip)
		var previous := parts.size()
		parts.append(support)
		_join(edges, 1, previous, hip, "Torso")
		var anchor := hip
		for link: int in 2:
			var limb := limbs[link]
			_place(limb, anchor)
			_join(edges, previous, parts.size(), anchor, "Limb")
			previous = parts.size()
			parts.append(limb)
			anchor = _port(limb, true)
		_place(foot, anchor)
		_join(edges, previous, parts.size(), anchor, "Limb")
		parts.append(foot)
	_center(pelvis, Vector3(0, hip_height + pelvis_height * 0.15, 0))
	var pelvis_box: AABB = pelvis.transform * pelvis._bounds
	_center(torso, Vector3(0, pelvis_box.end.y + torso._bounds.size.y * 0.5 - pelvis._bounds.size.y * 0.15, 0) + torso_pelvis_offset)
	_join(edges, 0, 1, Vector3(0, pelvis_box.end.y, 0), "Torso")
	var torso_box: AABB = torso.transform * torso._bounds
	for side: int in 2:
		var prefix := "Arm_%d" % [side + 1]
		var anchor := Vector3(0, lerpf(torso_box.position.y, torso_box.end.y, shoulder_height_ratio), torso_box.get_center().z + arm_pair_width * (-0.5 if side == 0 else 0.5))
		var previous := 0
		for link: int in 2:
			# ArmLimb is deliberately separate from the walking Limb/LegLimb role.
			var limb := _piece(prefix + "_Limb_%d" % [2-link], "ArmLimb", 1.0, arm_segment_lengths[link])
			if limb.is_empty(): return {}
			_orient(limb, _direction(arm_bend_degrees[link]))
			_place(limb, anchor)
			_join(edges, previous, parts.size(), anchor, "Arm")
			previous = parts.size()
			parts.append(limb)
			anchor = _port(limb, true)
		var hand := _piece(prefix, "Arm", hand_height)
		if hand.is_empty(): return {}
		_orient(hand, _direction(arm_bend_degrees.y))
		_place(hand, anchor)
		_join(edges, previous, parts.size(), anchor, "Arm")
		parts.append(hand)
	var head := _piece("Head", "Head", head_height)
	if head.is_empty(): return {}
	_place(head, Vector3(torso_box.get_center().x + 0.05, torso_box.end.y - 0.05, 0))
	var head_index := parts.size()
	_join(edges, 0, head_index, _port(head), "Neck")
	parts.append(head)
	if neck_mane_enabled:
		var mane := _piece("NeckMane", "Decoration", head_height * 0.7)
		if mane.is_empty(): return {}
		_center(mane, Vector3(0, torso_box.end.y - 0.1, part_width * 0.6))
		_join(edges, 0, parts.size(), _port(mane), "Torso")
		parts.append(mane)
	if ears_enabled:
		var box: AABB = head.transform * head._bounds
		for side: int in 2:
			var ear := _piece("EarLeft" if side == 0 else "EarRight", "Decoration", ear_heights[side])
			if ear.is_empty(): return {}
			_place(ear, Vector3(box.position.x + box.size.x * 0.2, box.end.y - box.size.y * 0.15, part_width * (-0.6 if side == 0 else 0.6)))
			_join(edges, head_index, parts.size(), _port(ear), "Torso")
			parts.append(ear)
	if tail_enabled:
		var tail := _piece("Tail", "Tail", tail_height)
		if tail.is_empty(): return {}
		var angle := deg_to_rad(tail_angle_degrees)
		_orient(tail, Vector3(-cos(angle), sin(angle), 0))
		_place(tail, Vector3(pelvis_box.position.x, hip_height + pelvis_height * 0.2, 0) + tail_root_offset)
		_join(edges, 1, parts.size(), _port(tail), "Tail")
		parts.append(tail)
	for piece: Dictionary in parts:
		piece.erase("_in")
		piece.erase("_out")
		piece.erase("_bounds")
	return {"parts":parts, "connections":edges}
