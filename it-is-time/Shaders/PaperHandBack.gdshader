shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform sampler2D front_texture : source_color, filter_linear_mipmap;
uniform sampler2D back_texture : source_color, filter_linear_mipmap;

void fragment() {
	// Both faces share the front volume silhouette; fill small AI contour gaps with paper.
	vec4 front = texture(front_texture, vec2(1.0 - UV.x, UV.y));
	vec4 back = texture(back_texture, UV);
	vec2 margin = vec2(0.012);
	float interior = min(min(texture(back_texture, UV + vec2(margin.x, 0.0)).a,
		texture(back_texture, UV - vec2(margin.x, 0.0)).a),
		min(texture(back_texture, UV + vec2(0.0, margin.y)).a,
		texture(back_texture, UV - vec2(0.0, margin.y)).a));
	ALBEDO = mix(front.rgb, back.rgb, smoothstep(0.05, 0.95, min(back.a, interior)));
	ALPHA = front.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
