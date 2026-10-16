@tool
extends "res://ui_module/shader_lab/components/visual_base.gd"
const Field = preload("res://ui_module/shader_lab/components/silhouette_field.gd")
const CutoutShader = preload("res://ui_module/shader_lab/shaders/cutout.gdshader")
@export var texture: Texture2D:
	set(value):
		if texture != null and texture.changed.is_connected(_texture_changed):
			texture.changed.disconnect(_texture_changed)
		texture = value
		if texture != null:
			texture.changed.connect(_texture_changed)
		_refresh()
## Optional artist-authored COMPLETE silhouette. White/opaque interior, transparent exterior.
@export var silhouette: Texture2D:
	set(value):
		if silhouette != null and silhouette.changed.is_connected(_texture_changed):
			silhouette.changed.disconnect(_texture_changed)
		silhouette = value
		if silhouette != null:
			silhouette.changed.connect(_texture_changed)
		Field.cache.clear()
		_refresh()
@export_range(0.4, 2.0, 0.1) var smoothing := 0.8:
	set(value):
		smoothing = value
		_refresh()
var display_rect := Rect2()
var draw_padding := 0.0

func _texture_changed() -> void:
	Field.cache.clear()
	_refresh()

func _refresh() -> void:
	if not is_inside_tree() or texture == null or profile == null or size.x <= 0 or size.y <= 0:
		return
	var art_size := texture.get_size()
	var ratio := minf(size.x / art_size.x, size.y / art_size.y)
	display_rect = Rect2((size - art_size * ratio) * 0.5, art_size * ratio)
	var mask_texture := silhouette if silhouette != null else texture
	if not mask_texture.get_size().is_equal_approx(art_size):
		push_warning("Cutout silhouette must have the same canvas/aspect as the subject.")
	# Tiny editor sizes must not allocate huge padding around a full-size mask.
	var max_dimension := clampi(ceili(maxf(display_rect.size.x, display_rect.size.y) * 2.0), 1, 256)
	var mask_scale := minf(1.0, float(max_dimension) / maxf(mask_texture.get_width(), mask_texture.get_height()))
	var raster_scale := display_rect.size.x / (mask_texture.get_width() * mask_scale)
	draw_padding = profile.backing_width + smoothing + 2.0
	var padding := maxi(3, ceili(draw_padding / raster_scale) + 2)
	var field := Field.build(mask_texture, padding, max_dimension)
	if field.is_empty():
		return
	if material == null:
		material = ShaderMaterial.new()
		material.shader = CutoutShader
	var mat := material as ShaderMaterial
	for key in ["subject_size", "field_size", "field_padding"]:
		var field_key: String = {"subject_size": "subject_size", "field_size": "size", "field_padding": "padding"}[key]
		mat.set_shader_parameter(key, field[field_key])
	mat.set_shader_parameter("subject_texture", texture)
	mat.set_shader_parameter("silhouette_distance", field.texture)
	mat.set_shader_parameter("display_size", display_rect.size)
	mat.set_shader_parameter("draw_padding", draw_padding)
	mat.set_shader_parameter("backing_width", profile.backing_width)
	mat.set_shader_parameter("backing_color", profile.backing_color)
	mat.set_shader_parameter("backing_enabled", profile.s2_enabled)
	mat.set_shader_parameter("smoothing", smoothing)
	queue_redraw()

func _draw() -> void:
	if texture != null and display_rect.has_area():
		# Draw outside visual rect; Control hit box and parent layout stay unchanged.
		draw_rect(display_rect.grow(draw_padding), Color.WHITE)

