extends SceneTree

var results: Array[Dictionary] = []
var world: WorldMapController
var completed: int = 0

func _initialize() -> void:
	call_deferred("run")

func frames(count: int = 4) -> void:
	for _frame in count:
		await physics_frame

func check(name: String, passed: bool) -> void:
	results.append({"name": name, "pass": passed})
	print("PASS " if passed else "FAIL ", name)

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)

func run() -> void:
	root.size = Vector2i(1280, 800)
	world = load("res://world_map/demo/WorldMapDemo.tscn").instantiate()
	world.auto_load = false
	world.save_path = "res://.tools/scenario_overlay_test_save.json"
	root.add_child(world)
	await world.initialized
	await frames()
	world.location_interaction_completed.connect(func(_id: StringName, _result: Dictionary) -> void: completed += 1)
	var town := world.get_location(&"town")
	world.player.global_position = town.interaction_point()
	world.player.cancel_movement()
	world.camera.focus_on_player()
	await frames()
	world.interaction.begin(town)
	await frames()
	var host: ScenarioOverlay = world.get_node("ScenarioOverlay")
	var panel := world.interaction.panel
	var entry: Button = panel.content.get_child(2)
	check("configured_town_entry", entry.text.contains("Enter town") and town.definition.scenario_scene != null)
	var player_position := world.player.global_position
	var camera_position := world.camera.global_position
	var scale_size := root.content_scale_size
	click(entry.get_global_rect().get_center())
	await frames(12)
	check("entry_button_opens_embedded_scene", host.scenario != null and host.scenario.initialized and not panel.visible)
	if host.scenario == null:
		quit(1)
		return
	check("map_stays_frozen", world.paused and world.player.map_paused and world.camera.map_paused and world.fog.map_paused)
	check("isolated_viewport_and_window_size", host.viewport.own_world_3d and host.scenario.get_viewport() == host.viewport and root.content_scale_size == scale_size)
	check("duplicate_open_rejected", not host.open_scenario(&"town", town.definition.scenario_scene))
	var scenario := host.scenario
	var npc: Interactable3D = scenario.get_node("Actors/NPC")
	var local_point := scenario.camera_controller.camera.unproject_position(npc.global_position + Vector3(0, 1, 0))
	click(host.viewport_container.global_position + local_point)
	await frames()
	check("embedded_mouse_picking", scenario.interaction_controller.selected == npc)
	var zoom_before := scenario.camera_controller.target_camera_size
	var wheel := InputEventMouseButton.new()
	wheel.position = host.viewport_container.get_global_rect().get_center()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	root.push_input(wheel, true)
	wheel.pressed = false
	root.push_input(wheel, true)
	await frames()
	check("embedded_mouse_zoom", scenario.camera_controller.target_camera_size < zoom_before)
	click(Vector2(5, 400))
	await frames(8)
	check("background_input_and_motion_blocked", world.player.global_position == player_position and world.camera.global_position == camera_position and not world.set_move_target(Vector2(200, 490)))
	root.size = Vector2i(1100, 740)
	await frames(8)
	check("responsive_floating_frame", host.frame.get_global_rect().end.x <= root.get_visible_rect().size.x and host.frame.get_global_rect().end.y <= root.get_visible_rect().size.y and host.viewport.size.x > 100)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://integration/scenario_overlay_preview.png")
	click(host.return_button.get_global_rect().get_center())
	await frames()
	check("return_ends_visit_once", completed == 1 and town.state.visits == 1 and world.interaction.active_location == null and host.overlay == null)
	check("map_resumes_and_town_remains_available", not world.paused and not world.ui.modal.visible and world.ui.save_button.disabled == false and town.can_interact())
	check("original_map_preserved", world.player.global_position == player_position and root.content_scale_size == scale_size)
	world.interaction.begin(town)
	await frames()
	world.interaction.request_scenario()
	await frames()
	host.scenario.request_scenario_exit(&"scenario_complete")
	await frames()
	check("scenario_end_signal_returns", completed == 2 and host.overlay == null and not world.paused and town.state.custom_data.scenario_exit_reason == "scenario_complete")
	world.interaction.begin(town)
	await frames()
	var invalid_scene := PackedScene.new()
	var invalid_root := Node3D.new()
	invalid_scene.pack(invalid_root)
	invalid_root.free()
	check("invalid_scene_keeps_original_interaction", not host.open_scenario(&"town", invalid_scene) and world.paused and world.interaction.panel.visible)
	world.resolve_location_interaction(&"town", {"success": true, "complete_location": false})
	await frames()
	var failed := results.filter(func(row: Dictionary) -> bool: return not row.pass).size()
	var file := FileAccess.open("res://integration/scenario_overlay_test_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": results.size() - failed, "failed": failed, "tests": results}, "\t"))
	world.queue_free()
	await frames()
	quit(0 if failed == 0 else 1)
