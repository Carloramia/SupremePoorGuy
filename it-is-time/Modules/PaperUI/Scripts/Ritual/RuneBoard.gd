@tool
extends Control
const Rules = preload("res://Modules/PaperUI/Scripts/Ritual/RuneRules.gd")
signal changed
signal notice(text: String)
var rules = Rules.new()
var selected_relic: String = ""
var hovered: Array = []
var drawing := false
var freehand := false
@export var read_only := false
@export var preview_path: Array = []
@export var preview_outline_only := false
var last_pointer := Vector2.ZERO
@export_group("Artwork")
@export var board_texture: Texture2D
@export var board_color := Color(0.64, 0.49, 0.29, 0.10)
@export var rim_color := Color(0.48, 0.32, 0.17, 0.60)
@export var empty_cell_color := Color(0.93, 0.87, 0.74, 0.58)
@export_group("Array Proportions")
## Grid radius relative to the shorter board side, from 7 to 61 cells.
@export var stage_radius_ratios := PackedFloat32Array([0.22, 0.29, 0.35, 0.40])
@export_range(1.05, 1.20, 0.01) var backdrop_padding_ratio := 1.12

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
	return grid_radius()/(sqrt(3.0)*rules.stage+0.91)

func grid_radius() -> float:
	var index := clampi(rules.stage-1,0,3)
	var ratio: float = stage_radius_ratios[index] if stage_radius_ratios.size()==4 else [0.22,0.29,0.35,0.40][index]
	return minf(size.x,size.y)*clampf(ratio,0.12,0.40)

func backdrop_radius() -> float:
	return grid_radius()*backdrop_padding_ratio

func point(cell: Array) -> Vector2:
	return size*0.5 + scale_unit()*Vector2(sqrt(3.0)*(float(cell[0])+float(cell[1])/2.0),1.5*float(cell[1]))

func cell_at(p: Vector2) -> Array:
	var best: Array = []
	var minimum := scale_unit()*0.92
	for cell in Rules.cells(rules.stage):
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
	_draw_backdrop()
	for cell in Rules.cells(rules.stage):
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
		draw_polyline(poly,Color(0.43,0.33,0.22,0.62),1.1,true)
	for item in rules.placed:
		_stroke(item.cells,Color("27231f"),3)
	_stroke(rules.draft,Color("fff3d2"),4)
	_stroke(preview_path,Color("fff3d2"),4)
	if not selected_relic.is_empty() and not hovered.is_empty():
		var preview := rules.preview_relic(selected_relic,hovered)
		for cell in preview.cells:
			draw_colored_polygon(polygon(cell),Color(0.2,0.85,0.7,0.65) if preview.valid else Color(0.9,0.25,0.2,0.65))

func _draw_backdrop() -> void:
	var center := size*0.5
	var radius := backdrop_radius()
	if board_texture != null:
		# Keep the replacement illustration slightly outside the drawable grid.
		draw_texture_rect(board_texture,Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2.0),false)
		return
	draw_colored_polygon(_ink_ring(radius,0.0),board_color)
	draw_polyline(_ink_ring(radius,0.0),rim_color,1.5,true)
	var faint := Color(rim_color,rim_color.a*0.38)
	draw_polyline(_ink_ring(radius*0.96,1.2),faint,0.9,true)
	# Six small compass marks and diamonds: stable ink, no animated noise.
	for i in 6:
		var angle := i*TAU/6.0-PI/2.0
		var direction := Vector2.from_angle(angle)
		var tangent := Vector2(-direction.y,direction.x)
		var at := center+direction*radius*1.025
		var length := clampf(radius*0.028,2.5,5.0)
		draw_line(at-direction*length,at+direction*length,rim_color,1.1,true)
		var diamond := PackedVector2Array([at-direction*length,at+tangent*length*0.65,at+direction*length,at-tangent*length*0.65,at-direction*length])
		draw_polyline(diamond,faint,0.9,true)

func _ink_ring(radius: float, phase: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in 97:
		var angle := float(i%96)*TAU/96.0
		var uneven := 1.0+0.0035*sin(angle*3.0+phase)+0.0025*sin(angle*7.0+0.8+phase)
		result.append(size*0.5+Vector2.from_angle(angle)*radius*uneven)
	return result

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
	if preview_outline_only:
		_draw_footprint_outline(points,bounds,unit)
		return
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

func footprint_edges() -> Array:
	# Shared hex edges cancel out, leaving only the combined object silhouette.
	var edges := {}
	for cell in preview_path:
		var at := Vector2(sqrt(3.0)*(float(cell[0])+float(cell[1])*0.5),float(cell[1])*1.5)
		var corners: Array[Vector2] = []
		for i in 6:
			corners.append(at+Vector2.from_angle(deg_to_rad(i*60-30)))
		for i in 6:
			var a := corners[i]
			var b := corners[(i+1)%6]
			var a_key := "%d,%d" % [roundi(a.x*1000),roundi(a.y*1000)]
			var b_key := "%d,%d" % [roundi(b.x*1000),roundi(b.y*1000)]
			var key := a_key+":"+b_key if a_key < b_key else b_key+":"+a_key
			if edges.has(key):
				edges.erase(key)
			else:
				edges[key] = [a,b]
	return edges.values()

func _draw_footprint_outline(_points: PackedVector2Array, bounds: Rect2, unit: float) -> void:
	for edge in footprint_edges():
		var a: Vector2 = size*0.5+(edge[0]-bounds.get_center())*unit
		var b: Vector2 = size*0.5+(edge[1]-bounds.get_center())*unit
		draw_line(a,b,Color("94513f"),1.8,true)

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
