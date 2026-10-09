@tool
extends "res://Scripts/Creatures/Generators/BeastGenerator.gd"

const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const TAIL_SEGMENT_NAMES: Array[String] = ["TailRoot", "TailTransition", "TailMiddle", "TailTip"]
@export_group("Horned Model Layout")
## Model layout uses two links per leg; manual captures take priority.
@export var use_model_layout: bool = true
@export_range(0.1, 4.0, 0.01, "or_greater") var leg_pair_width: float = 0.32
@export_range(0.0, 0.5, 0.01) var hip_x_ratio: float = 0.27
@export_range(-2.0, 2.0, 0.01) var torso_height_offset: float = 0.45
@export_range(0.05, 1.0, 0.01) var support_plate_size: float = 0.35
@export var curl_horns_enabled: bool = true
@export var ears_enabled: bool = true
@export_group("Standing Layout")
@export var balanced_standing_layout: bool = true
@export_range(0.6, 0.9, 0.01) var standing_extension_ratio: float = 0.82
@export_range(-2.0, 2.0, 0.01) var rear_foot_x_offset: float = -0.8
@export_range(-2.0, 2.0, 0.01) var fore_foot_x_offset: float = 0.45
## +X is forward; select the two-link solution whose rear knee bends toward -X.
@export var rear_knee_bends_backward: bool = true

@export_group("Tail Generation")
@export var tail_enabled: bool = true
## Opt-in: the original Tail scene remains the default and is never overwritten.
@export var use_segmented_tail: bool = false
@export var tail_segment_scenes: Array[PackedScene] = [
	preload("res://Scenes/Creatures/Bodyparts/HornedBeast/SegmentedTail_v1/TailRoot.tscn"),
	preload("res://Scenes/Creatures/Bodyparts/HornedBeast/SegmentedTail_v1/TailTransition.tscn"),
	preload("res://Scenes/Creatures/Bodyparts/HornedBeast/SegmentedTail_v1/TailMiddle.tscn"),
	preload("res://Scenes/Creatures/Bodyparts/HornedBeast/SegmentedTail_v1/TailTip.tscn")]
@export_range(0.05, 10.0, 0.01, "or_greater") var tail_length: float = 1.2
@export_range(0.01, 2.0, 0.01, "or_greater") var tail_height: float = 0.9
## Root at Torso's rear (-X) shell; Y ratio is measured from its center.
@export_range(-0.5, 0.5, 0.01) var tail_root_height_ratio: float = 0.2
## In generator units, before Overall Scale. Thickness follows Part Width.
@export var tail_root_offset: Vector3 = Vector3.ZERO
@export_range(-180.0, 180.0, 0.1) var tail_angle_degrees: float = -20.0

@export_group("Horn Generation")
@export_range(0.05, 5.0, 0.01, "or_greater") var horn_size_scale: float = 1.0
## X/Y attachment relative to Head bounds size, from its geometry center.
@export var horn_root_ratio: Vector2 = Vector2(-0.22, 0.38)
@export var horn_root_offset: Vector3 = Vector3.ZERO
@export_range(0.0, 10.0, 0.01, "or_greater") var horn_pair_depth_ratio: float = 0.6
@export var horn_left_rotation_degrees: Vector3 = Vector3.ZERO
## The right source model grows toward +X; turn it to match the left horn's -X direction.
@export var horn_right_rotation_degrees: Vector3 = Vector3(0, 180, 0)

@export_group("Horned Part Models")
@export var torso_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/HornedBeast/Torso/TorsoMain.tscn")
@export var support_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/HornedBeast/Connectors/Rivet.tscn")
@export var head_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/HornedBeast/Head/HeadMain.tscn")
@export var tail_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/HornedBeast/Tail/Tail.tscn")
@export var fore_upper_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/HornedBeast/Legs/Fore/UpperLeg.tscn")
@export var fore_lower_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/HornedBeast/Legs/Fore/LowerLeg.tscn")
@export var fore_foot_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/HornedBeast/Legs/Fore/Foot.tscn")
@export var hind_upper_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/HornedBeast/Legs/Hind/UpperLeg.tscn")
@export var hind_lower_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/HornedBeast/Legs/Hind/LowerLeg.tscn")
@export var hind_foot_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/HornedBeast/Legs/Hind/Foot.tscn")
@export var horn_left_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/HornedBeast/Horns/HornCurlLeft.tscn")
@export var horn_right_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/HornedBeast/Horns/HornCurlRight.tscn")
@export var ear_left_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/HornedBeast/Head/EarLeft.tscn")
@export var ear_right_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/HornedBeast/Head/EarRight.tscn")

