@tool
extends Node3D

signal framework_generated(plan: Dictionary)

const PART_SCENE_RULE = preload("res://Scripts/Creatures/Generators/GeneratedPartSceneRule.gd")
const MANUAL_LAYOUT = preload("res://Scripts/Creatures/Generators/CreatureManualLayout.gd")
@export_group("Manual Layout")
## Captured layout overrides procedural counts/curves; Overall Scale still applies.
@export var use_manual_layout: bool = false
@export var manual_layout: MANUAL_LAYOUT
@export_tool_button("清除手动布局", "Remove") var clear_manual_layout_button: Callable:
	get: return Callable(self, &"clear_manual_layout")

func clear_manual_layout() -> void:
	manual_layout = null
	use_manual_layout = false
	if Engine.is_editor_hint() and is_inside_tree(): EditorInterface.mark_scene_as_unsaved()

func _clear_generated_preview() -> void:
	for child: Node in get_children():
		if child.name in [&"Feets", &"LimbNetwork", &"ManualLayout"] or child.has_meta(&"generated_torso") or child.has_meta(&"generated_network_torso") or child.has_meta(&"generated_neck_line") or child.has_meta(&"generated_wings"):
			remove_child(child)
			child.queue_free()

func _generate_manual_framework() -> bool:
	if manual_layout == null or manual_layout.blueprint.get("parts", []).is_empty():
		push_warning("[creature_generator] Manual layout is enabled but empty; previous frame retained.")
		return false
	_clear_generated_preview()
	var preview := Node3D.new()
	preview.name = "ManualLayout"
	add_child(preview)
	var scene_owner: Node = self
	if Engine.is_editor_hint():
		var edited := get_tree().edited_scene_root
		if edited != null and (edited == self or edited.is_ancestor_of(self)): scene_owner = edited
	preview.owner = scene_owner
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = wireframe_color
	var blueprint := manual_layout.scaled_blueprint(overall_scale)
	for layout: Dictionary in blueprint.parts:
		var block := MeshInstance3D.new()
		block.name = str(layout.name)
		block.transform = layout.transform
		block.mesh = _create_wireframe(layout.size)
		block.material_override = material
		preview.add_child(block)
		block.owner = scene_owner
		var label := Label3D.new()
		label.text = str(layout.name)
		label.position.y = layout.size.y * 0.5 + 0.3
		label.font_size = label_font_size
		label.modulate = label_color
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		block.add_child(label)
		label.owner = scene_owner
	framework_generated.emit({"manual_blueprint": blueprint})
	if Engine.is_editor_hint(): EditorInterface.mark_scene_as_unsaved()
	return true

@export_group("Physical Part Scenes")
## Persistent rules; exact Part Name wins over Part Type. First match wins within each level.
## Missing types use the character's standard TestCreature_Part scene.
@export var part_scene_rules: Array[PART_SCENE_RULE] = []

func get_part_scene_rule(part_type: String, part_name: String, part_key: String = "") -> PART_SCENE_RULE:
	for rule: PART_SCENE_RULE in part_scene_rules:
		if rule != null and not rule.part_key.is_empty() and rule.part_key == part_key: return rule
	for rule: PART_SCENE_RULE in part_scene_rules:
		if rule != null and rule.part_key.is_empty() and not rule.part_name.is_empty() and rule.matches(part_type, part_name): return rule
	for rule: PART_SCENE_RULE in part_scene_rules:
		if rule != null and rule.part_key.is_empty() and rule.part_name.is_empty() and rule.matches(part_type, part_name): return rule
	return null

## Clone mutable settings without duplicating immutable scene assets.
static func _copy_default_value(value: Variant) -> Variant:
	if value is PackedScene: return value
	if value is PART_SCENE_RULE:
		var copy := PART_SCENE_RULE.new()
		for key: String in ["part_name", "part_key", "part_type", "part_scene", "size_mode", "size_multiplier", "use_joint_markers", "align_connectors_to_frame"]:
			copy.set(key, value.get(key))
		return copy
	if value is Resource: return value.duplicate(true)
	if value is Array:
		var copy: Array = value.duplicate()
		for index: int in copy.size(): copy[index] = _copy_default_value(value[index])
		return copy
	if value is Dictionary:
		var copy: Dictionary = value.duplicate()
		for key: Variant in copy: copy[key] = _copy_default_value(value[key])
		return copy
	return value

@export_group("Overall Size")
## Uniform size multiplier around the generator origin, applied after layout validation.
## Generate again to update the frame and the physical character. Does not scale the root Node3D.
@export_range(0.1, 10.0, 0.05, "or_greater") var overall_scale: float = 4.0
## Shared local Z size for Torso, SubTorso, feet, Limb blocks, Neck and Head.
## Applied before Overall Scale; overrides Z in all per-part size settings and the Torso curve.
## Physical Custom paper models use Part Width * Overall Scale as final depth, without Size Multiplier.
@export_range(0.01, 100.0, 0.01, "or_greater") var part_width: float = 0.2

