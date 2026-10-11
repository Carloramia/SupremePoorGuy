@tool
extends Control
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
signal changed
signal notice(text: String)
var rules = Rules.new()
var selected_relic: String = ""
var hovered: Array = []
var drawing := false
var freehand := false
@export var read_only := false
@export var preview_path: Array = []
var last_pointer := Vector2.ZERO
@export_group("Artwork")
@export var board_texture: Texture2D
@export var board_color := Color("27231f")
@export var rim_color := Color("bd7d32")
@export var empty_cell_color := Color("e6d6b8")

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	resized.connect(queue_redraw)
	set_process(true)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if drawing and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		drawing = false

func scale_unit() -> float:
	return minf(size.x/16.8,size.y/15.5)

func point(cell: Array) -> Vector2:
	return size*0.5 + scale_unit()*Vector2(sqrt(3.0)*(float(cell[0])+float(cell[1])/2.0),1.5*float(cell[1]))

func cell_at(p: Vector2) -> Array:
	var best: Array = []
	var minimum := scale_unit()*0.92
	for cell in Rules.cells():
		var d := p.distance_to(point(cell))
		if d < minimum:
			minimum = d
			best = cell
	return best

func polygon(cell: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in 6:
		p.append(point(cell)+Vector2(cos(deg_to_rad(i*60-30)),sin(deg_to_rad(i*60-30)))*scale_unit()*0.91)
	return p

func _draw() -> void:
	if read_only:
		_draw_preview()
		return
	var radius := scale_unit()*7.3
	if board_texture != null:
		draw_texture_rect(board_texture,Rect2(Vector2.ZERO,size),false)
	else:
		draw_circle(size*0.5,radius,board_color)
		draw_arc(size*0.5,radius,0,TAU,96,rim_color,3,true)
	for cell in Rules.cells():
		var color := empty_cell_color
		var owner := rules.owner_at(cell)
		if not owner.is_empty():
			var d := Rules.definition(owner.get("runeId",owner.get("relicId","")),owner.has("relicId"))
			color = Color(d.get("color","aaaaaa"))
			if not owner.get("enabled",true):
				color = color.darkened(0.65)
		if cell in rules.draft:
			color = Color("f1bc67")
		if cell == hovered and owner.is_empty():
			color = color.lightened(0.2)
		var poly := polygon(cell)
		draw_colored_polygon(poly,color)
		poly.append(poly[0])
		draw_polyline(poly,Color("75624c"),1,true)
	for item in rules.placed:
		_stroke(item.cells,Color("27231f"),3)
	_stroke(rules.draft,Color("fff3d2"),4)
	_stroke(preview_path,Color("fff3d2"),4)
	if not selected_relic.is_empty() and not hovered.is_empty():
		var preview := rules.preview_relic(selected_relic,hovered)
		for cell in preview.cells:
			draw_colored_polygon(polygon(cell),Color(0.2,0.85,0.7,0.65) if preview.valid else Color(0.9,0.25,0.2,0.65))

func _draw_preview() -> void:
	if preview_path.is_empty():
		return
	var points := PackedVector2Array()
	for cell in preview_path:
		points.append(Vector2(sqrt(3.0)*(float(cell[0])+float(cell[1])*0.5),float(cell[1])*1.5))
	var bounds := Rect2(points[0],Vector2.ZERO)
	for p in points:
		bounds = bounds.expand(p)
	var unit := minf(size.x/(bounds.size.x+2.2),size.y/(bounds.size.y+2.2))
	var shifted := PackedVector2Array()
	for p in points:
		var at := size*0.5+(p-bounds.get_center())*unit
		shifted.append(at)
		var poly := PackedVector2Array()
		for i in 6:
			poly.append(at+Vector2(cos(deg_to_rad(i*60-30)),sin(deg_to_rad(i*60-30)))*unit*0.85)
		draw_colored_polygon(poly,Color("94513f"))
		poly.append(poly[0])
		draw_polyline(poly,Color("bd7d32"),1,true)
	if shifted.size()>1:
		draw_polyline(shifted,Color("fff3d2"),2,true)

func _stroke(path: Array, color: Color, width: float) -> void:
	if path.size() < 2:
		return
	var points := PackedVector2Array()
	for cell in path:
		points.append(point(cell))
	draw_polyline(points,color,width,true)

func _gui_input(event: InputEvent) -> void:
	if read_only:
		return
	if event is InputEventMouseMotion:
		hovered = cell_at(event.position)
		if drawing:
			if freehand:
				for step in 16:
					var sample := cell_at(last_pointer.lerp(event.position,float(step+1)/16))
					if not sample.is_empty():
						rules.extend(sample)
			elif not hovered.is_empty():
				rules.extend(hovered)
			changed.emit()
		last_pointer = event.position
		queue_redraw()
	if event is InputEventMouseButton:
		var cell := cell_at(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			drawing = event.pressed and selected_relic.is_empty()
			last_pointer = event.position
			if event.pressed and not cell.is_empty():
				if not selected_relic.is_empty():
					if rules.place_relic(selected_relic,cell):
						selected_relic = ""
					else:
						notice.emit("无法放置：越界、占格冲突或同名奇物已在阵中")
				elif not rules.extend(cell):
					if not rules.owner_at(cell).is_empty():
						notice.emit("此格已占用；请在已刻入列表中停用、删除或回收")
					else:
						notice.emit("请从笔画末端的相邻空格继续，或先取消笔画")
			changed.emit()
			queue_redraw()
			accept_event()

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or not data.has("relic"):
		return false
	selected_relic = data.relic
	hovered = cell_at(at_position)
	queue_redraw()
	return not hovered.is_empty() and rules.preview_relic(selected_relic,hovered).valid

func _drop_data(at_position: Vector2, data: Variant) -> void:
	rules.place_relic(data.relic,cell_at(at_position))
	selected_relic = ""
	changed.emit()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		selected_relic = ""
		queue_redraw()