func _get_defaults_path() -> String:
	return "res://Resources/Generators/HornedBeastGeneratorDefaults.tres"

func get_part_scene_rule(part_type: String, part_name: String, part_key: String = "") -> PART_SCENE_RULE:
	var authored := super.get_part_scene_rule(part_type, part_name, part_key)
	if authored != null: return authored
	var scene: PackedScene
	if part_type == "Torso": scene = torso_scene
	elif part_type == "SubTorso": scene = support_scene
	elif part_type == "Head": scene = head_scene
	elif part_type == "Tail":
		var index := _tail_segment_index(part_name)
		scene = tail_segment_scenes[index] if use_segmented_tail and index >= 0 and index < tail_segment_scenes.size() else tail_scene
	elif part_name.begins_with("ForeLeg_"):
		scene = fore_lower_scene if part_name.ends_with("_Limb_1") else (fore_upper_scene if part_name.ends_with("_Limb_2") else fore_foot_scene)
	elif part_name.begins_with("Leg_"):
		scene = hind_lower_scene if part_name.ends_with("_Limb_1") else (hind_upper_scene if part_name.ends_with("_Limb_2") else hind_foot_scene)
	else:
		scene = {"HornLeft": horn_left_scene, "HornRight": horn_right_scene, "EarLeft": ear_left_scene, "EarRight": ear_right_scene}.get(part_name)
	if scene == null: return null
	var rule := PART_SCENE_RULE.new()
	rule.part_key = part_key if not part_key.is_empty() else part_name
	rule.part_type = part_type
	rule.part_scene = scene
	rule.size_mode = PART_SCENE_RULE.SizeMode.FIT_UNIFORM
	if part_type == "Tail": rule.size_mode = PART_SCENE_RULE.SizeMode.FIT_BOX
	return rule

func generate_torso() -> bool:
	if not use_model_layout or use_manual_layout: return super.generate_torso()
	if not is_inside_tree() or not is_finite(overall_scale) or overall_scale < 0.1: return false
	var blueprint := _build_model_blueprint()
	if blueprint.is_empty():
		push_warning("[horned_beast] Invalid Part model or layout parameters; previous creature retained.")
		return false
	var previous := manual_layout
	manual_layout = MANUAL_LAYOUT.new()
	manual_layout.blueprint = blueprint
	var succeeded := _generate_manual_framework()
	manual_layout = previous
	return succeeded

func _make_part(node_name: String, role: String, subtype: String = "") -> Dictionary:
	var type := subtype if not subtype.is_empty() else ("LegLimb" if role == "Limb" else role)
	var rule := get_part_scene_rule(type, node_name, node_name)
	if rule == null or rule.part_scene == null: return {}
	var part := rule.part_scene.instantiate() as PhysicalBodyPart3D
	if part == null: return {}
	var target := GEOMETRY.bounds(part).size
	if type == "SubTorso": target = Vector3(support_plate_size, support_plate_size, part_width)
	elif type == "Tail" and not (use_segmented_tail and _tail_segment_index(node_name) >= 0): target = Vector3(tail_length, tail_height, part_width)
	elif type == "Horn": target *= horn_size_scale
	var actual := GEOMETRY.fit(part, target, rule, role, part_width)
	var inlet := part.get_node_or_null("JointIn") as Marker3D
	var outlet := part.get_node_or_null("JointOut") as Marker3D
	if actual.size == Vector3.ZERO or inlet == null or outlet == null:
		part.free()
		return {}
	var layout := {"name":node_name, "part_key":node_name, "role":role, "size":actual.size,
		"transform":Transform3D.IDENTITY, "segment_id":0, "_in":inlet.position, "_out":outlet.position,
		"_bounds":actual}
	if type == "SubTorso": layout["sub_torso"] = true
	part.free()
	return layout

func _place(layout: Dictionary, anchor: Vector3) -> void:
	var basis: Basis = Transform3D(layout.transform).basis
	layout.transform = Transform3D(basis, anchor - basis * Vector3(layout._in))

func _port(layout: Dictionary, outlet: bool = false) -> Vector3:
	return Transform3D(layout.transform) * Vector3(layout._out if outlet else layout._in)

func _connect(edges: Array[Dictionary], a: int, b: int, anchor: Vector3, kind: String) -> void:
	edges.append({"a":a, "b":b, "anchor":anchor, "basis":Basis.IDENTITY, "kind":kind})

func _tail_segment_name(index: int) -> String:
	return TAIL_SEGMENT_NAMES[index] if index < TAIL_SEGMENT_NAMES.size() else "TailSegment_%02d" % [index + 1]

