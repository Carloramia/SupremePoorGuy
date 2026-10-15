@tool
extends "res://Scripts/Creatures/Generators/BaseCreatureGenerator.gd"

const HUMAN_GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const HUMAN_PART_ROOT := "res://Scenes/Creatures/Bodyparts/Human/"
const REFERENCE_CALIBRATION = preload("res://Resources/Generators/HumanReferenceCalibration.tres")

@export_group("Human Assets")
@export_enum("Human1:1", "Human2:2", "Human3:3", "Human4:4", "Human5:5") var human_set: int = 1
@export var waist_visual_enabled: bool = true
@export_range(0.1, 2.0, 0.01) var waist_visual_scale: float = 1.0
@export var waist_visual_offset: Vector3 = Vector3(0.0, 0.0, -0.06)
@export_group("Human Standing Layout")
## Use each source sheet's limb directions and knee bend; feet remain grounded.
@export var use_reference_pose: bool = true
## Preserve source boot directions unless both toes should face +X.
@export var feet_face_forward: bool = false
## Maximum ankle-to-hip reach divided by total leg length; reserves knee bend.
@export_range(0.6, 0.98, 0.01) var standing_extension_ratio: float = 0.98
## Used only when Use Reference Pose is disabled.
@export var arm_bend_degrees: Vector2 = Vector2(8.0, 22.0)
@export var head_offset: Vector3 = Vector3.ZERO
## Small depth layers prevent coplanar paper faces at shoulders, hips and neck.
@export_range(0.5, 2.0, 0.05) var paper_layer_ratio: float = 1.0
## Uniform XY scaling only; paper depth is always Part Width * Overall Scale.
@export_range(0.1, 3.0, 0.01) var limb_size: float = 1.0

func _init() -> void:
	_apply_default_preset()

func _get_defaults_path() -> String:
	return "res://Resources/Generators/HumanGeneratorDefaults.tres"

func get_part_scene_rule(part_type: String, part_name: String, part_key: String = "") -> PART_SCENE_RULE:
	var authored := super.get_part_scene_rule(part_type, part_name, part_key)
	if authored != null: return authored
	var category := ""
	var suffix := ""
	if part_name in ["Torso", "Head", "WaistVisual"]:
		category = "Head/" if part_name == "Head" else "Torso/"
		suffix = "Pelvis" if part_name == "WaistVisual" else part_name
	elif part_name.begins_with("Arm_") or part_name.begins_with("Leg_"):
		var arm := part_name.begins_with("Arm_")
		var side := "Right" if part_name.begins_with("Arm_R") or part_name.begins_with("Leg_R") else "Left"
		category = ("Arms/" if arm else "Legs/") + side + "/"
		if part_name.ends_with("_Limb_2"): suffix = "UpperArm" if arm else "UpperLeg"
		elif part_name.ends_with("_Limb_1"): suffix = "Forearm" if arm else "LowerLeg"
		else: suffix = "Hand" if arm else "Foot"
		suffix += side
	else: return null
	var rule := PART_SCENE_RULE.new()
	rule.part_key = part_key if not part_key.is_empty() else part_name
	rule.part_type = part_type
	rule.part_scene = load(HUMAN_PART_ROOT + category + "Human%d%s.tscn" % [human_set, suffix]) as PackedScene
	rule.size_mode = PART_SCENE_RULE.SizeMode.KEEP_SIZE
	var reference := reference_for(part_name)
	rule.size_multiplier = float(reference.get("scale", 1.0))
	if part_name.begins_with("Arm_") or part_name.begins_with("Leg_"): rule.size_multiplier *= limb_size
	if part_name == "WaistVisual": rule.size_multiplier *= waist_visual_scale
	return rule

func reference_for(part_name: String) -> Dictionary:
	var value: Variant = REFERENCE_CALIBRATION.get_meta("calibration", {})
	if not value is Dictionary or int(value.get("version",0)) != 2: return {}
	return value.get("sets", {}).get(str(human_set), {}).get("parts", {}).get(part_name, {})

