class_name WorldMapController
extends Node2D

signal battle_requested(request_data: Dictionary)
signal location_discovered(location_id: StringName)
signal location_selected(location_id: StringName)
signal location_interaction_started(location_id: StringName)
signal location_interaction_completed(location_id: StringName, result: Dictionary)
signal invalid_destination(reason: String)
signal world_map_paused
signal world_map_resumed
signal save_completed
signal load_completed
signal initialized

@export var definition: WorldMapDefinition
@export var spawn_id: StringName = &""
@export var auto_load: bool = true
@export var save_path: String = WorldMapSaveService.DEFAULT_PATH
@export var player_speed: float = 165.0
@export var player_visual_scene: PackedScene
var generator: WorldMapGenerator = WorldMapGenerator.new()
var grid: HexGrid
var runtime_state: WorldMapRuntimeState
var navigation: WorldMapNavigation
var player: WorldMapPlayer
var camera: WorldMapCameraController
var fog: WorldMapFog
var locations: WorldMapLocationManager
var interaction: LocationInteractionController
var ui: WorldMapUI
var terrain: WorldMapTerrainLayer
var roads: WorldMapRoadManager = WorldMapRoadManager.new()
var save_service: WorldMapSaveService = WorldMapSaveService.new()
# Interaction intent is independent from the latest ground movement destination.
var current_interaction_target: StringName = &""
var paused: bool = false
var is_initialized: bool = false
var movement_blockers: Dictionary = {}
var scene_location_ids: Array[StringName] = []

func _ready() -> void:
	if definition == null:
		push_error("WorldMap requires WorldMapDefinition")
		return
	definition = definition.duplicate(true)
	var generated := generator.generate(definition, 2026, definition.generator_config)
	# Static fixed Hex overrides are applied before terrain and Navigation are built.
	# Keys are "q,r"; values contain enabled / terrain / custom metadata.
	for key: String in generated.hex_overrides:
		var parts := key.split(",")
		if parts.size() == 2:
			var hex := Vector2i(int(parts[0]), int(parts[1]))
			if not bool(generated.hex_overrides[key].get("enabled", true)) and not definition.disabled_hexes.has(hex):
				definition.disabled_hexes.append(hex)
	grid = HexGrid.new(definition)
	for key: String in generated.hex_overrides:
		var parts := key.split(",")
		if parts.size() == 2:
			var hex := Vector2i(int(parts[0]), int(parts[1]))
			if grid.cells.has(hex):
				grid.cells[hex].terrain = generated.hex_overrides[key].get("terrain", &"grass")
				grid.cells[hex].custom = generated.hex_overrides[key].get("custom", {}).duplicate(true)
	runtime_state = WorldMapRuntimeState.new()
	runtime_state.map_id = definition.map_id
	runtime_state.active_spawn_id = spawn_id if definition.spawns.has(String(spawn_id)) else definition.default_spawn_id
	runtime_state.player_position = definition.spawn_position(spawn_id)
	terrain = WorldMapTerrainLayer.new()
	add_child(terrain)
	terrain.build(definition)
	roads.register_children(get_node_or_null("Roads"))
	navigation = WorldMapNavigation.new()
	add_child(navigation)
	var obstacles := get_node_or_null("Obstacles") as Node2D
	if obstacles == null:
		obstacles = Node2D.new()
		add_child(obstacles)
	player = WorldMapPlayer.new()
	player.navigation = navigation
	player.base_speed = player_speed
	player.visual_scene = player_visual_scene
	add_child(player)
	player.global_position = to_global(runtime_state.player_position)
	camera = WorldMapCameraController.new()
	camera.player = player
	camera.bounds = Rect2(to_global(definition.world_rect().position), definition.world_rect().size)
	add_child(camera)
	camera.focus_on_player()
	fog = WorldMapFog.new()
	add_child(fog)
	fog.setup(definition)
	locations = get_node_or_null("Locations") as WorldMapLocationManager
	if locations == null:
		locations = WorldMapLocationManager.new()
		add_child(locations)
	locations.definition = definition
	locations.runtime_states = runtime_state.location_runtime_states
	locations.register_scene_locations()
	for id: StringName in locations.registry:
		scene_location_ids.append(id)
	ui = WorldMapUI.new()
	add_child(ui)
	interaction = LocationInteractionController.new()
	interaction.world_map = self
	interaction.ui = ui
	add_child(interaction)
	locations.location_discovered.connect(func(id: StringName) -> void:
		location_discovered.emit(id)
		ui.notify("Discovered: " + locations.get_location(id).definition.display_name))
	interaction.interaction_started.connect(func(id: StringName) -> void: location_interaction_started.emit(id))
	interaction.interaction_completed.connect(func(id: StringName, result: Dictionary) -> void: location_interaction_completed.emit(id, result))
	interaction.battle_requested.connect(func(request: Dictionary) -> void: battle_requested.emit(request))
	ui.save_requested.connect(func() -> void: save_world_map())
	ui.load_requested.connect(func() -> void: load_world_map())
	ui.focus_requested.connect(focus_on_player)
	ui.hex_debug_changed.connect(func(enabled: bool) -> void:
		terrain.show_hex_debug = enabled)
	ui.nav_debug_changed.connect(func(enabled: bool) -> void:
		get_tree().debug_navigation_hint = enabled
		for location: WorldMapLocation in locations.registry.values():
			location.show_debug = enabled
			location.queue_redraw())
	await navigation.build(definition, obstacles)
	player.agent.set_navigation_map(navigation.navigation_map)
	runtime_state.procedural_results = generated.to_dict()
	_apply_generated(generated.to_dict())
	if auto_load and FileAccess.file_exists(save_path):
		load_world_map(save_path, true)
	fog.update_vision(player.global_position)
	locations.detect(player.global_position, fog)
	is_initialized = true
	initialized.emit()
	_restore_pending_interaction()

