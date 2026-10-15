class_name BlobShadow
extends MeshInstance3D

@export var shadow_size: Vector2 = Vector2(1.5, 0.9)
@export_range(0.0, 1.0) var opacity: float = 0.28

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = shadow_size
	mesh = quad
	rotation_degrees.x = -90
	position.y = 0.025
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, cull_disabled, depth_draw_never; uniform float opacity = 0.28; void fragment(){ float d = length((UV - vec2(0.5)) * 2.0); ALBEDO = vec3(0.08,0.1,0.09); ALPHA = (1.0 - smoothstep(0.35, 1.0, d)) * opacity; }"
	material.shader = shader
	material.set_shader_parameter("opacity", opacity)
	material_override = material
