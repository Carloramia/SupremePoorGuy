@tool
extends Node3D

signal framework_generated(plan: Dictionary)

@export_group("Overall Size")
## Uniform size multiplier around the generator origin, applied after layout validation.
## Generate again to update the frame and the physical character. Does not scale the root Node3D.
@export_range(0.1, 10.0, 0.05, "or_greater") var overall_scale: float = 1.0

@export_group("SubTorsoGeneration")
## Dimensions are measured in local 3D units. Each axis is sampled independently.
@export var minimum_size: Vector3 = Vector3(0.5, 0.5, 0.3)
@export var maximum_size: Vector3 = Vector3(2, 2, 0.4)
## Maximum 3D distance from each Limb endpoint to its nearest Torso surface, including inside points.
@export_range(0.0, 100.0, 0.01, "or_greater") var max_limb_end_height_difference: float = 0.2
@export var wireframe_color: Color = Color(0.2, 0.9, 1, 1)
@export var label_color: Color = Color(1, 1, 1, 1)
## Shared font size for all labels in the generated frame; changes update existing labels too.
@export_range(1, 256, 1, "or_greater") var label_font_size: int = 32:
	set(value):
		label_font_size = maxi(value, 1)
		_update_label_sizes(self)
@export_tool_button("生成随机框架", "Node3D") var generate_torso_button: Callable = generate_torso
@export_tool_button("将当前参数写为脚本默认值", "Save") var save_defaults_button: Callable = save_current_parameters_as_defaults

@export_group("Feet Generation")
@export_range(2, 10, 1) var feets: int = 6
@export_range(0.0, 100.0, 0.1) var unsymmetrie: float = 0.0
@export_range(0.0, 100.0, 0.1) var inhomogeneity: float = 0.0
## Scales position ranges only: X multiplier = 1 + Narrowty / 100; Z is its reciprocal.
@export_range(0.0, 100.0, 0.1, "or_greater") var narrowty: float = 33.6
## X = length, Y = height, Z = width. At zero inhomogeneity every Feet uses this size.
@export var base_foot_size: Vector3 = Vector3(0.6, 0.3, 0.4)
@export var minimum_foot_size: Vector3 = Vector3(0.4, 0.6, 0.3)
@export var maximum_foot_size: Vector3 = Vector3(0.8, 0.6, 0.5)
## Horizontal surface-to-surface distance, not center-to-center distance.
@export_range(0.0, 100.0, 0.01, "or_greater") var minimum_feet_distance: float = 0.2

@export_group("Limb Lines")
## Sum of segment lengths. Inhomogeneity varies mirror pairs; Unsymmetrie varies each side.
@export_range(0.01, 100.0, 0.01, "or_greater") var base_limb_length: float = 2.0
## These ranges control shape proportions; the result is normalized to its total length.
@export_range(0.01, 10.0, 0.01, "or_greater") var minimum_segment_height: float = 0.4
@export_range(0.01, 10.0, 0.01, "or_greater") var maximum_segment_height: float = 0.8
@export_range(0.01, 10.0, 0.01, "or_greater") var minimum_bend_offset: float = 0.1
@export_range(0.01, 10.0, 0.01, "or_greater") var maximum_bend_offset: float = 0.3

@export_group("Limb Block Generation")
## Local Y runs along the segment; X/Z are the two cross-section dimensions.
## Dimensions are independent of the line length; centers and joint anchors stay on the line.
@export var limb_minimum_size: Vector3 = Vector3(0.4, 0.4, 0.2)
@export var limb_maximum_size: Vector3 = Vector3(0.4, 0.8, 0.2)
## Override only local Y with the corresponding segment length; X/Z retain their size ranges.
@export var limb_y_matches_segment: bool = true

@export_group("Limb Network")
## Merge junction endpoints closer than this 3D distance; original Limb tips remain connected.
@export_range(0.0, 100.0, 0.01, "or_greater") var limb_endpoint_merge_distance: float = 0.2
## Additional free vertices sampled inside the Limb-tip bounds expanded by Padding.
@export_range(0, 32, 1) var network_extra_endpoint_count: int = 4
@export_range(0.0, 100.0, 0.01, "or_greater") var network_extra_endpoint_padding: float = 0.5
## Pull free endpoints toward the network center and favor connections through its core.
@export_range(0.0, 1.0, 0.01) var network_center_bias: float = 0.65
@export_range(0, 32, 1) var network_core_extra_connections: int = 3

@export_group("TorsoGeneration")
## Torso dimensions on generator X/Y/Z axes. Centers lie on network segments; edges need not follow them.
@export var torso_minimum_size: Vector3 = Vector3(0.6, 0.6, 0.3)
@export var torso_maximum_size: Vector3 = Vector3(1.4, 1.4, 0.5)
@export_range(0.0, 100.0, 0.01, "or_greater") var torso_connection_distance: float = 0.4
## Maximum pairwise intersection volume as a percentage of EACH Torso/SubTorso volume.
## Equality is allowed; this is not the sum of overlaps with different boxes.
@export_range(0.0, 100.0, 0.1) var max_torso_overlap_percent: float = 20.0
@export_range(0.0, 1.0, 0.01) var torso_center_size_bias: float = 0.6
@export_range(0.0, 1.0, 0.01) var torso_center_density_bias: float = 0.65
## Additional legal connected blocks near the core after the body becomes connected.
@export_range(0, 32, 1) var torso_core_extra_blocks: int = 6

@export_group("Neck Generation")
## Number of free NeckLines; roots must stay within the Torso surface-distance limit.
@export_range(0, 256, 1) var neck_number: int = 1
@export_range(0.0, 100.0, 0.01, "or_greater") var max_neck_start_surface_distance: float = 0.5
@export_range(0.01, 100.0, 0.01, "or_greater") var neck_minimum_length: float = 1.0
@export_range(0.01, 100.0, 0.01, "or_greater") var neck_maximum_length: float = 1.2
@export_range(4, 32, 1) var neck_segment_count: int = 4
## Maximum upward tangent angle; first and last segments stay parallel to +X.
@export_range(0.0, 85.0, 0.1) var neck_maximum_angle: float = 60.0

## Square cross-section of the cuboids following NeckLine.
@export_range(0.01, 10.0, 0.01, "or_greater") var neck_block_thickness: float = 0.15
## Maximum diameter of the actual overlap volume, including other body/neck/head blocks.
@export_range(0.0, 100.0, 0.01, "or_greater") var max_neck_overlap_diameter: float = 0.5
@export_group("Head Generation")
@export var head_minimum_size: Vector3 = Vector3(0.3, 0.3, 0.3)
@export var head_maximum_size: Vector3 = Vector3(0.7, 0.7, 0.7)

const BOX_GEOMETRY = preload("res://Scripts/Creatures/CreatureBoxGeometry.gd")
const MAX_NETWORK_TORSOS: int = 256
const MAX_NETWORK_TORSO_ATTEMPTS: int = 4096
const MAX_GENERATION_ATTEMPTS: int = 128
const TORSO_CLEARANCE: float = 0.1

var _random := RandomNumberGenerator.new()

func _update_label_sizes(node: Node) -> void:
	if node is Label3D:
		(node as Label3D).font_size = label_font_size
	for child: Node in node.get_children():
		_update_label_sizes(child)

func _ready() -> void:
	_random.randomize()
	_update_label_sizes(self)

## Only the editor button may rewrite this shared tool script; saved scene overrides remain.
func save_current_parameters_as_defaults() -> bool:
	if not Engine.is_editor_hint():
		push_warning("[creature_generator] Saving script defaults is editor-only.")
		return false
	var script := get_script() as GDScript
	var path := script.resource_path
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[creature_generator] Cannot read script: %s" % path)
		return false
	var source := file.get_as_text()
	file.close()
	var updated := _build_default_source(source)
	if updated.is_empty():
		return false
	if updated == source:
		print("[creature_generator] Script defaults already match current parameters.")
		return true
	if not _write_default_source(path, updated):
		return false
	# Let the editor reload after this callback finishes, not while it executes.
	EditorInterface.get_resource_filesystem().call_deferred(&"scan")
	print("[creature_generator] Current parameters saved as script defaults: %s" % path)
	return true

## Replace typed export initializers only, preserving annotations, functions and comments.
func _build_default_source(source: String) -> String:
	var pattern := RegEx.new()
	if pattern.compile("(?m)^(@export[^\r\n]*\\bvar[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]*:[^=\r\n]+=[ \t]*)([^\r\n]*)") != OK:
		return ""
	var updated := source
	var matches := pattern.search_all(source)
	# Reverse replacements keep all offsets measured against the original source.
	for index: int in range(matches.size() - 1, -1, -1):
		var matched := matches[index]
		var value: Variant = get(matched.get_string(2))
		if value is Callable:
			continue
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_VECTOR3, TYPE_COLOR]:
			push_error("[creature_generator] Unsupported default parameter: %s" % matched.get_string(2))
			return ""
		var components: Array = [value]
		if value is Vector3:
			components = [value.x, value.y, value.z]
		elif value is Color:
			components = [value.r, value.g, value.b, value.a]
		for component: Variant in components:
			if component is float and not is_finite(component):
				push_error("[creature_generator] Default parameters must be finite: %s" % matched.get_string(2))
				return ""
		var start := matched.get_start(3)
		var end := matched.get_end(3)
		# Keep any inline comment from the original declaration.
		var initializer := matched.get_string(3)
		var comment_at := initializer.find("#")
		var comment := " " + initializer.substr(comment_at) if comment_at >= 0 else ""
		var suffix := ":" if initializer.get_slice("#", 0).strip_edges().ends_with(":") else ""
		updated = updated.substr(0, start) + var_to_str(value) + suffix + comment + updated.substr(end)
	return updated

