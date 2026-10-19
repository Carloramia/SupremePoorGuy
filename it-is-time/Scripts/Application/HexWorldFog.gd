extends RefCounted
const SIGHT = preload("res://Scripts/Application/HexMapSight.gd")
var view: Control
var buffer: SubViewport
var canvas: ColorRect
var visible_pixels: Array[Vector2i] = []
var cell_pixels := {}
var sight_image: Image
var sight_texture: ImageTexture

func create(owner_view: Control) -> void:
	view=owner_view
	buffer=SubViewport.new()
	buffer.name="PixelFogBuffer"
	buffer.disable_3d=true
	buffer.transparent_bg=true
	buffer.world_2d=World2D.new()
	view.world_canvas.add_child(buffer)
	canvas=ColorRect.new()
	buffer.add_child(canvas)
	view.fog_rect=TextureRect.new()
	view.fog_rect.texture=buffer.get_texture()
	view.fog_rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	view.fog_rect.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	view.fog_rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	view.fog_rect.z_index=1000
	view.world_canvas.add_child(view.fog_rect)
	view.fog_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code=SIGHT.fog_shader()
	view.fog_material=ShaderMaterial.new()
	view.fog_material.shader=shader
	canvas.material=view.fog_material
	var map: Dictionary=view.Catalog.world()
	view.fog_material.set_shader_parameter("map_origin",view.Catalog.v(map.bounds.position))
	view.fog_material.set_shader_parameter("map_size",view.Catalog.v(map.bounds.size))
	view.fog_material.set_shader_parameter("radius",float(map.fog.radius))
	view.fog_material.set_shader_parameter("feather",clampf(float(map.fog.radius)*.14,48,110))

func rebuild() -> void:
	view.fog_image=Image.create(1024,600,false,Image.FORMAT_RG8)
	view.fog_image.fill(Color.BLACK)
	visible_pixels.clear()
	for id: String in view.runtime.data.get("explored_cells",[]): _paint(view.runtime.hex.parse_key(id),false)
	view.fog_texture=ImageTexture.create_from_image(view.fog_image)
	view.fog_material.set_shader_parameter("explored_mask",view.fog_texture)
	sight_image=Image.create(256,1,false,Image.FORMAT_RG8)
	sight_texture=ImageTexture.create_from_image(sight_image)
	view.fog_material.set_shader_parameter("sight_rays",sight_texture)
	view.last_fog_position=Vector2.INF
	update()

func update() -> void:
	resize()
	view.fog_material.set_shader_parameter("player",view.runtime.player())
	if view.runtime.player().distance_to(view.last_fog_position)<24: return
	view.last_fog_position=view.runtime.player()
	view.runtime._update_hex_visibility()
	for point: Vector2i in visible_pixels: view.fog_image.set_pixelv(point,Color(1,0,0))
	visible_pixels.clear()
	var radius := float(view.Catalog.world().fog.radius)
	var occluders: Array=view.runtime.hex.sight_occluders(view.runtime.player(),view.runtime.player(),radius)
	SIGHT.update_rays(sight_image,view.runtime.player(),radius,occluders)
	sight_texture.update(sight_image)
	view.fog_material.set_shader_parameter("sight_origin",view.runtime.player())
	var origin: Vector2=view.Catalog.v(view.Catalog.world().bounds.position)
	var scale: Vector2=Vector2(view.fog_image.get_size())/view.Catalog.v(view.Catalog.world().bounds.size)
	var first := Vector2i(((view.runtime.player()-Vector2.ONE*radius-origin)*scale).floor()).max(Vector2i.ZERO)
	var last := Vector2i(((view.runtime.player()+Vector2.ONE*radius-origin)*scale).ceil()).min(view.fog_image.get_size()-Vector2i.ONE)
	for x: int in range(first.x,last.x+1):
		for y: int in range(first.y,last.y+1):
			if SIGHT.surface_visible_in_rays(sight_image,view.runtime.player(),origin+(Vector2(x,y)+Vector2.ONE*0.5)/scale,radius):
				var point := Vector2i(x,y)
				view.fog_image.set_pixelv(point,Color(1,1,0))
				visible_pixels.append(point)
	view.fog_texture.update(view.fog_image)

func resize() -> void:
	buffer.size=Vector2i((view.size/3.0).ceil()).max(Vector2i.ONE)
	canvas.size=Vector2(buffer.size)
	buffer.render_target_update_mode=SubViewport.UPDATE_ALWAYS if view.mode=="world" and view.draw_fog else SubViewport.UPDATE_DISABLED
	view.world_scene.update_fog_view(view,buffer.get_texture())

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
