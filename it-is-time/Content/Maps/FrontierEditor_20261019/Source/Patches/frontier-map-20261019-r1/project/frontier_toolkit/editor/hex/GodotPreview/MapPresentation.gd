extends RefCounted
## Visual-only landmark footing. Does not reveal cells or change interaction ranges.
static var _ground_shader:Shader

static func install_landmark_bases(scene:Node2D,objects:Array) -> void:
	for object in objects:
		if object.get("type","") not in ["town","house"]:continue
		var config:Dictionary=object.get("ground_patch",{})
		if not config.get("enabled",true):continue
		var node:=scene.get_node_or_null("Objects/"+str(object.id)) as Node2D
		if not node or node.has_node("GroundPatch"):continue
		var sprite:=node.get_node_or_null("Visual") as Sprite2D
		if not sprite or not sprite.texture:continue
		var footprint:=Vector2(sprite.texture.get_width(),sprite.texture.get_height())*sprite.scale.abs()
		var dimensions:=Vector2(maxf(footprint.x*1.85,300),maxf(footprint.y*1.6,230))
		if config.get("size") is Array and config.size.size()==2:dimensions=Vector2(config.size[0],config.size[1])
		var patch:Control
		var path:=str(config.get("asset",""))
		if not path.is_empty() and ResourceLoader.exists(path):
			var texture:=TextureRect.new();texture.texture=load(path);texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;texture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;patch=texture
		else:
			var color:=ColorRect.new();var material:=ShaderMaterial.new();material.shader=ground_shader();color.material=material;patch=color
			material.set_shader_parameter("base_color",Color(config.get("color","#a6ae80")))
			material.set_shader_parameter("opacity",float(config.get("opacity",.88)))
		patch.name="GroundPatch";patch.mouse_filter=Control.MOUSE_FILTER_IGNORE;patch.z_index=-1
		patch.size=dimensions;patch.position=sprite.position-dimensions*.5+Vector2(0,footprint.y*.20)
		node.add_child(patch)

static func ground_shader() -> Shader:
	if _ground_shader:return _ground_shader
	_ground_shader=Shader.new()
	_ground_shader.code="""shader_type canvas_item;
uniform vec4 base_color : source_color=vec4(.65,.68,.5,1);
uniform float opacity=.88;
float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float n(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1)),f.x),f.y);}
void fragment(){
 vec2 p=UV*2.0-1.0;
 float grain=n(UV*15.0)*.65+n(UV*39.0)*.35;
 float contour=length(p/vec2(.94,.80))+(n(UV*5.0)-.5)*.15;
 float base=1.0-smoothstep(.48,.99,contour);
 float shadow=1.0-smoothstep(.48,1.02,length((p-vec2(.035,.13))/vec2(.96,.77)));
 float curves=pow(1.0-abs(sin((contour+grain*.045)*22.0)),16.0)*.035;
 vec3 earth=base_color.rgb*(.94+.12*grain);
 earth=mix(earth,vec3(.83,.80,.60),.13+curves);
 float alpha=max(base*opacity,shadow*.17);
 COLOR=vec4(mix(vec3(.18,.22,.17),earth,base),alpha);
}"""
	return _ground_shader
