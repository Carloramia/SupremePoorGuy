shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
uniform vec4 ground_color : source_color = vec4(.58,.57,.42,1.0);
uniform float radius = 20.0;
uniform float feather = .7;
uniform float orientation = 0.0;
uniform bool halo = false;
varying vec2 point;
void vertex(){ point=VERTEX.xz; }
void fragment(){
    vec2 p=mat2(vec2(cos(orientation),-sin(orientation)),vec2(sin(orientation),cos(orientation)))*point;
    float d=max(abs(p.y),max(abs(.8660254*p.x+.5*p.y),abs(.8660254*p.x-.5*p.y)))-radius*.8660254;
    float width=max(feather,.001);
    float alpha=halo ? 1.0-smoothstep(0.0,width*4.0,max(d,0.0)) : 1.0-smoothstep(-width,width,d);
    if(alpha<.001)discard;
    ALBEDO=ground_color.rgb;
    ALPHA=alpha*ground_color.a;
}
