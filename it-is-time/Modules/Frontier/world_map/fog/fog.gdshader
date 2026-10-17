shader_type canvas_item;
render_mode unshaded;

uniform sampler2D explored_mask;
uniform vec2 world_origin;
uniform vec2 world_size;
uniform vec2 player_position;
uniform float vision_radius = 210.0;
uniform float feather = 35.0;

void fragment() {
	vec2 point = world_origin + UV * world_size;
	float explored = texture(explored_mask, UV).r;
	float visible = 1.0 - smoothstep(vision_radius - feather, vision_radius, distance(point, player_position));
	float darkness = mix(0.97, 0.56, explored) * (1.0 - visible);
	COLOR = vec4(0.025, 0.043, 0.060, darkness);
}
