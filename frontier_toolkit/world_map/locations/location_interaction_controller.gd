class_name LocationInteractionController
extends Node

signal interaction_started(location_id: StringName)
signal interaction_completed(location_id: StringName, result: Dictionary)
signal battle_requested(request: Dictionary)
signal scenario_requested(location_id: StringName, scene: PackedScene)
var active_location: WorldMapLocation
var world_map: WorldMapController
var ui: WorldMapUI
var panel: LocationInteractionPanel

func begin(location: WorldMapLocation) -> bool:
	if active_location or not location.can_interact():
		return false
	if not location.definition.interaction_ui_scene:
		push_warning("Interaction UI missing: %s" % location.location_id)
		ui.notify("Interaction UI is not configured")
		return false
	var instance := location.definition.interaction_ui_scene.instantiate()
	if not instance is LocationInteractionPanel:
		instance.free()
		push_warning("Interaction UI must inherit LocationInteractionPanel")
		return false
	active_location = location
	panel = instance
	panel.setup(location)
	panel.interaction_completed.connect(func(result: Dictionary) -> void: resolve(location.location_id, result))
	panel.battle_start_requested.connect(request_battle)
	panel.scenario_start_requested.connect(request_scenario)
	world_map.player.cancel_movement("interaction")
	world_map.set_world_map_paused(true)
	ui.open_interaction(panel)
	interaction_started.emit(location.location_id)
	return true

func request_scenario() -> void:
	if active_location and panel and active_location.definition.scenario_scene:
		scenario_requested.emit(active_location.location_id, active_location.definition.scenario_scene)

func request_battle() -> void:
	if active_location == null or not world_map.runtime_state.pending_battle.is_empty():
		return
	# External contract: core never changes scenes or touches a BattleManager.
	var request: Dictionary = {"map_id": String(world_map.definition.map_id), "location_id": String(active_location.location_id), "encounter_data": active_location.definition.encounter_data.duplicate(true)}
	world_map.runtime_state.pending_battle = request.duplicate(true)
	world_map.save_world_map()
	battle_requested.emit(request)

func resolve(id: StringName, result: Dictionary) -> bool:
	if active_location == null or active_location.location_id != id:
		push_warning("No matching active interaction: %s" % id)
		return false
	var location := active_location
	location.state.visits += 1
	location.state.custom_data.merge(result.get("custom_data", {}) if result.get("custom_data") is Dictionary else {}, true)
	location.state.custom_data["last_result"] = result.duplicate(true)
	# Lifecycle policy is centralized here; UI produces data only.
	if bool(result.get("success", false)) and bool(result.get("complete_location", result.get("result_type", "") == "victory")) and not location.definition.repeatable:
		var outcomes: Array[int] = [LocationRuntimeState.Lifecycle.COMPLETED, LocationRuntimeState.Lifecycle.HIDDEN_SESSION, LocationRuntimeState.Lifecycle.REMOVED_PERMANENTLY, LocationRuntimeState.Lifecycle.RESPAWNABLE]
		location.state.lifecycle = outcomes[clampi(location.completion_behavior(), 0, 3)] as LocationRuntimeState.Lifecycle
	location.refresh_marker()
	active_location = null
	panel = null
	world_map.runtime_state.pending_battle = {}
	world_map.clear_interaction_target()
	world_map.player.cancel_movement("interaction completed")
	ui.close_interaction()
	world_map.set_world_map_paused(false)
	world_map.save_world_map()
	interaction_completed.emit(id, result)
	return true