func _process(_delta: float) -> void:
	if not is_initialized or paused:
		return
	runtime_state.player_position = to_local(player.global_position)
	fog.update_vision(player.global_position)
	locations.detect(player.global_position, fog)
	ui.show_tooltip(locations.hit_test(get_global_mouse_position()), get_viewport().get_mouse_position())
	var hex := HexMath.world_to_axial(to_local(player.global_position), definition.hex_size)
	ui.status.text = "%s · %d discoveries · %s\nHex (%d, %d)   Speed %.0f" % [definition.map_id, _discovered_count(), WorldMapCameraController.Mode.keys()[camera.mode], hex.x, hex.y, player.effective_speed()]
	if not current_interaction_target.is_empty():
		var target := locations.get_location(current_interaction_target)
		if target and target.can_interact() and player.global_position.distance_to(target.interaction_point()) <= target.effective_interaction_radius():
			if not interaction.begin(target):
				clear_interaction_target()

func _unhandled_input(event: InputEvent) -> void:
	if paused or not is_initialized or camera.dragging:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
		var location := locations.hit_test(point)
		if location:
			select_location(location.location_id)
		else:
			set_move_target(point, true)
		get_viewport().set_input_as_handled()

func set_move_target(point: Vector2, snap_to_road: bool = false) -> bool:
	if paused or not movement_blockers.is_empty():
		return false
	var destination := point
	var road_route := PackedVector2Array()
	if snap_to_road:
		# Road snapping applies only to ground intent, never location interaction points.
		# Invalid raw clicks remain invalid; snapping cannot rescue obstacle/exterior clicks.
		if not navigation.contains_ground(point):
			_reject("无法到达该位置 / Unreachable destination")
			return false
		var candidate := roads.snap_candidate(point)
		if not candidate.is_empty():
			destination = candidate.position
			road_route = roads.plan_route(player.global_position, candidate, navigation)
			if road_route.is_empty():
				_reject("无法沿道路到达该位置 / Unreachable road route")
				return false
	var accepted := player.set_move_route(road_route) if not road_route.is_empty() else player.set_move_target(destination)
	if not accepted:
		_reject("无法到达该位置 / Unreachable destination")
		return false
	if camera.follow_on_move_command:
		camera.focus_on_player()
	return true

func select_location(id: StringName) -> bool:
	if paused:
		return false
	var location := locations.get_location(id)
	if location == null or not location.visible or not location.can_interact():
		clear_interaction_target()
		_reject("Location unavailable")
		return false
	current_interaction_target = id
	if not set_move_target(location.interaction_point()):
		clear_interaction_target()
		_reject("无法到达该地点 / Unreachable location")
		return false
	location_selected.emit(id)
	return true

