@tool
extends "res://ui_module/shader_lab/components/visual_base.gd"
const PaperShader = preload("res://ui_module/shader_lab/shaders/paper.gdshader")
@export var paper_color := Color("#eee4d1"):
	set(value):
		paper_color = value
		_refresh()
@export_range(0.0, 64.0) var corner_radius := 12.0:
	set(value):
		corner_radius = value
		_refresh()
@export var paper_texture: Texture2D:
	set(value):
		paper_texture = value
		_refresh()
## Red=1 protects the surface from edge wear. UV covers the component.
@export var protection_mask: Texture2D:
	set(value):
		protection_mask = value
		_refresh()
@export_range(2.0, 32.0) var protected_margin := 8.0:
	set(value):
		protected_margin = value
		_refresh()

func _refresh() -> void:
	if not is_inside_tree() or profile == null:
		return
	if material == null:
		material = ShaderMaterial.new()
		material.shader = PaperShader
	var mat := material as ShaderMaterial
	mat.set_shader_parameter("control_size", size)
	mat.set_shader_parameter("paper_color", paper_color)
	mat.set_shader_parameter("corner_radius", corner_radius)
	mat.set_shader_parameter("seed", profile.seed)
	mat.set_shader_parameter("grain_size", profile.grain_size)
	for param in ["paper_grain", "pigment_grain", "edge_coverage", "edge_size", "ink_loss"]:
		mat.set_shader_parameter(param, profile.get(param) if profile.s3_enabled else 0.0)
	mat.set_shader_parameter("protected_margin", protected_margin)
	mat.set_shader_parameter("use_paper_texture", paper_texture != null)
	mat.set_shader_parameter("paper_texture", paper_texture)
	mat.set_shader_parameter("use_protection_mask", protection_mask != null)
	mat.set_shader_parameter("protection_mask", protection_mask)
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)