@export_group("Framework Display")
@export var wireframe_color: Color = Color(0.2, 0.9, 1, 1)
@export var label_color: Color = Color(1, 1, 1, 1)
@export_range(1, 256, 1, "or_greater") var label_font_size: int = 32:
	set(value):
		label_font_size = maxi(value, 1)
		_update_label_sizes(self)
@export_tool_button("生成随机框架", "Node3D") var generate_torso_button: Callable = generate_torso
@export_tool_button("将当前参数保存为当前物种默认值", "Save") var save_defaults_button: Callable = save_current_parameters_as_defaults

@export_group("Feet Generation")
## Exact counts; Leg has three limb segments and ForeLeg has two. Odd counts include a center foot.
@export_range(0.0, 100.0, 0.1) var unsymmetrie: float = 0.0
@export_range(0.0, 100.0, 0.1) var inhomogeneity: float = 0.0
## Z is overridden by Part Width.
@export var base_foot_size: Vector3 = Vector3(0.6, 0.3, 0.2)
## Z is overridden by Part Width.
@export var minimum_foot_size: Vector3 = Vector3(0.6, 0.3, 0.2)
@export var maximum_foot_size: Vector3 = Vector3(0.6, 0.3, 0.2)
## Minimum horizontal shell clearance. Too many feet for the body length makes the layout invalid.
@export_range(0.0, 100.0, 0.01, "or_greater") var minimum_feet_distance: float = 0.2

@export_group("Torso Generation")
## Exact central Torso count; independent SubTorsos are generated for the feet.
@export_range(1, 32, 1) var torso_count: int = 6
## Full X extent of the torso chain, before Overall Scale; excludes head/neck/feet.
@export_range(0.1, 100.0, 0.05, "or_greater") var body_length: float = 2.0
## Adjacent X overlap / the smaller block X length. Central Torso centers stay on Z=0.
@export_range(0.0, 95.0, 0.1) var torso_overlap_percent: float = 20.0
## Curves are sampled from the rearmost Torso (0) to the foremost Torso (1).
## Values are signed height offsets in units of the sampled reference height.
## Upper - Lower sets height; their midpoint sets the body's vertical position.
@export var torso_upper_curve: Curve = _make_torso_curve([[Vector2(0, 0.19101131), 0.0, 0.0, 0, 0], [Vector2(0.44957983, 0.77528095), 0.0, 0.0, 0, 0], [Vector2(1, 0.3370787), 0.0, 0.0, 0, 0]], 0.0, 1.0)
@export var torso_lower_curve: Curve = _make_torso_curve([[Vector2(0, -0.32458997), 0.0, 0.0, 0, 0], [Vector2(0.4873949, -0.9101124), 0.0, 0.0, 0, 0], [Vector2(0.9397759, -0.60000014), 0.0, 0.0, 0, 0], [Vector2(1, -0.46229506), 0.0, 0.0, 0, 0]], -3.0, 3.0)

## Moves each Torso vertically without changing its contour-defined size; reference-height units.
@export var torso_height_offset_curve: Curve = _make_torso_curve([[Vector2(0, 0), 0.0, 0.0, 0, 0], [Vector2(1, 0), 0.0, 0.0, 0, 0]], -3.0, 3.0)

@export_group("SubTorso Generation")
## One support per foot, touching the parent Torso. Z is overridden by Part Width.
## Feet retain the support X/Z; paired supports touch the sides; center supports start below the body and can slide upward.
@export var sub_torso_size: Vector3 = Vector3(0.5, 0.4, 0.3)
## Shared forward (+X) / backward (-X) offset before Overall Scale.
## Selects the nearest Torso after shifting, then clamps to its X span to keep contact.
## Corresponding feet and limb attachments follow the shifted support.
@export_range(-100.0, 100.0, 0.01, "or_less", "or_greater") var sub_torso_x_offset: float = 0.5
## Rear-to-front sample at the parent Torso: 0 aligns with its lower contour, 1 with its upper contour.
## Values are clamped to 0..1; empty curves keep the lower attachment. Limb endpoints follow.
@export var sub_torso_height_curve: Curve = _make_torso_curve([[Vector2(0, 0), 0.0, 0.0, 0, 0], [Vector2(1, 0), 0.0, 0.0, 0, 0]], 0.0, 1.0)

@export_group("Torso Reference Height")
## Sampled once as the vertical unit used by both contour curves.
@export_range(0.01, 100.0, 0.01, "or_greater") var torso_minimum_height: float = 0.5
@export_range(0.01, 100.0, 0.01, "or_greater") var torso_maximum_height: float = 0.7
## Used by the physical character to identify adjacent body blocks.
@export_range(0.0, 100.0, 0.01, "or_greater") var torso_connection_distance: float = 0.3