func reference_port(part: PhysicalBodyPart3D, part_name: String, port_name: String) -> Vector3:
	var reference := reference_for(part_name)
	if part.scene_file_path == str(reference.get("asset", "")) and reference.get("ports", {}).has(port_name):
		var pixel: Array = reference.ports[port_name]
		var pivot: Array = reference.pivot
		var unit := float(reference.pixel_unit)
		var model := part.get_node(part.custom_model_path) as Node3D
		return model.transform * Vector3((float(pixel[0])-float(pivot[0]))*unit, (float(pivot[1])-float(pixel[1]))*unit, 0.0)
	var marker := part.get_node_or_null("JointOut" if port_name == "out" else "JointIn") as Marker3D
	return marker.position if marker != null else Vector3.ZERO

func reference_direction(part_name: String) -> Vector3:
	var joints: Array = reference_for(part_name).get("source_joints", [])
	if joints.size() != 2: return Vector3.DOWN
	var start: Array = joints[0]
	var end: Array = joints[1]
	return Vector3(float(end[0])-float(start[0]), float(start[1])-float(end[1]), 0.0).normalized()

func apply_reference_connectors(part: PhysicalBodyPart3D, part_name: String) -> void:
	for key: String in ["in", "out"]:
		var marker := part.get_node_or_null("JointIn" if key == "in" else "JointOut") as Marker3D
		if marker != null: marker.position = reference_port(part, part_name, key)

func waist_attachment_shift(torso: PhysicalBodyPart3D, waist: PhysicalBodyPart3D, multiplier: float) -> Vector3:
	return reference_port(torso, "Torso", "waist") - reference_port(waist, "WaistVisual", "in") + waist_visual_offset * multiplier

func generate_torso() -> bool:
	if use_manual_layout: return _generate_manual_framework()
	if not is_inside_tree(): return false
	var blueprint := _build_human_blueprint()
	if blueprint.is_empty():
		push_warning("[human_generator] Invalid parameters or missing Human Part connectors; previous layout retained.")
		return false
	var previous := manual_layout
	manual_layout = MANUAL_LAYOUT.new()
	manual_layout.blueprint = blueprint
	var succeeded := _generate_manual_framework()
	manual_layout = previous
	return succeeded

func _piece(node_name: String, role: String) -> Dictionary:
	var type := "LegLimb" if role == "Limb" else role
	var rule := get_part_scene_rule(type, node_name, node_name)
	if rule == null or rule.part_scene == null: return {}
	var instance := rule.part_scene.instantiate()
	if not instance is PhysicalBodyPart3D:
		instance.free()
		return {}
	var part := instance as PhysicalBodyPart3D
	var inlet := part.get_node_or_null("JointIn") as Marker3D
	var outlet := part.get_node_or_null("JointOut") as Marker3D
	var bounds := HUMAN_GEOMETRY.fit(part, Vector3.ONE, rule, role, part_width)
	apply_reference_connectors(part, node_name)
	if inlet == null or outlet == null or bounds.size == Vector3.ZERO or inlet.position.distance_to(outlet.position) < 0.001:
		part.free()
		return {}
	var result := {"name":node_name, "part_key":node_name, "role":role, "size":bounds.size,
		"transform":Transform3D.IDENTITY, "segment_id":0,
		"_in":inlet.position, "_out":outlet.position, "_bounds":bounds}
	result["_ports"] = {}
	for key: String in reference_for(node_name).get("ports", {}): result._ports[key] = reference_port(part, node_name, key)
	part.free()
	return result

func _place(piece: Dictionary, anchor: Vector3) -> void:
	piece.transform.origin = anchor - piece.transform.basis * Vector3(piece._in)

func _port(piece: Dictionary, outlet: bool = false) -> Vector3:
	return Transform3D(piece.transform) * Vector3(piece._out if outlet else piece._in)

