shader_type canvas_item;
render_mode unshaded;

uniform sampler2D subject_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D silhouette_distance : filter_linear, repeat_disable;
uniform vec2 subject_size = vec2(128.0);
uniform vec2 field_size = vec2(192.0);
uniform float field_padding = 32.0;
uniform vec2 display_size = vec2(128.0);
uniform float draw_padding = 10.0;
uniform float backing_width : hint_range(0.0, 32.0) = 6.0;
uniform vec4 backing_color : source_color = vec4(1.0);
uniform float smoothing : hint_range(0.4, 2.0) = 0.8;
uniform bool backing_enabled = true;

void fragment() {
	vec2 p = UV * (display_size + 2.0 * draw_padding) - draw_padding;
	vec2 subject_uv = p / display_size;
	float inside = step(0.0, subject_uv.x) * step(0.0, subject_uv.y)
		* step(subject_uv.x, 1.0) * step(subject_uv.y, 1.0);
	vec4 art = texture(subject_texture, clamp(subject_uv, vec2(0.0), vec2(1.0)));
	art.a *= inside;
	vec2 field_uv = (subject_uv * subject_size + field_padding) / field_size;
	float scale_px = display_size.x / subject_size.x;
	float distance_px = texture(silhouette_distance, field_uv).r * scale_px;
	float aa = max(fwidth(distance_px), smoothing);
	float backing = backing_enabled ? 1.0 - smoothstep(backing_width - aa, backing_width + aa, distance_px) : 0.0;
	backing *= backing_color.a;
	float alpha = art.a + backing * (1.0 - art.a);
	vec3 rgb = (art.rgb * art.a + backing_color.rgb * backing * (1.0 - art.a)) / max(alpha, 0.0001);
	COLOR *= vec4(rgb, alpha);
}
