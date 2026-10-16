shader_type canvas_item;
render_mode unshaded;

uniform float ink_loss : hint_range(0.0, 0.6) = 0.12;
uniform float edge_roughness : hint_range(0.0, 1.0) = 0.3;
uniform float edge_coverage : hint_range(0.0, 1.0) = 0.35;
uniform float grain_size : hint_range(0.5, 8.0) = 1.3;
uniform float seed = 17.0;
uniform float protected_core : hint_range(0.25, 0.9) = 0.5;
varying vec2 local_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.7) * 43758.5453);
}
void vertex() { local_position = VERTEX; }
void fragment() {
	// Ribbon UV.y encodes distance across the editable base stroke.
	float across = abs(UV.y * 2.0 - 1.0);
	float patch = step(1.0 - edge_coverage, hash(floor(local_position / 13.0)));
	float grain = hash(floor(local_position / grain_size));
	float erosion = patch * edge_roughness * (0.12 + grain * 0.28);
	float aa = max(fwidth(across), 0.02);
	float edge = 1.0 - smoothstep(1.0 - erosion - aa, 1.0 - erosion, across);
	float loss = step(1.0 - ink_loss, grain) * smoothstep(protected_core, 1.0, across);
	COLOR.a *= edge * (1.0 - loss * 0.85);
}
