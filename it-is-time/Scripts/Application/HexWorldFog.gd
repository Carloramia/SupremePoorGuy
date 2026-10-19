extends RefCounted
var view: Control
var visible_pixels: Array[Vector2i] = []
var cell_pixels := {}
var sight_image: Image
var sight_texture: ImageTexture

func create(owner_view: Control) -> void:
	view=owner_view
	view.fog_rect=ColorRect.new()
	view.fog_rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	view.fog_rect.z_index=1000
	view.world_canvas.add_child(view.fog_rect)
	view.fog_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code="""shader_type canvas_item;
uniform sampler2D explored_mask : filter_linear;
uniform sampler2D sight_depth : filter_linear, repeat_enable;
uniform vec2 sight_origin;
uniform vec2 map_origin; uniform vec2 map_size;
uniform vec2 player; uniform vec2 camera; uniform vec2 view_size;
uniform float zoom=1.0; uniform float radius=630.0;
uniform vec4 unknown_color : source_color=vec4(.208,.282,.251,1.0);
uniform vec4 explored_color : source_color=vec4(.094,.169,.149,.76);
void fragment(){
 vec2 world=(UV*view_size-view_size*.5)/zoom+camera;
 vec2 uv=(world-map_origin)/map_size;
 vec2 state=texture(explored_mask,clamp(uv,vec2(0),vec2(1))).rg;
 if(any(lessThan(uv,vec2(0)))||any(greaterThan(uv,vec2(1))))state=vec2(0);
 vec2 offset=world-sight_origin;
 float angle=atan(offset.y,offset.x)/6.28318530718;
 float reach=texture(sight_depth,vec2(angle+0.5/256.0,0.5)).r*radius;
 float visible=1.0-smoothstep(max(reach-12.0,0.0),max(reach,0.001),length(offset));
 COLOR=mix(unknown_color,explored_color,state.r); COLOR.a*=1.0-visible;
}"""
	view.fog_material=ShaderMaterial.new()
	view.fog_material.shader=shader
	view.fog_rect.material=view.fog_material
	var map: Dictionary=view.Catalog.world()
	view.fog_material.set_shader_parameter("map_origin",view.Catalog.v(map.bounds.position))
	view.fog_material.set_shader_parameter("map_size",view.Catalog.v(map.bounds.size))
	view.fog_material.set_shader_parameter("radius",float(map.fog.radius))

func rebuild() -> void:
	view.fog_image=Image.create(1024,600,false,Image.FORMAT_RG8)
	view.fog_image.fill(Color.BLACK)
	visible_pixels.clear()
	for id: String in view.runtime.data.get("explored_cells",[]): _paint(view.runtime.hex.parse_key(id),false)
	view.fog_texture=ImageTexture.create_from_image(view.fog_image)
	view.fog_material.set_shader_parameter("explored_mask",view.fog_texture)
	sight_image=Image.create(256,1,false,Image.FORMAT_R8)
	sight_texture=ImageTexture.create_from_image(sight_image)
	view.fog_material.set_shader_parameter("sight_depth",sight_texture)
	view.last_fog_position=Vector2.INF
	update()

func update() -> void:
	view.fog_material.set_shader_parameter("player",view.runtime.player())
	if view.runtime.player().distance_to(view.last_fog_position)<24: return
	view.last_fog_position=view.runtime.player()
	view.runtime._update_hex_visibility()
	for point: Vector2i in visible_pixels: view.fog_image.set_pixelv(point,Color(1,0,0))
	visible_pixels.clear()
	var sight: PackedVector2Array=view.runtime.hex.vision_polygon(view.runtime.player(),float(view.Catalog.world().fog.radius))
	sight_image.fill(Color.BLACK)
	for index: int in sight.size():
		sight_image.set_pixel(index,0,Color(sight[index].distance_to(view.runtime.player())/float(view.Catalog.world().fog.radius),0,0))
	sight_texture.update(sight_image)
	view.fog_material.set_shader_parameter("sight_origin",view.runtime.player())
	if sight.size()>=3:
		var origin: Vector2=view.Catalog.v(view.Catalog.world().bounds.position)
		var scale: Vector2=Vector2(view.fog_image.get_size())/view.Catalog.v(view.Catalog.world().bounds.size)
		var radius := float(view.Catalog.world().fog.radius)
		var first := Vector2i(((view.runtime.player()-Vector2.ONE*radius-origin)*scale).floor()).max(Vector2i.ZERO)
		var last := Vector2i(((view.runtime.player()+Vector2.ONE*radius-origin)*scale).ceil()).min(view.fog_image.get_size()-Vector2i.ONE)
		for x: int in range(first.x,last.x+1):
			for y: int in range(first.y,last.y+1):
				if Geometry2D.is_point_in_polygon(origin+(Vector2(x,y)+Vector2.ONE*0.5)/scale,sight):
					var point := Vector2i(x,y)
					view.fog_image.set_pixelv(point,Color(1,1,0))
					visible_pixels.append(point)
	view.fog_texture.update(view.fog_image)

func _paint(coordinate: Vector2i, visible: bool) -> void:
	if not cell_pixels.has(coordinate):
		var points: PackedVector2Array=view.runtime.hex.polygon(coordinate)
		var map: Dictionary=view.Catalog.world()
		var origin: Vector2=view.Catalog.v(map.bounds.position)
		var scale: Vector2=Vector2(view.fog_image.get_size())/view.Catalog.v(map.bounds.size)
		var bounds := Rect2(points[0],Vector2.ZERO)
		for point: Vector2 in points: bounds=bounds.expand(point)
		var first := Vector2i(((bounds.position-origin)*scale).floor()).max(Vector2i.ZERO)
		var last := Vector2i(((bounds.end-origin)*scale).ceil()).min(view.fog_image.get_size()-Vector2i.ONE)
		var pixels: Array[Vector2i] = []
		for x: int in range(first.x,last.x+1):
			for y: int in range(first.y,last.y+1):
				if Geometry2D.is_point_in_polygon(origin+(Vector2(x,y)+Vector2.ONE*0.5)/scale,points): pixels.append(Vector2i(x,y))
		cell_pixels[coordinate]=pixels
	for point: Vector2i in cell_pixels[coordinate]:
		view.fog_image.set_pixelv(point,Color(1,1 if visible else 0,0))
		if visible: visible_pixels.append(point)
