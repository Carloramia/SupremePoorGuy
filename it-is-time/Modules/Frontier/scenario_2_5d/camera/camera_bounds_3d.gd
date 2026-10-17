class_name CameraBounds3D
extends Node3D

@export var bounds: Rect2 = Rect2(-18, -14, 36, 28)

# Manual bounds today; a future mesh-derived adapter can call this API.
func set_bounds(value: Rect2) -> void:
	bounds = value
