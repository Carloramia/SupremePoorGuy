class_name WorldMapRuntimeState
extends RefCounted

var map_id: StringName
var player_position: Vector2
var active_spawn_id: StringName
var exploration_samples: Array[Dictionary] = []
var location_runtime_states: Dictionary = {}
var procedural_seed: int = 2026
var procedural_results: Dictionary = {}
var pending_battle: Dictionary = {}

func to_dict() -> Dictionary:
	var states: Dictionary = {}
	var discovered: Array[String] = []
	var removed: Array[String] = []
	for id: StringName in location_runtime_states:
		var state: LocationRuntimeState = location_runtime_states[id]
		states[String(id)] = state.to_dict()
		if state.discovered:
			discovered.append(String(id))
		if state.lifecycle == LocationRuntimeState.Lifecycle.REMOVED_PERMANENTLY:
			removed.append(String(id))
	# Only JSON primitives cross persistence boundaries, never scene references.
	return {"save_version": 1, "map_id": String(map_id), "player_position": {"x": player_position.x, "y": player_position.y}, "active_spawn_id": String(active_spawn_id), "exploration_samples": exploration_samples, "location_runtime_states": states, "discovered_locations": discovered, "removed_locations": removed, "procedural_seed": procedural_seed, "procedural_results": procedural_results, "pending_battle": pending_battle}

static func from_dict(data: Dictionary) -> WorldMapRuntimeState:
	var state := WorldMapRuntimeState.new()
	state.map_id = StringName(data.get("map_id", ""))
	var position_data: Dictionary = data.get("player_position", {})
	state.player_position = Vector2(float(position_data.get("x", 0)), float(position_data.get("y", 0)))
	state.active_spawn_id = StringName(data.get("active_spawn_id", ""))
	for sample: Dictionary in data.get("exploration_samples", []):
		state.exploration_samples.append(sample.duplicate(true))
	for id: String in data.get("location_runtime_states", {}):
		state.location_runtime_states[StringName(id)] = LocationRuntimeState.from_dict(data.location_runtime_states[id])
	state.procedural_seed = int(data.get("procedural_seed", 2026))
	state.procedural_results = data.get("procedural_results", {}).duplicate(true)
	state.pending_battle = data.get("pending_battle", {}).duplicate(true)
	return state
