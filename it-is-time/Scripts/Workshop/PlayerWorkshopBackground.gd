@tool
extends CanvasLayer

const PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")

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
@export_range(1.0, 360.0, 1.0, "or_greater") var workspace_rotation_speed_degrees: float = 30.0

@onready var _workspace_content: Node2D = $WorkspaceContent
@onready var _grid: TileMapLayer = $WorkspaceContent/GridBackground
@onready var _material_grid: TileMapLayer = $WorkspaceContent/MaterialGrid
@onready var _grid_input: Control = $GridInput
@onready var _right_panel: Control = $WorkshopRightpanel
@onready var _build_button: Button = $WorkshopBuildButton
@onready var _material_cursor_preview: TextureRect = $MaterialCursorPreview
@onready var _holder_cursor_preview: TextureRect = $HolderCursorPreview
@onready var _attachment_preview: Sprite2D = $AttachmentPreview
@onready var _attachment_point_marker: Node2D = $AttachmentPointMarker
@onready var _status_label: Label = $StatusLabel

const TEST_MATERIAL: Resource = preload("res://Resources/Materials/TestMaterial.tres")

var _selected_material: StringName = &""
var _selected_holder_name: StringName = &""
var _selected_holder_texture: Texture2D
var _selected_holder_preview_size: Vector2 = Vector2.ONE * TEST_MATERIAL.cell_size
var _selected_holder_center_from_socket: Vector2 = Vector2.ZERO
var _attachment_holder_name: StringName = &""
var _attachment_holder_preview_size: Vector2 = Vector2.ONE * TEST_MATERIAL.cell_size
var _attachment_holder_center_from_socket: Vector2 = Vector2.ZERO
var _attachment_canvas_position: Vector2 = Vector2.ZERO
var _attachment_is_set: bool = false
var _rotate_left_pressed: bool = false
var _rotate_right_pressed: bool = false
var _middle_dragging: bool = false

signal weapon_build_requested(
	material_cells: Array[Vector2i],
	attachment_canvas_position: Vector2,
	attachment_grid_position: Vector2,
	item_rotation: float,
	holder_name: StringName
)

func _ready() -> void:
	_material_cursor_preview.texture = TEST_MATERIAL.icon
	_build_tileset()
	_build_material_tileset()
	_fill_visible_area()
	_grid_input.gui_input.connect(_on_grid_gui_input)
	_right_panel.connect(&"material_selected", _on_material_selected)
	_right_panel.connect(&"holder_selected", _on_holder_selected)
	_right_panel.call(&"configure_holders", _get_holder_options())
	_build_button.connect(&"build_requested", _on_build_requested)
	_build_button.call(&"set_build_available", false)
	if not get_viewport().size_changed.is_connected(_fill_visible_area):
		get_viewport().size_changed.connect(_fill_visible_area)

func _process(delta: float) -> void:
	var rotation_direction := float(int(_rotate_right_pressed) - int(_rotate_left_pressed))
	if not is_zero_approx(rotation_direction):
		_rotate_workspace(
			rotation_direction * deg_to_rad(workspace_rotation_speed_degrees) * delta
		)
	if not is_instance_valid(_material_cursor_preview):
		return
	_material_cursor_preview.visible = not _selected_material.is_empty()
	if _material_cursor_preview.visible:
		_material_cursor_preview.position = get_viewport().get_mouse_position() + Vector2(14.0, 14.0)
	_holder_cursor_preview.visible = not _selected_holder_name.is_empty()
	if _holder_cursor_preview.visible:
		_holder_cursor_preview.position = get_viewport().get_mouse_position() + Vector2(14.0, 14.0)
		_holder_cursor_preview.rotation = 0.0
	_update_attachment_preview_transform()

func _input(event: InputEvent) -> void:
	# Always release the drag state, even if the pointer is over another Control.
	if (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE
		and not (event as InputEventMouseButton).pressed
	):
		_middle_dragging = false
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.physical_keycode == KEY_Q:
			_rotate_left_pressed = key_event.pressed
			get_viewport().set_input_as_handled()
		elif key_event.physical_keycode == KEY_E:
			_rotate_right_pressed = key_event.pressed
			get_viewport().set_input_as_handled()

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
		):
			if not _selected_holder_name.is_empty():
				place_attachment_at_screen_position(mouse_event.position)
			elif not _selected_material.is_empty():
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
	var source_image: Image = TEST_MATERIAL.get_display_texture().get_image()
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
	_selected_holder_name = &""
	_selected_holder_texture = null

