extends Node2D
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
const SIGHT = preload("res://Scripts/Application/HexMapSight.gd")
var map: Dictionary
var objects: Node2D
var background_node: Node2D
var _textures := {}
var _tiles: Array = []
var _detailed := false
var _faces: Node2D
var _face_materials := {}
var _surfaces := {}
var _last_face_position := Vector2.INF

func _ready() -> void:
	map=CATALOG.world()
	background_node=Node2D.new()
	background_node.name="Background"
	background_node.z_index=-900
	add_child(background_node)
	background_node.draw.connect(_draw_background)
	objects=Node2D.new()
	objects.name="Objects"
	add_child(objects)
	for object: Dictionary in map.objects:
		var holder := Node2D.new()
		holder.name=object.id
		holder.position=CATALOG.v(object.position)
		holder.z_index=int(object.visual.get("z_index",0))
		objects.add_child(holder)
		if object.type=="road": continue
		_add_art(holder,object.source_visual,"Visual")
		for layer: Dictionary in object.source_visual.get("layers",[]): _add_art(holder,layer,"Layer"+str(holder.get_child_count()))
	preload("res://Scripts/Application/HexMapPresentation.gd").install_landmark_bases(self,map.objects)
	for spec: Dictionary in map.get("mountain_surfaces",[]):
		var holder := objects.get_node(NodePath(spec.id)) as Node2D
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		var shadow_spec: Dictionary=spec.get("seam_shadow",{})
		var points: Array=shadow_spec.get("triangles",[])
		for index: int in range(0,points.size(),2):
			vertices.append(Vector3(points[index]-holder.position.x,points[index+1]-holder.position.y,0))
			colors.append(Color(shadow_spec.color))
		if not vertices.is_empty():
			var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_COLOR]=colors
			var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			var shadow := MeshInstance2D.new(); shadow.name="BlackSeamShadow"; shadow.mesh=mesh; shadow.z_index=-1
			holder.add_child(shadow)
		_surfaces[spec.id]=spec
	background_node.queue_redraw()

func _add_art(parent: Node2D, visual: Dictionary, title: String) -> void:
	var asset: Dictionary=CATALOG.index().assets.get(visual.get("asset_id",""),{})
	if asset.is_empty(): return
	var sprite := Sprite2D.new()
	sprite.name=title
	sprite.texture=load(asset.get("render_path",asset.path)) as Texture2D
	if sprite.texture==null: sprite.free(); return
	var width := float(visual.get("width",asset.width))
	var height := width*float(asset.height)/float(asset.width)*float(visual.get("height_scale",1))
	sprite.scale=Vector2(width,height)/sprite.texture.get_size()
	sprite.offset=(Vector2.ONE*0.5-CATALOG.v(visual.get("anchor",asset.get("anchor",[0.5,1]))))*sprite.texture.get_size()
	sprite.position=CATALOG.v(visual.get("offset",[0,0]))
	sprite.rotation_degrees=float(visual.get("rotation",0))
	sprite.z_index=int(visual.get("z_index",0)) if title!="Visual" else 0
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	parent.add_child(sprite)

func refresh(runtime: RefCounted) -> void:
	for object: Dictionary in map.objects:
		var holder := objects.get_node(NodePath(object.id)) as Node2D
		holder.visible=(object.id not in runtime.data.destroyed) and runtime.object_visible(object)
	_last_face_position=Vector2.INF