func clear_interaction_target() -> void:
	current_interaction_target = &""

func pause_movement(reason: String = "external") -> void:
	player.pause_movement(reason)

func resume_movement() -> void:
	if movement_blockers.is_empty():
		player.resume_movement()

func cancel_movement(reason: String = "external") -> void:
	player.cancel_movement(reason)

func set_movement_blocker(reason: StringName, blocked: bool) -> void:
	if blocked:
		movement_blockers[reason] = true
		pause_movement(String(reason))
	else:
		movement_blockers.erase(reason)
		resume_movement()

func focus_on_player() -> void:
	camera.focus_on_player()

func set_world_map_paused(value: bool) -> void:
	if paused == value:
		return
	# Module-only pause: external scene systems and the modal UI keep running.
	paused = value
	player.map_paused = value
	camera.map_paused = value
	camera.dragging = false
	fog.map_paused = value
	if value:
		player.velocity = Vector2.ZERO
		world_map_paused.emit()
	else:
		world_map_resumed.emit()

func resolve_location_interaction(id: StringName, result_data: Dictionary) -> bool:
	return interaction.resolve(id, result_data)

func add_location(location: WorldMapLocation) -> bool:
	var added := locations.add_location(location)
	if added:
		var descriptor := _location_descriptor(location)
		var descriptors: Array = runtime_state.procedural_results.get("locations", [])
		descriptors.append(descriptor)
		runtime_state.procedural_results["locations"] = descriptors
		save_world_map()
	return added

func remove_location(id: StringName, permanently: bool = true) -> bool:
	if interaction.active_location and interaction.active_location.location_id == id:
		return false
	var changed := locations.remove_location(id, permanently)
	if changed:
		if current_interaction_target == id:
			clear_interaction_target()
			cancel_movement("location removed")
		save_world_map()
	return changed

func replace_location(id: StringName, replacement: WorldMapLocation) -> bool:
	if interaction.active_location and interaction.active_location.location_id == id:
		return false
	if not locations.replace_location(id, replacement):
		return false
	var descriptors: Array = runtime_state.procedural_results.get("locations", [])
	for index in range(descriptors.size() - 1, -1, -1):
		if descriptors[index].get("id", "") == String(id):
			descriptors.remove_at(index)
	descriptors.append(_location_descriptor(replacement))
	runtime_state.procedural_results["locations"] = descriptors
	save_world_map()
	return true

func get_location(id: StringName) -> WorldMapLocation:
	return locations.get_location(id)

func has_location(id: StringName) -> bool:
	return locations.has_location(id)

func restore_location(id: StringName) -> bool:
	var changed := locations.restore_location(id)
	if changed:
		save_world_map()
	return changed

func respawn_location(id: StringName) -> bool:
	return restore_location(id)

func save_world_map(path: String = "") -> bool:
	runtime_state.player_position = to_local(player.global_position)
	runtime_state.exploration_samples = fog.samples.duplicate(true)
	runtime_state.location_runtime_states = locations.runtime_states
	var saved := save_service.save_state(runtime_state, path if not path.is_empty() else save_path)
	ui.notify("World saved" if saved else save_service.last_error)
	if saved:
		save_completed.emit()
	return saved

func load_world_map(path: String = "", new_session: bool = false) -> bool:
	if interaction.active_location:
		return false
	var loaded := save_service.load_state(path if not path.is_empty() else save_path)
	if loaded == null:
		ui.notify(save_service.last_error)
		return false
	if loaded.map_id != definition.map_id:
		_reject("Save map_id does not match this map")
		return false
	if navigation.legal_path(to_global(loaded.player_position), to_global(loaded.player_position)).is_empty():
		push_warning("Saved position invalid; using spawn")
		loaded.player_position = definition.spawn_position(loaded.active_spawn_id)
	runtime_state = loaded
	_apply_generated(loaded.procedural_results)
	locations.apply_runtime_states(loaded.location_runtime_states, new_session)
	player.cancel_movement("load")
	clear_interaction_target()
	player.global_position = to_global(loaded.player_position)
	fog.restore(loaded.exploration_samples, player.global_position)
	locations.detect(player.global_position, fog)
	camera.focus_on_player()
	ui.notify("World restored")
	load_completed.emit()
	if is_initialized:
		_restore_pending_interaction.call_deferred()
	return true

