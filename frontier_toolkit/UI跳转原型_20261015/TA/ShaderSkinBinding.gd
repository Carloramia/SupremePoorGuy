@tool
extends Node
## Completes the upstream UISkinSlots contract without changing its code or layout.
const SlotsScript = preload("res://Scripts/UI/UISkinSlots.gd")
const Field = preload("res://TA/SilhouetteField.gd")
const CutoutShader = preload("res://TA/Shaders/cutout.gdshader")
@export var target_root := NodePath("..")
@export var initial_preset: Resource
var slots_nodes: Array[Node] = []
var prepared: Dictionary = {}
var focus_targets: Dictionary = {}
var visual_hosts: Dictionary = {}
var source_visibility: Dictionary = {}
var active := false

func _ready() -> void:
	_start.call_deferred()

func _start() -> void:
	rescan()
	if initial_preset != null:
		apply_preset(initial_preset)

func rescan() -> void:
	slots_nodes.clear()
	var subtree := get_node_or_null(target_root)
	if subtree == null:
		return
	if subtree.get_script() == SlotsScript:
		slots_nodes.append(subtree)
	for node in subtree.find_children("*", "Node", true, false):
		if node.get_script() == SlotsScript:
			slots_nodes.append(node)

func apply_preset(preset: Resource) -> void:
	if slots_nodes.is_empty():
		rescan()
	for slots in slots_nodes:
		slots.local_preset = preset
		slots.enabled = true
		slots.refresh()
		_prepare_focus(slots, preset)
	active = true
	_process(0.0)

func restore() -> void:
	for host in focus_targets:
		if not is_instance_valid(host):
			continue
		var saved: Dictionary = focus_targets[host]
		if saved.overridden:
			host.add_theme_stylebox_override("focus", saved.style)
		else:
			host.remove_theme_stylebox_override("focus")
		saved.ring.queue_free()
	focus_targets.clear()
	for source in source_visibility:
		if is_instance_valid(source):
			source.visible = source_visibility[source]
	source_visibility.clear()
	for host in visual_hosts:
		if is_instance_valid(visual_hosts[host]):
			visual_hosts[host].hide()
			visual_hosts[host].queue_free()
	visual_hosts.clear()
	for slots in slots_nodes:
		if is_instance_valid(slots):
			slots.enabled = false
			slots.refresh()
	active = false
	prepared.clear()

func _invalidate() -> void:
	Field.cache.clear()
	prepared.clear()

func _process(_delta: float) -> void:
	if not active:
		return
	for slots in slots_nodes:
		if not is_instance_valid(slots):
			continue
		if not slots.enabled:
			_restore_component(slots)
			continue
		var host := slots.get_parent() as Control
		var preset: Resource = slots.local_preset if slots.local_preset != null else slots.shared_preset
		if host is Button and preset != null:
			var saved: Dictionary = focus_targets.get(host, {})
			if saved.is_empty() or saved.get("preset") != preset or saved.get("seed") != preset.stable_seed:
				_prepare_focus(slots, preset)
		_sync_layers(slots)
		if focus_targets.has(host):
			var ring: NinePatchRect = focus_targets[host].ring
			ring.visible = host.has_focus()
			ring.position = Vector2(-3, -3)
			for side in 4:
				ring.set_patch_margin(side, mini(int(slots._value("patch_margin")), floori((host.size.y + 6.0) * 0.5) if side in [SIDE_TOP, SIDE_BOTTOM] else floori((host.size.x + 6.0) * 0.5)))
			ring.size = host.size + Vector2(6, 6)
			ring.material.set_shader_parameter("ui_size_px", ring.size)
		# Upstream preserves the original panel fill. Hide only that fill while a
		# new paper is active; copied margins and original restore stay intact.
		if host is PanelContainer and slots._value("surface_texture") != null:
			var style := host.get_theme_stylebox("panel") as StyleBoxFlat
			if style != null and style.draw_center:
				var transparent := style.duplicate() as StyleBoxFlat
				transparent.draw_center = false
				host.add_theme_stylebox_override("panel", transparent)
		var targets: Array = [slots.get_node("Surface"), slots.get_node("Outline"), host.get_node_or_null(slots.surface_target)]
		for path in slots.illustration_targets:
			targets.append(host.get_node_or_null(path))
		for target in targets:
			if not target is Control or not target.material is ShaderMaterial:
				continue
			var material := target.material as ShaderMaterial
			if material.shader == CutoutShader and target is TextureRect:
				_prepare_cutout(target, material)
			elif target is NinePatchRect and host is Button:
				var tint := Color.WHITE
				if host.disabled:
					tint = Color(0.82, 0.82, 0.80, 0.65)
				elif host.is_pressed():
					tint = Color(0.88, 0.91, 0.82)
				elif host.is_hovered():
					tint = Color(1.0, 0.97, 0.90)
				material.set_shader_parameter("ui_state_tint", tint)