func update_fog_view(view: Control, fog_texture: Texture2D) -> void:
	if _faces==null:
		_faces=Node2D.new(); _faces.name="VisibleMountainFaces"; _faces.z_index=1000
		view.world_canvas.add_child(_faces)
		for id: String in _surfaces:
			var copy := objects.get_node(NodePath(id)).duplicate() as Node2D
			copy.z_index=0
			_faces.add_child(copy)
			var material := ShaderMaterial.new(); var shader := Shader.new()
			shader.code=SIGHT.surface_shader(); material.shader=shader
			material.set_shader_parameter("radius",float(map.fog.radius))
			material.set_shader_parameter("map_origin",CATALOG.v(map.bounds.position))
			material.set_shader_parameter("fog_texture",fog_texture)
			material.set_shader_parameter("fog_texture_available",true)
			var mask_spec: Dictionary=_surfaces[id].get("rear_edge_mask",{})
			if not mask_spec.is_empty():
				var image := Image.new()
				if image.load_png_from_buffer(Marshalls.base64_to_raw(mask_spec.png))==OK:
					material.set_shader_parameter("rear_mask",ImageTexture.create_from_image(image))
					var b: Array=mask_spec.bounds
					material.set_shader_parameter("rear_bounds",Vector4(b[0],b[1],b[2],b[3]))
					material.set_shader_parameter("rear_distance_scale",float(mask_spec.distance_scale))
					material.set_shader_parameter("rear_mask_enabled",true)
			for child: Node in copy.get_children():
				if child is Sprite2D or child is MeshInstance2D: child.material=material
			_face_materials[id]=material
	_faces.transform=transform
	_faces.visible=view.draw_fog and bool(map.fog.enabled)
	for material: ShaderMaterial in _face_materials.values():
		material.set_shader_parameter("view_size",view.size)
		material.set_shader_parameter("camera",view.camera)
		material.set_shader_parameter("zoom",view.zoom)
		material.set_shader_parameter("player",view.runtime.player())
	if view.runtime.player().distance_to(_last_face_position)<16: return
	_last_face_position=view.runtime.player()
	var radius := float(map.fog.radius)
	var occluders: Array=view.runtime.hex.sight_occluders(_last_face_position,_last_face_position,radius)
	for surface: Dictionary in view.runtime.hex.art_surfaces:
		var in_sight := false
		for ring: PackedVector2Array in surface._rings:
			for index: int in ring.size():
				var near := Geometry2D.get_closest_point_to_segment(_last_face_position,ring[index],ring[(index+1)%ring.size()])
				if near.distance_to(_last_face_position)<radius-12 and SIGHT.visible(_last_face_position,near.move_toward(_last_face_position,2),occluders):
					in_sight=true; break
			if in_sight: break
		_faces.get_node(NodePath(surface.site_id)).visible=in_sight

func update_view(rect: Rect2, zoom: float) -> void:
	_detailed=float(map.background.size[0])*zoom>2764.8
	_tiles.clear()
	var wanted := {str(map.background.asset):true}
	if _detailed:
		for tile: Dictionary in map.background.source_tiles.tiles:
			var draw_rect := _tile_rect(tile)
			if not rect.grow(200).intersects(draw_rect): continue
			_tiles.append(tile)
			wanted[str(tile.path)]=true
			wanted[str(tile.clipped_path)]=true
	# Hold only visible tiles, so viewing the full world never allocates the full master canvas.
	for path: String in _textures.keys():
		if not wanted.has(path): _textures.erase(path)
	for path: String in wanted:
		if not _textures.has(path): _textures[path]=ResourceLoader.load(path,"Texture2D",ResourceLoader.CACHE_MODE_IGNORE)
	background_node.queue_redraw()

func _tile_rect(tile: Dictionary) -> Rect2:
	var pixels := CATALOG.v(map.background.source_tiles.pixel_size)
	var scale := CATALOG.v(map.background.size)/pixels
	return Rect2(CATALOG.v(map.background.position)+(Vector2(float(tile.rect[0]),float(tile.rect[1]))+CATALOG.v(tile.get("offset",[0,0])))*scale,Vector2(float(tile.rect[2]),float(tile.rect[3]))*scale)

func _draw_background() -> void:
	if map.is_empty(): return
	var overview: Texture2D=_textures.get(str(map.background.asset))
	if overview!=null: background_node.draw_texture_rect(overview,Rect2(CATALOG.v(map.background.position),CATALOG.v(map.background.size)),false)
	if not _detailed: return
	# Raw underpaint avoids seams; even-odd masks retain the authored holes and overlap order.
	for clipped: bool in [false,true]:
		for tile: Dictionary in _tiles:
			var texture: Texture2D=_textures.get(str(tile.clipped_path if clipped else tile.path))
			if texture!=null: background_node.draw_texture_rect(texture,_tile_rect(tile),false)
