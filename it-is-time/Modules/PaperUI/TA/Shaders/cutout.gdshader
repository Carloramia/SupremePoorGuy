shader_type canvas_item;
render_mode unshaded;
uniform vec2 ui_size_px = vec2(128.0);
uniform int ui_seed = 42;
uniform float backing_width : hint_range(0.0, 32.0) = 6.0;
uniform vec4 backing_color : source_color = vec4(1.0);
uniform float smoothing : hint_range(0.4, 2.0) = 0.7;
uniform bool backing_enabled = true;
uniform bool ui_prepared = false;
uniform sampler2D silhouette_distance : filter_linear, repeat_disable;
uniform vec2 field_size = vec2(192.0);
uniform vec2 subject_size = vec2(128.0);
uniform float field_padding = 32.0;
uniform vec2 display_size = vec2(128.0);
varying vec4 item_tint;
void vertex() {
	item_tint = COLOR;
	if (ui_prepared && backing_enabled) {
		VERTEX += (UV * 2.0 - 1.0) * (backing_width + smoothing + 2.0);
	}
}
void fragment() {
	if (ui_prepared && backing_enabled) {
		float pad = backing_width + smoothing + 2.0;
		vec2 p = UV * (display_size + 2.0 * pad) - pad;
		vec2 art_uv = p / display_size;
		float inside = step(0.0, art_uv.x) * step(0.0, art_uv.y) * step(art_uv.x, 1.0) * step(art_uv.y, 1.0);
		vec4 art = texture(TEXTURE, clamp(art_uv, vec2(0.0), vec2(1.0)));
		art.a *= inside;
		vec2 field_uv = (art_uv * subject_size + field_padding) / field_size;
		float distance_px = texture(silhouette_distance, field_uv).r * display_size.x / subject_size.x;
		float aa = max(fwidth(distance_px), smoothing);
		float backing = (1.0 - smoothstep(backing_width - aa, backing_width + aa, distance_px)) * backing_color.a;
		float alpha = art.a + backing * (1.0 - art.a);
		vec3 rgb = (art.rgb * art.a + backing_color.rgb * backing * (1.0 - art.a)) / max(alpha, 0.0001);
		COLOR = vec4(rgb, alpha) * item_tint;
	} else {
		COLOR = texture(TEXTURE, UV) * item_tint;
	}
}
