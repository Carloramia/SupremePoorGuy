shader_type spatial;
render_mode unshaded;

uniform vec4 ground_color : source_color = vec4(0.12, 0.14, 0.18, 1.0);
uniform vec2 ground_half_size = vec2(60.0, 40.0);
uniform float fade_start : hint_range(0.0, 0.9) = 0.45;
uniform float fade_end : hint_range(0.5, 1.0) = 0.95;
varying vec2 ground_position;

void vertex() {
	ground_position = VERTEX.xz;
}

void fragment() {
	vec2 edge = abs(ground_position) / max(ground_half_size, vec2(0.001));
	float brightness = 1.0 - smoothstep(fade_start, max(fade_end, fade_start + 0.001), max(edge.x, edge.y));
	ALBEDO = ground_color.rgb * brightness;
}
