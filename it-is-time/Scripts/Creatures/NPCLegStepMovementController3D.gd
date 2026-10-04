extends "res://Scripts/Creatures/LegStepMovementControllerBase3D.gd"

@export_group("NPC Input")
@export var state_machine_path: NodePath = NodePath("../NPCStateMachine3D")

var _state_machine: Node

func _ready() -> void:
	_state_machine = get_node_or_null(state_machine_path)
	super()

func get_input_movement_direction() -> Vector3:
	var source := get_player_command_source()
	if source != null: return source.get_movement_direction()
	if is_instance_valid(_state_machine) and _state_machine.has_method("get_movement_direction"):
		var requested_direction: Variant = _state_machine.call("get_movement_direction")
		if requested_direction is Vector3:
			return requested_direction
	return Vector3.ZERO

func is_fast_speed_active() -> bool:
	if is_instance_valid(_state_machine) and _state_machine.has_method("is_fast_movement_requested"):
		return bool(_state_machine.call("is_fast_movement_requested"))
	return false

func is_burst_requested() -> bool:
	var source := get_player_command_source()
	return source != null and source.is_jump_requested()
