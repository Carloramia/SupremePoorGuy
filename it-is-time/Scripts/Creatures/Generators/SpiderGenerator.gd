@tool
extends "res://Scripts/Creatures/Generators/BaseCreatureGenerator.gd"

@export_group("Spider Body")
## Only X/Y are used. Z thickness always comes from Part Width.
@export var front_torso_size: Vector3 = Vector3(1.4, 0.7, 1.1)
## Only X/Y are used. Z thickness always comes from Part Width.
@export var rear_torso_size: Vector3 = Vector3(2.0, 1.0, 1.6)
## Rear Torso upward offset in generator units, before Overall Scale.
@export_range(0.0, 10.0, 0.01, "or_greater") var rear_torso_y_offset: float = 0.0
@export_range(0.0, 0.5, 0.01) var body_overlap: float = 0.12
## Only X/Y are used. Z thickness always comes from Part Width.
@export var spider_head_size: Vector3 = Vector3(0.65, 0.45, 0.7)
@export_range(0.0, 0.3, 0.01) var head_overlap: float = 0.04

@export_group("Spider Legs")
## Four mirrored pairs are fixed. The ascending Limb is followed by one longer Leg.
@export_range(0.1, 5.0, 0.01) var upper_limb_length: float = 0.9
@export_range(0.2, 10.0, 0.01) var lower_leg_length: float = 1.8
## Lower Leg width along its local X axis, independent of Z thickness.
@export_range(0.01, 10.0, 0.01, "or_greater") var leg_width: float = 0.16
## Upper Limb width along its local X axis, independent of Z thickness.
@export_range(0.01, 10.0, 0.01, "or_greater") var limb_width: float = 0.16
@export_range(5.0, 75.0, 0.1) var upper_limb_elevation: float = 35.0
@export_range(0.0, 65.0, 0.1) var lower_leg_outward_angle: float = 25.0
## Controls forward/backward spread within each XY sheet; Z remains fixed per side.
@export_range(0.0, 70.0, 0.1) var leg_fan_angle: float = 45.0
@export_range(0.1, 0.95, 0.01) var leg_root_spread: float = 0.8

func _init() -> void:
	_apply_default_preset()

func _get_defaults_path() -> String:
	return "res://Resources/Generators/SpiderGeneratorDefaults.tres"

func generate_torso() -> bool:
	if use_manual_layout: return _generate_manual_framework()
	if not is_inside_tree() or not is_finite(overall_scale) or overall_scale < 0.1: return false
	var blueprint := _build_spider_blueprint()
	if blueprint.is_empty():
		push_warning("[spider_generator] Invalid dimensions: rear Torso must be larger and Leg longer than Limb; previous frame retained.")
		return false
	var previous := manual_layout
	manual_layout = MANUAL_LAYOUT.new()
	manual_layout.blueprint = blueprint
	var succeeded := _generate_manual_framework()
	manual_layout = previous
	return succeeded

