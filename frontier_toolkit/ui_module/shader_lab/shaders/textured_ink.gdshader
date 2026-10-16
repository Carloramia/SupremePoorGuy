shader_type canvas_item;
render_mode unshaded;
// For authored transparent line textures and NinePatchRect. UV derivatives track
// each nine-slice region; noise uses local pixels, so it never stretches with UV.
uniform float ink_loss : hint_range(0.0, 0.6) = 0.12;
uniform float edge_coverage : hint_range(0.0, 1.0) = 0.35;
uniform float irregularity : hint_range(0.0, 2.0) = 0.35;
uniform float grain_size : hint_range(0.5, 8.0) = 1.3;
uniform vec4 ink_color : source_color = vec4(0.188, 0.184, 0.168, 1.0);
uniform float seed = 17.0;
varying vec2 local_position;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.7) * 43758.5453);
}
void vertex() { local_position = VERTEX; }
void fragment() {
	vec2 dx = dFdx(UV);
	vec2 dy = dFdy(UV);
	float patch = step(1.0 - edge_coverage, hash(floor(local_position / 13.0)));
	float grain = hash(floor(local_position / grain_size));
	vec2 offset = (dx * sin(local_position.y * 0.11 + seed) + dy * sin(local_position.x * 0.09 + seed)) * irregularity;
	float alpha = texture(TEXTURE, UV + offset).a;
	float core = min(min(texture(TEXTURE, UV + dx).a, texture(TEXTURE, UV - dx).a),
		min(texture(TEXTURE, UV + dy).a, texture(TEXTURE, UV - dy).a));
	alpha *= 1.0 - step(1.0 - ink_loss, grain) * patch * (1.0 - core) * 0.75;
	COLOR *= vec4(ink_color.rgb, ink_color.a * alpha);
}
