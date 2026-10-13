@tool
extends Control
## Decorative loose-leaf binding. It never intercepts page input.
@export var next_page: NodePath
@export var hole_inset := 22.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 10

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var other := get_node_or_null(next_page) as Control
	var page := get_parent() as Control
	if other == null or page == null:
		return
	var left := page.global_position.x + page.size.x - global_position.x - hole_inset
	var right := other.global_position.x - global_position.x + hole_inset
	for ratio in [0.22,0.5,0.78]:
		var y: float = page.global_position.y - global_position.y + page.size.y * ratio
		for x in [left,right]:
			draw_circle(Vector2(x,y),8,Color("aa8858"))
			draw_circle(Vector2(x,y),5.5,Color("382b20"))
		var ring := PackedVector2Array()
		for i in 41:
			var angle := TAU*i/40.0
			ring.append(Vector2((left+right)*0.5+cos(angle)*(right-left)*0.5,y+sin(angle)*10))
		draw_polyline(ring,Color("49301d"),8,true)
		draw_polyline(ring,Color("b57b3d"),5,true)
		draw_polyline(ring,Color("edc386"),1.5,true)
