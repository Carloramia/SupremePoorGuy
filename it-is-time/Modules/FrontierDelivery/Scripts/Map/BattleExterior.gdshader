shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform sampler2D artwork : source_color, filter_linear, repeat_disable;
uniform vec2 blur_uv = vec2(.03);
uniform float opacity = .55;
void fragment(){
    vec4 blurred=texture(artwork,UV)*.25;
    blurred+=(texture(artwork,UV+vec2(blur_uv.x,0.0))+texture(artwork,UV-vec2(blur_uv.x,0.0))+texture(artwork,UV+vec2(0.0,blur_uv.y))+texture(artwork,UV-vec2(0.0,blur_uv.y)))*.125;
    blurred+=(texture(artwork,UV+blur_uv)+texture(artwork,UV-blur_uv)+texture(artwork,UV+vec2(blur_uv.x,-blur_uv.y))+texture(artwork,UV+vec2(-blur_uv.x,blur_uv.y)))*.0625;
    ALBEDO=blurred.rgb;
    ALPHA=blurred.a*opacity;
}
