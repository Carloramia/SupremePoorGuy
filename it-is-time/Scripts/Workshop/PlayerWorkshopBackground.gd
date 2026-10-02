@tool
extends CanvasLayer

## Builds a repeating TileMapLayer background for the workshop canvas.
@export_group("Grid Background")
@export_range(8, 256, 1, "or_greater") var grid_size: int = 64
@export_range(1, 8, 1, "or_greater") var line_width: int = 1
@export var background_color: Color = Color("4b4f55")
@export var grid_color: Color = Color("9da3aa")

@export_group("Canvas Navigation")
@export_range(0.1, 1.0, 0.05) var minimum_zoom: float = 0.25
@export_range(1.0, 8.0, 0.05) var maximum_zoom: float = 4.0
@export_range(1.01, 2.0, 0.01) var zoom_step: float = 1.15

@onready var _workspace_content: Node2D = $WorkspaceContent
@onready var _grid: TileMapLayer = $WorkspaceContent/GridBackground
@onready var _material_grid: TileMapLayer = $WorkspaceContent/MaterialGrid
@onready var _grid_input: Control = $GridInput
@onready var _right_panel: Control = $WorkshopRightpanel
@onready var _build_button: Button = $WorkshopBuildButton
@onready var _material_cursor_preview: TextureRect = $MaterialCursorPreview

const TEST_MATERIAL_ID: StringName = &"TestMaterial"
const TEST_MATERIAL_TEXTURE: Texture2D = preload("res://Assets/2DResources/Samples/WhiteCube.png")

var _selected_material: StringName = &""
var _middle_dragging: bool = false

signal weapon_build_requested(material_cells: Array[Vector2i])

func _ready() -> void:
	_build_tileset()
	_build_material_tileset()
	_fill_visible_area()
	_grid_input.gui_input.connect(_on_grid_gui_input)
	_right_panel.connect(&"material_selected", _on_material_selected)
	_build_button.connect(&"build_requested", _on_build_requested)
	_build_button.call(&"set_build_available", false)
	if not get_viewport().size_changed.is_connected(_fill_visible_area):
		get_viewport().size_changed.connect(_fill_visible_area)

func _process(_delta: float) -> void:
	if not is_instance_valid(_material_cursor_preview):
		return
	_material_cursor_preview.visible = not _selected_material.is_empty()
	if _material_cursor_preview.visible:
		_material_cursor_preview.position = get_viewport().get_mouse_position() + Vector2(14.0, 14.0)

func _input(event: InputEvent) -> void:
	# Always release the drag state, even if the pointer is over another Control.
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE
		and not (event as InputEventMouseButton).pressed
	):
		_middle_dragging = false

func _on_grid_gui_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_MIDDLE:
			_middle_dragging = mouse_event.pressed
			_grid_input.accept_event()
			return
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mouse_event.position, zoom_step)
			_grid_input.accept_event()
			return
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mouse_event.position, 1.0 / zoom_step)
			_grid_input.accept_event()
			return
		if (
			mouse_event.button_index == MOUSE_BUTTON_LEFT
			and mouse_event.pressed
			and not _selected_material.is_empty()
		):
			place_selected_material_at_screen_position(mouse_event.position)
			_grid_input.accept_event()
	elif event is InputEventMouseMotion and _middle_dragging:
		var motion_event := event as InputEventMouseMotion
		_workspace_content.position += motion_event.relative
		_fill_visible_area()
		_grid_input.accept_event()

func _zoom_at(screen_position: Vector2, factor: float) -> void:
	var old_zoom := _workspace_content.scale.x
	var new_zoom := clampf(old_zoom * factor, minimum_zoom, maximum_zoom)
	if is_equal_approx(old_zoom, new_zoom):
		return
	var local_anchor := _workspace_content.to_local(screen_position)
	_workspace_content.scale = Vector2.ONE * new_zoom
	_workspace_content.position += screen_position - _workspace_content.to_global(local_anchor)
	_fill_visible_area()

func get_canvas_offset() -> Vector2:
	return _workspace_content.position

func get_canvas_zoom() -> float:
	return _workspace_content.scale.x

func _build_tileset() -> void:
	var size := maxi(grid_size, 1)
	var stroke := clampi(line_width, 1, size)
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(background_color)

	# Drawing only the top and left edges produces one clean line per repeated tile.
	for offset in stroke:
		for coordinate in size:
			image.set_pixel(coordinate, offset, grid_color)
			image.set_pixel(offset, coordinate, grid_color)

	var texture := ImageTexture.create_from_image(image)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(size, size)
	atlas.create_tile(Vector2i.ZERO)

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(size, size)
	tile_set.add_source(atlas, 0)
	_grid.tile_set = tile_set

func _build_material_tileset() -> void:
	var size := maxi(grid_size, 1)
	var inset := clampi(line_width, 1, maxi(size / 4, 1))
	var source_image := TEST_MATERIAL_TEXTURE.get_image()
	if source_image.is_compressed():
		source_image.decompress()
	source_image.convert(Image.FORMAT_RGBA8)
	source_image.resize(size - inset * 2, size - inset * 2, Image.INTERPOLATE_NEAREST)
	var tile_image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	tile_image.fill(Color.TRANSPARENT)
	tile_image.blit_rect(source_image, source_image.get_used_rect(), Vector2i(inset, inset))
	var texture := ImageTexture.create_from_image(tile_image)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = texture
	atlas.texture_region_size = Vector2i(size, size)
	atlas.create_tile(Vector2i.ZERO)
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(size, size)
	tile_set.add_source(atlas, 0)
	_material_grid.tile_set = tile_set

func _on_material_selected(material_id: StringName) -> void:
	_selected_material = material_id

func place_selected_material_at_screen_position(screen_position: Vector2) -> bool:
	if _selected_material != TEST_MATERIAL_ID or _material_grid.tile_set == null:
		return false
	var local_position := _material_grid.to_local(screen_position)
	var cell := _material_grid.local_to_map(local_position)
	_material_grid.set_cell(cell, 0, Vector2i.ZERO)
	_build_button.call(&"set_build_available", true)
	return true

func get_selected_material() -> StringName:
	return _selected_material

func has_material_at_cell(cell: Vector2i) -> bool:
	return _material_grid.get_cell_source_id(cell) == 0

func get_placed_material_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _material_grid.get_used_cells():
		if has_material_at_cell(cell):
			cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return cells

func _on_build_requested() -> void:
	var cells := get_placed_material_cells()
	if cells.is_empty():
		return
	weapon_build_requested.emit(cells)

func _fill_visible_area() -> void:
	if not is_instance_valid(_grid) or _grid.tile_set == null:
		return

	_grid.clear()
	var viewport_rect := get_viewport().get_visible_rect()
	var top_left := _grid.local_to_map(_grid.to_local(viewport_rect.position))
	var bottom_right := _grid.local_to_map(_grid.to_local(viewport_rect.end))
	var minimum := Vector2i(
		mini(top_left.x, bottom_right.x) - 2,
		mini(top_left.y, bottom_right.y) - 2
	)
	var maximum := Vector2i(
		maxi(top_left.x, bottom_right.x) + 2,
		maxi(top_left.y, bottom_right.y) + 2
	)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			_grid.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
