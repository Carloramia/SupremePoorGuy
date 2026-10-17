class_name WorldMapTerrainLayer
extends TileMapLayer

var definition: WorldMapDefinition
var debug_overlay: WorldMapHexDebugOverlay
var show_hex_debug: bool = false:
	set(value):
		show_hex_debug = value
		if is_instance_valid(debug_overlay):
			debug_overlay.visible = value

func build(map_definition: WorldMapDefinition) -> void:
	definition = map_definition
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# The TileMapLayer is a visual projection only; stable identities remain axial.
	var size := Vector2i(roundi(definition.hex_size * 2), roundi(sqrt(3.0) * definition.hex_size))
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var vertices := HexMath.polygon(Vector2(size) * 0.5, definition.hex_size + 1.0)
	for x in size.x:
		for y in size.y:
			if Geometry2D.is_point_in_polygon(Vector2(x, y), vertices):
				image.set_pixel(x, y, Color("466453"))
	var atlas := TileSetAtlasSource.new()
	atlas.texture = ImageTexture.create_from_image(image)
	atlas.texture_region_size = size
	atlas.create_tile(Vector2i.ZERO)
	var tiles := TileSet.new()
	tiles.tile_size = size
	tiles.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	tiles.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	tiles.tile_layout = TileSet.TILE_LAYOUT_STACKED
	tiles.add_source(atlas, 0)
	tile_set = tiles
	# TileMap centers start at half a tile. Normalize that offset and the integer
	# texture height so the visual projection matches exact axial world coordinates.
	scale = Vector2(definition.hex_size * 2.0 / size.x, sqrt(3.0) * definition.hex_size / size.y)
	position = -map_to_local(Vector2i.ZERO) * scale
	# TileMapLayer draws tiles in internal child items above its own _draw commands.
	# A separate CanvasItem above terrain and fog keeps debug geometry visible.
	debug_overlay = WorldMapHexDebugOverlay.new()
	debug_overlay.name = "HexDebugOverlay"
	debug_overlay.definition = definition
	debug_overlay.transform = transform.affine_inverse()
	debug_overlay.z_index = 6
	debug_overlay.visible = show_hex_debug
	add_child(debug_overlay)
	for hex in definition.enabled_cells():
		var cell := HexMath.axial_to_cell(hex)
		set_cell(cell, 0, Vector2i.ZERO)
	queue_redraw()

func _draw() -> void:
	if not definition:
		return
	# Low-cost landmarks, no Hex Nodes.
	for hex in definition.enabled_cells():
		var center := map_to_local(HexMath.axial_to_cell(hex))
		var hash_value := absi(hex.x * 73856093 ^ hex.y * 19349663)
		if hash_value % 5 == 0:
			draw_circle(center + Vector2(-15, 8), 6, Color(0.2, 0.35, 0.27, 0.5))
			draw_circle(center + Vector2(-11, 2), 9, Color(0.23, 0.4, 0.31, 0.7))
