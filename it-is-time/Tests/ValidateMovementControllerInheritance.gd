extends SceneTree

const BASE_SCRIPT: Script = preload("res://Scripts/Creatures/LegStepMovementControllerBase3D.gd")
const PLAYER_SCRIPT: Script = preload("res://Scripts/Creatures/LegStepMovementController3D.gd")
const NPC_SCRIPT: Script = preload("res://Scripts/Creatures/NPCLegStepMovementController3D.gd")

func _initialize() -> void:
	var base: Node = BASE_SCRIPT.new()
	var player: Node = PLAYER_SCRIPT.new()
	var npc: Node = NPC_SCRIPT.new()
	assert(PLAYER_SCRIPT.get_base_script() == BASE_SCRIPT)
	assert(NPC_SCRIPT.get_base_script() == BASE_SCRIPT)
	assert(_has_property(base, &"slow_step_distance"))
	assert(_has_property(player, &"slow_step_distance"))
	assert(_has_property(npc, &"slow_step_distance"))
	assert(not _has_property(base, &"right_action"))
	assert(_has_property(player, &"right_action"))
	assert(not _has_property(npc, &"right_action"))
	assert(_has_property(npc, &"state_machine_path"))
	assert(base.get_input_movement_direction().is_zero_approx())
	assert(not base.is_fast_speed_active())
	assert(not base.is_burst_requested())
	print("MOVEMENT_CONTROLLER_INHERITANCE_VALIDATION_PASSED")
	base.free()
	player.free()
	npc.free()
	quit()

func _has_property(object: Object, property_name: StringName) -> bool:
	for property: Dictionary in object.get_property_list():
		if property.name == property_name:
			return true
	return false
