shader_type canvas_item;
render_mode unshaded;

uniform vec2 control_size = vec2(200.0, 100.0);
uniform vec4 paper_color : source_color = vec4(0.94, 0.89, 0.79, 1.0);
uniform float corner_radius : hint_range(0.0, 64.0) = 12.0;
uniform float grain_size : hint_range(0.5, 8.0) = 1.3;
uniform float paper_grain : hint_range(0.0, 0.3) = 0.055;
uniform float pigment_grain : hint_range(0.0, 0.3) = 0.045;
uniform float edge_coverage : hint_range(0.0, 1.0) = 0.35;
uniform float edge_size : hint_range(0.0, 8.0) = 1.4;
uniform float ink_loss : hint_range(0.0, 0.6) = 0.12;
uniform float protected_margin : hint_range(2.0, 32.0) = 8.0;
uniform float seed = 17.0;
uniform sampler2D paper_texture : repeat_enable, filter_linear;
uniform bool use_paper_texture = false;
uniform sampler2D protection_mask : filter_linear;
uniform bool use_protection_mask = false;
varying vec2 local_position;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.7) * 43758.5453);
}
void vertex() { local_position = VERTEX; }
void fragment() {
	vec2 p = local_position;
	float r = min(corner_radius, min(control_size.x, control_size.y) * 0.5);
	vec2 q = abs(p - control_size * 0.5) - control_size * 0.5 + r + 1.0;
	float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
	float fine = hash(floor(p / grain_size));
	float pigment = hash(floor(p / (grain_size * 2.3)));
	float patch = step(1.0 - edge_coverage, hash(floor(p / 15.0)));
	float protect = use_protection_mask ? texture(protection_mask, UV).r : 0.0;
	float edge_zone = (1.0 - smoothstep(0.0, protected_margin, -d)) * (1.0 - protect);
	float erosion = patch * edge_size * fine * edge_zone;
	float aa = max(fwidth(d), 0.7);
	float alpha = 1.0 - smoothstep(-aa, 0.0, d + erosion);
	alpha *= 1.0 - step(1.0 - ink_loss, fine) * edge_zone * patch * 0.65;
	float fiber = use_paper_texture ? texture(paper_texture, p / 128.0).r - 0.5 : fine - 0.5;
	vec3 rgb = paper_color.rgb * (1.0 + fiber * paper_grain + (pigment - 0.5) * pigment_grain);
	COLOR *= vec4(rgb, alpha * paper_color.a);
}
