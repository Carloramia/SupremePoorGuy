shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;
uniform int sprite_axis = 2;
uniform vec4 edge_distances = vec4(1.28);
void vertex() {
    vec2 uv;
    if (sprite_axis == 0) { uv = vec2(VERTEX.z <= 0.0 ? 1.0 : 0.0, VERTEX.y >= 0.0 ? 0.0 : 1.0); }
    else if (sprite_axis == 1) { uv = vec2(VERTEX.x >= 0.0 ? 1.0 : 0.0, VERTEX.z <= 0.0 ? 0.0 : 1.0); }
    else { uv = vec2(VERTEX.x >= 0.0 ? 1.0 : 0.0, VERTEX.y >= 0.0 ? 0.0 : 1.0); }
    vec2 point = vec2(mix(-edge_distances.x, edge_distances.y, uv.x), mix(edge_distances.z, -edge_distances.w, uv.y));
    if (sprite_axis == 0) { VERTEX.z = -point.x; VERTEX.y = point.y; }
    else if (sprite_axis == 1) { VERTEX.x = point.x; VERTEX.z = -point.y; }
    else { VERTEX.xy = point; }
}
void fragment() {
    vec4 base = texture(sprite_texture, UV) * COLOR;
    ALBEDO = base.rgb;
    ALPHA = base.a;
}
