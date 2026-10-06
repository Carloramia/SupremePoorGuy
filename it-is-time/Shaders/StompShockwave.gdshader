shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 wave_color : source_color = vec4(1.0,0.55,0.12,1.0);
uniform float opacity = 1.0;
uniform float energy = 4.0;
uniform float progress = 0.0;
void fragment() {
	float rim = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),2.5);
	float ripple = 0.8+0.2*sin(UV.y*65.0-progress*20.0);
	ALBEDO = wave_color.rgb;
	EMISSION = wave_color.rgb*energy;
	ALPHA = clamp((0.04+rim*0.6)*ripple*opacity*wave_color.a,0.0,1.0);
}
