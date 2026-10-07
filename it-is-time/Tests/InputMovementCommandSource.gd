extends Node
## Test fixture: explicit player movement commands for birds that now also carry AI.
func get_movement_direction() -> Vector3:
	return Vector3(Input.get_action_strength("Right")-Input.get_action_strength("Left"),0.0,Input.get_action_strength("Down")-Input.get_action_strength("Up")).normalized()
func is_jump_requested() -> bool: return Input.is_action_just_pressed("Space")
func is_fast_movement_requested() -> bool: return Input.is_action_pressed("Shift")
