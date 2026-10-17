class_name WorldMapLocationManager
extends Node2D

signal location_discovered(location_id: StringName)
var registry: Dictionary = {}
var runtime_states: Dictionary = {}
var definition: WorldMapDefinition

func register_scene_locations() -> void:
	for child in get_children():
		if child is WorldMapLocation:
			add_location(child)

func add_location(location: WorldMapLocation) -> bool:
	if location.location_id.is_empty() or location.definition == null or has_location(location.location_id):
		location.hide()
		push_warning("Location missing definition, empty or duplicate ID")
		return false
	if not definition.contains(location.position):
		location.hide()
		push_warning("Location outside enabled map: %s" % location.location_id)
		return false
	if location.get_parent() != null and location.get_parent() != self:
		push_warning("Location must be unparented or a direct manager child")
		return false
	if location.get_parent() == null:
		add_child(location)
	registry[location.location_id] = location
	if not runtime_states.has(location.location_id):
		runtime_states[location.location_id] = LocationRuntimeState.new()
	location.state = runtime_states[location.location_id]
	location.default_discovery = definition.discovery_radius
	location.default_interaction = definition.interaction_radius
	location.z_index = 9
	location.refresh_marker()
	return true

func remove_location(id: StringName, permanently: bool = true) -> bool:
	var location := get_location(id)
	if not location:
		return false
	location.state.lifecycle = LocationRuntimeState.Lifecycle.REMOVED_PERMANENTLY if permanently else LocationRuntimeState.Lifecycle.HIDDEN_SESSION
	location.refresh_marker()
	return true

func replace_location(id: StringName, replacement: WorldMapLocation) -> bool:
	if replacement.definition == null or not definition.contains(replacement.position):
		return false
	var previous := get_location(id)
	if previous:
		registry.erase(id)
		remove_child(previous)
		previous.queue_free()
	replacement.location_id = id
	return add_location(replacement)

func get_location(id: StringName) -> WorldMapLocation:
	return registry.get(id) as WorldMapLocation

func has_location(id: StringName) -> bool:
	return registry.has(id)

func restore_location(id: StringName) -> bool:
	var location := get_location(id)
	if not location:
		push_warning("Unknown location: %s" % id)
		return false
	location.state.lifecycle = LocationRuntimeState.Lifecycle.AVAILABLE
	location.refresh_marker()
	return true

func respawn_location(id: StringName) -> bool:
	return restore_location(id)

func detect(point: Vector2, fog: WorldMapFog) -> void:
	for location: WorldMapLocation in registry.values():
		if not location.state.discovered and location.is_active() and point.distance_to(location.global_position) <= location.effective_discovery_radius():
			location.state.discovered = true
			location_discovered.emit(location.location_id)
		location.currently_visible = fog.visibility_at(location.global_position) == WorldMapFog.Visibility.VISIBLE
		location.refresh_marker()

func hit_test(point: Vector2) -> WorldMapLocation:
	for location: WorldMapLocation in registry.values():
		if location.visible and location.global_position.distance_to(point) <= 26:
			return location
	return null

func apply_runtime_states(states: Dictionary, new_session: bool = false) -> void:
	runtime_states = states
	for location: WorldMapLocation in registry.values():
		if not runtime_states.has(location.location_id):
			runtime_states[location.location_id] = LocationRuntimeState.new()
		location.state = runtime_states[location.location_id]
		# HIDE_SESSION is reset only on a genuinely new session, not a manual Load.
		if new_session and location.state.lifecycle == LocationRuntimeState.Lifecycle.HIDDEN_SESSION:
			location.state.lifecycle = LocationRuntimeState.Lifecycle.AVAILABLE
		location.refresh_marker()