func _tail_segment_index(part_name: String) -> int:
	if part_name.begins_with("TailSegment_"): return part_name.trim_prefix("TailSegment_").to_int() - 1
	return TAIL_SEGMENT_NAMES.find(part_name)

func _append_segmented_tail(parts: Array[Dictionary], edges: Array[Dictionary], tail_anchor: Vector3) -> bool:
	if tail_segment_scenes.is_empty() or tail_segment_scenes.size() > 16: return false
	var chain: Array[Dictionary] = []
	var anchor := Vector3.ZERO
	var bounds := AABB()
	for index in range(tail_segment_scenes.size()):
		if tail_segment_scenes[index] == null: return false
		var piece := _make_part(_tail_segment_name(index), "Tail")
		if piece.is_empty(): return false
		_place(piece, anchor)
		var local: AABB = piece._bounds
		var box: AABB = piece.transform * local
		bounds = box if chain.is_empty() else bounds.merge(box)
		chain.append(piece)
		anchor = _port(piece, true)
	if bounds.size.x <= 0.001 or bounds.size.y <= 0.001: return false
	# Fit the entire unrotated chain to the existing Tail Length/Height controls.
	# Bake stretch into each local mesh/collider/port, retaining unit body scale.
	var stretch := Vector3(tail_length / bounds.size.x, tail_height / bounds.size.y, part_width / bounds.size.z)
	var rotation := Basis(Vector3.BACK, deg_to_rad(tail_angle_degrees))
	var previous := 0
	for piece: Dictionary in chain:
		piece.size *= stretch
		piece._in *= stretch
		piece._out *= stretch
		piece.transform = Transform3D(rotation, tail_anchor + rotation * (Vector3(piece.transform.origin) * stretch))
		_connect(edges, previous, parts.size(), _port(piece), "Torso" if previous == 0 else "Tail")
		previous = parts.size()
		parts.append(piece)
	return true

