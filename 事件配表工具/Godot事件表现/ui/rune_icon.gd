extends Control
## Placeholder line art, replace with production textures later.
var rune_id := ""
const GOLD := Color("d4ba80")

func _ready() -> void:
	custom_minimum_size = Vector2(96, 38)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var shape: Array[Vector2] = []
	match rune_id:
		"big": shape = [Vector2(-23, 10), Vector2(0, -12), Vector2(23, 10)]
		"many": shape = [Vector2(-25, -10), Vector2(-8, 10), Vector2(8, -10), Vector2(25, 10)]
		"shell": shape = [Vector2(-23, -10), Vector2(-14, 10), Vector2(23, 10), Vector2(14, -10), Vector2(-23, -10)]
		_: shape = [Vector2(-23, -10), Vector2(-10, 10), Vector2(3, -10), Vector2(16, 10), Vector2(25, -5)]
	var points := PackedVector2Array()
	for point in shape:
		points.append(size / 2 + point)
	draw_polyline(points, GOLD, 3, true)
	for point in points:
		draw_circle(point, 3, Color("e9dfb1"))
