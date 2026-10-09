class_name BillboardVisual3D
extends Node3D

signal visual_animation_requested(animation_name: StringName)
@export var texture: Texture2D
@export var visual_height: float = 2.5
@export var visual_scale: Vector2 = Vector2.ONE
@export var ground_offset: float = 0.0
@export var pivot_offset: Vector2 = Vector2.ZERO
@export var linear_filter: bool = true
var mesh_instance: MeshInstance3D
var paper_material: ShaderMaterial
var animation_source: Resource

func _ready() -> void:
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "PaperQuad"
	var quad := QuadMesh.new()
	var aspect: float = float(texture.get_width()) / maxf(texture.get_height(), 1.0) if texture else 0.7
	quad.size = Vector2(visual_height * aspect, visual_height) * visual_scale
	mesh_instance.mesh = quad
	mesh_instance.position = Vector3(pivot_offset.x, ground_offset + quad.size.y * 0.5 + pivot_offset.y, 0)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	paper_material = ShaderMaterial.new()
	paper_material.shader = preload("res://scenario_2_5d/visuals/paper.gdshader")
	if not linear_filter:
		var pixel_shader := Shader.new()
		pixel_shader.code = paper_material.shader.code.replace("filter_linear_mipmap", "filter_nearest_mipmap")
		paper_material.shader = pixel_shader
	if not texture:
		push_warning("Billboard texture missing; using cream fallback")
		var fallback := GradientTexture2D.new()
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color("eadcba"), Color("eadcba")])
		fallback.gradient = gradient
		texture = fallback
	paper_material.set_shader_parameter("paper_texture", texture)
	mesh_instance.material_override = paper_material
	add_child(mesh_instance)

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		var offset := camera.global_position - global_position
		if Vector2(offset.x, offset.z).length_squared() > 0.001:
			global_rotation = Vector3(0, atan2(offset.x, offset.z), 0)

func set_tint(value: Color) -> void:
	if paper_material:
		paper_material.set_shader_parameter("tint", value)

func set_frame(rect: Rect2) -> void:
	if paper_material:
		paper_material.set_shader_parameter("frame_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))

func set_animation_source(source: Resource) -> void:
	animation_source = source

func play_visual_animation(animation_name: StringName) -> void:
	visual_animation_requested.emit(animation_name)
