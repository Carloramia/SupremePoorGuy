@tool
class_name WorldMapRoad
extends WorldMapSpeedArea

@export var center_line: PackedVector2Array = PackedVector2Array([Vector2.ZERO, Vector2(200, 0)]):
	set(value):
		center_line = value
		_refresh_geometry()
@export_range(4, 200) var road_width: float = 64.0:
	set(value):
		road_width = maxf(4.0, value)
		_refresh_geometry()
@export_range(0, 200) var snap_margin: float = 24.0
@export var surface_color: Color = Color("a47e50"):
	set(value):
		surface_color = value
		queue_redraw()
@export var edge_color: Color = Color("624c36"):
	set(value):
		edge_color = value
		queue_redraw()

var collision_nodes: Array[CollisionShape2D] = []

func _ready() -> void:
	z_index = 1
	super._ready()
	if not Engine.is_editor_hint():
		_rebuild_collision()
	queue_redraw()

func nearest_center_point(world_point: Vector2) -> Dictionary:
	var result: Dictionary = {}
	var nearest_distance := INF
	for index in range(center_line.size() - 1):
		var start := to_global(center_line[index])
		var end := to_global(center_line[index + 1])
		if start.is_equal_approx(end):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(world_point, start, end)
		var distance := closest.distance_to(world_point)
		if distance < nearest_distance:
			nearest_distance = distance
			result = {"position": closest, "distance": distance, "road": self, "segment_index": index}
	return result

func snap_radius() -> float:
	return road_width * 0.5 + snap_margin

func _draw() -> void:
	if center_line.size() < 2:
		return
	# Rounded joins/caps match the rectangular segments plus circular speed areas.
	_draw_strip(edge_color, road_width + 4.0)
	_draw_strip(surface_color, road_width)
	draw_polyline(center_line, Color("d4b284"), 2.0, true)

func _draw_strip(color: Color, width: float) -> void:
	draw_polyline(center_line, color, width, true)
	for point in center_line:
		draw_circle(point, width * 0.5, color)

func _refresh_geometry() -> void:
	queue_redraw()
	if is_node_ready() and not Engine.is_editor_hint():
		_rebuild_collision()

func _rebuild_collision() -> void:
	for child in collision_nodes:
		remove_child(child)
		child.queue_free()
	collision_nodes.clear()
	if center_line.size() < 2:
		return
	for index in range(center_line.size() - 1):
		var start := center_line[index]
		var end := center_line[index + 1]
		if start.is_equal_approx(end):
			continue
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(start.distance_to(end), road_width)
		var collision := CollisionShape2D.new()
		collision.shape = rectangle
		collision.position = (start + end) * 0.5
		collision.rotation = (end - start).angle()
		_add_collision(collision)
	for point in center_line:
		var circle := CircleShape2D.new()
		circle.radius = road_width * 0.5
		var collision := CollisionShape2D.new()
		collision.shape = circle
		collision.position = point
		_add_collision(collision)

func _add_collision(collision: CollisionShape2D) -> void:
	add_child(collision)
	collision_nodes.append(collision)
