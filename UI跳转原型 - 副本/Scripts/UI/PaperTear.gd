extends Control
## Visual-only paper fragments. Inventory deletion has already been committed.
signal finished
var progress := 0.0:
	set(value):
		progress = value
		queue_redraw()
var caption := ""
func play() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(self,"progress",1.0,0.35)
	tween.tween_callback(func():
		finished.emit()
		queue_free())
func _draw() -> void:
	var seam := PackedVector2Array()
	for i in 13:
		seam.append(Vector2(size.x*0.5+(7 if i%2 else -7),size.y*i/12.0))
	var left := PackedVector2Array([Vector2.ZERO])
	left.append_array(seam)
	left.append(Vector2(0,size.y))
	var right := PackedVector2Array([Vector2(size.x,0),Vector2(size.x,size.y)])
	var reverse := seam.duplicate()
	reverse.reverse()
	right.append_array(reverse)
	for i in 2:
		var direction := -1 if i == 0 else 1
		draw_set_transform(Vector2(direction*progress*65,progress*progress*45),direction*progress*0.1)
		draw_colored_polygon(left if i == 0 else right,Color(0.76,0.56,0.28,1-progress))
		draw_polyline(seam,Color(0.95,0.87,0.7,1-progress),2,true)
	draw_set_transform(Vector2.ZERO)