func _orient(piece: Dictionary, angle: float) -> void:
	var radians := deg_to_rad(angle)
	_orient_to(piece, Vector3(sin(radians), -cos(radians), 0.0))

func _orient_to(piece: Dictionary, direction: Vector3) -> void:
	var native: Vector3 = piece._out - piece._in
	piece.transform.basis = Basis(Quaternion(native.normalized(), direction.normalized()))

func _join(edges: Array[Dictionary], a: int, b: int, anchor: Vector3, kind: String) -> void:
	edges.append({"a":a, "b":b, "anchor":anchor, "basis":Basis.IDENTITY, "kind":kind})

func _build_human_blueprint() -> Dictionary:
	if human_set < 1 or human_set > 5: return {}
	for value: float in [part_width, overall_scale, limb_size, waist_visual_scale, paper_layer_ratio, standing_extension_ratio]:
		if not is_finite(value) or value <= 0.0: return {}
	if standing_extension_ratio >= 1.0 or not arm_bend_degrees.is_finite() or not head_offset.is_finite() or not waist_visual_offset.is_finite(): return {}
	var torso := _piece("Torso", "Torso")
	var head := _piece("Head", "Head")
	var waist := _piece("WaistVisual", "Decoration")
	if torso.is_empty() or head.is_empty() or waist.is_empty(): return {}
	waist.transform.origin = Vector3(torso._ports.waist) - Vector3(waist._ports["in"]) + waist_visual_offset
	var parts: Array[Dictionary] = [torso]
	var edges: Array[Dictionary] = []
	var legs: Array[Dictionary] = []
	var torso_height := INF
	var reference_height_sum := 0.0
	var maximum_height := INF
	var left_hip: Vector3 = waist.transform * Vector3(waist._ports.hip_L)
	var right_hip: Vector3 = waist.transform * Vector3(waist._ports.hip_R)
	var center_x := (left_hip.x + right_hip.x) * 0.5
	var inner_margin := absf(right_hip.x-left_hip.x) * 0.25
	# Torso remains one rigid body; its hip anchors follow the waist's illustrated ports.
	for side: String in ["R", "L"]:
		var upper := _piece("Leg_%s_Limb_2" % side, "Limb")
		var lower := _piece("Leg_%s_Limb_1" % side, "Limb")
		var foot := _piece("Leg_" + side, "Leg")
		if upper.is_empty() or lower.is_empty() or foot.is_empty(): return {}
		if feet_face_forward and float(foot._out.x) < float(foot._in.x):
			foot.transform.basis = Basis(Vector3.UP, PI)
		var hip: Vector3 = waist.transform * Vector3(waist._ports["hip_" + side])
		hip.z += part_width * paper_layer_ratio * (1.0 if side == "R" else -1.0)
		var first_length: float = Vector3(upper._in).distance_to(upper._out)
		var second_length: float = Vector3(lower._in).distance_to(lower._out)
		var sole: AABB = Transform3D(foot.transform.basis, Vector3.ZERO) * AABB(foot._bounds)
		var ankle_height: float = (foot.transform.basis * Vector3(foot._in)).y - sole.position.y
		var reach := (first_length + second_length) * standing_extension_ratio
		var offset_x := 0.0
		var bend_sign := 1.0
		if use_reference_pose:
			var first_direction := reference_direction(str(upper.name))
			var second_direction := reference_direction(str(lower.name))
			var desired := first_direction*first_length + second_direction*second_length
			reach = minf(reach, desired.length())
			# Exploded-sheet poses may cross the feet when attached; keep each sole on its own side.
			var foot_x := minf(hip.x+desired.x,center_x-inner_margin) if side == "L" else maxf(hip.x+desired.x,center_x+inner_margin)
			offset_x = clampf(foot_x-hip.x, -reach*0.95, reach*0.95)
			var turn := first_direction.cross(second_direction).z
			if not is_zero_approx(turn): bend_sign = -signf(turn)
		var preferred_height := sqrt(maxf(reach*reach-offset_x*offset_x,0.0)) + ankle_height - hip.y
		torso_height = minf(torso_height, preferred_height)
		reference_height_sum += preferred_height
		maximum_height = minf(maximum_height, reach+ankle_height-hip.y)
		legs.append({"upper":upper, "lower":lower, "foot":foot, "hip":hip, "first":first_length, "second":second_length, "ankle_height":ankle_height,"offset_x":offset_x,"bend_sign":bend_sign,"reach":reach,"side":side})
	if use_reference_pose: torso_height = minf(reference_height_sum/legs.size(), maximum_height-0.001)
	torso.transform.origin.y = torso_height
	for leg: Dictionary in legs:
		var hip: Vector3 = leg.hip + Vector3.UP * torso_height
		if use_reference_pose:
			# Adjust chain tilt before its bend angle to share one grounded Torso height.
			var drop: float = hip.y-float(leg.ankle_height)
			var horizontal := sqrt(maxf(float(leg.reach)*float(leg.reach)-drop*drop,0.0)) * signf(float(leg.offset_x))
			var foot_x := minf(hip.x+horizontal,center_x-inner_margin) if leg.side == "L" else maxf(hip.x+horizontal,center_x+inner_margin)
			leg.offset_x = foot_x-hip.x
		var ankle := Vector3(hip.x+float(leg.offset_x), leg.ankle_height, hip.z)
		var distance := hip.distance_to(ankle)
		if distance <= absf(float(leg.first)-float(leg.second)) or distance >= float(leg.first)+float(leg.second): return {}
		var along := (float(leg.first)*float(leg.first) - float(leg.second)*float(leg.second) + distance*distance) / (2.0*distance)
		var bend := sqrt(maxf(float(leg.first)*float(leg.first)-along*along,0.0))
		var direction := (ankle-hip).normalized()
		var knee := hip + direction*along + Vector3(-direction.y,direction.x,0.0)*bend*float(leg.bend_sign)
		_orient_to(leg.upper, knee-hip)
		_orient_to(leg.lower, ankle-knee)
		_place(leg.upper, hip)
		_place(leg.lower, knee)
		_place(leg.foot, ankle)
		var previous := 0
		for piece: Dictionary in [leg.upper, leg.lower, leg.foot]:
			_join(edges, previous, parts.size(), _port(piece), "HumanLeg")
			previous = parts.size()
			parts.append(piece)
	for side: String in ["R", "L"]:
		var anchor: Vector3 = torso.transform * Vector3(torso._ports["shoulder_" + side])
		anchor.z += part_width * paper_layer_ratio * (1.0 if side == "R" else -1.0)
		var previous := 0
		for link: int in 3:
			var node_name := "Arm_" + side + ("_Limb_%d" % [2-link] if link < 2 else "")
			var limb := _piece(node_name, "ArmLimb" if link < 2 else "Arm")
			if limb.is_empty(): return {}
			if not use_reference_pose: _orient(limb, arm_bend_degrees[mini(link,1)])
			elif link < 2: _orient_to(limb, reference_direction(node_name))
			_place(limb, anchor)
			_join(edges, previous, parts.size(), anchor, "HumanArm")
			previous = parts.size()
			parts.append(limb)
			anchor = _port(limb, true)
	_place(head, torso.transform * Vector3(torso._ports.head) + Vector3(0.0, 0.0, part_width * paper_layer_ratio * 0.5) + head_offset)
	_join(edges, 0, parts.size(), _port(head), "HumanHead")
	parts.append(head)
	for piece: Dictionary in parts:
		piece.erase("_in")
		piece.erase("_out")
		piece.erase("_bounds")
		piece.erase("_ports")
	return {"parts":parts, "connections":edges}
