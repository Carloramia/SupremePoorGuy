shader_type canvas_item;
render_mode unshaded;
uniform vec2 ui_size_px = vec2(200.0, 100.0);
uniform int ui_seed = 42;
uniform float grain_size : hint_range(0.5, 8.0) = 1.3;
uniform float paper_grain : hint_range(0.0, 0.3) = 0.055;
uniform float pigment_grain : hint_range(0.0, 0.3) = 0.04;
uniform float edge_coverage : hint_range(0.0, 1.0) = 0.3;
uniform float edge_size : hint_range(0.0, 5.0) = 1.2;
uniform float ink_loss : hint_range(0.0, 0.6) = 0.1;
uniform float protected_margin : hint_range(2.0, 32.0) = 8.0;
uniform bool use_protection_mask = false;
uniform sampler2D protection_mask : filter_linear, repeat_disable;
uniform vec4 ui_state_tint : source_color = vec4(1.0);
varying vec2 local_px;
varying vec4 item_tint;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + float(ui_seed) * 13.7) * 43758.5453);
}
void vertex() { local_px = VERTEX; item_tint = COLOR; }
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float grain = hash(floor(local_px / grain_size));
	float pigment = hash(floor(local_px / (grain_size * 2.3)));
	float patch = step(1.0 - edge_coverage, hash(floor(local_px / 15.0)));
	vec2 p = abs(local_px - ui_size_px * 0.5) - ui_size_px * 0.5 + 12.0;
	float distance_to_edge = -(length(max(p, vec2(0.0))) + min(max(p.x, p.y), 0.0) - 12.0);
	float protection = use_protection_mask ? texture(protection_mask, local_px / ui_size_px).r : 0.0;
	float edge = (1.0 - smoothstep(0.0, protected_margin, distance_to_edge)) * (1.0 - protection);
	float erosion = edge * patch * grain * edge_size;
	base.a *= smoothstep(erosion - 0.8, erosion + 0.6, distance_to_edge);
	base.a *= 1.0 - step(1.0 - ink_loss, grain) * patch * edge * 0.5;
	base.rgb *= 1.0 + (grain - 0.5) * paper_grain + (pigment - 0.5) * pigment_grain;
	COLOR = base * item_tint * ui_state_tint;
}