@export_group("Limb Lines")
## Nominal reach controls torso clearance and bend size; endpoints are fitted to the body shell.
@export_range(0.01, 100.0, 0.01, "or_greater") var base_limb_length: float = 0.6
@export_range(0.01, 10.0, 0.01, "or_greater") var minimum_segment_height: float = 0.4
@export_range(0.01, 10.0, 0.01, "or_greater") var maximum_segment_height: float = 0.8
@export_range(0.01, 10.0, 0.01, "or_greater") var minimum_bend_offset: float = 0.5
@export_range(0.01, 10.0, 0.01, "or_greater") var maximum_bend_offset: float = 0.5

@export_group("Limb Block Generation")
## Z is overridden by Part Width.
@export var limb_minimum_size: Vector3 = Vector3(0.3, 0.3, 0.15)
@export var limb_maximum_size: Vector3 = Vector3(0.3, 0.3, 0.15)
@export var limb_y_matches_segment: bool = true

@export_group("Limb Network Preview")
## The network remains a preview; it no longer decides body count or body placement.
@export_range(0.0, 100.0, 0.01, "or_greater") var limb_endpoint_merge_distance: float = 0.2
@export_range(0, 32, 1) var network_extra_endpoint_count: int = 4
@export_range(0.0, 100.0, 0.01, "or_greater") var network_extra_endpoint_padding: float = 0.5
@export_range(0.0, 1.0, 0.01) var network_center_bias: float = 0.65
@export_range(0, 32, 1) var network_core_extra_connections: int = 3

@export_group("Neck Generation")
@export_range(0, 256, 1) var neck_number: int = 1
const max_neck_start_surface_distance: float = 0.0
@export_range(0.01, 100.0, 0.01, "or_greater") var neck_minimum_length: float = 0.2
@export_range(0.01, 100.0, 0.01, "or_greater") var neck_maximum_length: float = 0.4
## Zero attaches the Head directly to the front body surface, without any Neck block.
@export_range(0, 10, 1) var neck_segment_count: int = 1
@export_range(0.0, 85.0, 0.1) var neck_maximum_angle: float = 60.0
@export_range(0.01, 10.0, 0.01, "or_greater") var neck_block_thickness: float = 0.4
## Maximum diameter of the overlap in the XY section; shared Z width does not enlarge this limit.
@export_range(0.0, 100.0, 0.01, "or_greater") var max_neck_overlap_diameter: float = 0.5
@export_group("Head Generation")
## Z is overridden by Part Width.
@export var head_minimum_size: Vector3 = Vector3(0.3, 0.3, 0.3)
@export var head_maximum_size: Vector3 = Vector3(0.7, 0.7, 0.7)

const BOX_GEOMETRY = preload("res://Scripts/Creatures/CreatureBoxGeometry.gd")
const MAX_GENERATION_ATTEMPTS: int = 128
var _random := RandomNumberGenerator.new()

func _update_label_sizes(node: Node) -> void:
	if node is Label3D:
		(node as Label3D).font_size = label_font_size
	for child: Node in node.get_children():
		_update_label_sizes(child)

func _ready() -> void:
	_random.randomize()
	_update_label_sizes(self)
	if Engine.is_editor_hint():
		var filesystem := EditorInterface.get_resource_filesystem()
		if not filesystem.filesystem_changed.is_connected(_on_defaults_filesystem_changed):
			filesystem.filesystem_changed.connect(_on_defaults_filesystem_changed)
		if not filesystem.resources_reload.is_connected(_on_defaults_resources_changed):
			filesystem.resources_reload.connect(_on_defaults_resources_changed)
		if not filesystem.resources_reimported.is_connected(_on_defaults_resources_changed):
			filesystem.resources_reimported.connect(_on_defaults_resources_changed)

const DEFAULTS_DATA = preload("res://Scripts/Creatures/Generators/CreatureGeneratorDefaults.gd")

# Keep a strong reference: ResourceLoader's path cache alone does not retain this snapshot.
var _defaults_preset: DEFAULTS_DATA
var _defaults_cached_path: String = ""
var _defaults_loaded: bool = false
var _defaults_modified_time: int = 0

