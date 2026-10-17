@tool
extends StaticBody3D
## Static paper scenery. Its collision and visual share the same thickness.

@export_range(0.001, 10.0, 0.001, "or_greater") var thickness: float = 0.08:
	set(value):
		thickness = maxf(0.001, value)
		if is_inside_tree(): _sync_geometry.call_deferred()
@export var collision_enabled: bool = true:
	set(value):
		collision_enabled = value
		if is_inside_tree(): _sync_geometry.call_deferred()
@export var image_scale: Vector2 = Vector2.ONE:
	set(value):
		image_scale = value.max(Vector2.ONE*0.001)
		if is_inside_tree(): _sync_geometry.call_deferred()
@export_range(0.0, 1.0) var opacity: float = 1.0:
	set(value):
		opacity = clampf(value,0.0,1.0)
		if is_inside_tree(): _sync_geometry.call_deferred()
@export_storage var unit_collision: ConcavePolygonShape3D

func _ready() -> void:
	_sync_geometry()

func _sync_geometry() -> void:
	var visual := get_node_or_null("Model/Visual") as MeshInstance3D
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if visual == null or collision == null or unit_collision == null: return
	visual.scale = Vector3(image_scale.x,image_scale.y,thickness)
	visual.transparency = 1.0-opacity
	collision.disabled = not collision_enabled
	if not collision_enabled:
		# Disabled scenery needs no per-instance physics mesh during battle loading.
		collision.shape = null
		return
	# Never mutate the shared source shape or another instance's collision.
	var faces := unit_collision.get_faces()
	for index: int in faces.size(): faces[index] *= Vector3(image_scale.x,image_scale.y,thickness)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	collision.shape = shape
