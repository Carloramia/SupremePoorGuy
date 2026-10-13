shader_type spatial;
render_mode unshaded, cull_back, skip_vertex_transform;

uniform mat4 source_to_part;
uniform vec3 source_root;
uniform vec3 source_axis;
uniform float source_length;
uniform float protected_length;
uniform mat4 target_frame;
uniform float target_length;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool has_texture = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_cutoff = 0.5;

void vertex() {
	vec3 point = (source_to_part * vec4(VERTEX, 1.0)).xyz - source_root;
	float distance_along = dot(point, source_axis);
	float mapped_distance = distance_along;
	float middle_scale = (target_length - 2.0 * protected_length)
		/ (source_length - 2.0 * protected_length);
	float axial_scale = 1.0;
	if (distance_along >= source_length - protected_length) {
		mapped_distance = target_length + distance_along - source_length;
	} else if (distance_along > protected_length) {
		mapped_distance = protected_length + (distance_along - protected_length) * middle_scale;
		axial_scale = middle_scale;
	}
	vec3 world_position = (target_frame * vec4(
		point + source_axis * (mapped_distance - distance_along), 1.0)).xyz;
	vec3 part_normal = transpose(inverse(mat3(source_to_part))) * NORMAL;
	part_normal += source_axis * dot(part_normal, source_axis) * (1.0 / axial_scale - 1.0);
	VERTEX = (VIEW_MATRIX * vec4(world_position, 1.0)).xyz;
	NORMAL = normalize(mat3(VIEW_MATRIX) * mat3(target_frame) * part_normal);
}

void fragment() {
	vec4 color = albedo_color;
	if (has_texture) {
		color *= texture(albedo_texture, UV);
	}
	if (color.a < alpha_cutoff) {
		discard;
	}
	ALBEDO = color.rgb;
}
