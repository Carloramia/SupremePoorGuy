extends "res://Scripts/Creatures/LegStepMovementControllerBase3D.gd"

## Character physics adapter. Keyboard bindings and input ownership live on PlayerController3D.
func get_input_movement_direction() -> Vector3:
	var source := get_player_command_source()
	return source.get_movement_direction() if source != null else Vector3.ZERO

func is_burst_requested() -> bool:
	var source := get_player_command_source()
	return source != null and source.is_jump_requested()

func is_fast_speed_active() -> bool:
	var source := get_player_command_source()
	return source != null and source.is_fast_requested()
