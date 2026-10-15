extends SceneTree

var results: Array[Dictionary] = []
var events: Dictionary = {"explore": 0, "combat": 0, "request": 0}
var scene: ScenarioController

func _initialize() -> void:
	call_deferred("run")

func check(name: String, passed: bool) -> void:
	results.append({"name": name, "pass": passed})
	print("PASS " if passed else "FAIL ", name)

func frames(count: int = 3) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func mouse_button(point: Vector2, index: MouseButton, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = index
	event.pressed = down
	root.push_input(event, true)

func run() -> void:
	root.size = Vector2i(1920, 1080)
	scene = load("res://scenario_2_5d/demo/Scenario25DDemo.tscn").instantiate()
	root.add_child(scene)
	await frames()
	scene.explore_ground_clicked.connect(func(_point: Vector3) -> void: events.explore += 1)
	scene.combat_ground_clicked.connect(func(_point: Vector3) -> void: events.combat += 1)
	scene.interaction_requested.connect(func(_id: StringName, _data: InteractableDefinition, _state: InteractableRuntimeState) -> void: events.request += 1)
	var rig := scene.camera_controller
	var camera := rig.camera
	var interaction := scene.interaction_controller
	var occlusion := scene.occlusion_controller
	var hero: Node3D = scene.get_node("Actors/Hero")
	var building: ScenarioOccluder3D = scene.get_node("Geometry/Building")
	var crate: Interactable3D = scene.get_node("Actors/Crate")
	var npc: Interactable3D = scene.get_node("Actors/NPC")
	check("lifecycle_initialized", scene.initialized)
	check("orthographic", camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	var rotation := camera.rotation
	var relative_position := camera.position
	var start_size := camera.size
	mouse_button(Vector2(950, 800), MOUSE_BUTTON_WHEEL_UP, true)
	check("zoom_target_changes_before_actual", rig.target_camera_size < start_size and camera.size == start_size)
	await frames(12)
	check("zoom_smoothly_converges", camera.size < start_size and camera.size > rig.target_camera_size)
	for index in 50:
		mouse_button(Vector2(950, 800), MOUSE_BUTTON_WHEEL_UP, true)
	check("zoom_min", rig.target_camera_size == scene.definition.min_camera_size)
	for index in 80:
		mouse_button(Vector2(950, 800), MOUSE_BUTTON_WHEEL_DOWN, true)
	check("zoom_max", rig.target_camera_size == scene.definition.max_camera_size)
	rig.target_camera_size = 14.0
	camera.size = 14.0
	mouse_button(Vector2(950, 800), MOUSE_BUTTON_MIDDLE, true)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(1060, 820)
	motion.relative = Vector2(110, 20)
	root.push_input(motion, true)
	check("drag_changes_target_xz", rig.target_position != rig.position and rig.target_position.y == rig.position.y)
	await frames(8)
	check("drag_moves_rig", rig.position.length() > 0.01)
	mouse_button(Vector2(150, 100), MOUSE_BUTTON_MIDDLE, false)
	var stopped := rig.position
	await frames(8)
	check("release_over_ui_stops_no_inertia", not rig.dragging and rig.position.is_equal_approx(stopped))
	check("fixed_rotation_height_structure", camera.rotation.is_equal_approx(rotation) and camera.position.is_equal_approx(relative_position))
	mouse_button(Vector2(950, 800), MOUSE_BUTTON_RIGHT, true)
	root.push_input(motion, true)
	mouse_button(Vector2(950, 800), MOUSE_BUTTON_RIGHT, false)
	check("right_mouse_cannot_rotate", camera.rotation.is_equal_approx(rotation))
	scene.set_camera_input_enabled(false)
	var locked_size := rig.target_camera_size
	mouse_button(Vector2(950, 800), MOUSE_BUTTON_WHEEL_UP, true)
	check("camera_input_lock", rig.target_camera_size == locked_size)
	scene.set_camera_input_enabled(true)
	paused = true
	mouse_button(Vector2(950, 800), MOUSE_BUTTON_WHEEL_UP, true)
	check("pause_independent_camera_input", rig.target_camera_size < locked_size)
	paused = false
	check("bounds_extreme_clamped", rig.clamp_position(Vector3(1000, 0, -1000)).length() < 30.0)
	rig.position = Vector3.ZERO
	rig.target_position = Vector3.ZERO
	camera.size = 20.0
	rig.target_camera_size = 20.0
	await frames()
	var visual: BillboardVisual3D = hero.get_node("VisualRoot/Billboard")
	check("quadmesh_upright", visual.mesh_instance.mesh is QuadMesh and is_zero_approx(visual.global_rotation.x) and is_zero_approx(visual.global_rotation.z))
	check("bottom_anchor", is_equal_approx(visual.mesh_instance.position.y, visual.visual_height * 0.5))
	check("quad_casts_no_shadow", visual.mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	check("blob_present", hero.get_node("VisualRoot/BlobShadow").mesh is QuadMesh)
	check("player_occluder_detection", occlusion.active_occluders.has(building))
	await frames(35)
	check("fade_material_instance_alpha", building.fade_amount < 0.3 and (building.materials[0] as StandardMaterial3D).albedo_color.a < 0.3)
	hero.position = Vector3(-5, 0, 4)
	await frames(60)
	check("fade_restores_original", building.fade_amount == 1.0 and (building.materials[0] as StandardMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)
	var crate_screen := camera.unproject_position(crate.global_position + Vector3(0, 0.7, 0))
	interaction.click_at(crate_screen)
	check("nearest_interactable_selected", interaction.selected == crate and crate.runtime_state.selected)
	check("object_click_no_ground_event", events.explore == 0 and events.combat == 0)
	check("info_panel_visible", scene.get_node("DemoUI").info_panel.visible)
	crate.request_interaction()
	check("request_signal", events.request == 1)
	interaction.click_at(camera.unproject_position(npc.global_position + Vector3(0, 1, 0)))
	check("selection_replaces_previous", interaction.selected == npc and not crate.runtime_state.selected)
	crate.set_hovered(true)
	check("hover_feedback", crate.hovered and crate.visual.paper_material.get_shader_parameter("tint") != Color.WHITE)
	crate.set_hovered(false)
	check("hover_restores", not crate.hovered and crate.visual.paper_material.get_shader_parameter("tint") == Color.WHITE)
	var ground_screen := camera.unproject_position(Vector3(3, 0, 6.5))
	interaction.click_at(ground_screen)
	check("explore_ground_dispatch", events.explore == 1 and events.combat == 0)
	scene.set_scene_mode(SceneMode.Mode.COMBAT)
	interaction.click_at(ground_screen)
	check("combat_ground_dispatch", events.explore == 1 and events.combat == 1)
	var previous_events: int = events.explore + events.combat
	interaction.click_at(camera.unproject_position(Vector3(2.5, 0.6, 5.5)))
	check("solid_obstacle_blocks_ground", previous_events == events.explore + events.combat)
	crate.position = Vector3(-5, 0, -3.2)
	await frames()
	interaction.click_at(camera.unproject_position(crate.global_position + Vector3(0, 0.7, 0)))
	check("building_blocks_hidden_object_pick", interaction.selected != crate)
	interaction.select_object(crate)
	await frames(6)
	check("selected_occlusion_target_fades", occlusion.active_occluders.has(building))
	var extra := Marker3D.new()
	scene.add_child(extra)
	extra.position = Vector3(7, 1.2, -1)
	scene.register_occlusion_target(extra)
	await frames(6)
	check("multiple_targets_and_occluders", occlusion.active_occluders.has(building) and occlusion.active_occluders.has(scene.get_node("Actors/Tree")))
	scene.unregister_occlusion_target(extra)
	extra.queue_free()
	await frames(6)
	check("unregister_restores_tree", not occlusion.active_occluders.has(scene.get_node("Actors/Tree")))
	var second := ScenarioOccluder3D.new()
	second.position = Vector3(-5, 4.7, 0.5)
	second.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 3, 0.3)
	shape.shape = box
	second.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.material_override = StandardMaterial3D.new()
	second.add_child(mesh)
	scene.add_child(second)
	await frames(5)
	check("multiple_blockers_same_ray", occlusion.active_occluders.has(building) and occlusion.active_occluders.has(second))
	second.queue_free()
	interaction.select_object(null)
	await frames(60)
	check("deselect_restores_building", building.fade_amount == 1.0)
	scene.set_focus_target(hero)
	scene.focus_on_target()
	check("focus_api", is_equal_approx(rig.position.x, rig.clamp_position(hero.position).x))
	var temporary := Node3D.new()
	scene.add_child(temporary)
	scene.set_focus_target(temporary)
	temporary.queue_free()
	await frames()
	scene.focus_on_target()
	check("freed_focus_target_safe", not is_instance_valid(rig.focus_target))
	scene.clear_focus_target()
	check("navigation_spawn_slots", scene.has_node("NavigationRoot") and scene.get_node("SpawnRoot/Arrival").spawn_id == &"outpost_arrival")
	root.size = Vector2i(1280, 720)
	await frames()
	var point := camera.unproject_position(npc.global_position + Vector3(0, 1, 0))
	interaction.click_at(point)
	check("resize_pick_valid", interaction.selected == npc)
	var ui: CanvasLayer = scene.get_node("DemoUI")
	var before_request: int = events.request
	previous_events = events.explore + events.combat
	var button_rect: Rect2 = ui.interact.get_global_rect()
	mouse_button(button_rect.get_center(), MOUSE_BUTTON_LEFT, true)
	mouse_button(button_rect.get_center(), MOUSE_BUTTON_LEFT, false)
	await frames()
	check("ui_button_request_and_no_clickthrough", events.request == before_request + 1 and events.explore + events.combat == previous_events)
	var failed: int = results.filter(func(row: Dictionary) -> bool: return not row.pass).size()
	var file := FileAccess.open("res://scenario_2_5d/debug/test_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": results.size() - failed, "failed": failed, "tests": results}, "\t"))
	print("SCENARIO TESTS ", results.size() - failed, "/", results.size())
	scene.queue_free()
	await process_frame
	quit(0 if failed == 0 else 1)
