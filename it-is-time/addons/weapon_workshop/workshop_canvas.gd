@tool
extends Control

signal edit_started
signal edited
var layout: WeaponLayout
var mode := 0
var zoom := 1.0
var offset := Vector2.ZERO
var _drawing := false
var _erasing := false
var _panning := false
const CELL := 32.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	resized.connect(queue_redraw)

func pivot() -> Vector2:
	if layout.attachment_is_set: return layout.attachment
	var sum := Vector2.ZERO
	for cell: Vector2i in layout.cells: sum += Vector2(cell)
	return sum/maxi(layout.cells.size(),1)

func grid_to_screen(point: Vector2) -> Vector2:
	return size*0.5+offset+(point-pivot()).rotated(layout.rotation_radians)*CELL*zoom

func screen_to_grid(point: Vector2) -> Vector2:
	return pivot()+((point-size*0.5-offset)/(CELL*zoom)).rotated(-layout.rotation_radians)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color(0.23,0.23,0.25))
	if layout == null: return
	var low := Vector2(INF,INF)
	var high := -low
	for point: Vector2 in [Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)]:
		var grid := screen_to_grid(point)
		low = low.min(grid); high = high.max(grid)
	for x: int in range(int(floor(low.x))-1,int(ceil(high.x))+2):
		draw_line(grid_to_screen(Vector2(x-0.5,low.y-1)),grid_to_screen(Vector2(x-0.5,high.y+1)),Color(0.45,0.45,0.48),1)
	for y: int in range(int(floor(low.y))-1,int(ceil(high.y))+2):
		draw_line(grid_to_screen(Vector2(low.x-1,y-0.5)),grid_to_screen(Vector2(high.x+1,y-0.5)),Color(0.45,0.45,0.48),1)
	var texture: Texture2D = layout.material.get_display_texture() if layout.material != null else null
	for cell: Vector2i in layout.cells:
		draw_set_transform(grid_to_screen(Vector2(cell)),layout.rotation_radians,Vector2.ONE*zoom)
		var rect := Rect2(Vector2.ONE*(-CELL*0.5),Vector2.ONE*CELL)
		if texture != null: draw_texture_rect(texture,rect,false)
		else: draw_rect(rect,Color.WHITE)
	draw_set_transform(Vector2.ZERO)
	if layout.attachment_is_set:
		var grip := grid_to_screen(layout.attachment)
		draw_circle(grip,8,Color(0.2,0.8,1,0.4))
		draw_line(grip-Vector2(12,0),grip+Vector2(12,0),Color.CYAN,2)
		draw_line(grip-Vector2(0,12),grip+Vector2(0,12),Color.CYAN,2)

func _gui_input(event: InputEvent) -> void:
	if layout == null: return
	if event is InputEventMouseButton:
		grab_focus()
		if event.button_index == MOUSE_BUTTON_MIDDLE: _panning = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var point := screen_to_grid(event.position)
			zoom = clampf(zoom*(1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0/1.15),0.15,5.0)
			offset += event.position-grid_to_screen(point)
		elif event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			_drawing = event.pressed
			_erasing = event.button_index == MOUSE_BUTTON_RIGHT or mode == 1
			if event.pressed:
				edit_started.emit()
				_edit_at(event.position)
		accept_event()
	elif event is InputEventMouseMotion:
		if _panning: offset += event.relative
		elif _drawing: _edit_at(event.position)
		accept_event()
	queue_redraw()

func _edit_at(point: Vector2) -> void:
	var grid := screen_to_grid(point)
	if mode == 2 and not _erasing:
		# Changing the pivot must not move the existing material layout on screen.
		layout.attachment = grid
		layout.attachment_is_set = true
		offset = point-size*0.5
	else:
		var cell := Vector2i(roundi(grid.x),roundi(grid.y))
		var old_pivot := pivot()
		if _erasing:
			if not layout.cells.has(cell): return
			layout.cells.erase(cell)
		elif not layout.cells.has(cell): layout.cells.append(cell)
		else: return
		offset += (pivot()-old_pivot).rotated(layout.rotation_radians)*CELL*zoom
	edited.emit()
	queue_redraw()