func _build_model_blueprint() -> Dictionary:
	if not _validate_species_settings() or rear_leg_count + foreleg_count == 0: return {}
	for value: float in [part_width, leg_pair_width, support_plate_size]:
		if not is_finite(value) or value <= 0.0: return {}
	if not is_finite(hip_x_ratio) or not is_finite(torso_height_offset): return {}
	if balanced_standing_layout and (not is_finite(standing_extension_ratio) or standing_extension_ratio <= 0.0 or standing_extension_ratio >= 1.0 or not is_finite(rear_foot_x_offset) or not is_finite(fore_foot_x_offset)): return {}
	for value: float in [tail_length, tail_height, horn_size_scale]:
		if not is_finite(value) or value <= 0.0: return {}
	for value: float in [tail_root_height_ratio, tail_angle_degrees, horn_pair_depth_ratio]:
		if not is_finite(value): return {}
	for value: Vector3 in [tail_root_offset, horn_root_offset, horn_left_rotation_degrees, horn_right_rotation_degrees]:
		if not value.is_finite(): return {}
	if not horn_root_ratio.is_finite(): return {}
	var parts: Array[Dictionary] = []
	var edges: Array[Dictionary] = []
	var torso := _make_part("Torso", "Torso")
	if torso.is_empty(): return {}
	parts.append(torso)
	var hip_sum := 0.0
	var hip_count := 0
	for fore: bool in [false, true]:
		var count := foreleg_count if fore else rear_leg_count
		for index: int in count:
			var prefix := ("ForeLeg_" if fore else "Leg_") + str(index+1)
			var support := _make_part("SubTorso_" + prefix, "Torso", "SubTorso")
			var upper := _make_part(prefix + "_Limb_2", "Limb")
			var lower := _make_part(prefix + "_Limb_1", "Limb")
			var foot := _make_part(prefix, "ForeLeg" if fore else "Leg")
			if support.is_empty() or upper.is_empty() or lower.is_empty() or foot.is_empty(): return {}
			var z := 0.0 if count == 1 else lerpf(-leg_pair_width * 0.5, leg_pair_width * 0.5, float(index)/float(count-1))
			var x := float(torso.size.x) * hip_x_ratio * (1.0 if fore else -1.0)
			_place(upper, Vector3(x, 0.0, z))
			_place(lower, _port(upper, true))
			_place(foot, _port(lower, true))
			var foot_bounds: AABB = foot._bounds
			var height := -(Transform3D(foot.transform).origin.y + foot_bounds.position.y)
			for layout: Dictionary in [upper, lower, foot]: layout.transform.origin.y += height
			if balanced_standing_layout:
				var upper_vector: Vector3 = upper._out-upper._in
				var lower_vector: Vector3 = lower._out-lower._in
				var l1 := upper_vector.length()
				var l2 := lower_vector.length()
				var offset := fore_foot_x_offset if fore else rear_foot_x_offset
				var ankle_y: float = foot._in.y-foot_bounds.position.y
				var hip_y := ankle_y+(l1+l2)*standing_extension_ratio
				var hip_position := Vector3(x,hip_y,z)
				var ankle := Vector3(x+offset+float(foot._in.x),ankle_y,z)
				var d := Vector2(ankle.x-x,ankle.y-hip_y)
				if d.length() >= l1+l2 or d.length() <= absf(l1-l2): return {}
				var cosine := clampf((l1*l1+d.length_squared()-l2*l2)/(2.0*l1*d.length()),-1.0,1.0)
				var bend := -1.0 if fore or rear_knee_bends_backward else 1.0
				var angle := d.angle()+bend*acos(cosine)
				upper.transform.basis = Basis(Vector3.BACK,angle-atan2(upper_vector.y,upper_vector.x))
				_place(upper,hip_position)
				var elbow := _port(upper,true)
				lower.transform.basis = Basis(Vector3.BACK,atan2(ankle.y-elbow.y,ankle.x-elbow.x)-atan2(lower_vector.y,lower_vector.x))
				_place(lower,elbow)
				_place(foot,_port(lower,true))
			var hip := _port(upper)
			_place(support, hip)
			var support_index := parts.size()
			parts.append(support)
			var foot_index := parts.size()
			parts.append(foot)
			var lower_index := parts.size()
			parts.append(lower)
			var upper_index := parts.size()
			parts.append(upper)
			_connect(edges, 0, support_index, hip, "Torso")
			_connect(edges, foot_index, lower_index, _port(foot), "Limb")
			_connect(edges, lower_index, upper_index, _port(lower), "Limb")
			_connect(edges, support_index, upper_index, hip, "Limb")
			hip_sum += hip.y
			hip_count += 1
	torso.transform.origin.y = hip_sum / float(hip_count) + torso_height_offset
	if tail_enabled:
		var torso_bounds: AABB = torso._bounds
		var tail_anchor: Vector3 = torso.transform * (torso_bounds.get_center() + Vector3(-torso_bounds.size.x * 0.5, torso_bounds.size.y * tail_root_height_ratio, 0.0)) + tail_root_offset
		if use_segmented_tail:
			if not _append_segmented_tail(parts, edges, tail_anchor): return {}
		else:
			var tail := _make_part("Tail", "Tail")
			if tail.is_empty(): return {}
			tail.transform.basis = Basis(Vector3.BACK, deg_to_rad(tail_angle_degrees))
			_place(tail, tail_anchor)
			_connect(edges, 0, parts.size(), tail_anchor, "Torso")
			parts.append(tail)
	var head := _make_part("Head", "Head")
	if head.is_empty(): return {}
	_place(head, _port(torso, true))
	var head_index := parts.size()
	parts.append(head)
	_connect(edges, 0, head_index, _port(head), "Neck")
	var head_origin: Vector3 = head.transform.origin
	var decorations: Array[String] = []
	if curl_horns_enabled: decorations.append_array(["HornLeft", "HornRight"])
	if ears_enabled: decorations.append_array(["EarLeft", "EarRight"])
	for decoration_name: String in decorations:
		var is_horn := decoration_name.begins_with("Horn")
		var decoration := _make_part(decoration_name, "Horn" if is_horn else "Decoration")
		if decoration.is_empty(): return {}
		var left: bool = decoration_name.ends_with("Left")
		var depth := part_width * ((horn_pair_depth_ratio if is_horn else 0.6) * (1.0 if left else -1.0))
		var root_offset := Vector3(-head.size.x * 0.22, head.size.y * (0.12 if decoration_name.begins_with("Ear") else 0.38), depth)
		if is_horn:
			root_offset = Vector3(head.size.x * horn_root_ratio.x, head.size.y * horn_root_ratio.y, depth) + horn_root_offset
			var rotation: Vector3 = horn_left_rotation_degrees if left else horn_right_rotation_degrees
			decoration.transform.basis = Basis.from_euler(rotation * (PI / 180.0))
		_place(decoration, head_origin + root_offset)
		var decoration_index := parts.size()
		parts.append(decoration)
		_connect(edges, head_index, decoration_index, _port(decoration), "Torso")
	for layout: Dictionary in parts:
		layout.erase("_in")
		layout.erase("_out")
		layout.erase("_bounds")
	return {"parts":parts, "connections":edges}

func _create_valid_plan() -> Dictionary:
	_random.seed = 42
	var plan := super._create_valid_plan()
	if not plan.is_empty(): plan["create_connection_markers"] = true
	return plan