func _prepare_cutout(target: TextureRect, material: ShaderMaterial) -> void:
	if target.texture == null or target.size.x <= 0.0 or target.size.y <= 0.0:
		return
	var width := _float_parameter(material, "backing_width", 6.0)
	var smoothing := _float_parameter(material, "smoothing", 0.7)
	var signature := [material.get_instance_id(), target.texture.get_instance_id(), target.size, target.stretch_mode, width, smoothing]
	if prepared.get(target.get_instance_id()) == signature:
		return
	prepared[target.get_instance_id()] = signature
	if not target.texture.changed.is_connected(_invalidate):
		target.texture.changed.connect(_invalidate)
	var image := target.texture.get_image()
	if image == null or image.is_empty():
		return
	# Opaque reference photos have no isolated subject alpha; never invent a mask.
	if image.detect_alpha() == Image.ALPHA_NONE:
		material.set_shader_parameter("ui_prepared", false)
		return
	var display := target.size
	var source := target.texture.get_size()
	if target.stretch_mode in [TextureRect.STRETCH_KEEP_ASPECT, TextureRect.STRETCH_KEEP_ASPECT_CENTERED]:
		display = source * minf(target.size.x / source.x, target.size.y / source.y)
	elif target.stretch_mode in [TextureRect.STRETCH_KEEP, TextureRect.STRETCH_KEEP_CENTERED]:
		display = source
	elif target.stretch_mode != TextureRect.STRETCH_SCALE:
		material.set_shader_parameter("ui_prepared", false)
		return
	var max_dimension := clampi(ceili(maxf(display.x, display.y) * 2.0), 1, 256)
	var mask_scale := minf(1.0, float(max_dimension) / maxf(source.x, source.y))
	var scale_px := display.x / maxf(1.0, roundf(source.x * mask_scale))
	var padding := maxi(3, ceili((width + smoothing + 2.0) / scale_px) + 2)
	var field := Field.build(target.texture, padding, max_dimension)
	if field.is_empty():
		return
	material.set_shader_parameter("silhouette_distance", field.texture)
	material.set_shader_parameter("field_size", field.size)
	material.set_shader_parameter("subject_size", field.subject_size)
	material.set_shader_parameter("field_padding", field.padding)
	material.set_shader_parameter("display_size", display)
	material.set_shader_parameter("ui_prepared", true)

func _float_parameter(material: ShaderMaterial, name_value: String, fallback: float) -> float:
	var value = material.get_shader_parameter(name_value)
	return float(value) if value != null else fallback