func _write_default_source(path: String, source: String) -> bool:
	# Compile before writing so invalid values or edits cannot corrupt the tool script.
	var candidate := GDScript.new()
	candidate.source_code = source
	if candidate.reload() != OK:
		push_error("[creature_generator] Refusing to save invalid script defaults.")
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[creature_generator] Cannot write script defaults: %s" % path)
		return false
	file.store_string(source)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		push_error("[creature_generator] Error while writing script defaults: %s" % error_string(error))
		return false
	return true

## Regenerate the Torso and Feet without accumulating previous frames.
func generate_torso() -> bool:
	if not is_finite(overall_scale) or overall_scale < 0.1:
		push_warning("[creature_generator] Overall Scale must be finite and at least 0.1; previous frame retained.")
		return false
	if not is_inside_tree():
		return false
	var plan := _create_valid_plan()
	if plan.is_empty():
		push_warning("[creature_generator] Generation failed: no legal layout; previous frame retained. Check sizes, Narrowty, minimum Feet distance, Limb endpoint distance, Torso overlap percentage and Neck/Head overlap constraints.")
		return false
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = wireframe_color
	var scene_owner: Node = self
	if Engine.is_editor_hint():
		var edited_root := get_tree().edited_scene_root
		if edited_root != null and (edited_root == self or edited_root.is_ancestor_of(self)):
			scene_owner = edited_root
	_generate_feet(plan, scene_owner, material)
	_generate_torsos(plan.torsos, scene_owner, material)
	_generate_limb_blocks(scene_owner, material)
	_generate_limb_network(plan.limb_network, scene_owner, material)
	_generate_network_torsos(plan.network_torsos, scene_owner, material)
	_generate_necks(plan.necks, scene_owner, material)
	# Plan coordinates remain in base units; consumers apply this metadata exactly once.
	plan[&"overall_scale"] = overall_scale
	_apply_framework_scale(overall_scale)
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
	print("[creature_generator] torsos=%d covered_parts=%d attempts=%d valid=true" % [plan.torsos.size(), plan.layouts.size(), plan.attempts])
	print("[creature_generator] overall_scale=%.3f" % overall_scale)
	framework_generated.emit(plan)
	return true

func _apply_framework_scale(multiplier: float) -> void:
	for child: Node in get_children():
		if not child is Node3D: continue
		if child.name not in [&"Feets", &"LimbNetwork"] and not child.has_meta(&"generated_torso") and not child.has_meta(&"generated_network_torso") and not child.has_meta(&"generated_neck_line"):
			continue
		var generated := child as Node3D
		generated.position *= multiplier
		generated.basis = generated.basis.scaled(Vector3.ONE * multiplier)

func _generate_torsos(torsos: Array[Dictionary], scene_owner: Node, material: Material) -> void:
	for child: Node in get_children():
		if child.name == &"Torso" or child.name == &"SubTorso" or child.has_meta(&"generated_torso") or child.has_meta(&"generated_network_torso"):
			remove_child(child)
			child.queue_free()
	for index: int in range(torsos.size()):
		var layout := torsos[index]
		_create_torso_frame(layout, "SubTorso" if index == 0 else "SubTorso_%d" % (index + 1), scene_owner, material, false)

func _generate_network_torsos(torsos: Array[Dictionary], scene_owner: Node, material: Material) -> void:
	for index: int in range(torsos.size()):
		_create_torso_frame(torsos[index], "Torso" if index == 0 else "Torso_%d" % (index + 1), scene_owner, material, true)
	print("[creature_generator] network_torsos=%d all_body_blocks_connected=true connection_distance=%.3f" % [torsos.size(), torso_connection_distance])

func _nearest_neck_torso_distance(point: Vector3, torsos: Array[Dictionary]) -> float:
	var distance := INF
	for torso: Dictionary in torsos:
		var bounds := AABB(torso.position - torso.size * 0.5, torso.size)
		distance = minf(distance, _point_to_torso_distance(point, bounds))
	return distance

## Prefer front surfaces but permit free points around them, rather than attaching to a body node.
func _sample_neck_origin(torsos: Array[Dictionary]) -> Vector3:
	var torso: Dictionary = torsos[_random.randi_range(0, torsos.size() - 1)]
	var half: Vector3 = torso.size * 0.5
	var point: Vector3 = torso.position + Vector3(half.x, _random.randf_range(-half.y, half.y), _random.randf_range(-half.z, half.z))
	var direction := Vector3(_random.randf_range(-1.0, 1.0), _random.randf_range(-1.0, 1.0), _random.randf_range(-1.0, 1.0)).normalized()
	return point + direction * _random.randf_range(0.0, maxf(max_neck_start_surface_distance, 0.0))

## Clip the entire segment against the Y/Z projection and the region behind a block's front face.
## This is a continuous +X visibility test, not endpoint-only sampling.
func _neckline_front_clear(points: PackedVector3Array, blocks: Array[Dictionary]) -> bool:
	for index: int in range(points.size() - 1):
		var start := points[index]
		var delta := points[index + 1] - start
		for block: Dictionary in blocks:
			var bounds := AABB(block.position - block.size * 0.5, block.size)
			var lower := 0.0
			var upper := 1.0
			for axis: int in [1, 2]:
				var low := bounds.position[axis] + 0.00001
				var high := bounds.end[axis] - 0.00001
				if absf(delta[axis]) < 0.00000001:
					if start[axis] < low or start[axis] > high:
						upper = -1.0
						break
				else:
					var first := (low - start[axis]) / delta[axis]
					var second := (high - start[axis]) / delta[axis]
					lower = maxf(lower, minf(first, second))
					upper = minf(upper, maxf(first, second))
			if lower > upper:
				continue
			var limit := bounds.end.x - 0.00001
			if absf(delta.x) < 0.00000001:
				if start.x < limit:
					return false
			elif delta.x > 0.0:
				upper = minf(upper, (limit - start.x) / delta.x)
			else:
				lower = maxf(lower, (limit - start.x) / delta.x)
			if lower <= upper:
				return false
	return true

