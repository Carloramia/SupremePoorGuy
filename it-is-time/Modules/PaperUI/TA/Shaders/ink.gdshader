shader_type canvas_item;
render_mode unshaded;
uniform vec2 ui_size_px = vec2(200.0, 60.0);
uniform int ui_seed = 42;
uniform vec4 ink_color : source_color = vec4(0.19, 0.18, 0.16, 1.0);
uniform float line_width : hint_range(0.8, 8.0) = 2.8;
uniform float width_variation : hint_range(0.0, 0.8) = 0.22;
uniform float irregularity : hint_range(0.0, 1.5) = 0.3;
uniform float ink_loss : hint_range(0.0, 0.6) = 0.1;
uniform float edge_coverage : hint_range(0.0, 1.0) = 0.3;
uniform float grain_size : hint_range(0.5, 8.0) = 1.3;
uniform float repeat_strength : hint_range(0.0, 1.0) = 0.65;
uniform vec4 ui_state_tint : source_color = vec4(1.0);
varying vec2 local_px;
varying vec4 item_tint;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)) + float(ui_seed) * 13.7) * 43758.5453);
}
void vertex() { local_px = VERTEX; item_tint = COLOR; }
void fragment() {
	// NinePatch regions have discontinuous UVs. Bound derivatives so a seam
	// cannot sample a distant opposite border and create a false middle line.
	vec2 limit_uv = TEXTURE_PIXEL_SIZE * 2.0;
	vec2 dx = clamp(dFdx(UV), -limit_uv, limit_uv);
	vec2 dy = clamp(dFdy(UV), -limit_uv, limit_uv);
	// Perturb edges within a subpixel. Source artwork supplies the actual strokes.
	vec2 offset = (dx * sin(local_px.y * 0.11 + float(ui_seed)) + dy * sin(local_px.x * 0.09 + float(ui_seed))) * irregularity;
	vec2 uv = UV + offset;
	float base = texture(TEXTURE, uv).a;
	float core = min(min(texture(TEXTURE, UV + dx * 0.7).a, texture(TEXTURE, UV - dx * 0.7).a),
		min(texture(TEXTURE, UV + dy * 0.7).a, texture(TEXTURE, UV - dy * 0.7).a));
	float pressure = (line_width - 2.8) * 0.5 + sin((local_px.x + local_px.y) * 0.07 + float(ui_seed)) * width_variation;
	vec2 grow = (abs(dx) + abs(dy)) * abs(pressure);
	float neighbor_hi = max(max(texture(TEXTURE, uv + vec2(grow.x, 0.0)).a, texture(TEXTURE, uv - vec2(grow.x, 0.0)).a),
		max(texture(TEXTURE, uv + vec2(0.0, grow.y)).a, texture(TEXTURE, uv - vec2(0.0, grow.y)).a));
	float neighbor_lo = min(min(texture(TEXTURE, uv + vec2(grow.x, 0.0)).a, texture(TEXTURE, uv - vec2(grow.x, 0.0)).a),
		min(texture(TEXTURE, uv + vec2(0.0, grow.y)).a, texture(TEXTURE, uv - vec2(0.0, grow.y)).a));
	float alpha = pressure > 0.0 ? max(base, neighbor_hi) : max(core, neighbor_lo);
	// Sparse low-alpha companion marks are already authored in the line texture.
	alpha *= mix(repeat_strength, 1.0, smoothstep(0.35, 0.8, base));
	float patch = step(1.0 - edge_coverage, hash(floor(local_px / 13.0)));
	float grain = hash(floor(local_px / grain_size));
	alpha *= 1.0 - step(1.0 - ink_loss, grain) * patch * (1.0 - core) * 0.7;
	COLOR = vec4(ink_color.rgb, alpha * ink_color.a) * item_tint * ui_state_tint;
}