func _prepare_focus(slots: Node, preset: Resource) -> void:
	var host := slots.get_parent() as Button
	if host == null or preset.outline_texture == null:
		return
	if not focus_targets.has(host):
		var style := host.get_theme_stylebox("focus")
		var empty := StyleBoxEmpty.new()
		for side in 4:
			empty.set_content_margin(side, style.get_content_margin(side))
		var ring := NinePatchRect.new()
		ring.name = "TAFocus"
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_anchor(host).add_child(ring)
		focus_targets[host] = {"overridden": host.has_theme_stylebox_override("focus"), "style": style, "ring": ring}
		host.add_theme_stylebox_override("focus", empty)
	var ring: NinePatchRect = focus_targets[host].ring
	ring.texture = preset.outline_texture
	for side in 4:
		ring.set_patch_margin(side, preset.patch_margin)
	ring.material = preset.outline_material.duplicate()
	ring.material.set_shader_parameter("ui_seed", preset.stable_seed)
	ring.material.set_shader_parameter("line_width", 1.8)
	focus_targets[host]["preset"] = preset
	focus_targets[host]["seed"] = preset.stable_seed

func _anchor(host: Control) -> Node2D:
	if visual_hosts.has(host) and is_instance_valid(visual_hosts[host]):
		return visual_hosts[host]
	# UISkinSlots is a plain Node: a direct CanvasItem chain is required for
	# inherited transforms. Node2D also stays outside Container layout/minimums.
	var anchor := Node2D.new()
	anchor.name = "TAVisuals"
	anchor.show_behind_parent = true
	host.add_child(anchor)
	visual_hosts[host] = anchor
	return anchor

func _restore_component(slots: Node) -> void:
	var host := slots.get_parent() as Control
	if focus_targets.has(host):
		var saved: Dictionary = focus_targets[host]
		if saved.overridden:
			host.add_theme_stylebox_override("focus", saved.style)
		else:
			host.remove_theme_stylebox_override("focus")
		focus_targets.erase(host)
	var source := host.get_node_or_null(slots.surface_target)
	if source_visibility.has(source):
		source.visible = source_visibility[source]
		source_visibility.erase(source)
	if visual_hosts.has(host):
		visual_hosts[host].hide()
		visual_hosts[host].queue_free()
		visual_hosts.erase(host)

func _sync_layers(slots: Node) -> void:
	var host := slots.get_parent() as Control
	var generated: NinePatchRect = slots.get_node("Surface")
	var outline: NinePatchRect = slots.get_node("Outline")
	var source := host.get_node_or_null(slots.surface_target) as CanvasItem
	var surface: CanvasItem = generated if host is Button else source
	var have_surface: bool = slots._value("surface_texture") != null and surface != null
	var have_outline: bool = slots._value("outline_texture") != null and (host is Button or host is PanelContainer or source != null)
	if not have_surface and not have_outline:
		generated.hide()
		outline.hide()
		return
	var anchor := _anchor(host)
	var visual_size := host.size
	if host is PanelContainer:
		var style := host.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			visual_size.x += style.expand_margin_right
	for pair in [[surface, "TASurface", have_surface], [outline, "TAOutline", have_outline]]:
		var original := pair[0] as CanvasItem
		var layer := anchor.get_node_or_null(pair[1]) as NinePatchRect
		if layer == null:
			layer = NinePatchRect.new()
			layer.name = pair[1]
			layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			anchor.add_child(layer)
		layer.visible = pair[2]
		if layer.visible and original != null:
			layer.texture = original.texture
			layer.material = original.material
			layer.position = Vector2.ZERO
			layer.region_rect = original.region_rect if original is NinePatchRect else Rect2()
			for side in 4:
				var available := visual_size.y if side in [SIDE_TOP, SIDE_BOTTOM] else visual_size.x
				layer.set_patch_margin(side, mini(int(slots._value("patch_margin")), floori(available * 0.5)))
			layer.size = visual_size
			if layer.material is ShaderMaterial:
				layer.material.set_shader_parameter("ui_size_px", layer.size)
			if original == source and not source_visibility.has(source):
				source_visibility[source] = source.visible
			original.hide()
	generated.hide()
	outline.hide()
