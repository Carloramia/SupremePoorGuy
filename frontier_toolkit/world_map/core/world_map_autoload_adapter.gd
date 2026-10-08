class_name WorldMapAutoloadAdapter
extends Node

# Optional session cache; NOT configured as an Autoload by this project.
# A scene host can export before leaving, recreate the scene, load its save,
# then pass battle results back through resolve_location_interaction.
var sessions: Dictionary = {}

func retain_session(world_map: WorldMapController) -> void:
	world_map.leave_world_map()
	sessions[world_map.definition.map_id] = world_map.export_session()

func get_session(map_id: StringName) -> Dictionary:
	return sessions.get(map_id, {}).duplicate(true)

func restore_session(world_map: WorldMapController) -> bool:
	return world_map.import_session(get_session(world_map.definition.map_id))

func return_battle_result(world_map: WorldMapController, location_id: StringName, result: Dictionary) -> bool:
	return world_map.resolve_location_interaction(location_id, result)
