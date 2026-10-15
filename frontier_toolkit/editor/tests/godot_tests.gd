extends SceneTree

var checks: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name": label, "pass": passed})
	print("PASS " if passed else "FAIL ", label)

func frames(count: int = 4) -> void:
	for _frame in count: await physics_frame

func run() -> void:
	var definition := load("res://editor/exports/frontier/WorldDefinition.tres") as WorldMapDefinition
	check("existing_world_definition_preserved", definition.map_id == &"frontier" and definition.width == 16 and definition.height == 12 and definition.disabled_hexes.size() == 7)
	check("full_authoring_data_in_resource", definition.editor_data.map.fog.retention == "recover" and definition.editor_data.map.objects.size() == 9)
	var camp: Dictionary = {}
	for object: Dictionary in definition.editor_data.map.objects:
		if object.type == "camp": camp = object
	check("camp_battle_associations_exported", camp.battle_map_id == "camp_battle_01" and camp.blocking_obstacle_ids == ["camp_barrier_01"] and camp.deployment_id == "player_deploy_01")
	var world := load("res://editor/exports/frontier/frontier.tscn").instantiate() as WorldMapController
	world.auto_load = false
	world.save_path = "res://editor/tests/native_preview_save.json"
	root.add_child(world)
	await world.initialized
	check("exported_world_initializes", world.is_initialized and world.roads.registry.size() == 2 and world.get_location(&"town") != null)
	check("static_obstacle_and_native_road_geometry", world.get_node("Obstacles/rock_ridge").polygon.size() == 6 and world.get_node("Roads/frontier_road").center_line.size() == 8)
	world.queue_free()
	await frames()
	var battle := load("res://editor/exports/camp_battle_01/camp_battle_01.tscn").instantiate() as ScenarioController
	root.add_child(battle)
	await frames()
	check("battle_uses_existing_scenario_controller", battle.initialized and battle.definition.default_scene_mode == SceneMode.Mode.COMBAT)
	check("six_invisible_entity_airwalls", battle.get_node("AirWalls").get_child_count() == 6 and battle.get_node("AirWalls/Wall0") is StaticBody3D and battle.get_node("AirWalls/Wall0").get_child_count() == 1)
	check("airwall_height_and_collision_layer", battle.get_node("AirWalls/Wall0").collision_layer == 1 and battle.get_node("AirWalls/Wall0/CollisionShape3D").shape.size.y == 12)
	check("decorative_tree_has_no_inferred_collision", battle.get_node("Objects/arena_tree_01").get_node_or_null("EntityCollision") == null)
	check("mud_and_web_have_effect_regions_not_solid_bodies", battle.get_node("Objects/arena_mud_01/EffectRegion") is Area3D and battle.get_node("Objects/arena_web_01/EffectRegion") is Area3D and not battle.has_node("Objects/arena_mud_01/EntityCollision"))
	check("damage_data_and_interval_retained", battle.get_node("Objects/arena_rock_01").get_meta("editor_object").interval == 1)
	check("deployment_slots_are_independent_markers", battle.get_node("Objects/player_deploy_01/Slot0") is Marker3D and battle.get_node("Objects/player_deploy_01/Slot1") is Marker3D)
	check("battle_background_is_separate_from_units", battle.get_node("SoftBackground") is MeshInstance3D and battle.get_node("Objects/camp_guard_01").get_meta("monster_config_id") == "demo_guard")
	check("battle_contains_no_exploration_fog", battle.get_node_or_null("Fog") == null)
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1280, 800)
		await frames(8)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://editor/tests/battle_preview.png")
	battle.queue_free()
	await frames()
	var failed := checks.filter(func(row: Dictionary) -> bool: return not row.pass).size()
	var file := FileAccess.open("res://editor/tests/godot-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": checks.size() - failed, "failed": failed, "tests": checks}, "\t"))
	quit(0 if failed == 0 else 1)