func export_session() -> Dictionary:
	runtime_state.player_position = to_local(player.global_position)
	runtime_state.exploration_samples = fog.samples.duplicate(true)
	return runtime_state.to_dict().duplicate(true)

func leave_world_map() -> bool:
	cancel_movement("leave map")
	return save_world_map()

func import_session(data: Dictionary, new_session: bool = false) -> bool:
	if interaction.active_location or not save_service.validate_save_data(data) or data.get("map_id") != String(definition.map_id):
		return false
	runtime_state = WorldMapRuntimeState.from_dict(data)
	_apply_generated(runtime_state.procedural_results)
	locations.apply_runtime_states(runtime_state.location_runtime_states, new_session)
	var point := to_global(runtime_state.player_position)
	if navigation.legal_path(point, point).is_empty():
		point = to_global(definition.spawn_position(runtime_state.active_spawn_id))
	player.cancel_movement("session restore")
	clear_interaction_target()
	player.global_position = point
	fog.restore(runtime_state.exploration_samples, point)
	locations.detect(point, fog)
	camera.focus_on_player()
	_restore_pending_interaction.call_deferred()
	return true

func _restore_pending_interaction() -> void:
	if runtime_state.pending_battle.is_empty() or interaction.active_location:
		return
	var pending_id := StringName(runtime_state.pending_battle.get("location_id", ""))
	var pending_location := locations.get_location(pending_id)
	if pending_location and interaction.begin(pending_location):
		battle_requested.emit(runtime_state.pending_battle.duplicate(true))
	else:
		push_warning("Pending battle location unavailable: %s" % pending_id)
		runtime_state.pending_battle = {}

func _apply_generated(result: Dictionary) -> void:
	var persisted_ids: Array[StringName] = []
	for descriptor: Dictionary in result.get("locations", []):
		persisted_ids.append(StringName(descriptor.get("id", "")))
	for id: StringName in locations.registry.keys():
		if not scene_location_ids.has(id) and not persisted_ids.has(id):
			var obsolete := locations.get_location(id)
			locations.registry.erase(id)
			locations.remove_child(obsolete)
			obsolete.queue_free()
	for descriptor: Dictionary in result.get("locations", []):
		var id := StringName(descriptor.get("id", ""))
		if locations.has_location(id) and not bool(descriptor.get("overrides_scene", false)):
			continue
		var resource_path := String(descriptor.get("definition", ""))
		if not ResourceLoader.exists(resource_path):
			push_warning("Generated definition missing: %s" % resource_path)
			continue
		var location := WorldMapLocation.new()
		location.location_id = id
		location.definition = load(resource_path) as LocationDefinition
		location.position = Vector2(float(descriptor.get("x", 0)), float(descriptor.get("y", 0)))
		location.interaction_offset = Vector2(float(descriptor.get("interaction_x", 0)), float(descriptor.get("interaction_y", 35)))
		location.discovery_radius = float(descriptor.get("discovery_radius", -1))
		location.interaction_radius = float(descriptor.get("interaction_radius", -1))
		location.completion_behavior_override = int(descriptor.get("completion_behavior_override", -1))
		var added := locations.replace_location(id, location) if locations.has_location(id) else locations.add_location(location)
		if not added:
			location.free()

func _location_descriptor(location: WorldMapLocation) -> Dictionary:
	return {"id": String(location.location_id), "definition": location.definition.resource_path, "x": location.position.x, "y": location.position.y, "interaction_x": location.interaction_offset.x, "interaction_y": location.interaction_offset.y, "discovery_radius": location.discovery_radius, "interaction_radius": location.interaction_radius, "completion_behavior_override": location.completion_behavior_override, "overrides_scene": true}

func _discovered_count() -> int:
	var count := 0
	for state: LocationRuntimeState in locations.runtime_states.values():
		if state.discovered:
			count += 1
	return count

func _reject(reason: String) -> void:
	ui.notify(reason)
	invalid_destination.emit(reason)
