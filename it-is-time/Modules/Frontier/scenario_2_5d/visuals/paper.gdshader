shader_type spatial;
render_mode cull_disabled, diffuse_lambert, depth_prepass_alpha;
uniform sampler2D paper_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float fade = 1.0;
uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);
void fragment() {
	vec4 paper = texture(paper_texture, frame_rect.xy + UV * frame_rect.zw);
	ALBEDO = paper.rgb * tint.rgb * 0.22;
	EMISSION = paper.rgb * tint.rgb * 0.68;
	ROUGHNESS = 1.0;
	ALPHA = paper.a * tint.a * fade;
	if (paper.a < 0.08) { discard; }
}