func _get_default_preset(force_reload: bool = false) -> DEFAULTS_DATA:
	var path := _get_defaults_path()
	if _defaults_loaded and path == _defaults_cached_path and not force_reload:
		return _defaults_preset
	if _defaults_preset != null and _defaults_preset.changed.is_connected(_on_default_preset_changed):
		_defaults_preset.changed.disconnect(_on_default_preset_changed)
	_defaults_preset = null
	_defaults_cached_path = path
	_defaults_loaded = true
	_defaults_modified_time = 0
	if not path.is_empty() and FileAccess.file_exists(path):
		var mode := ResourceLoader.CACHE_MODE_REPLACE if force_reload else ResourceLoader.CACHE_MODE_REUSE
		_defaults_preset = ResourceLoader.load(path, "", mode) as DEFAULTS_DATA
		_defaults_modified_time = FileAccess.get_modified_time(path)
		if _defaults_preset != null:
			_defaults_preset.changed.connect(_on_default_preset_changed)
	return _defaults_preset

func _on_default_preset_changed() -> void:
	# Refresh revert controls, never overwrite existing scene/instance settings.
	notify_property_list_changed()

func _on_defaults_filesystem_changed() -> void:
	if not _defaults_loaded or _defaults_cached_path.is_empty(): return
	var modified := FileAccess.get_modified_time(_defaults_cached_path) if FileAccess.file_exists(_defaults_cached_path) else 0
	if modified == _defaults_modified_time: return
	_get_default_preset(true)
	notify_property_list_changed()

func _on_defaults_resources_changed(paths: PackedStringArray) -> void:
	if _defaults_cached_path.is_empty() or _defaults_cached_path not in paths: return
	_get_default_preset(true)
	notify_property_list_changed()

func _get_defaults_path() -> String:
	return ""

func _property_can_revert(property: StringName) -> bool:
	var preset := _get_default_preset()
	return preset != null and preset.parameters.has(property)

func _property_get_revert(property: StringName) -> Variant:
	var preset := _get_default_preset()
	if preset == null: return null
	var value: Variant = preset.parameters.get(property)
	return _copy_default_value(value)

func _apply_default_preset() -> void:
	var preset := _get_default_preset()
	if preset == null: return
	for property: Dictionary in get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_EDITOR) == 0: continue
		if not preset.parameters.has(property.name): continue
		var value: Variant = preset.parameters[property.name]
		set(property.name, _copy_default_value(value))

