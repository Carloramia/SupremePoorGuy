@tool
class_name WorldMapSpeedArea
extends Area2D

@export var speed_multiplier: float = 1.5
# Area2D already exposes priority in Godot 4.7; reuse that editable property.
@export var tint: Color = Color(0.85, 0.69, 0.4, 0.22)

func _ready() -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
	collision_layer = 0
	collision_mask = 1
	body_entered.connect(func(body: Node2D) -> void:
		if body is WorldMapPlayer and not body.speed_areas.has(self):
			body.speed_areas.append(self))
	body_exited.connect(func(body: Node2D) -> void:
		if body is WorldMapPlayer:
			body.speed_areas.erase(self))
	queue_redraw()

func _draw() -> void:
	for child in get_children():
		if child is CollisionPolygon2D:
			draw_colored_polygon(child.polygon, tint)
			draw_polyline(child.polygon + PackedVector2Array([child.polygon[0]]), Color(tint, 0.6), 2)
