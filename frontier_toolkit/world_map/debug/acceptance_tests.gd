extends SceneTree

var world: WorldMapController
var checks: Dictionary = {}
var details: Dictionary = {}
var failures: int = 0
var scene := preload("res://world_map/demo/WorldMapDemo.tscn")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 800)
	world = scene.instantiate()
	world.auto_load = false
	world.save_path = "res://.tools/acceptance_save.json"
	root.add_child(world)
	await world.initialized
	world.player.base_speed = 600.0
	var ridge_path := world.navigation.legal_path(Vector2(120, 220), Vector2(690, 220))
	var started := world.set_move_target(Vector2(690, 220))
	var visual_matches := world.player.path_line.points == ridge_path
	await frames_until(func() -> bool: return not world.player.has_target, 900)
	check(1, started and ridge_path.size() >= 3 and visual_matches and world.player.global_position.distance_to(Vector2(690, 220)) < 8, "Real Navigation2D detour and arrival; path points=%d, final=%s" % [ridge_path.size(), world.player.global_position])

	world.set_move_target(Vector2(220, 650))
	await frames(12)
	var redirected := world.set_move_target(Vector2(690, 500))
	check(2, redirected and world.player.movement_target == Vector2(690, 500) and world.player.path_line.points[-1].distance_to(Vector2(690, 500)) < 1, "Mid-route destination replaced immediately")
	world.cancel_movement("test")
	var before := world.player.global_position
	var rejected := not world.set_move_target(Vector2(500, 300)) and not world.set_move_target(Vector2(-1000, -1000)) and not world.set_move_target(HexMath.axial_to_world(Vector2i(7, 4), 64))
	await frames(4)
	check(3, rejected and world.player.global_position == before, "Obstacle, exterior and disabled Hex rejected without snapping")

	teleport(Vector2(140, 620))
	var explored_point := world.player.global_position
	teleport(Vector2(650, 1020))
	var transitioned := world.fog.visibility_at(explored_point) == WorldMapFog.Visibility.EXPLORED
	teleport(explored_point)
	check(4, transitioned and world.fog.visibility_at(explored_point) == WorldMapFog.Visibility.VISIBLE and world.fog.fog_material.shader != null, "Continuous capsule exploration, EXPLORED and VISIBLE transitions; shader falloff present")

	var herbs := world.get_location(&"herbs")
	var initially_hidden := not herbs.state.discovered and not herbs.visible
	teleport(Vector2(620, 650))
	check(5, initially_hidden and herbs.state.discovered and herbs.visible, "Distance-based discovery makes hidden marker persistent")
	teleport(Vector2(120, 220))
	world.ui.show_tooltip(herbs, Vector2(600, 300))
	check(6, herbs.visible and herbs.modulate.a < 1 and world.locations.hit_test(herbs.global_position) == herbs and world.ui.tooltip.visible and world.select_location(&"herbs"), "Distant discovered marker stays hit-testable, dim and hoverable")
	world.cancel_movement()
	world.clear_interaction_target()

	var town := world.get_location(&"town")
	teleport(Vector2(120, 220))
	world.select_location(&"town")
	await frames_until(func() -> bool: return world.interaction.active_location != null, 600)
	check(7, world.interaction.active_location == town and world.player.global_position.distance_to(town.interaction_point()) <= town.effective_interaction_radius(), "Selected location navigates to separate interaction point and automatically opens UI")
	world.resolve_location_interaction(&"town", {"success": true, "complete_location": false})

	teleport(town.interaction_point())
	await frames(3)
	check(8, world.interaction.active_location == null and not world.paused, "Passing an unselected location never opens formal UI")
	teleport(Vector2(120, 220))
	world.select_location(&"town")
	world.set_move_target(Vector2(140, 600))
	var retained := world.current_interaction_target == &"town"
	teleport(town.interaction_point())
	await frames(3)
	check(9, retained and world.interaction.active_location == town, "Ground click retains A; entering A radius later triggers it")
	world.resolve_location_interaction(&"town", {"success": true})

	teleport(Vector2(120, 220))
	world.select_location(&"town")
	var replaced := world.select_location(&"herbs")
	check(10, replaced and world.current_interaction_target == &"herbs", "New location replaces previous interaction intent")
	check(11, not world.select_location(&"blocked_site") and world.current_interaction_target.is_empty(), "Unreachable interaction point clears selected location")
	world.cancel_movement()

	teleport(town.interaction_point())
	world.select_location(&"town")
	await frames(3)
	var settlement_buttons := world.interaction.panel.content.get_children().filter(func(node: Node) -> bool: return node is Button)
	var rest_buttons := settlement_buttons.filter(func(button: Button) -> bool: return button.text == "Rest & resupply")
	rest_buttons[0].pressed.emit()
	check(12, town.visible and town.can_interact() and not world.paused and not world.player.has_target and world.current_interaction_target.is_empty(), "Settlement action completes visit, stays repeatable and clears movement")

	teleport(herbs.interaction_point())
	world.select_location(&"herbs")
	await frames(3)
	var resource_buttons := world.interaction.panel.content.get_children().filter(func(node: Node) -> bool: return node is Button)
	resource_buttons[0].pressed.emit()
	check(13, herbs.state.lifecycle == LocationRuntimeState.Lifecycle.REMOVED_PERMANENTLY and not herbs.visible and FileAccess.file_exists(world.save_path), "Collect action removes resource and autosaves")

	var monument := world.get_location(&"monument")
	teleport(monument.interaction_point())
	world.select_location(&"monument")
	await frames(3)
	var event_buttons := world.interaction.panel.content.get_children().filter(func(node: Node) -> bool: return node is Button)
	event_buttons[0].pressed.emit()
	var first_choice: bool = monument.state.custom_data.get("choice") == "knowledge"
	world.restore_location(&"monument")
	world.select_location(&"monument")
	await frames(3)
	event_buttons = world.interaction.panel.content.get_children().filter(func(node: Node) -> bool: return node is Button)
	event_buttons[1].pressed.emit()
	check(14, first_choice and monument.state.custom_data.get("choice") == "blessing" and monument.state.lifecycle == LocationRuntimeState.Lifecycle.HIDDEN_SESSION, "Both event choices produce distinct runtime data; session lifecycle respected")

	var bandits := world.get_location(&"bandits")
	teleport(bandits.interaction_point())
	world.select_location(&"bandits")
	await frames(3)
	var battle_buttons := world.interaction.panel.content.get_children().filter(func(node: Node) -> bool: return node is Button)
	battle_buttons[0].pressed.emit()
	var adapter := world.get_node("FakeBattleAdapter") as FakeBattleAdapter
	var request_valid: bool = adapter.request.get("map_id") == "frontier" and adapter.request.get("location_id") == "bandits" and world.paused
	adapter.return_result("defeat")
	var defeat_kept := bandits.can_interact()
	world.select_location(&"bandits")
	await frames(3)
	world.interaction.request_battle()
	adapter.return_result("error")
	var error_kept := bandits.can_interact()
	world.select_location(&"bandits")
	await frames(3)
	world.interaction.request_battle()
	adapter.return_result("victory")
	check(15, request_valid and defeat_kept and error_kept and bandits.state.lifecycle == LocationRuntimeState.Lifecycle.COMPLETED and not world.paused, "External request and FakeBattle victory / defeat / error roundtrips")

	teleport(Vector2(1200, 990))
	var saved_position := world.player.global_position
	var saved_sample_count := world.fog.samples.size()
	var saved_mask := world.fog.mask.get_data().duplicate()
	world.save_world_map()
	world.restore_location(&"herbs")
	# restore autosaves by design; restore the snapshot for this explicit load test.
	var snapshot := world.export_session()
	snapshot.location_runtime_states.herbs.lifecycle = LocationRuntimeState.Lifecycle.REMOVED_PERMANENTLY
	var snapshot_file := FileAccess.open("res://.tools/load_snapshot.json", FileAccess.WRITE)
	snapshot_file.store_string(JSON.stringify(snapshot))
	snapshot_file.close()
	teleport(Vector2(120, 220))
	world.set_move_target(Vector2(250, 600))
	var loaded := world.load_world_map("res://.tools/load_snapshot.json")
	check(16, loaded and world.player.global_position == saved_position and world.fog.samples.size() >= saved_sample_count and world.fog.mask.get_data() == saved_mask and herbs.state.discovered and herbs.state.lifecycle == LocationRuntimeState.Lifecycle.REMOVED_PERMANENTLY and not world.player.has_target and world.current_interaction_target.is_empty() and monument.state.lifecycle == LocationRuntimeState.Lifecycle.HIDDEN_SESSION, "JSON restores player, byte-identical fog mask, discovered/removed/session states and clears transient path")

	teleport(Vector2(220, 490))
	await frames(5)
	var road := is_equal_approx(world.player.effective_speed(), 900)
	teleport(Vector2(380, 500))
	await frames(5)
	var mud := is_equal_approx(world.player.effective_speed(), 300)
	teleport(Vector2(220, 490))
	await frames(5)
	check(17, road and mud and is_equal_approx(world.player.effective_speed(), 900), "Physical Road/Mud Area2D overlap uses priority, not multiplication")

	world.focus_on_player()
	var follow := world.camera.mode == WorldMapCameraController.Mode.FOLLOW_PLAYER
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	world.camera._unhandled_input(right)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100, 30)
	var camera_before := world.camera.global_position
	world.camera._unhandled_input(motion)
	var pan := world.camera.mode == WorldMapCameraController.Mode.FREE and world.camera.global_position != camera_before
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	world.camera._unhandled_input(wheel)
	world.focus_on_player()
	check(18, follow and pan and world.camera.zoom.x > 1 and world.camera.mode == WorldMapCameraController.Mode.FOLLOW_PLAYER, "Camera follow, RMB pan, wheel zoom and focus API")

	teleport(town.interaction_point())
	world.select_location(&"town")
	await frames(3)
	var frozen_position := world.player.global_position
	var frozen_camera := world.camera.global_position
	var frozen_fog := world.fog.samples.size()
	world.camera._unhandled_input(wheel)
	var move_rejected := not world.set_move_target(Vector2(200, 500))
	await frames(12)
	var frozen := world.paused and not paused and world.player.global_position == frozen_position and world.camera.global_position == frozen_camera and world.fog.samples.size() == frozen_fog
	world.resolve_location_interaction(&"town", {"success": true})
	check(19, frozen and move_rejected and not world.paused and not world.player.map_paused and not world.camera.map_paused and not world.fog.map_paused, "Modal freezes module input/movement/camera/fog while SceneTree and UI keep running; completion resumes")
	await extra_validation()
	var output := {"engine": Engine.get_version_info().string, "checks": checks, "details": details, "failures": failures}
	var report := FileAccess.open("res://world_map/debug/test_results.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(output, "\t"))
	report.close()
	print("ACCEPTANCE COMPLETE: %d failures" % failures)
	world.queue_free()
	await frames(3)
	quit(1 if failures else 0)

func extra_validation() -> void:
	var corrupt := FileAccess.open("res://.tools/corrupt.json", FileAccess.WRITE)
	corrupt.store_string("{not valid")
	corrupt.close()
	check(20, world.save_service.load_state("res://.tools/corrupt.json") == null and world.save_service.load_state("res://.tools/missing.json") == null, "Missing and corrupt save fail gracefully")
	world.restore_location(&"herbs")
	world.get_location(&"herbs").completion_behavior_override = LocationDefinition.CompletionBehavior.RESPAWNABLE
	teleport(world.get_location(&"herbs").interaction_point())
	world.select_location(&"herbs")
	await frames(3)
	world.resolve_location_interaction(&"herbs", {"success": true, "complete_location": true})
	var respawnable := world.get_location(&"herbs").state.lifecycle == LocationRuntimeState.Lifecycle.RESPAWNABLE
	world.respawn_location(&"herbs")
	check(21, respawnable and world.get_location(&"herbs").can_interact(), "RESPAWNABLE policy and public respawn API")
	teleport(Vector2(120, 220))
	world.set_move_target(Vector2(280, 700))
	await frames(5)
	world.pause_movement("story")
	var point := world.player.global_position
	await frames(5)
	var retained := world.player.has_target and world.player.global_position == point
	world.resume_movement()
	await frames(5)
	var resumed := world.player.global_position != point
	world.cancel_movement("story")
	check(22, retained and resumed and not world.player.has_target and world.player.path_line.points.is_empty(), "PAUSE retains intent; resume moves; CANCEL clears path")

	var second: WorldMapController = scene.instantiate()
	second.auto_load = false
	second.position = Vector2(2200, 1500)
	second.save_path = "res://.tools/second_map.json"
	root.add_child(second)
	await second.initialized
	var independent := second.navigation.navigation_map != world.navigation.navigation_map
	var shifted_spawn := second.player.global_position == second.to_global(Vector2(120, 220))
	var shifted_path := second.navigation.legal_path(second.player.global_position, second.to_global(Vector2(690, 220)))
	check(23, independent and shifted_spawn and shifted_path.size() >= 3 and second.fog.visibility_at(second.player.global_position) == WorldMapFog.Visibility.VISIBLE, "Two independent map subtrees, translated positions and private Navigation maps")
	second.queue_free()
	await frames(3)

	var monster := world.get_location(&"monster")
	teleport(monster.interaction_point())
	world.select_location(&"monster")
	await frames(3)
	world.interaction.request_battle()
	var battle_session := world.export_session()
	var returned: WorldMapController = scene.instantiate()
	returned.save_path = world.save_path
	root.add_child(returned)
	await returned.initialized
	await frames(4)
	var returned_adapter := returned.get_node("FakeBattleAdapter") as FakeBattleAdapter
	var restored_battle: bool = returned_adapter.request.get("location_id") == "monster" and returned.paused and returned.player.global_position == world.player.global_position and returned.runtime_state.procedural_seed == world.runtime_state.procedural_seed
	returned_adapter.return_result("victory")
	check(24, restored_battle and returned.get_location(&"monster").state.lifecycle == LocationRuntimeState.Lifecycle.REMOVED_PERMANENTLY and not returned.player.has_target, "Battle scene reconstruction restores pending request, player, seed and removes monster on victory")
	returned.queue_free()
	(world.get_node("FakeBattleAdapter") as FakeBattleAdapter).return_result("defeat")
	await frames(3)

	var dynamic := WorldMapLocation.new()
	dynamic.location_id = &"dynamic_herbs"
	dynamic.definition = load("res://world_map/demo/data/resource.tres")
	dynamic.position = Vector2(1100, 1000)
	dynamic.discovery_radius = 400
	var added := world.add_location(dynamic)
	var replacement := WorldMapLocation.new()
	replacement.definition = load("res://world_map/demo/data/event.tres")
	replacement.position = Vector2(1180, 1000)
	replacement.completion_behavior_override = LocationDefinition.CompletionBehavior.RESPAWNABLE
	var replaced := world.replace_location(&"dynamic_herbs", replacement)
	world.remove_location(&"dynamic_herbs")
	var dynamic_session := world.export_session()
	world.respawn_location(&"dynamic_herbs")
	var imported := world.import_session(dynamic_session)
	var rebuilt := world.get_location(&"dynamic_herbs")
	check(25, added and replaced and imported and rebuilt.position == Vector2(1180, 1000) and rebuilt.definition.type_id == &"event" and rebuilt.state.lifecycle == LocationRuntimeState.Lifecycle.REMOVED_PERMANENTLY, "Runtime registry add/replace/remove and session reconstruction preserve descriptors and tombstones")

	var malformed := world.export_session()
	malformed.player_position = {"x": "wrong", "y": 0}
	var rejects_position := not world.save_service.validate_save_data(malformed)
	malformed = world.export_session()
	malformed.location_runtime_states.town.visits = {"bad": "type"}
	var rejects_state := not world.save_service.validate_save_data(malformed)
	malformed = world.export_session()
	malformed.save_version = 999
	check(26, rejects_position and rejects_state and world.save_service.migrate_save_data(malformed).is_empty(), "Invalid field types and unknown save versions rejected before runtime parsing")

	# Exercise actual viewport input propagation, not just public movement methods.
	teleport(Vector2(120, 220))
	world.camera.focus_on_player()
	await frames(3)
	var save_click := InputEventMouseButton.new()
	var saves_seen: Array[int] = [0]
	world.save_completed.connect(func() -> void: saves_seen[0] += 1)
	save_click.position = world.ui.save_button.get_global_rect().get_center()
	save_click.button_index = MOUSE_BUTTON_LEFT
	save_click.pressed = true
	root.push_input(save_click, true)
	save_click.pressed = false
	root.push_input(save_click, true)
	await frames(3)
	var ui_consumed := not world.player.has_target and saves_seen[0] == 1
	var location_click := InputEventMouseButton.new()
	location_click.position = world.get_viewport().get_canvas_transform() * world.get_location(&"town").global_position
	location_click.button_index = MOUSE_BUTTON_LEFT
	location_click.pressed = true
	root.push_input(location_click, true)
	await frames(2)
	var selected_by_input := world.current_interaction_target == &"town"
	world.cancel_movement()
	world.clear_interaction_target()
	check(27, ui_consumed and selected_by_input, "Viewport GUI consumes Save clicks (%s); location marker click selects interaction through real input routing (%s)" % [ui_consumed, selected_by_input])

	var visual_alignment := true
	for hex in world.definition.enabled_cells():
		var visual_point := world.terrain.to_global(world.terrain.map_to_local(HexMath.axial_to_cell(hex)))
		if visual_point.distance_to(world.to_global(HexMath.axial_to_world(hex, world.definition.hex_size))) > 0.01:
			visual_alignment = false
	teleport(Vector2(730, 700))
	var lake_target := Vector2(1160, 750)
	var lake_path := world.navigation.legal_path(world.player.global_position, lake_target)
	var lake_started := world.set_move_target(lake_target)
	await frames_until(func() -> bool: return not world.player.has_target, 900)
	check(28, visual_alignment and lake_started and lake_path.size() >= 3 and world.player.global_position.distance_to(lake_target) < 8, "Every TileMap center matches axial geometry; actual movement detours around second irregular obstacle")

func teleport(point: Vector2) -> void:
	world.player.cancel_movement("test teleport")
	world.player.global_position = point
	world.fog.update_vision(point)
	world.locations.detect(point, world.fog)

func frames(count: int) -> void:
	for _index in count:
		await physics_frame

func frames_until(predicate: Callable, maximum: int) -> void:
	for _index in maximum:
		if predicate.call():
			return
		await physics_frame

func check(id: int, passed: bool, description: String) -> void:
	checks[str(id)] = "PASS" if passed else "FAIL"
	details[str(id)] = description
	if not passed:
		failures += 1
	print("TEST %02d %s: %s" % [id, checks[str(id)], description])
