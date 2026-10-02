shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_strength : hint_range(0.0, 8.0, 0.1) = 3.0;
uniform vec4 dim_color : source_color = vec4(0.08, 0.09, 0.10, 0.42);

void fragment() {
	vec4 blurred_screen = textureLod(screen_texture, SCREEN_UV, blur_strength);
	vec3 darkened = mix(blurred_screen.rgb, dim_color.rgb, dim_color.a);
	COLOR = vec4(darkened, 1.0);
}