func _on_holder_selected(
	holder_name: StringName,
	holder_texture: Texture2D,
	holder_preview: Dictionary
) -> void:
	_selected_material = &""
	_selected_holder_name = holder_name
	_selected_holder_texture = holder_texture if holder_texture != null else TEST_MATERIAL.get_display_texture()
	_selected_holder_preview_size = holder_preview.get(
		&"preview_size",
		Vector2.ONE * TEST_MATERIAL.cell_size
	)
	_selected_holder_center_from_socket = holder_preview.get(
		&"center_from_socket",
		Vector2.ZERO
	)
	_holder_cursor_preview.texture = _selected_holder_texture
	_set_status("点击画布任意位置设置连接点；按住 Q/E 平滑旋转网格和材料。", false)

func place_selected_material_at_screen_position(screen_position: Vector2) -> bool:
	if _selected_material != TEST_MATERIAL.material_id or _material_grid.tile_set == null:
		return false
	var local_position := _material_grid.to_local(screen_position)
	var cell := _material_grid.local_to_map(local_position)
	_material_grid.set_cell(cell, 0, Vector2i.ZERO)
	_update_build_availability()
	return true

func place_attachment_at_screen_position(screen_position: Vector2) -> bool:
	if _selected_holder_name.is_empty():
		return false
	_attachment_canvas_position = _workspace_content.to_local(screen_position)
	_attachment_is_set = true
	_attachment_holder_name = _selected_holder_name
	_attachment_holder_preview_size = _selected_holder_preview_size
	_attachment_holder_center_from_socket = _selected_holder_center_from_socket
	_attachment_preview.texture = (
		_selected_holder_texture if _selected_holder_texture != null else TEST_MATERIAL.get_display_texture()
	)
	_update_attachment_preview_transform()
	_attachment_preview.visible = true
	_attachment_point_marker.visible = true
	_set_status("连接点已设置。按住 Q/E 可围绕连接点平滑旋转。", false)
	_update_build_availability()
	return true

func get_attachment_canvas_position() -> Vector2:
	return _attachment_canvas_position

func has_attachment_point() -> bool:
	return _attachment_is_set

func get_workspace_rotation() -> float:
	return _workspace_content.rotation

func get_selected_holder_name() -> StringName:
	return _selected_holder_name

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
	if not _attachment_is_set:
		_set_status("无法创建：请先在画布上设置持握连接点。", true)
		_update_build_availability()
		return
	var attachment_grid_position := _canvas_to_grid_position(_attachment_canvas_position)
	var item_rotation := -_workspace_content.rotation
	print(
		("[workshop_attachment] canvas=%s grid=%s workspace_rotation_deg=%.3f "
		+ "item_rotation_deg=%.3f holder=%s cells=%s")
		% [
			_attachment_canvas_position,
			attachment_grid_position,
			rad_to_deg(_workspace_content.rotation),
			rad_to_deg(item_rotation),
			_attachment_holder_name,
			cells,
		]
	)
	weapon_build_requested.emit(
		cells,
		_attachment_canvas_position,
		attachment_grid_position,
		item_rotation,
		_attachment_holder_name
	)

func _update_build_availability() -> void:
	var available := (
		not get_placed_material_cells().is_empty()
		and _attachment_is_set
	)
	_build_button.call(&"set_build_available", available)
	if not get_placed_material_cells().is_empty() and not available:
		_set_status("请从右侧选择持握部位，并在画布上设置连接点。", true)

func _rotate_workspace(angle_delta: float) -> bool:
	var pivot: Variant = _get_rotation_pivot()
	if pivot == null:
		_set_status("请先放置材料，再旋转工作区。", true)
		return false
	var pivot_local: Vector2 = pivot
	var fixed_canvas_position := _workspace_content.to_global(pivot_local)
	_workspace_content.rotation += angle_delta
	_workspace_content.position += fixed_canvas_position - _workspace_content.to_global(pivot_local)
	_fill_visible_area()
	_update_attachment_preview_transform()
	return true

func _get_rotation_pivot() -> Variant:
	if _attachment_is_set:
		return _attachment_canvas_position
	var cells := get_placed_material_cells()
	if cells.is_empty():
		return null
	var average := Vector2.ZERO
	for cell: Vector2i in cells:
		average += _material_grid.map_to_local(cell)
	return average / float(cells.size())

func _canvas_to_grid_position(canvas_position: Vector2) -> Vector2:
	var zero_center := _material_grid.map_to_local(Vector2i.ZERO)
	return (canvas_position - zero_center) / float(maxi(grid_size, 1))