func _capture_default_parameters() -> Dictionary:
	var parameters: Dictionary = {}
	for property: Dictionary in get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_EDITOR) == 0 or (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
		var value: Variant = get(property.name)
		if value is Callable or property.name in [&"manual_layout", &"use_manual_layout"]: continue
		parameters[property.name] = _copy_default_value(value)
	return parameters

func _save_default_preset(path: String) -> bool:
	if path.is_empty(): return false
	var preset := DEFAULTS_DATA.new()
	preset.parameters = _capture_default_parameters()
	var error := ResourceSaver.save(preset,path)
	if error != OK:
		push_error("[creature_generator] Cannot save defaults: %s (%s)" % [path,error_string(error)])
		return false
	# Refresh cached defaults for subsequent instances without changing their live values.
	var cached := load(path) as DEFAULTS_DATA
	if cached != null: cached.parameters = _copy_default_value(preset.parameters)
	if path == _get_defaults_path():
		_get_default_preset()
		_defaults_modified_time = FileAccess.get_modified_time(path)
	notify_property_list_changed()
	return true

func save_current_parameters_as_defaults() -> bool:
	if not Engine.is_editor_hint():
		push_warning("[creature_generator] Saving defaults is editor-only.")
		return false
	var path := _get_defaults_path()
	if not _save_default_preset(path): return false
	EditorInterface.get_resource_filesystem().call_deferred(&"scan")
	print("[creature_generator] Saved independent generator defaults: ",path)
	return true

## Regenerate the Torso and Feet without accumulating previous frames.
func generate_torso() -> bool:
	if not is_finite(overall_scale) or overall_scale < 0.1:
		push_warning("[creature_generator] Overall Scale must be finite and at least 0.1; previous frame retained.")
		return false
	if not is_inside_tree():
		return false
	if use_manual_layout: return _generate_manual_framework()
	if has_node("ManualLayout"): _clear_generated_preview()
	var plan := _create_valid_plan()
	if plan.is_empty():
		push_warning("[creature_generator] Generation failed: no legal layout; previous frame retained. Check upper/lower contour order and connectivity, body length, foot counts/clearance and Neck/Head overlap constraints.")
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
	_generate_species_preview(plan, scene_owner, material)
	# Plan coordinates remain in base units; consumers apply this metadata exactly once.
	plan[&"overall_scale"] = overall_scale
	_apply_framework_scale(overall_scale)
	if Engine.is_editor_hint():
		EditorInterface.mark_scene_as_unsaved()
	print("[creature_generator] torsos=%d covered_parts=%d attempts=%d valid=true" % [plan.network_torsos.size(), plan.layouts.size(), plan.attempts])
	print("[creature_generator] overall_scale=%.3f" % overall_scale)
	framework_generated.emit(plan)
	return true

func _apply_framework_scale(multiplier: float) -> void:
	for child: Node in get_children():
		if not child is Node3D: continue
		if child.name not in [&"Feets", &"LimbNetwork"] and not child.has_meta(&"generated_torso") and not child.has_meta(&"generated_network_torso") and not child.has_meta(&"generated_neck_line") and not child.has_meta(&"generated_wings"):
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
			var origin := _sample_neck_origin([torsos[-1]])
			if single:
				origin.z *= _asymmetry()
			var total_length := 0.0 if neck_segment_count == 0 else _sample_dimension(neck_minimum_length, neck_maximum_length)
			var head_size := _sample_size(head_minimum_size, head_maximum_size)
			head_size.z = part_width
			var batch: Array[Dictionary] = [{"points": _create_neck_points(origin, total_length), "length": total_length, "head_size": head_size}]
			if not single:
				var partner_origin := _mirror_point(origin).lerp(_sample_neck_origin([torsos[-1]]), _asymmetry())
				var partner_length := 0.0 if neck_segment_count == 0 else lerpf(total_length, _sample_dimension(neck_minimum_length, neck_maximum_length), _asymmetry())
				batch.append({"points": _create_neck_points(partner_origin, partner_length), "length": partner_length, "head_size": Vector3(lerpf(head_size.x, _sample_dimension(head_minimum_size.x, head_maximum_size.x), _asymmetry()), lerpf(head_size.y, _sample_dimension(head_minimum_size.y, head_maximum_size.y), _asymmetry()), part_width)})
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
						if _neck_overlap_diameter(next, existing) > maxf(max_neck_overlap_diameter, 0.0) + 0.00001:
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

func _neck_overlap_diameter(first: Dictionary, second: Dictionary) -> float:
	# All generated Neck/Head/body boxes rotate only in XY. Their intersection is
	# an XY polygon extruded along Z, so remove that extrusion from its diameter.
	var diameter := BOX_GEOMETRY.overlap_diameter(first, second)
	var z_span := maxf(0.0, minf(first.aabb.end.z, second.aabb.end.z) - maxf(first.aabb.position.z, second.aabb.position.z))
	return sqrt(maxf(diameter * diameter - z_span * z_span, 0.0))

func _neck_blocks(points: PackedVector3Array, head_size: Vector3) -> Array[Dictionary]:
	var blocks: Array[Dictionary] = []
	var thickness := maxf(neck_block_thickness, 0.01)
	head_size.z = part_width
	for index: int in range(points.size() - 1):
		var direction := points[index + 1] - points[index]
		blocks.append({"name": "Neck" if index == 0 else "Neck_%d" % (index + 1), "size": Vector3(thickness, direction.length(), part_width), "position": (points[index] + points[index + 1]) * 0.5, "basis": Basis(Quaternion(Vector3.UP, direction.normalized()))})
	blocks.append({"name": "Head", "size": head_size, "position": points[-1] + Vector3(head_size.x * 0.5, 0, 0), "basis": Basis.IDENTITY})
	return blocks

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
	if not vertices.is_empty():
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
	for key: StringName in [&"extra_leg_count", &"variation_radius", &"distribution_scale", &"allowed_spread"]:
		if frames.has_meta(key): frames.remove_meta(key)
	var layouts: Array[Dictionary] = plan.layouts
	var old_range := frames.get_node_or_null("VariationRange")
	if old_range != null:
		frames.remove_child(old_range)
		old_range.queue_free()
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
	print("[creature_generator] rear_legs=%d forelegs=%d torso_count=%d body_length=%.3f overlap_percent=%.2f" % [name_counts.Leg, name_counts.ForeLeg, torso_count, body_length, torso_overlap_percent])

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

func _sample_foot_size() -> Vector3:
	var strength := clampf(inhomogeneity / 100.0, 0.0, 1.0)
	var size := Vector3.ZERO
	for axis: int in range(3):
		var base := maxf(base_foot_size[axis], 0.01)
		var low := maxf(minf(base, minf(minimum_foot_size[axis], maximum_foot_size[axis])), 0.01)
		var high := maxf(base, maxf(minimum_foot_size[axis], maximum_foot_size[axis]))
		size[axis] = lerpf(base, _random.randf_range(low, high), strength)
	size.z = part_width
	return size

func _create_limb_points(role: String, foot_height: float, total_length: float) -> PackedVector3Array:
	var start := Vector3(0.0, foot_height * 0.5, 0.0)
	var points := PackedVector3Array([start])
	var rear_offset := _sample_dimension(minimum_bend_offset, maximum_bend_offset)
	var first := start + Vector3(-rear_offset, _sample_dimension(minimum_segment_height, maximum_segment_height), 0.0)
	points.append(first)
	if role == "ForeLeg":
		# Forward return is shorter than the initial rearward bend: end remains behind start.
		points.append(first + Vector3(rear_offset * _sample_limb_return_ratio(), _sample_dimension(minimum_segment_height, maximum_segment_height), 0.0))
	else:
		var front_offset := _sample_dimension(minimum_bend_offset, maximum_bend_offset)
		var second := first + Vector3(front_offset, _sample_dimension(minimum_segment_height, maximum_segment_height), 0.0)
		points.append(second)
		# Third segment bends back less than the second moved forward.
		points.append(second + Vector3(-front_offset * _sample_limb_return_ratio(), _sample_dimension(minimum_segment_height, maximum_segment_height), 0.0))
	# Uniformly scale the shape about its start, keeping bends and start position intact.
	var raw_length := 0.0
	for index: int in range(1, points.size()):
		raw_length += points[index - 1].distance_to(points[index])
	var length_scale := total_length / raw_length
	for index: int in range(1, points.size()):
		points[index] = start + (points[index] - start) * length_scale
	return points

func _sample_limb_return_ratio() -> float:
	return _random.randf_range(0.25, 0.75)

func _sample_limb_length() -> float:
	return base_limb_length * (1.0 + _random.randf_range(-0.25, 0.25) * clampf(inhomogeneity / 100.0, 0.0, 1.0))

func _sample_neck_origin(torsos: Array[Dictionary]) -> Vector3:
	var torso: Dictionary = torsos[-1]
	var half: Vector3 = torso.size * 0.5
	# Every root starts on the foremost Torso front face; the first segment leaves horizontally.
	return torso.position + Vector3(half.x, _random.randf_range(-half.y * 0.5, half.y * 0.5), _random.randf_range(-half.z, half.z))

func _create_neck_points(origin: Vector3, total_length: float) -> PackedVector3Array:
	var count := clampi(neck_segment_count, 0, 10)
	var points := PackedVector3Array([origin])
	var weights: Array[float] = []
	var weight_sum := 0.0
	for index: int in range(count):
		var weight := lerpf(1.0, 0.35, float(index) / float(maxi(count - 1, 1)))
		weights.append(weight)
		weight_sum += weight
	for index: int in range(count):
		var angle := 0.0
		if index > 0 and index < count - 1:
			angle = deg_to_rad(clampf(neck_maximum_angle, 0.0, 85.0))
		points.append(points[-1] + Vector3(cos(angle), sin(angle), 0.0) * total_length * weights[index] / weight_sum)
	return points

func _create_valid_plan() -> Dictionary:
	# Reject invalid scripted values rather than silently changing requested counts.
	if not _validate_species_settings() or torso_count < 1 or torso_count > 32 or neck_segment_count < 0 or neck_segment_count > 10:
		return {}
	for property: Dictionary in get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_EDITOR) == 0: continue
		var value: Variant = get(property.name)
		if value is float and not is_finite(value): return {}
		if value is Vector3 and not value.is_finite(): return {}
	if part_width < 0.01 or body_length < 0.1 or base_limb_length <= 0.0 or torso_overlap_percent < 0.0 or torso_overlap_percent > 95.0: return {}
	for attempt: int in range(MAX_GENERATION_ATTEMPTS):
		var height := _sample_dimension(torso_minimum_height, torso_maximum_height)
		var width := part_width
		var layouts: Array[Dictionary] = []
		_append_species_feet(layouts, width)
		var max_foot_height := 0.0
		for layout: Dictionary in layouts: max_foot_height = maxf(max_foot_height, layout.size.y)
		var bottom := max_foot_height + maxf(base_limb_length * 0.65, 0.1) + maxf(sub_torso_size.y, 0.01)
		var torsos := _plan_body(height, width, bottom)
		if torsos.is_empty(): return {}
		var subtorsos := _plan_subtorsos(layouts, torsos, bottom)
		if subtorsos.size() != layouts.size(): return {}
		if not _feet_clear(layouts): continue
		_fit_limbs(layouts, subtorsos)
		_assign_limb_block_sizes(layouts)
		var necks := _plan_necks(torsos, subtorsos)
		if necks.size() != neck_number: continue
		var plan := {"torsos": subtorsos, "network_torsos": torsos, "separate_subtorsos": true, "layouts": layouts,
			"limb_network": _build_limb_network(layouts), "necks": necks,
			"attempts": attempt + 1, "extra_leg_count": 0, "radius": body_length * 0.5}
		var completed := _complete_species_plan(plan)
		if not completed.is_empty(): return completed
	return {}

