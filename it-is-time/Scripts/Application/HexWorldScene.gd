extends Node2D
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
var map: Dictionary
var objects: Node2D
var background_node: Node2D
var _textures := {}
var _tiles: Array = []
var _detailed := false

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
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	parent.add_child(sprite)

func refresh(runtime: RefCounted) -> void:
	for object: Dictionary in map.objects:
		var holder := objects.get_node(NodePath(object.id)) as Node2D
		holder.visible=(object.id not in runtime.data.destroyed) and runtime.object_visible(object)

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