func _plan_necks(torsos: Array[Dictionary], subtorsos: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count := clampi(neck_number, 0, 256)
	if count == 0 or torsos.is_empty():
		return result
	var body_layouts := torsos.duplicate()
	body_layouts.append_array(subtorsos)
	var boxes: Array[Dictionary] = []
	for layouts: Array[Dictionary] in [torsos, subtorsos]:
		for layout: Dictionary in layouts:
			boxes.append(BOX_GEOMETRY.box(layout.size, Transform3D(Basis.IDENTITY, layout.position)))
	while result.size() < count:
		# An odd count starts with one center neck. Remaining necks form correlated pairs.
		var single := result.is_empty() and count % 2 == 1
		var accepted := false
		for attempt: int in range(MAX_GENERATION_ATTEMPTS):
			var origin := _sample_neck_origin(torsos)
			if single:
				origin.z *= _asymmetry()
			var total_length := _sample_dimension(neck_minimum_length, neck_maximum_length)
			var head_size := _sample_size(head_minimum_size, head_maximum_size)
			var batch: Array[Dictionary] = [{"points": _create_neck_points(origin, total_length), "length": total_length, "head_size": head_size}]
			if not single:
				var partner_origin := _mirror_point(origin).lerp(_sample_neck_origin(torsos), _asymmetry())
				var partner_length := lerpf(total_length, _sample_dimension(neck_minimum_length, neck_maximum_length), _asymmetry())
				batch.append({"points": _create_neck_points(partner_origin, partner_length), "length": partner_length, "head_size": head_size.lerp(_sample_size(head_minimum_size, head_maximum_size), _asymmetry())})
			var test_boxes := boxes.duplicate()
			var legal := true
			for neck: Dictionary in batch:
				var points: PackedVector3Array = neck.points
				if _nearest_neck_torso_distance(points[0], torsos) > maxf(max_neck_start_surface_distance, 0.0) + 0.00001:
					legal = false
					break
				if not _neckline_front_clear(points, body_layouts):
					legal = false
					break
				neck.blocks = _neck_blocks(points, neck.head_size)
				for block: Dictionary in neck.blocks:
					var next := BOX_GEOMETRY.box(block.size, Transform3D(block.basis, block.position))
					for existing: Dictionary in test_boxes:
						if BOX_GEOMETRY.overlap_diameter(next, existing) > maxf(max_neck_overlap_diameter, 0.0) + 0.00001:
							legal = false
							break
					if not legal:
						break
					test_boxes.append(next)
				if not legal:
					break
			if not legal:
				continue
			boxes = test_boxes
			result.append_array(batch)
			accepted = true
			break
		if not accepted:
			push_warning("[creature_generator] Neck generation failed: requested=%d planned=%d; root surface distance, front obstruction, symmetry or overlap constraints could not be satisfied. Retrying the body layout." % [count, result.size()])
			return []
	return result

func _neck_blocks(points: PackedVector3Array, head_size: Vector3) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	var thickness := maxf(neck_block_thickness, 0.01)
	for index: int in range(points.size() - 1):
		var direction := points[index + 1] - points[index]
		blocks.append({"name": "Neck" if index == 0 else "Neck_%d" % (index + 1), "size": Vector3(thickness, direction.length(), thickness), "position": (points[index] + points[index + 1]) * 0.5, "basis": Basis(Quaternion(Vector3.UP, direction.normalized()))})
	blocks.append({"name": "Head", "size": head_size, "position": points[-1] + Vector3(head_size.x * 0.5, 0, 0), "basis": Basis.IDENTITY})
	return blocks

func _create_neck_points(origin: Vector3, total_length: float) -> PackedVector3Array:
	var count := clampi(neck_segment_count, 4, 32)
	var points := PackedVector3Array([origin])
	var weight_sum := float(count) * (1.0 + 0.35) * 0.5
	for index: int in range(count):
		var progress := float(index) / float(count - 1)
		var length := total_length * lerpf(1.0, 0.35, progress) / weight_sum
		var angle := deg_to_rad(clampf(neck_maximum_angle, 0.0, 85.0)) * sin(PI * progress)
		# Make the two horizontal end segments exact, avoiding trigonometric roundoff.
		if index == 0 or index == count - 1:
			angle = 0.0
		points.append(points[-1] + Vector3(cos(angle), sin(angle), 0.0) * length)
	return points

func _generate_necks(necks: Array[Dictionary], scene_owner: Node, material: Material) -> void:
	for child: Node in get_children():
		if child.has_meta(&"generated_neck_line"):
			remove_child(child)
			child.queue_free()
	for index: int in range(necks.size()):
		var neck: Dictionary = necks[index]
		var points: PackedVector3Array = neck.points
		var vertices := PackedVector3Array()
		for segment: int in range(points.size() - 1):
			vertices.append(points[segment])
			vertices.append(points[segment + 1])
		var line := MeshInstance3D.new()
		line.name = "NeckLine" if index == 0 else "NeckLine_%d" % (index + 1)
		add_child(line)
		line.owner = scene_owner
		line.mesh = _create_line_mesh(vertices)
		line.material_override = material
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		line.set_meta(&"generated_neck_line", true)
		line.set_meta(&"neck_points", points)
		line.set_meta(&"neck_length", neck.length)
		for block: Dictionary in neck.blocks:
			var mesh := MeshInstance3D.new()
			mesh.name = block.name
			line.add_child(mesh)
			mesh.owner = scene_owner
			mesh.transform = Transform3D(block.basis, block.position)
			mesh.mesh = _create_wireframe(block.size)
			mesh.material_override = material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.set_meta(&"generated_neck_block", block.name != "Head")
			mesh.set_meta(&"generated_head", block.name == "Head")
			mesh.set_meta(&"block_size", block.size)
	print("[creature_generator] necks=%d requested=%d max_root_surface_distance=%.3f symmetry=%.3f" % [necks.size(), neck_number, max_neck_start_surface_distance, 1.0 - _asymmetry()])

func _create_torso_frame(layout: Dictionary, node_name: String, scene_owner: Node, material: Material, network_torso: bool) -> void:
	var size: Vector3 = layout.size
	var torso := Node3D.new()
	torso.name = node_name
	add_child(torso)
	torso.owner = scene_owner
	torso.transform = Transform3D(layout.get("basis", Basis.IDENTITY), layout.position)
	if network_torso:
		torso.set_meta(&"generated_network_torso", true)
		torso.set_meta(&"source_segment", layout.source_segment)
	else:
		torso.set_meta(&"generated_torso", true)
		torso.set_meta(&"covered_limb_count", layout.covered_limb_count)
	var wireframe := MeshInstance3D.new()
	wireframe.name = "Wireframe"
	torso.add_child(wireframe)
	wireframe.owner = scene_owner
	wireframe.mesh = _create_wireframe(size)
	wireframe.material_override = material
	wireframe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var label := Label3D.new()
	label.name = "NameLabel"
	torso.add_child(label)
	label.owner = scene_owner
	label.text = str(torso.name)
	label.position = Vector3(0.0, size.y * 0.5 + 0.3, 0.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = label_font_size
	label.pixel_size = 0.01
	label.modulate = label_color

## Segment cuboids are visual frames and deliberately bypass volume overlap validation.
func _generate_limb_blocks(scene_owner: Node, material: Material) -> void:
	var frames := get_node("Feets") as Node3D
	var total := 0
	for foot: Node in frames.get_children():
		if not foot.has_meta(&"limb_points"):
			continue
		var limb := foot.get_node("Limb") as MeshInstance3D
		for child: Node in limb.get_children():
			if child.has_meta(&"generated_limb_block"):
				limb.remove_child(child)
				child.queue_free()
		var points: PackedVector3Array = foot.get_meta(&"limb_points")
		var block_sizes: Array = foot.get_meta(&"limb_block_sizes")
		for index: int in range(points.size() - 1):
			var start := points[index]
			var end := points[index + 1]
			var direction := end - start
			var length := direction.length()
			var block := MeshInstance3D.new()
			block.name = "Segment_%d" % (index + 1)
			limb.add_child(block)
			block.owner = scene_owner
			var block_size: Vector3 = block_sizes[index]
			block.mesh = _create_wireframe(block_size)
			block.position = (start + end) * 0.5
			# Local Y follows the segment; its size is sampled independently of endpoint spacing.
			block.basis = Basis(Quaternion(Vector3.UP, direction / length))
			block.material_override = material
			block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			block.set_meta(&"generated_limb_block", true)
			block.set_meta(&"block_size", block_size)
			total += 1
	print("[creature_generator] limb_blocks=%d minimum_size=%s maximum_size=%s y_matches_segment=%s overlap_allowed=true" % [total, limb_minimum_size, limb_maximum_size, limb_y_matches_segment])

func _generate_limb_network(network: Dictionary, scene_owner: Node, material: Material) -> void:
	var mesh_node := get_node_or_null("LimbNetwork") as MeshInstance3D
	if mesh_node == null:
		mesh_node = MeshInstance3D.new()
		mesh_node.name = "LimbNetwork"
		add_child(mesh_node)
	mesh_node.owner = scene_owner
	mesh_node.transform = Transform3D.IDENTITY
	var vertices: PackedVector3Array = network.vertices
	mesh_node.mesh = _create_line_mesh(vertices) if not vertices.is_empty() else ArrayMesh.new()
	mesh_node.material_override = material
	mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_node.set_meta(&"limb_endpoints", network.endpoints)
	mesh_node.set_meta(&"extra_endpoints", network.extra_endpoints)
	mesh_node.set_meta(&"junctions", network.junctions)
	print("[creature_generator] limb_network endpoints=%d extra_endpoints=%d junctions=%d segments=%d merge_distance=%.3f connected=true" % [network.endpoints.size(), network.extra_endpoints.size(), network.junctions.size(), vertices.size() / 2, limb_endpoint_merge_distance])

func _network_root(parents: Array[int], index: int) -> int:
	while parents[index] != index:
		index = parents[index]
	return index

## Merge nearby tips into junctions, then randomly connect different components until one remains.
func _build_limb_network(layouts: Array[Dictionary]) -> Dictionary:
	var endpoints := PackedVector3Array()
	var parents: Array[int] = []
	for layout: Dictionary in layouts:
		endpoints.append(_limb_endpoint(layout))
	var limb_endpoints := endpoints.duplicate()
	var extra_endpoints := _sample_network_extra_endpoints(limb_endpoints)
	endpoints.append_array(extra_endpoints)
	for index: int in range(endpoints.size()):
		parents.append(index)
	var threshold := maxf(limb_endpoint_merge_distance, 0.0)
	for first: int in range(endpoints.size()):
		for second: int in range(first):
			if endpoints[first] == endpoints[second] or endpoints[first].distance_to(endpoints[second]) < threshold:
				parents[_network_root(parents, first)] = _network_root(parents, second)
	var clusters: Dictionary = {}
	for index: int in range(endpoints.size()):
		var root := _network_root(parents, index)
		if not clusters.has(root):
			clusters[root] = []
		clusters[root].append(index)
	var junctions := PackedVector3Array()
	var vertices := PackedVector3Array()
	for members: Array in clusters.values():
		var junction := Vector3.ZERO
		for index: int in members:
			junction += endpoints[index]
		junction /= float(members.size())
		junctions.append(junction)
		# Keep every original tip on the network even when its junction is merged.
		for index: int in members:
			if endpoints[index] != junction:
				vertices.append(endpoints[index])
				vertices.append(junction)
	var profile := _network_profile(limb_endpoints)
	parents.clear()
	for index: int in range(junctions.size()):
		parents.append(index)
	for connection: int in range(maxi(junctions.size() - 1, 0)):
		var candidates: Array[Vector2i] = []
		for first: int in range(junctions.size()):
			for second: int in range(first):
				if _network_root(parents, first) != _network_root(parents, second):
					candidates.append(Vector2i(first, second))
		var weights: Array[float] = []
		for candidate: Vector2i in candidates:
			var centrality := (_core_weight(junctions[candidate.x], profile) + _core_weight(junctions[candidate.y], profile)) * 0.5
			weights.append(lerpf(1.0, 0.1 + centrality * centrality * 10.0, clampf(network_center_bias, 0.0, 1.0)))
		var edge := candidates[_weighted_index(weights)]
		parents[_network_root(parents, edge.x)] = _network_root(parents, edge.y)
		if junctions[edge.x] != junctions[edge.y]:
			vertices.append(junctions[edge.x])
			vertices.append(junctions[edge.y])
	# A random chain also directly links free vertices; duplicate edges are skipped.
	var order: Array[int] = []
	for index: int in range(extra_endpoints.size()):
		order.append(index)
	for index: int in range(order.size() - 1, 0, -1):
		var other := _random.randi_range(0, index)
		var saved := order[index]
		order[index] = order[other]
		order[other] = saved
	for index: int in range(order.size() - 1):
		_append_network_edge(vertices, extra_endpoints[order[index]], extra_endpoints[order[index + 1]])
	# Additional short core links create more routes centrally without increasing peripheral degree.
	var core_edges: Array[Vector2i] = []
	for first: int in range(junctions.size()):
		for second: int in range(first):
			if _core_weight(junctions[first], profile) >= 0.5 and _core_weight(junctions[second], profile) >= 0.5:
				core_edges.append(Vector2i(first, second))
	var added := 0
	while not core_edges.is_empty() and added < clampi(network_core_extra_connections, 0, 32):
		var selected := _random.randi_range(0, core_edges.size() - 1)
		var edge := core_edges[selected]
		core_edges.remove_at(selected)
		var old_size := vertices.size()
		_append_network_edge(vertices, junctions[edge.x], junctions[edge.y])
		if vertices.size() > old_size:
			added += 1
	var original_vertices := vertices.duplicate()
	for index: int in range(0, original_vertices.size(), 2):
		if _random.randf() >= _asymmetry():
			var a := _nearest_mirror(original_vertices[index], endpoints, junctions)
			var b := _nearest_mirror(original_vertices[index + 1], endpoints, junctions)
			_append_network_edge(vertices, a, b)
	return {"endpoints": limb_endpoints, "extra_endpoints": extra_endpoints, "junctions": junctions, "vertices": vertices}

func _network_profile(points: PackedVector3Array) -> Dictionary:
	if points.is_empty():
		return {"center": Vector3.ZERO, "radius": 0.01}
	var low := points[0]
	var high := points[0]
	for point: Vector3 in points:
		low = low.min(point)
		high = high.max(point)
	var center := (low + high) * 0.5
	var radius := 0.01
	for point: Vector3 in points:
		radius = maxf(radius, point.distance_to(center))
	return {"center": center, "radius": radius}

func _core_weight(position: Vector3, profile: Dictionary) -> float:
	return clampf(1.0 - position.distance_to(profile.center) / float(profile.radius), 0.0, 1.0)

func _weighted_index(weights: Array[float]) -> int:
	var total := 0.0
	for weight: float in weights:
		total += weight
	var pick := _random.randf() * total
	for index: int in range(weights.size()):
		pick -= weights[index]
		if pick <= 0.0:
			return index
	return weights.size() - 1

func _sample_profile_torso_size(position: Vector3, profile: Dictionary, fallback: float = 0.0) -> Vector3:
	var bias := clampf(torso_center_size_bias, 0.0, 1.0)
	var centrality := _core_weight(position, profile)
	var size := Vector3.ZERO
	for axis: int in range(3):
		var low := maxf(minf(torso_minimum_size[axis], torso_maximum_size[axis]), 0.01)
		var high := maxf(maxf(torso_minimum_size[axis], torso_maximum_size[axis]), low)
		var lower_fraction := bias * centrality * (1.0 - fallback)
		var upper_fraction := 1.0 - bias + bias * centrality
		if centrality < 0.5:
			upper_fraction *= 1.0 - bias * 0.5
		lower_fraction = minf(lower_fraction, upper_fraction)
		size[axis] = lerpf(low, high, _random.randf_range(lower_fraction, upper_fraction))
	return size

## Reuse a sampled quantile as the candidate moves, avoiding a new random size that opens gaps.
func _profile_size_at_position(size: Vector3, from: Vector3, to: Vector3, profile: Dictionary, fallback: float) -> Vector3:
	var bias := clampf(torso_center_size_bias, 0.0, 1.0)
	var first := _core_weight(from, profile)
	var second := _core_weight(to, profile)
	var lower := bias * first * (1.0 - fallback)
	var upper := 1.0 - bias + bias * first
	if first < 0.5:
		upper *= 1.0 - bias * 0.5
	lower = minf(lower, upper)
	var next_lower := bias * second * (1.0 - fallback)
	var next_upper := 1.0 - bias + bias * second
	if second < 0.5:
		next_upper *= 1.0 - bias * 0.5
	next_lower = minf(next_lower, next_upper)
	var result := size
	for axis: int in range(3):
		var low := maxf(minf(torso_minimum_size[axis], torso_maximum_size[axis]), 0.01)
		var high := maxf(maxf(torso_minimum_size[axis], torso_maximum_size[axis]), low)
		if high - low < 0.000001:
			continue
		var fraction := (size[axis] - low) / (high - low)
		var quantile := clampf((fraction - lower) / maxf(upper - lower, 0.000001), 0.0, 1.0)
		result[axis] = lerpf(low, high, lerpf(next_lower, next_upper, quantile))
	return result

func _asymmetry() -> float:
	return clampf(unsymmetrie / 100.0, 0.0, 1.0)

func _mirror_point(point: Vector3) -> Vector3:
	return Vector3(point.x, point.y, -point.z)

func _nearest_mirror(point: Vector3, first: PackedVector3Array, second: PackedVector3Array) -> Vector3:
	var target := _mirror_point(point)
	var best := point
	var distance := INF
	for points: PackedVector3Array in [first, second]:
		for candidate: Vector3 in points:
			var next := candidate.distance_squared_to(target)
			if next < distance:
				distance = next
				best = candidate
	return best

func _append_network_edge(vertices: PackedVector3Array, first: Vector3, second: Vector3) -> void:
	if first == second:
		return
	for index: int in range(0, vertices.size(), 2):
		if (vertices[index] == first and vertices[index + 1] == second) or (vertices[index] == second and vertices[index + 1] == first):
			return
	vertices.append(first)
	vertices.append(second)

func _sample_network_extra_endpoints(limb_endpoints: PackedVector3Array) -> PackedVector3Array:
	var extra := PackedVector3Array()
	if limb_endpoints.is_empty():
		return extra
	var low := limb_endpoints[0]
	var high := low
	for point: Vector3 in limb_endpoints:
		low = low.min(point)
		high = high.max(point)
	# Give degenerate bounds a small volume so free points can still be distinct.
	var padding := Vector3.ONE * maxf(network_extra_endpoint_padding, 0.0)
	low -= padding
	high += padding
	for axis: int in range(3):
		if high[axis] == low[axis]:
			low[axis] -= 0.01
			high[axis] += 0.01
	var count := clampi(network_extra_endpoint_count, 0, 32)
	for index: int in range(count):
		for attempt: int in range(64):
			var point := Vector3(_random.randf_range(low.x, high.x), _random.randf_range(low.y, high.y), _random.randf_range(low.z, high.z))
			point = point.lerp((low + high) * 0.5, clampf(network_center_bias, 0.0, 1.0))
			if index % 2 == 1:
				point = _mirror_point(extra[index - 1]).lerp(point, _asymmetry())
			elif index == count - 1:
				point.z *= _asymmetry()
			if not limb_endpoints.has(point) and not extra.has(point):
				extra.append(point)
				break
	return extra

## Randomly visit network segments and cover each selected segment with overlapping boxes.
func _plan_network_torsos(subtorsos: Array[Dictionary], vertices: PackedVector3Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if vertices.is_empty():
		return result
	var boxes: Array[Dictionary] = []
	var parents: Array[int] = []
	for torso: Dictionary in subtorsos:
		var sub_box := BOX_GEOMETRY.box(torso.size, Transform3D(Basis.IDENTITY, torso.position))
		if not _torso_overlap_is_legal(sub_box.aabb, boxes):
			return []
		boxes.append(sub_box)
		parents.append(parents.size())
	var components := boxes.size()
	var threshold := maxf(torso_connection_distance, 0.0)
	for first: int in range(boxes.size()):
		for second: int in range(first):
			if _network_root(parents, first) != _network_root(parents, second) and BOX_GEOMETRY.connected(boxes[first], boxes[second], threshold):
				parents[_network_root(parents, first)] = _network_root(parents, second)
				components -= 1
	var order: Array[int] = []
	for segment: int in range(vertices.size() / 2):
		order.append(segment)
	var profile := _network_profile(vertices)
	var attempted := 0
	var rejected_overlap := 0
	var passes := 0
	# Keep accepted boxes and retry every segment until connected or a safety limit is reached.
	while true:
		passes += 1
		for index: int in range(order.size() - 1, 0, -1):
			var other := _random.randi_range(0, index)
			var saved := order[index]
			order[index] = order[other]
			order[other] = saved
		var priorities: Dictionary = {}
		for segment: int in order:
			var midpoint := (vertices[segment * 2] + vertices[segment * 2 + 1]) * 0.5
			var weight := 1.0 + _core_weight(midpoint, profile) * clampf(torso_center_density_bias, 0.0, 1.0) * 8.0
			priorities[segment] = -log(maxf(_random.randf(), 0.000001)) / weight
		order.sort_custom(func(a: int, b: int) -> bool: return priorities[a] < priorities[b])
		for segment: int in order:
			var start := vertices[segment * 2]
			var end := vertices[segment * 2 + 1]
			if _random.randf() < 0.5:
				var saved := start
				start = end
				end = saved
			var direction := end - start
			var length := direction.length()
			var basis := Basis.IDENTITY
			var unit_direction := direction / length
			var travel := 0.0
			var previous_span := 0.0
			while true:
				if result.size() >= MAX_NETWORK_TORSOS:
					push_warning("[creature_generator] Torso network exceeded its generation limit after %d passes; remaining_components=%d, generated=%d, attempts=%d, overlap_rejections=%d." % [passes, components, result.size(), attempted, rejected_overlap])
					return []
				var accepted := false
				var size := Vector3.ZERO
				var span := 0.0
				var position := Vector3.ZERO
				var batch: Array[Dictionary] = []
				for attempt: int in range(MAX_GENERATION_ATTEMPTS):
					attempted += 1
					if attempted > MAX_NETWORK_TORSO_ATTEMPTS:
						push_warning("[creature_generator] Torso network exceeded the retry limit after %d passes; remaining_components=%d, generated=%d, attempts=%d, overlap_rejections=%d; previous frame retained." % [passes, components, result.size(), attempted, rejected_overlap])
						return []
					size = _sample_profile_torso_size(start + unit_direction * travel, profile, clampf(float(attempt) / 64.0, 0.0, 1.0))
					span = INF
					for axis: int in range(3):
						if absf(unit_direction[axis]) > 0.000001:
							span = minf(span, size[axis] / absf(unit_direction[axis]))
					var candidate_travel := travel
					var step_offset := 0.0
					if previous_span > 0.0:
						# Try overlap, exact contact, or a small legal gap along the segment.
						var centrality := _core_weight(start + unit_direction * travel, profile)
						var density := clampf(torso_center_density_bias, 0.0, 1.0)
						var contact_step := (previous_span + span) * 0.5
						var overlap := contact_step * minf(0.1, clampf(max_torso_overlap_percent, 0.0, 100.0) / 100.0 * 0.2) * centrality * density
						var gap := threshold * lerpf(0.5, 0.95 * (1.0 - centrality), density)
						var step := contact_step if attempt % 3 == 0 else _random.randf_range(contact_step - overlap, contact_step + gap)
						step_offset = step - contact_step
						candidate_travel = minf(travel + step, length)
					elif attempt > 0:
						# A strict volume percentage may require the first box to
						# leave most of the anchor volume before it becomes legal.
						candidate_travel = minf(travel + _random.randf_range(0.0, span), length)
					position = start + direction * (candidate_travel / length)
					var reference_size := size
					var reference_position := start + unit_direction * travel
					for refinement: int in range(4):
						size = _profile_size_at_position(reference_size, reference_position, position, profile, clampf(float(attempt) / 64.0, 0.0, 1.0))
						span = INF
						for axis: int in range(3):
							if absf(unit_direction[axis]) > 0.000001:
								span = minf(span, size[axis] / absf(unit_direction[axis]))
						if previous_span > 0.0:
							candidate_travel = minf(travel + (previous_span + span) * 0.5 + step_offset, length)
							position = start + unit_direction * candidate_travel
					batch = [{"size": size, "position": position, "basis": basis, "source_segment": PackedVector3Array([start, end])}]
					if _random.randf() >= _asymmetry():
						var counterpart := _mirror_segment(start, end, vertices)
						var other_position := counterpart[0].lerp(counterpart[1], candidate_travel / length)
						var other_size := size.lerp(_sample_profile_torso_size(other_position, profile, clampf(float(attempt) / 64.0, 0.0, 1.0)), _asymmetry())

						if position.distance_to(other_position) > 0.00001:
							batch.append({"size": other_size, "position": other_position, "basis": basis, "source_segment": counterpart})
					if result.size() + batch.size() > MAX_NETWORK_TORSOS:
						continue
					var candidate_boxes := boxes.duplicate()
					var legal := true
					for candidate: Dictionary in batch:
						var next := BOX_GEOMETRY.box(candidate.size, Transform3D(candidate.basis, candidate.position))
						if not _torso_overlap_is_legal(next.aabb, candidate_boxes):
							legal = false
							break
						candidate_boxes.append(next)
					if not legal:
						rejected_overlap += 1
						continue
					travel = candidate_travel
					accepted = true
					break
				if not accepted:
					# Another segment or a later pass may provide a legal route.
					break
				for candidate: Dictionary in batch:
					var next_box := BOX_GEOMETRY.box(candidate.size, Transform3D(candidate.basis, candidate.position))
					var new_index := boxes.size()
					parents.append(new_index)
					components += 1
					for existing: int in range(boxes.size()):
						if _network_root(parents, new_index) != _network_root(parents, existing) and BOX_GEOMETRY.connected(next_box, boxes[existing], threshold):
							parents[_network_root(parents, new_index)] = _network_root(parents, existing)
							components -= 1
					boxes.append(next_box)
					result.append(candidate)
				if components == 1:
					print("[creature_generator] torso_overlap max_percent=%.2f rejected=%d attempts=%d passes=%d valid=true" % [max_torso_overlap_percent, rejected_overlap, attempted, passes])
					_add_core_torsos(result, boxes, vertices, profile)
					return result
				if travel >= length:
					break
				previous_span = span
		print("[creature_generator] torso_network pass=%d remaining_components=%d generated=%d attempts=%d overlap_rejections=%d retrying=true" % [passes, components, result.size(), attempted, rejected_overlap])
	return []

## Densify the core only with blocks attached to the already-connected body.
## Both members of a mirror pair must pass overlap and connectivity checks together.
func _add_core_torsos(result: Array[Dictionary], boxes: Array[Dictionary], vertices: PackedVector3Array, profile: Dictionary) -> void:
	var added := 0
	var target := clampi(torso_core_extra_blocks, 0, 32)
	var weights: Array[float] = []
	for index: int in range(0, vertices.size(), 2):
		weights.append(0.01 + pow(_core_weight((vertices[index] + vertices[index + 1]) * 0.5, profile), 2.0))
	for attempt: int in range(256):
		if added >= target or result.size() >= MAX_NETWORK_TORSOS:
			break
		var segment := _weighted_index(weights) * 2
		var start := vertices[segment]
		var end := vertices[segment + 1]
		var fraction := _random.randf()
		var position := start.lerp(end, fraction)
		if _core_weight(position, profile) < 0.5:
			continue
		var size := _sample_profile_torso_size(position, profile, clampf(float(attempt) / 256.0, 0.0, 0.75))
		var batch: Array[Dictionary] = [{"size": size, "position": position, "basis": Basis.IDENTITY, "source_segment": PackedVector3Array([start, end])}]
		if _random.randf() >= _asymmetry():
			var counterpart := _mirror_segment(start, end, vertices)
			var other_position := counterpart[0].lerp(counterpart[1], fraction)
			if position.distance_to(other_position) > 0.00001:
				var other_size := size.lerp(_sample_profile_torso_size(other_position, profile), _asymmetry())
				batch.append({"size": other_size, "position": other_position, "basis": Basis.IDENTITY, "source_segment": counterpart})
		if added + batch.size() > target or result.size() + batch.size() > MAX_NETWORK_TORSOS:
			continue
		var test_boxes := boxes.duplicate()
		var legal := true
		for candidate: Dictionary in batch:
			if _core_weight(candidate.position, profile) < 0.5:
				legal = false
				break
			var next := BOX_GEOMETRY.box(candidate.size, Transform3D(Basis.IDENTITY, candidate.position))
			if not _torso_overlap_is_legal(next.aabb, test_boxes):
				legal = false
				break
			var connected := false
			for existing: Dictionary in test_boxes:
				if candidate.position.distance_to(existing.transform.origin) < 0.00001:
					legal = false
					break
				connected = connected or BOX_GEOMETRY.connected(next, existing, maxf(torso_connection_distance, 0.0))
			if not legal or not connected:
				legal = false
				break
			test_boxes.append(next)
		if not legal:
			continue
		for candidate: Dictionary in batch:
			boxes.append(BOX_GEOMETRY.box(candidate.size, Transform3D(Basis.IDENTITY, candidate.position)))
			result.append(candidate)
		added += batch.size()
	var core_count := 0
	var edge_count := 0
	var core_volume := 0.0
	var edge_volume := 0.0
	for candidate: Dictionary in result:
		var volume: float = candidate.size.x * candidate.size.y * candidate.size.z
		if _core_weight(candidate.position, profile) >= 0.5:
			core_count += 1
			core_volume += volume
		else:
			edge_count += 1
			edge_volume += volume
	print("[creature_generator] torso_distribution core_count=%d edge_count=%d core_mean_volume=%.3f edge_mean_volume=%.3f core_added=%d/%d" % [core_count, edge_count, core_volume / maxi(core_count, 1), edge_volume / maxi(edge_count, 1), added, target])

func _mirror_segment(start: Vector3, end: Vector3, vertices: PackedVector3Array) -> PackedVector3Array:
	var best := PackedVector3Array([start, end])
	var distance := INF
	for index: int in range(0, vertices.size(), 2):
		for reverse: bool in [false, true]:
			var a := vertices[index + (1 if reverse else 0)]
			var b := vertices[index + (0 if reverse else 1)]
			var next := a.distance_squared_to(_mirror_point(start)) + b.distance_squared_to(_mirror_point(end))
			if next < distance:
				distance = next
				best = PackedVector3Array([a, b])
	return best

## Torso generation uses axis-aligned boxes in generator-local coordinates.
func _torso_overlap_volume(first: AABB, second: AABB) -> float:
	var overlap_size := first.end.min(second.end) - first.position.max(second.position)
	# Face/edge/point contact has no volume and remains legal at a zero threshold.
	if overlap_size.x <= 0.0 or overlap_size.y <= 0.0 or overlap_size.z <= 0.0:
		return 0.0
	return overlap_size.x * overlap_size.y * overlap_size.z

func _torso_overlap_is_legal(candidate: AABB, boxes: Array[Dictionary]) -> bool:
	var candidate_volume := candidate.get_volume()
	if candidate_volume <= 0.0: return false
	var limit := clampf(max_torso_overlap_percent, 0.0, 100.0) / 100.0
	for existing: Dictionary in boxes:
		var bounds: AABB = existing.aabb
		var existing_volume := bounds.get_volume()
		if existing_volume <= 0.0: return false
		var overlap := _torso_overlap_volume(candidate, bounds)
		if overlap / candidate_volume > limit + 0.000001 or overlap / existing_volume > limit + 0.000001:
			return false
	return true

func _sample_dimension(first: float, second: float) -> float:
	var low := maxf(minf(first, second), 0.01)
	var high := maxf(maxf(first, second), low)
	return _random.randf_range(low, high)

func _create_wireframe(size: Vector3) -> ArrayMesh:
	var half := size * 0.5
	var corners := PackedVector3Array([
		Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z),
		Vector3(half.x, half.y, -half.z), Vector3(-half.x, half.y, -half.z),
		Vector3(-half.x, -half.y, half.z), Vector3(half.x, -half.y, half.z),
		Vector3(half.x, half.y, half.z), Vector3(-half.x, half.y, half.z)
	])
	var edges := PackedInt32Array([0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7])
	var vertices := PackedVector3Array()
	for index: int in edges:
		vertices.append(corners[index])
	return _create_line_mesh(vertices)

func _create_line_mesh(vertices: PackedVector3Array) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh

func _generate_feet(plan: Dictionary, scene_owner: Node, material: Material) -> void:
	var frames := get_node_or_null("Feets") as Node3D
	if frames == null:
		frames = Node3D.new()
		frames.name = "Feets"
		add_child(frames)
	frames.owner = scene_owner
	frames.transform = Transform3D.IDENTITY
	# Rebuild generated limbs after classification; names change between generations.
	for child: Node in frames.get_children():
		if child.name != &"VariationRange" and (child.has_meta(&"initial_position") or str(child.name).begins_with("Feet_") or str(child.name).begins_with("ForeLeg_") or str(child.name).begins_with("Arm_") or str(child.name).begins_with("Leg_")):
			frames.remove_child(child)
			child.queue_free()
	frames.set_meta(&"extra_leg_count", plan.extra_leg_count)
	var layouts: Array[Dictionary] = plan.layouts
	var count := layouts.size()
	var radius: float = plan.radius
	frames.set_meta(&"variation_radius", radius)
	frames.set_meta(&"distribution_scale", _get_distribution_scale())
	frames.set_meta(&"allowed_spread", layouts[0].allowed_spread)
	var range_circle := frames.get_node_or_null("VariationRange") as MeshInstance3D
	if range_circle == null:
		range_circle = MeshInstance3D.new()
		range_circle.name = "VariationRange"
		frames.add_child(range_circle)
	range_circle.owner = scene_owner
	range_circle.mesh = _create_range_circle(radius)
	var range_material := StandardMaterial3D.new()
	range_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	range_material.albedo_color = wireframe_color.darkened(0.5)
	range_circle.material_override = range_material
	range_circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var name_counts := {"ForeLeg": 0, "Leg": 0}
	for index: int in range(layouts.size()):
		var layout := layouts[index]
		var initial: Vector2 = layout.position
		var target: Vector2 = layout.target_position
		var travel_fraction: float = layout.travel_fraction
		var position: Vector2 = layout.final_position
		var foot_size: Vector3 = layout.size
		var role: String = layout.role
		name_counts[role] += 1
		var foot_name := "%s_%d" % [role, name_counts[role]]
		var foot := frames.get_node_or_null(NodePath(foot_name)) as Node3D
		if foot == null:
			foot = Node3D.new()
			foot.name = foot_name
			frames.add_child(foot)
		foot.owner = scene_owner
		foot.position = Vector3(position.x, foot_size.y * 0.5, position.y)
		foot.rotation = Vector3.ZERO
		foot.scale = Vector3.ONE
		foot.set_meta(&"foot_index", index)
		foot.set_meta(&"limb_type", role)
		foot.set_meta(&"initial_position", initial)
		foot.set_meta(&"target_position", target)
		foot.set_meta(&"travel_fraction", travel_fraction)
		var wireframe := foot.get_node_or_null("Wireframe") as MeshInstance3D
		if wireframe == null:
			wireframe = MeshInstance3D.new()
			wireframe.name = "Wireframe"
			foot.add_child(wireframe)
		wireframe.transform = Transform3D.IDENTITY
		wireframe.mesh = _create_wireframe(foot_size)
		wireframe.material_override = material
		wireframe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wireframe.owner = scene_owner
		var points: PackedVector3Array = layout.limb_points
		foot.set_meta(&"limb_length", layout.limb_length)
		foot.set_meta(&"limb_points", points)
		foot.set_meta(&"limb_block_sizes", layout.limb_block_sizes)
		var limb_line := MeshInstance3D.new()
		limb_line.name = "Limb"
		foot.add_child(limb_line)
		limb_line.owner = scene_owner
		var line_vertices := PackedVector3Array()
		for segment: int in range(points.size() - 1):
			line_vertices.append(points[segment])
			line_vertices.append(points[segment + 1])
		limb_line.mesh = _create_line_mesh(line_vertices)
		limb_line.material_override = material
		limb_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var label := foot.get_node_or_null("NameLabel") as Label3D
		if label == null:
			label = Label3D.new()
			label.name = "NameLabel"
			foot.add_child(label)
		label.owner = scene_owner
		label.text = foot_name
		label.position = Vector3(0.0, foot_size.y * 0.5 + 0.2, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.font_size = label_font_size
		label.pixel_size = 0.01
		label.modulate = label_color
	print("[creature_generator] feets=%d forelegs=%d legs=%d extra_legs=%d unsymmetrie=%.2f narrowty=%.2f allowed_xz=%s variation_radius=%.3f" % [count, name_counts.ForeLeg, name_counts.Leg, plan.extra_leg_count, unsymmetrie, narrowty, layouts[0].allowed_spread, radius])

func _sample_feet_target(initial: Vector2, radius: float, strength: float) -> Vector2:
	if strength <= 0.0:
		return initial
	# Uniform disk sampling, rejecting points outside the total variation circle.
	for attempt: int in range(64):
		var angle := _random.randf_range(0.0, TAU)
		var distance := sqrt(_random.randf()) * radius * strength
		var target := initial + Vector2(cos(angle), sin(angle)) * distance
		if target.length_squared() <= radius * radius:
			return target
	return initial

func _create_range_circle(radius: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	for segment: int in range(64):
		var start := TAU * float(segment) / 64.0
		var end := TAU * float(segment + 1) / 64.0
		vertices.append(Vector3(cos(start) * radius, 0.0, sin(start) * radius))
		vertices.append(Vector3(cos(end) * radius, 0.0, sin(end) * radius))
	return _create_line_mesh(vertices)

## Plan and validate before touching the saved scene or its previous meshes.
func _create_valid_plan() -> Dictionary:
	if not is_finite(network_center_bias) or not is_finite(torso_center_size_bias) or not is_finite(torso_center_density_bias) or not is_finite(max_neck_start_surface_distance) or not is_finite(neck_block_thickness) or not is_finite(max_neck_overlap_diameter) or not head_minimum_size.is_finite() or not head_maximum_size.is_finite() or not is_finite(neck_minimum_length) or not is_finite(neck_maximum_length) or not is_finite(neck_maximum_angle) or not minimum_size.is_finite() or not maximum_size.is_finite() or not base_foot_size.is_finite() or not minimum_foot_size.is_finite() or not maximum_foot_size.is_finite() or not is_finite(minimum_feet_distance) or not is_finite(inhomogeneity) or not is_finite(unsymmetrie) or not is_finite(narrowty) or not is_finite(base_limb_length) or not limb_minimum_size.is_finite() or not limb_maximum_size.is_finite() or not is_finite(max_limb_end_height_difference) or not is_finite(limb_endpoint_merge_distance) or not is_finite(network_extra_endpoint_padding) or not torso_minimum_size.is_finite() or not torso_maximum_size.is_finite() or not is_finite(torso_connection_distance) or not is_finite(max_torso_overlap_percent):
		return {}
	var gap := maxf(minimum_feet_distance, 0.0)
	for attempt: int in range(MAX_GENERATION_ATTEMPTS):
		# Feet distribution uses the configured size envelope, not a pre-generated Torso.
		var layouts := _sample_initial_feet(minimum_size.max(maximum_size).max(Vector3.ONE * 0.01), gap)
		if layouts.is_empty():
			continue
		var radius := _get_variation_radius(layouts)
		if not _apply_feet_offsets(layouts, radius, gap):
			continue
		var extra_leg_count := _assign_limb_roles(layouts)
		_assign_limb_lengths(layouts)
		for index: int in range(layouts.size()):
			var layout: Dictionary = layouts[index]
			var size: Vector3 = layout.size
			var points := _create_limb_points(layout.role, size.y, layout.limb_length)
			if index % 2 == 1 and layouts[index - 1].role == layout.role:
				var partner: PackedVector3Array = layouts[index - 1].limb_points
				for point: int in range(1, points.size()):
					var correlated: Vector3 = points[0] + (partner[point] - partner[0]) * (layout.limb_length / layouts[index - 1].limb_length)
					points[point] = correlated.lerp(points[point], _asymmetry())
				var length := 0.0
				for point: int in range(1, points.size()):
					length += points[point].distance_to(points[point - 1])
				for point: int in range(1, points.size()):
					points[point] = points[0] + (points[point] - points[0]) * layout.limb_length / length
				if _asymmetry() == 0.0:
					points = partner.duplicate()
			layout.limb_points = points
		# All Limb geometry is fixed before the first Torso is sampled.
		var torsos := _plan_torsos(layouts)
		if torsos.is_empty():
			continue
		var network := _build_limb_network(layouts)
		var network_torsos := _plan_network_torsos(torsos, network.vertices)
		if network_torsos.is_empty():
			return {}
		var necks := _plan_necks(network_torsos, torsos)
		if necks.size() != clampi(neck_number, 0, 256):
			continue
		_assign_limb_block_sizes(layouts)
		return {"necks": necks, "torsos": torsos, "network_torsos": network_torsos, "layouts": layouts, "limb_network": network, "extra_leg_count": extra_leg_count, "radius": radius, "attempts": attempt + 1}
	return {}

## Store samples in the plan so preview and physics consume identical dimensions.
func _assign_limb_block_sizes(layouts: Array[Dictionary]) -> void:
	for index: int in range(layouts.size()):
		var layout: Dictionary = layouts[index]
		var sizes: Array[Vector3] = []
		var points: PackedVector3Array = layout.limb_points
		for segment: int in range(points.size() - 1):
			var size := _sample_size(limb_minimum_size, limb_maximum_size)
			if index % 2 == 1 and layouts[index - 1].role == layout.role:
				var partner: Vector3 = layouts[index - 1].limb_block_sizes[segment]
				size = partner.lerp(size, _asymmetry())
			if limb_y_matches_segment:
				size.y = points[segment].distance_to(points[segment + 1])
			sizes.append(size)
		layout.limb_block_sizes = sizes

## Strict interval overlap: touching edges alone does not cover a part.
func _overlaps_x(a: AABB, b: AABB) -> bool:
	return minf(a.end.x, b.end.x) > maxf(a.position.x, b.position.x)

func _limb_endpoint(layout: Dictionary) -> Vector3:
	var points: PackedVector3Array = layout.limb_points
	var position: Vector2 = layout.final_position
	var size: Vector3 = layout.size
	return Vector3(position.x, size.y * 0.5, position.y) + points[points.size() - 1]

## Shortest distance to the shell, not the center or the solid volume.
func _point_to_torso_distance(point: Vector3, bounds: AABB) -> float:
	var closest := point.clamp(bounds.position, bounds.end)
	if closest != point:
		return point.distance_to(closest)
	# Interior points must reach a face; only points on the surface return zero.
	var lower := point - bounds.position
	var upper := bounds.end - point
	return minf(minf(lower.x, upper.x), minf(minf(lower.y, upper.y), minf(lower.z, upper.z)))

func _sample_size(low: Vector3, high: Vector3) -> Vector3:
	return Vector3(_sample_dimension(low.x, high.x), _sample_dimension(low.y, high.y), _sample_dimension(low.z, high.z))

func _plan_torsos(layouts: Array[Dictionary]) -> Array[Dictionary]:
	var torsos: Array[Dictionary] = []
	var uncovered: Array[int] = []
	var endpoints := PackedVector3Array()
	var tallest := 0.0
	for index: int in range(layouts.size()):
		uncovered.append(index)
		tallest = maxf(tallest, _foot_bounds(layouts[index]).end.y)
		endpoints.append(_limb_endpoint(layouts[index]))
	var distance_limit := maxf(max_limb_end_height_difference, 0.0) + 0.00001
	while not uncovered.is_empty():
		var accepted := false
		for attempt: int in range(MAX_GENERATION_ATTEMPTS):
			var target: Vector3 = endpoints[uncovered[_random.randi_range(0, uncovered.size() - 1)]]
			var size := _sample_size(minimum_size, maximum_size)
			var center := target + Vector3(_random.randf_range(-0.35, 0.35) * size.x, size.y * 0.5, _random.randf_range(-0.35, 0.35) * size.z)
			center.y = maxf(target.y, tallest + TORSO_CLEARANCE) + size.y * 0.5
			var batch: Array[Dictionary] = []
			var paired := _random.randf() >= _asymmetry()
			# A block crossing the mirror plane is represented once, centered on that plane.
			if paired and absf(center.z) < size.z * 0.5:
				center.z *= _asymmetry()
				paired = false
			batch.append({"size": size, "position": center})
			if paired:
				var partner_target := _nearest_mirror(target, endpoints, PackedVector3Array())
				var other_size := size.lerp(_sample_size(minimum_size, maximum_size), _asymmetry())
				var independent := partner_target + Vector3(_random.randf_range(-0.35, 0.35) * other_size.x, other_size.y * 0.5, _random.randf_range(-0.35, 0.35) * other_size.z)
				independent.y = maxf(partner_target.y, tallest + TORSO_CLEARANCE) + other_size.y * 0.5
				batch.append({"size": other_size, "position": _mirror_point(center).lerp(independent, _asymmetry())})
			var lift := 0.0
			for candidate: Dictionary in batch:
				var bounds := AABB(candidate.position - candidate.size * 0.5, candidate.size)
				for previous: Dictionary in torsos:
					var old: AABB = previous.bounds
					if _overlaps_x(bounds, old) and minf(bounds.end.z, old.end.z) > maxf(bounds.position.z, old.position.z):
						lift = maxf(lift, old.end.y + TORSO_CLEARANCE - bounds.position.y)
			var legal := true
			var covers := false
			for index: int in range(batch.size()):
				var candidate: Dictionary = batch[index]
				candidate.position.y += lift
				candidate.bounds = AABB(candidate.position - candidate.size * 0.5, candidate.size)
				candidate.covered_limb_count = 0
				legal = legal and _is_layout_valid(candidate.bounds, layouts, maxf(minimum_feet_distance, 0.0))
				for prior: int in range(index):
					legal = legal and not candidate.bounds.intersects(batch[prior].bounds)
				var has_endpoint := false
				for endpoint: Vector3 in endpoints:
					has_endpoint = has_endpoint or _point_to_torso_distance(endpoint, candidate.bounds) <= distance_limit
				legal = legal and has_endpoint
				for pending: int in uncovered:
					covers = covers or _point_to_torso_distance(endpoints[pending], candidate.bounds) <= distance_limit
			if not legal or not covers:
				continue
			for candidate: Dictionary in batch:
				for index: int in range(uncovered.size() - 1, -1, -1):
					if _point_to_torso_distance(endpoints[uncovered[index]], candidate.bounds) <= distance_limit:
						uncovered.remove_at(index)
						candidate.covered_limb_count += 1
				torsos.append(candidate)
			accepted = true
			break
		if not accepted:
			return []
	return torsos

func _sample_foot_size() -> Vector3:
	var strength := clampf(inhomogeneity / 100.0, 0.0, 1.0)
	var size := Vector3.ZERO
	for axis: int in range(3):
		var base := maxf(base_foot_size[axis], 0.01)
		var low := maxf(minf(base, minf(minimum_foot_size[axis], maximum_foot_size[axis])), 0.01)
		var high := maxf(base, maxf(minimum_foot_size[axis], maximum_foot_size[axis]))
		size[axis] = lerpf(base, _random.randf_range(low, high), strength)
	return size

func _get_distribution_scale() -> Vector2:
	var length_scale := 1.0 + maxf(narrowty, 0.0) / 100.0
	return Vector2(length_scale, 1.0 / length_scale)

func _sample_initial_feet(torso_size: Vector3, gap: float) -> Array[Dictionary]:
	var count := clampi(feets, 2, 10)
	var sizes: Array[Vector3] = []
	var largest := Vector3.ZERO
	for index: int in range(count):
		var size := _sample_foot_size()
		if index % 2 == 1:
			size = sizes[index - 1].lerp(size, _asymmetry())
		sizes.append(size)
		largest = largest.max(size)
	# Grow the sampling area with the count, dimensions and requested separation.
	var rows := ceilf(sqrt(float(count)))
	var distribution_scale := _get_distribution_scale()
	var spread_x := maxf(torso_size.x, (largest.x + gap) * rows) * distribution_scale.x
	var spread_z := maxf(torso_size.z * 1.5, (largest.z + gap) * rows) * distribution_scale.y
	var minimum_z := (largest.z + gap) * 0.5 + 0.01
	var layouts: Array[Dictionary] = []
	# Do not expand the narrowed width to bypass the mirror separation requirement.
	if spread_z < minimum_z:
		return []
	for pair: int in range(floori(float(count) * 0.5)):
		var accepted := false
		for attempt: int in range(64):
			var position := Vector2(_random.randf_range(-spread_x, spread_x), _random.randf_range(minimum_z, spread_z))
			var first := {"position": position, "final_position": position, "size": sizes[pair * 2]}
			
			# Vector2 stores X/Z: mirror across the local X-Y plane by reversing Z.
			var mirrored := Vector2(position.x, -position.y)
			var second := {"position": mirrored, "final_position": mirrored, "size": sizes[pair * 2 + 1]}
			if _foot_fits(first, layouts, gap) and _foot_fits(second, layouts, gap) and _feet_separated(first, second, gap):
				layouts.append(first)
				layouts.append(second)
				accepted = true
				break
		if not accepted:
			return []
	if count % 2 != 0:
		for attempt: int in range(64):
			var position := Vector2(_random.randf_range(-spread_x, spread_x), _random.randf_range(-spread_z, spread_z) * _asymmetry())
			var extra := {"position": position, "final_position": position, "size": sizes[count - 1]}
			if _foot_fits(extra, layouts, gap):
				layouts.append(extra)
				break
	if layouts.size() != count:
		return []
	for layout: Dictionary in layouts:
		layout.allowed_spread = Vector2(spread_x, spread_z)
	return layouts

func _get_variation_radius(layouts: Array[Dictionary]) -> float:
	var radius := 0.0
	for layout: Dictionary in layouts:
		var size: Vector3 = layout.size
		var position: Vector2 = layout.position
		var half := Vector2(size.x, size.z) * 0.5
		for corner: Vector2 in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
			radius = maxf(radius, (position + corner).length())
	return radius

func _apply_feet_offsets(layouts: Array[Dictionary], radius: float, gap: float) -> bool:
	var strength := clampf(unsymmetrie / 100.0, 0.0, 1.0)
	var placed: Array[Dictionary] = []
	for layout: Dictionary in layouts:
		var accepted := false
		for attempt: int in range(64):
			var initial: Vector2 = layout.position
			var target := _sample_feet_target(initial, radius, strength)
			var fraction := _random.randf_range(0.0, strength)
			layout.final_position = initial.lerp(target, fraction)
			if _foot_fits(layout, placed, gap):
				layout.target_position = target
				layout.travel_fraction = fraction
				placed.append(layout)
				accepted = true
				break
		if not accepted:
			return false
	return true

func _foot_bounds(layout: Dictionary) -> AABB:
	var size: Vector3 = layout.size
	var position: Vector2 = layout.final_position
	return AABB(Vector3(position.x - size.x * 0.5, 0.0, position.y - size.z * 0.5), size)

func _feet_separated(first: Dictionary, second: Dictionary, gap: float) -> bool:
	var a := _foot_bounds(first)
	var b := _foot_bounds(second)
	if a.intersects(b):
		return false
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dz := maxf(maxf(a.position.z - b.end.z, b.position.z - a.end.z), 0.0)
	return Vector2(dx, dz).length() >= gap

## At zero retain the original Unsymmetrie behavior; otherwise constrain final centers too.
func _is_within_distribution(layout: Dictionary) -> bool:
	if narrowty <= 0.0 or not layout.has("allowed_spread"):
		return true
	var position: Vector2 = layout.final_position
	var limit: Vector2 = layout.allowed_spread
	return absf(position.x) <= limit.x and absf(position.y) <= limit.y

func _foot_fits(candidate: Dictionary, placed: Array[Dictionary], gap: float) -> bool:
	if not _is_within_distribution(candidate):
		return false
	for other: Dictionary in placed:
		if not _feet_separated(candidate, other, gap):
			return false
	return true

func _is_layout_valid(torso_bounds: AABB, layouts: Array[Dictionary], gap: float) -> bool:
	for index: int in range(layouts.size()):
		var bounds := _foot_bounds(layouts[index])
		if not _is_within_distribution(layouts[index]):
			return false
		if torso_bounds.position.y <= bounds.end.y or torso_bounds.intersects(bounds):
			return false
		for other_index: int in range(index):
			if not _feet_separated(layouts[index], layouts[other_index], gap):
				return false
	return true

## +X is front; classify only after all final horizontal offsets are known.
func _assign_limb_roles(layouts: Array[Dictionary]) -> int:
	var paired_layout := true
	for index: int in range(0, layouts.size() - 1, 2):
		var position: Vector2 = layouts[index].final_position
		paired_layout = paired_layout and Vector2(position.x, -position.y).is_equal_approx(layouts[index + 1].final_position)
	if _asymmetry() == 0.0 and paired_layout:
		var pairs: Array[int] = []
		for index: int in range(0, layouts.size() - 1, 2):
			pairs.append(index)
		pairs.sort_custom(func(a: int, b: int) -> bool: return layouts[a].final_position.x < layouts[b].final_position.x)
		for index: int in range(layouts.size()):
			layouts[index].role = "ForeLeg"
		var rear: int = pairs.pop_front()
		layouts[rear].role = "Leg"
		layouts[rear + 1].role = "Leg"
		if not pairs.is_empty():
			pairs.pop_back() # Front pair remains ForeLeg.
		var extra_pairs := _random.randi_range(0, pairs.size())
		for index: int in range(extra_pairs):
			var pair: int = pairs[index]
			layouts[pair].role = "Leg"
			layouts[pair + 1].role = "Leg"
		return extra_pairs * 2
	var remaining: Array[int] = []
	for index: int in range(layouts.size()):
		remaining.append(index)
	remaining.sort_custom(func(first: int, second: int) -> bool:
		var a: Vector2 = layouts[first].final_position
		var b: Vector2 = layouts[second].final_position
		# Preserve deterministic ordering for exact mirror pairs with the same X.
		return first < second if a.x == b.x else a.x < b.x
	)
	for rear: int in range(mini(2, remaining.size())):
		var index: int = remaining.pop_front()
		layouts[index].role = "Leg"
	for front: int in range(mini(2, remaining.size())):
		var index: int = remaining.pop_back()
		layouts[index].role = "ForeLeg"
	var extra_count := _sample_extra_leg_count(remaining.size())
	for extra: int in range(extra_count):
		var index: int = remaining.pop_front()
		layouts[index].role = "Leg"
	for index: int in remaining:
		layouts[index].role = "ForeLeg"
	return extra_count

func _sample_extra_leg_count(available: int) -> int:
	if available <= 0:
		return 0
	var even_probability := 1.0 - clampf(unsymmetrie / 100.0, 0.0, 1.0)
	if even_probability >= 1.0 or _random.randf() < even_probability:
		return 2 * _random.randi_range(0, floori(float(available) * 0.5))
	return 1 + 2 * _random.randi_range(0, floori(float(available - 1) * 0.5))

## Initial ordering retains mirror partners at indices 2n / 2n+1, even after classification.
func _assign_limb_lengths(layouts: Array[Dictionary]) -> void:
	var size_strength := clampf(inhomogeneity / 100.0, 0.0, 1.0)
	var asymmetry_strength := clampf(unsymmetrie / 100.0, 0.0, 1.0)
	var pair_length := maxf(base_limb_length, 0.01)
	for index: int in range(layouts.size()):
		if index % 2 == 0:
			pair_length = maxf(base_limb_length, 0.01) * (1.0 + _random.randf_range(-0.5, 0.5) * size_strength)
		layouts[index].limb_length = pair_length * (1.0 + _random.randf_range(-0.5, 0.5) * asymmetry_strength)

## Local points start at the cuboid top center and strictly rise at every segment.
func _create_limb_points(role: String, foot_height: float, total_length: float) -> PackedVector3Array:
	var start := Vector3(0.0, foot_height * 0.5, 0.0)
	var points := PackedVector3Array([start])
	var rear_offset := _sample_dimension(minimum_bend_offset, maximum_bend_offset)
	var first := start + Vector3(-rear_offset, _sample_dimension(minimum_segment_height, maximum_segment_height), 0.0)
	points.append(first)
	if role == "ForeLeg":
		# Forward return is shorter than the initial rearward bend: end remains behind start.
		points.append(first + Vector3(rear_offset * _random.randf_range(0.25, 0.75), _sample_dimension(minimum_segment_height, maximum_segment_height), 0.0))
	else:
		var front_offset := _sample_dimension(minimum_bend_offset, maximum_bend_offset)
		var second := first + Vector3(front_offset, _sample_dimension(minimum_segment_height, maximum_segment_height), 0.0)
		points.append(second)
		# Third segment bends back less than the second moved forward.
		points.append(second + Vector3(-front_offset * _random.randf_range(0.25, 0.75), _sample_dimension(minimum_segment_height, maximum_segment_height), 0.0))
	# Uniformly scale the shape about its start, keeping bends and start position intact.
	var raw_length := 0.0
	for index: int in range(1, points.size()):
		raw_length += points[index - 1].distance_to(points[index])
	var length_scale := total_length / raw_length
	for index: int in range(1, points.size()):
		points[index] = start + (points[index] - start) * length_scale
	return points