static func _make_torso_curve(points: Array = [[Vector2(0, 1), 0.0, 0.0, 0, 0], [Vector2(1, 1), 0.0, 0.0, 0, 0]], lower: float = 0.05, upper: float = 3.0) -> Curve:
	var curve := Curve.new()
	curve.min_value = lower
	curve.max_value = upper
	for point: Array in points:
		curve.add_point(point[0], point[1], point[2], point[3], point[4])
	return curve

func _sample_contour(curve: Curve, progress: float, fallback: float) -> float:
	return curve.sample(progress) if curve != null and curve.point_count > 0 else fallback

func _plan_body(height: float, width: float, bottom: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var lower_values: Array[float] = []
	var upper_values: Array[float] = []
	var lowest := INF
	for index: int in range(torso_count):
		var progress := float(index) / float(torso_count - 1) if torso_count > 1 else 0.5
		var upper := _sample_contour(torso_upper_curve, progress, 1.0)
		var lower := _sample_contour(torso_lower_curve, progress, 0.0)
		var offset := _sample_contour(torso_height_offset_curve, progress, 0.0)
		if not is_finite(offset) or not is_finite(upper) or not is_finite(lower) or (upper - lower) * height < 0.01:
			push_warning("[creature_generator] Torso contours invalid at %.3f: upper=%.3f lower=%.3f; require upper above lower and height >= 0.01." % [progress, upper, lower])
			return []
		upper_values.append(upper + offset)
		lower_values.append(lower + offset)
		lowest = minf(lowest, lower + offset)
	# Only the contours determine Y. Equal X spans retain the requested body length and overlap.
	var overlap := torso_overlap_percent / 100.0
	var length := body_length / (1.0 + float(torso_count - 1) * (1.0 - overlap))
	var spacing := length * (1.0 - overlap)
	# Raise the entire frame together if a lower contour dips below the leg-clearance baseline.
	var baseline := bottom - minf(lowest, 0.0) * height
	for index: int in range(torso_count):
		var low := baseline + lower_values[index] * height
		var high := baseline + upper_values[index] * height
		var x := -body_length * 0.5 + length * 0.5 + float(index) * spacing
		var size := Vector3(length, high - low, width)
		var position := Vector3(x, (high + low) * 0.5, 0.0)
		result.append({"size": size, "position": position, "source_segment": PackedVector3Array(),
			"sub_torso": false, "upper_height": high, "lower_height": low,
			"contour_progress": float(index) / float(torso_count - 1) if torso_count > 1 else 0.5})
		if index > 0:
			var previous: Dictionary = result[index - 1]
			var first := BOX_GEOMETRY.box(previous.size, Transform3D(Basis.IDENTITY, previous.position))
			var second := BOX_GEOMETRY.box(size, Transform3D(Basis.IDENTITY, position))
			if not BOX_GEOMETRY.connected(first, second, maxf(torso_connection_distance, 0.0)):
				push_warning("[creature_generator] Neighboring contour blocks %d/%d are disconnected; soften the contour or increase Torso Connection Distance." % [index, index + 1])
				return []
	return result

func _plan_subtorsos(layouts: Array[Dictionary], torsos: Array[Dictionary], _bottom: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var size := sub_torso_size.max(Vector3.ONE * 0.01)
	size.z = part_width
	for index: int in range(layouts.size()):
		var foot: Dictionary = layouts[index]
		var horizontal: Vector2 = foot.final_position
		horizontal.x += sub_torso_x_offset
		var parent_index := 0
		var distance := INF
		for torso: int in range(torsos.size()):
			var next: float = absf(horizontal.x - torsos[torso].position.x)
			if next < distance:
				distance = next
				parent_index = torso
		var parent: Dictionary = torsos[parent_index]
		var is_center: bool = is_zero_approx(foot.position.y)
		var side := signf(foot.position.y)
		# Equal widths imply side-touching centers are exactly one Part Width apart.
		var x := clampf(horizontal.x, parent.position.x - parent.size.x * 0.5, parent.position.x + parent.size.x * 0.5)
		var z := 0.0 if is_center else side * part_width
		var progress: float = parent.contour_progress
		var sampled := _sample_contour(sub_torso_height_curve, progress, 0.0)
		if not is_finite(sampled):
			push_warning("[creature_generator] SubTorso height curve must contain finite values.")
			return []
		var ratio := clampf(sampled, 0.0, 1.0)
		var lower: float = parent.position.y - parent.size.y * 0.5
		var upper: float = parent.position.y + parent.size.y * 0.5
		# Account for support thickness: side supports align bottom/top faces to the contours.
		# A center support retains its bottom-mounted connection at zero and slides upward with the curve.
		var lower_center := lower + (size.y * -0.5 if is_center else size.y * 0.5)
		var y := lerpf(lower_center, upper - size.y * 0.5, ratio)
		foot.final_position = Vector2(x, z)
		foot.target_position = foot.final_position
		foot.sub_torso_index = index
		result.append({"position": Vector3(x, y, z),
			"size": size, "sub_torso": true, "parent_torso_index": parent_index,
			"source_foot_index": index, "covered_limb_count": 1})
	return result

func _append_foot_group(layouts: Array[Dictionary], count: int, role: String, side: float, body_width: float) -> void:
	var rows := ceili(float(count) / 2.0)
	for row: int in range(rows):
		var x := side * body_length * 0.25 if rows == 1 else lerpf(body_length * 0.08, body_length * 0.42, float(row) / float(rows - 1)) * side
		var paired := row * 2 + 1 < count
		var pair_size := _sample_foot_size()
		var first_index := layouts.size()
		for member: int in range(2 if paired else 1):
			var size := pair_size.lerp(_sample_foot_size(), _asymmetry()) if member == 1 else pair_size
			var z := body_width * 0.5 + size.z * 0.5 + maxf(minimum_feet_distance, 0.0) + 0.1
			z *= (1.0 if member == 0 else -1.0) if paired else 0.0
			var initial := Vector2(x, z)
			var offset := Vector2(_random.randf_range(-1.0, 1.0), _random.randf_range(-1.0, 1.0)) * _asymmetry() * minf(body_length * 0.08, base_limb_length * 0.25)
			layouts.append({"role": role, "position": initial, "target_position": initial + offset,
				"final_position": initial + offset, "travel_fraction": 1.0, "size": size,
				"partner_index": first_index if member == 1 else -1})

func _feet_clear(layouts: Array[Dictionary]) -> bool:
	for first: int in range(layouts.size()):
		for second: int in range(first):
			var a: Vector2 = layouts[first].final_position
			var b: Vector2 = layouts[second].final_position
			var sa: Vector3 = layouts[first].size
			var sb: Vector3 = layouts[second].size
			var dx := maxf(absf(a.x - b.x) - (sa.x + sb.x) * 0.5, 0.0)
			var dz := maxf(absf(a.y - b.y) - (sa.z + sb.z) * 0.5, 0.0)
			if Vector2(dx, dz).length() < maxf(minimum_feet_distance, 0.0) - 0.00001 or (dx == 0.0 and dz == 0.0): return false
	return true

func _fit_limbs(layouts: Array[Dictionary], torsos: Array[Dictionary]) -> void:
	for index: int in range(layouts.size()):
		var layout: Dictionary = layouts[index]
		var partner: int = layout.get("partner_index", -1)
		var sampled_length := _sample_limb_length()
		var points := _create_limb_points(layout.role, layout.size.y, sampled_length)
		if partner >= 0 and is_zero_approx(_asymmetry()):
			points = layouts[partner].limb_points.duplicate()
			for point: int in range(points.size()): points[point].z = -points[point].z
		else:
			var horizontal: Vector2 = layout.final_position
			var origin := Vector3(horizontal.x, layout.size.y * 0.5, horizontal.y)
			var tip := origin + points[-1]
			var nearest := Vector3.ZERO
			var distance := INF
			var targets: Array[Dictionary] = []
			if layout.has("sub_torso_index"):
				targets.append(torsos[layout.sub_torso_index])
			else:
				targets = torsos
			for torso: Dictionary in targets:
				var candidate: Vector3 = tip.clamp(torso.position - torso.size * 0.5, torso.position + torso.size * 0.5)
				# Attach to the lower shell even if the sampled tip starts inside the body.
				candidate.y = torso.position.y - torso.size.y * 0.5
				var next := tip.distance_squared_to(candidate)
				if next < distance:
					nearest = candidate
					distance = next
			var correction := nearest - origin - points[-1]
			for point: int in range(1, points.size()): points[point] += correction * float(point) / float(points.size() - 1)
		layout.limb_points = points
		var actual_length := 0.0
		for point: int in range(1, points.size()): actual_length += points[point].distance_to(points[point - 1])
		layout.limb_length = actual_length

func _assign_limb_block_sizes(layouts: Array[Dictionary]) -> void:
	for layout: Dictionary in layouts:
		var sizes: Array[Vector3] = []
		var points: PackedVector3Array = layout.limb_points
		for segment: int in range(points.size() - 1):
			var size := _sample_size(limb_minimum_size, limb_maximum_size)
			var partner: int = layout.get("partner_index", -1)
			if partner >= 0:
				size = layouts[partner].limb_block_sizes[segment].lerp(size, _asymmetry())
			size.z = part_width
			if limb_y_matches_segment: size.y = points[segment].distance_to(points[segment + 1])
			sizes.append(size)
		layout.limb_block_sizes = sizes

## Species hooks keep scene consumers independent of the concrete generator.
func generate_framework() -> bool:
	return generate_torso()

func _validate_species_settings() -> bool:
	return false

func _append_species_feet(_layouts: Array[Dictionary], _width: float) -> void:
	pass

func _complete_species_plan(plan: Dictionary) -> Dictionary:
	return plan

func _generate_species_preview(_plan: Dictionary, _scene_owner: Node, _material: Material) -> void:
	pass
