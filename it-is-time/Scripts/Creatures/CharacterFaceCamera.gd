extends Node3D

## Rotates the character horizontally opposite to the active Camera3D's
## forward direction when that camera belongs to a DragCamera3D rig.
@export var face_active_drag_camera: bool = true
@export var use_model_front: bool = true

func _process(_delta: float) -> void:
	if not face_active_drag_camera:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or not _belongs_to_drag_camera(camera):
		return
	# Camera3D looks along its local -Z axis. Its reverse direction is therefore
	# global +Z; projecting it removes camera pitch from the character rotation.
	var horizontal_direction := camera.global_basis.z
	horizontal_direction.y = 0.0
	if horizontal_direction.is_zero_approx():
		return
	horizontal_direction = horizontal_direction.normalized()
	look_at(global_position + horizontal_direction, Vector3.UP, use_model_front)

func _belongs_to_drag_camera(camera: Camera3D) -> bool:
	var current: Node = camera
	while current != null:
		if current.is_in_group(&"drag_camera_3d"):
			return true
		current = current.get_parent()
	return false