func _update_attachment_preview_transform() -> void:
	if (
		not _attachment_is_set
		or not is_instance_valid(_attachment_preview)
		or not is_instance_valid(_attachment_point_marker)
	):
		return
	var socket_screen_position := _workspace_content.to_global(_attachment_canvas_position)
	_attachment_point_marker.position = socket_screen_position
	_attachment_point_marker.rotation = 0.0
	_attachment_preview.position = socket_screen_position
	var pixels_per_world_unit := (
		float(grid_size) / maxf(TEST_MATERIAL.cell_size, 0.001)
		* absf(_workspace_content.scale.x)
	)
	_attachment_preview.position += Vector2(
		_attachment_holder_center_from_socket.x,
		-_attachment_holder_center_from_socket.y
	) * pixels_per_world_unit
	_attachment_preview.rotation = 0.0
	var texture_size := _attachment_preview.texture.get_size()
	_attachment_preview.scale = Vector2(
		_attachment_holder_preview_size.x * pixels_per_world_unit / maxf(texture_size.x, 1.0),
		_attachment_holder_preview_size.y * pixels_per_world_unit / maxf(texture_size.y, 1.0)
	)

func _set_status(message: String, is_error: bool) -> void:
	_status_label.text = message
	_status_label.modulate = Color(1.0, 0.55, 0.55) if is_error else Color.WHITE

func _get_holder_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var character := PLAYER_CONTEXT.controlled_character(self)
	if character != null:
		for node: Node in character.find_children("*", "RigidBody3D", true, false):
			var part := node as RigidBody3D
			if not _has_body_tag(part, 2):
				continue
			var sprite: Sprite3D
			var sprites := part.find_children("*", "Sprite3D", true, false)
			if not sprites.is_empty():
				sprite = sprites[0] as Sprite3D
			var edges := Vector4(
				float(part.get(&"left_distance")),
				float(part.get(&"right_distance")),
				float(part.get(&"top_distance")),
				float(part.get(&"bottom_distance"))
			)
			var socket := part.get_node_or_null("ItemSocket3D") as Marker3D
			var socket_position := socket.position if socket != null else _get_default_socket_position(character)
			var visual_center := Vector2(
				(edges.y - edges.x) * 0.5,
				(edges.z - edges.w) * 0.5
			)
			if sprite != null:
				visual_center += Vector2(sprite.position.x, sprite.position.y)
			result.append({
				&"name": StringName(part.name),
				&"texture": sprite.texture if sprite != null else TEST_MATERIAL.get_display_texture(),
				&"preview_size": Vector2(edges.x + edges.y, edges.z + edges.w),
				&"center_from_socket": visual_center - Vector2(socket_position.x, socket_position.y),
			})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.get(&"name", &"") == &"Arm_R":
			return true
		if b.get(&"name", &"") == &"Arm_R":
			return false
		return String(a.get(&"name", &"")) < String(b.get(&"name", &""))
	)
	if result.is_empty():
		result.append({
			&"name": &"Arm_R",
			&"texture": TEST_MATERIAL.get_display_texture(),
			&"preview_size": Vector2.ONE * TEST_MATERIAL.cell_size,
			&"center_from_socket": Vector2.ZERO,
		})
	return result

func _get_default_socket_position(character: Node) -> Vector3:
	var default_socket := character.get_node_or_null("Arm_R/ItemSocket3D") as Marker3D
	return default_socket.position if default_socket != null else Vector3.ZERO

func _has_body_tag(body: RigidBody3D, required_tag: int) -> bool:
	for property: Dictionary in body.get_property_list():
		if property.name == &"tags":
			var tags: Array = body.get(&"tags")
			return tags != null and required_tag in tags
	return false

func _fill_visible_area() -> void:
	if not is_instance_valid(_grid) or _grid.tile_set == null:
		return

	_grid.clear()
	var viewport_rect := get_viewport().get_visible_rect()
	var corners: Array[Vector2] = [
		viewport_rect.position,
		Vector2(viewport_rect.end.x, viewport_rect.position.y),
		viewport_rect.end,
		Vector2(viewport_rect.position.x, viewport_rect.end.y),
	]
	var first_cell := _grid.local_to_map(_grid.to_local(corners[0]))
	var minimum := first_cell
	var maximum := first_cell
	for corner: Vector2 in corners.slice(1):
		var cell := _grid.local_to_map(_grid.to_local(corner))
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
		maximum.x = maxi(maximum.x, cell.x)
		maximum.y = maxi(maximum.y, cell.y)
	minimum -= Vector2i.ONE * 2
	maximum += Vector2i.ONE * 2
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			_grid.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
