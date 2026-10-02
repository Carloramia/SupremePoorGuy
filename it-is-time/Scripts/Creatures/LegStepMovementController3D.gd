extends "res://Scripts/Creatures/LegStepMovementControllerBase3D.gd"

## Player-controlled adapter. All gait and physics behavior lives in the shared base class.
@export_group("Player Input")
@export var right_action: StringName = &"Right"
@export var left_action: StringName = &"Left"
@export var up_action: StringName = &"Up"
@export var down_action: StringName = &"Down"
@export var burst_action: StringName = &"Space"
@export var fast_speed_action: StringName = &"Shift"

## Returns a unit XZ-plane direction. Opposite actions cancel each other.
func get_input_movement_direction() -> Vector3:
	var direction := Vector3(
		Input.get_action_strength(right_action) - Input.get_action_strength(left_action),
		0.0,
		Input.get_action_strength(down_action) - Input.get_action_strength(up_action)
	)
	return direction.normalized() if not direction.is_zero_approx() else Vector3.ZERO

func is_burst_requested() -> bool:
	return Input.is_action_just_pressed(burst_action)

func is_fast_speed_active() -> bool:
	return Input.is_action_pressed(fast_speed_action)
