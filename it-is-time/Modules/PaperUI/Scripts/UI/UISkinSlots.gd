@tool
extends Node
const Preset = preload("res://Modules/PaperUI/Scripts/UI/UISkinPreset.gd")
@export var shared_preset: Resource:
	set(value):
		shared_preset = value
		_watch(value)
		_schedule()
@export var local_preset: Resource:
	set(value):
		local_preset = value
		_watch(value)
		_schedule()
@export var enabled := true:
	set(value):
		enabled = value
		_schedule()
@export var surface_target := NodePath("Paper")
@export var illustration_targets: Array[NodePath] = []
@export var decoration_targets: Array[NodePath] = []
@export var legacy_outline_targets: Array[NodePath] = []
var originals: Dictionary = {}
var button_styles: Dictionary = {}
var managed_materials: Dictionary = {}
var managed_textures: Dictionary = {}
var button_skin_active := false
var panel_original: StyleBox
var panel_overridden := false
var panel_skin_active := false
var hidden_outlines: Dictionary = {}
var queued := false

func _ready() -> void:
	var host := get_parent() as Control
	if host:
		host.resized.connect(_schedule)
	for preset in [shared_preset,local_preset]:
		if preset and not preset.changed.is_connected(_schedule):
			preset.changed.connect(_schedule)
	_schedule()

func _schedule() -> void:
	if is_inside_tree() and not queued:
		queued = true
		refresh.call_deferred()

func _watch(preset: Resource) -> void:
	if is_inside_tree() and preset and not preset.changed.is_connected(_schedule):
		preset.changed.connect(_schedule)

func _value(field: String):
	var source = local_preset if local_preset else shared_preset
	return source.get(field) if enabled and source is Preset else null

func _remember(target: CanvasItem) -> void:
	if target not in originals:
		originals[target] = {"material":target.material}
		if target is TextureRect or target is NinePatchRect:
			originals[target]["texture"] = target.texture

func _material(target: CanvasItem, supplied: Material) -> void:
	_remember(target)
	if supplied == null:
		if target in managed_materials:
			target.material = originals[target].material
			target.use_parent_material = originals[target].parent_material
			managed_materials.erase(target)
		return
	if target not in managed_materials:
		originals[target].material = target.material
		originals[target]["parent_material"] = target.use_parent_material
		managed_materials[target] = true
	var instance := supplied.duplicate() as Material
	if instance is ShaderMaterial and instance.shader:
		for uniform in instance.shader.get_shader_uniform_list():
			if uniform.name == "ui_size_px" and target is Control:
				instance.set_shader_parameter("ui_size_px",target.size)
			elif uniform.name == "ui_seed":
				instance.set_shader_parameter("ui_seed",_value("stable_seed"))
	target.material = instance
	target.use_parent_material = false

func refresh() -> void:
	queued = false
	var host := get_parent() as Control
	if host == null:
		return
	var surface := host.get_node_or_null(surface_target) as CanvasItem
	var generated: NinePatchRect = $Surface
	var outline: NinePatchRect = $Outline
	var texture: Texture2D = _value("surface_texture")
	var outline_texture: Texture2D = _value("outline_texture")
	generated.hide()
	if surface and (surface is TextureRect or surface is NinePatchRect):
		_remember(surface)
		if texture:
			if surface not in managed_textures:
				originals[surface].texture = surface.texture
				if surface is NinePatchRect:
					originals[surface]["region"] = surface.region_rect
				managed_textures[surface] = true
			surface.texture = texture
			if surface is NinePatchRect:
				surface.region_rect = _value("surface_region")
		elif surface in managed_textures:
			surface.texture = originals[surface].texture
			if surface is NinePatchRect:
				surface.region_rect = originals[surface].region
			managed_textures.erase(surface)
		_material(surface,_value("surface_material"))
	elif host is Button:
		for state in ["normal","hover","pressed","hover_pressed","disabled"]:
			if texture and not button_skin_active:
				button_styles[state] = {"overridden":host.has_theme_stylebox_override(state),"style":host.get_theme_stylebox(state)}
			if texture:
				var empty := StyleBoxEmpty.new()
				for side in 4:
					empty.set_content_margin(side,button_styles[state].style.get_content_margin(side))
				host.add_theme_stylebox_override(state,empty)
			elif button_skin_active and button_styles[state].overridden:
				host.add_theme_stylebox_override(state,button_styles[state].style)
			elif button_skin_active:
				host.remove_theme_stylebox_override(state)
		button_skin_active = texture != null
		generated.visible = texture != null
		generated.texture = texture
	var visual_size := host.size
	if host is PanelContainer:
		if texture or outline_texture:
			if not panel_skin_active:
				panel_original = host.get_theme_stylebox("panel")
				panel_overridden = host.has_theme_stylebox_override("panel")
			var replacement := panel_original.duplicate() as StyleBoxFlat
			if replacement:
				if outline_texture:
					for side in 4:
						replacement.set_border_width(side,0)
				if _value("remove_legacy_shadows"):
					replacement.shadow_size = 0
				host.add_theme_stylebox_override("panel",replacement)
			panel_skin_active = true
		elif panel_skin_active:
			if panel_overridden:
				host.add_theme_stylebox_override("panel",panel_original)
			else:
				host.remove_theme_stylebox_override("panel")
			panel_skin_active = false
		var panel := host.get_theme_stylebox("panel") as StyleBoxFlat
		if panel:
			visual_size.x += panel.expand_margin_right
	for layer in [generated,outline]:
		layer.position = Vector2.ZERO
		layer.size = visual_size
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var margin = _value("patch_margin")
		for side in 4:
			layer.set_patch_margin(side,int(margin) if margin != null else 16)
	_material(generated,_value("surface_material"))
	outline.visible = outline_texture != null
	outline.texture = outline_texture
	_material(outline,_value("outline_material"))
	for path in legacy_outline_targets:
		var old := host.get_node_or_null(path) as CanvasItem
		if old:
			if outline_texture:
				if old not in hidden_outlines:
					hidden_outlines[old] = old.visible
				old.hide()
			elif old in hidden_outlines:
				old.visible = hidden_outlines[old]
				hidden_outlines.erase(old)
	for pair in [[illustration_targets,"cutout_material"],[decoration_targets,"decoration_material"]]:
		for path in pair[0]:
			var target := host.get_node_or_null(path) as CanvasItem
			if target:
				_material(target,_value(pair[1]))
	# The TA adapter draws these through a CanvasItem chain that inherits the host transform.
	if has_meta(&"ta_bound"):
		generated.hide()
		outline.hide()