func _valid_size(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and minf(value.x, value.y) > 0.0

func _generate_manual_framework() -> bool:
	if not is_finite(part_width) or part_width < 0.01: return false
	if manual_layout == null: return super._generate_manual_framework()
	# Apply live depth to captured layouts without modifying their shared resource.
	var original := manual_layout
	manual_layout = MANUAL_LAYOUT.new()
	manual_layout.blueprint = original.blueprint.duplicate(true)
	for part: Dictionary in manual_layout.blueprint.get("parts", []):
		part.size.z = part_width
	manual_layout.blueprint["paper_depth"] = part_width
	var succeeded := super._generate_manual_framework()
	manual_layout = original
	return succeeded

func _block(node_name: String, role: String, size: Vector3, center: Vector3, basis: Basis = Basis.IDENTITY) -> Dictionary:
	size.z = part_width
	return {"name":node_name, "part_key":node_name, "role":role, "size":size,
		"transform":Transform3D(basis, center), "segment_id":0}

func _segment(node_name: String, role: String, start: Vector3, end: Vector3) -> Dictionary:
	var vector := end - start
	var along := vector.normalized()
	# Rotate only around Z: the local sheet thickness stays parallel to global Z.
	var across := Vector3(along.y, -along.x, 0)
	var basis := Basis(across, along, Vector3.BACK)
	var width := leg_width if role == "Leg" else limb_width
	return _block(node_name, role, Vector3(width, vector.length(), part_width), (start + end) * 0.5, basis)

func _connect(edges: Array[Dictionary], a: int, b: int, anchor: Vector3, kind: String) -> void:
	edges.append({"a":a, "b":b, "anchor":anchor, "basis":Basis.IDENTITY, "kind":kind})

func _build_spider_blueprint() -> Dictionary:
	if not _valid_size(front_torso_size) or not _valid_size(rear_torso_size) or not _valid_size(spider_head_size): return {}
	if rear_torso_size.x <= front_torso_size.x or rear_torso_size.y <= front_torso_size.y: return {}
	for value: float in [part_width, leg_width, limb_width, rear_torso_y_offset, upper_limb_length, lower_leg_length, upper_limb_elevation, lower_leg_outward_angle, leg_fan_angle, leg_root_spread, body_overlap, head_overlap]:
		if not is_finite(value): return {}
	if part_width < 0.01 or leg_width < 0.01 or limb_width < 0.01 or upper_limb_length <= 0.0 or lower_leg_length <= upper_limb_length: return {}
	if rear_torso_y_offset < 0.0: return {}
	if upper_limb_elevation < 5.0 or upper_limb_elevation > 75.0 or lower_leg_outward_angle < 0.0 or lower_leg_outward_angle > 65.0: return {}
	if leg_fan_angle < 0.0 or leg_fan_angle > 70.0 or leg_root_spread <= 0.0 or leg_root_spread > 0.95: return {}
	if body_overlap < 0.0 or body_overlap >= front_torso_size.x or head_overlap < 0.0 or head_overlap >= minf(front_torso_size.x, spider_head_size.x): return {}
	var rise := deg_to_rad(upper_limb_elevation)
	var descend := deg_to_rad(lower_leg_outward_angle)
	var directions: Array[Dictionary] = []
	var root_y := 0.0
	for pair: int in 4:
		var fan := deg_to_rad(lerpf(leg_fan_angle, -leg_fan_angle, float(pair) / 3.0))
		var outward := Vector3(sin(fan), 0, 0)
		var upper := (outward * cos(rise) + Vector3.UP * sin(rise)).normalized()
		var lower := (outward * sin(descend) + Vector3.DOWN * cos(descend)).normalized()
		# Different XY slopes need different root heights for all box soles to touch Y=0.
		var height := -upper.y * upper_limb_length - lower.y * lower_leg_length + absf(lower.x) * leg_width * 0.5
		directions.append({"upper":upper, "lower":lower, "height":height})
		root_y += height * 0.25
	if root_y <= front_torso_size.y * 0.5: return {}
	var parts: Array[Dictionary] = []
	var edges: Array[Dictionary] = []
	parts.append(_block("Torso_Front", "Torso", front_torso_size, Vector3(0, root_y, 0)))
	var rear_x := -(front_torso_size.x + rear_torso_size.x) * 0.5 + body_overlap
	parts.append(_block("Torso_Rear", "Torso", rear_torso_size, Vector3(rear_x, root_y + rear_torso_y_offset, 0)))
	# Center the anchor in the shared height interval (or in the gap if separated).
	var overlap_bottom := maxf(root_y - front_torso_size.y * 0.5, root_y + rear_torso_y_offset - rear_torso_size.y * 0.5)
	var overlap_top := minf(root_y + front_torso_size.y * 0.5, root_y + rear_torso_y_offset + rear_torso_size.y * 0.5)
	_connect(edges, 0, 1, Vector3(-front_torso_size.x * 0.5 + body_overlap * 0.5, (overlap_bottom + overlap_top) * 0.5, 0), "Torso")
	for side: int in 2:
		var sign_z := -1.0 if side == 0 else 1.0
		for pair: int in 4:
			var t := float(pair) / 3.0
			var direction: Dictionary = directions[pair]
			# Equal-depth sheets occupy adjacent Z layers: Torso=0, Limb=±width, Leg=±2*width.
			var root_point := Vector3(lerpf(0.5, -0.5, t) * front_torso_size.x * leg_root_spread, direction.height, sign_z * part_width)
			var knee := root_point + Vector3(direction.upper) * upper_limb_length
			var leg_root := knee + Vector3(0, 0, sign_z * part_width)
			var tip := leg_root + Vector3(direction.lower) * lower_leg_length
			var prefix := "Leg_%d" % [side * 4 + pair + 1]
			var upper_index := parts.size()
			parts.append(_segment(prefix + "_Limb_1", "Limb", root_point, knee))
			var torso_anchor := root_point - Vector3(0, 0, sign_z * part_width * 0.5)
			_connect(edges, 0, upper_index, torso_anchor, "Limb")
			var lower := _segment(prefix, "Leg", leg_root, tip)
			var knee_anchor := (knee + leg_root) * 0.5
			_connect(edges, upper_index, parts.size(), knee_anchor, "Limb")
			parts.append(lower)
	var head_center := Vector3(front_torso_size.x * 0.5 + spider_head_size.x * 0.5 - head_overlap, root_y, 0)
	_connect(edges, 0, parts.size(), Vector3(front_torso_size.x * 0.5 - head_overlap * 0.5, root_y, 0), "Neck")
	parts.append(_block("Head", "Head", spider_head_size, head_center))
	return {"parts":parts, "connections":edges, "generator_type":"spider", "paper_depth":part_width}
