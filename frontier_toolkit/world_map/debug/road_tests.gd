extends SceneTree

var world: WorldMapController
var results: Dictionary = {}
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 800)
	world = load("res://world_map/demo/WorldMapDemo.tscn").instantiate()
	world.auto_load = false
	world.save_path = "res://.tools/road_test_save.json"
	root.add_child(world)
	await world.initialized
	await frames(3)
	check("registry", world.roads.registry.size() == 2, "Demo registers main and south center lines")
	var road := world.get_node("Roads/Road") as WorldMapRoad
	var nearest := road.nearest_center_point(Vector2(300, 510))
	check("projection", Vector2(nearest.position).is_equal_approx(Vector2(300, 490)), "Click within road width projects to nearest segment center")
	check("near_road", world.roads.snap_destination(Vector2(550, 540)).is_equal_approx(Vector2(550, 490)), "Ground near the road snaps within configurable margin")
	check("far_ground", world.roads.snap_destination(Vector2(550, 590)) == Vector2(550, 590), "Distant ground remains exact")
	check("closest_road", world.roads.snap_destination(Vector2(250, 710)).distance_to(Vector2(200, 490)) > 100 and world.roads.snap_destination(Vector2(250, 710)).distance_to(Vector2(250, 710)) < 20, "Nearest south-road segment selected across road registry")
	check("endpoint", road.nearest_center_point(Vector2(1190, 415)).position == Vector2(1150, 415), "Projection clamps beyond the last endpoint")
	var empty_road := WorldMapRoad.new()
	empty_road.center_line = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	check("degenerate", empty_road.nearest_center_point(Vector2(10, 10)).is_empty(), "Zero-length segments safely ignored")
	empty_road.free()

	teleport(Vector2(220, 490))
	await frames(5)
	var on_road := is_equal_approx(world.player.effective_speed(), world.player.base_speed * 1.5)
	teleport(Vector2(380, 500))
	await frames(5)
	var mud_override := is_equal_approx(world.player.effective_speed(), world.player.base_speed * 0.5)
	teleport(Vector2(220, 490))
	await frames(5)
	var left_mud := is_equal_approx(world.player.effective_speed(), world.player.base_speed * 1.5)
	teleport(Vector2(550, 600))
	await frames(5)
	check("speed_areas", on_road and mud_override and left_mud and is_equal_approx(world.player.effective_speed(), world.player.base_speed), "Real Area2D contacts accelerate road movement, Mud overrides and exit restores base speed")

	teleport(Vector2(220, 490))
	await frames(3)
	click_ground(Vector2(550, 540))
	var clicked_target := world.player.movement_target
	var clicked_marker := world.player.target_marker.global_position
	var clicked_path := world.player.path_line.points
	check("mouse_snap", world.player.has_target and clicked_target == Vector2(550, 490) and clicked_marker == clicked_target and not clicked_path.is_empty() and clicked_path[-1].distance_to(clicked_target) < 1, "Real viewport ground click snaps target, marker and actual navigation path")
	await until_stopped(900)
	check("arrival", world.player.global_position.distance_to(Vector2(550, 490)) < 8, "Player actually arrives at snapped center line")

	world.cancel_movement()
	world.current_interaction_target = &"town"
	world.set_move_target(Vector2(580, 525), true)
	check("intent", world.current_interaction_target == &"town", "Road ground command retains selected location intent")
	world.clear_interaction_target()
	var herbs := world.get_location(&"herbs")
	world.locations.detect(herbs.global_position, world.fog)
	var selected := world.select_location(&"herbs")
	check("location_exact", selected and world.player.movement_target == herbs.interaction_point(), "Location commands preserve exact interaction points without road snapping")
	world.cancel_movement()
	world.clear_interaction_target()
	world.set_move_target(Vector2(550, 525))
	check("api_exact", world.player.movement_target == Vector2(550, 525), "Programmatic API preserves exact destination unless snapping explicitly enabled")
	world.cancel_movement()
	check("invalid_raw", not world.set_move_target(Vector2(500, 300), true) and not world.set_move_target(Vector2(-1000, -1000), true), "Road snapping rejects obstacle and exterior raw clicks")

	var blocked_road := WorldMapRoad.new()
	blocked_road.center_line = PackedVector2Array([Vector2(500, 280), Vector2(500, 320)])
	blocked_road.snap_margin = 200
	world.get_node("Roads").add_child(blocked_road)
	world.roads.register_road(blocked_road)
	check("invalid_snapped", world.navigation.contains_ground(Vector2(390, 300)) and not world.set_move_target(Vector2(390, 300), true) and not world.player.has_target, "Unreachable snapped center line is rejected instead of falling back or bypassing obstacles")
	world.roads.unregister_road(blocked_road)
	blocked_road.queue_free()
	world.set_world_map_paused(true)
	var frozen := not world.set_move_target(Vector2(550, 510), true)
	world.set_world_map_paused(false)
	check("pause", frozen, "Road commands respect subsystem pause")
	await centerline_validation()

	var shifted: WorldMapController = load("res://world_map/demo/WorldMapDemo.tscn").instantiate()
	shifted.auto_load = false
	shifted.position = Vector2(2000, 1300)
	root.add_child(shifted)
	await shifted.initialized
	var shifted_snap := shifted.roads.snap_destination(shifted.to_global(Vector2(550, 525)))
	check("translated_map", shifted_snap.distance_to(shifted.to_global(Vector2(550, 490))) < 0.01, "Road projection remains correct in translated independent map instances")
	shifted.queue_free()
	var output := {"engine": Engine.get_version_info().string, "results": results, "failures": failures}
	var file := FileAccess.open("res://world_map/debug/road_test_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print("ROAD TESTS COMPLETE: ", results.size(), " checks, ", failures, " failures")
	world.queue_free()
	await frames(3)
	quit(0 if failures == 0 else 1)

func centerline_validation() -> void:
	teleport(Vector2(200, 340))
	await frames(3)
	var started := world.set_move_target(Vector2(640, 510), true)
	var route := world.player.movement_route.duplicate()
	check("bend_path", started and route.has(Vector2(200, 490)) and route.has(Vector2(520, 490)) and world.player.path_line.points == route, "Planned path includes road bends rather than an off-road diagonal")
	var maximum_deviation := 0.0
	var closest_bend := INF
	for _frame in 1400:
		maximum_deviation = maxf(maximum_deviation, center_distance(world.player.global_position))
		closest_bend = minf(closest_bend, world.player.global_position.distance_to(Vector2(200, 490)))
		if not world.player.has_target:
			break
		await physics_frame
	check("bend_trajectory", maximum_deviation < 0.1 and closest_bend < 0.1 and world.player.global_position.distance_to(Vector2(640, 490)) < 0.1, "Actual physics trajectory stays on centerline and reaches the corner before turning; deviation=%.4f" % maximum_deviation)

	teleport(Vector2(550, 490))
	world.set_move_target(Vector2(330, 895), true)
	var branch_route := world.player.movement_route.duplicate()
	check("branch_route", branch_route.has(Vector2(200, 490)) and branch_route.has(Vector2(240, 650)) and branch_route.has(Vector2(260, 800)), "Changing roads follows the main/south junction and all branch bends")
	maximum_deviation = 0.0
	for _frame in 1800:
		maximum_deviation = maxf(maximum_deviation, center_distance(world.player.global_position))
		if not world.player.has_target:
			break
		await physics_frame
	check("branch_trajectory", maximum_deviation < 0.1 and world.player.global_position.distance_to(Vector2(330, 895)) < 0.1, "Actual movement across the shared junction stays on road centers")

	teleport(Vector2(550, 600))
	var original := world.player.global_position
	world.set_move_target(Vector2(600, 500), true)
	check("entry_connector", world.player.global_position == original and world.player.movement_route.has(Vector2(550, 490)), "Off-road approach uses Navigation to enter nearest center without teleporting")
	await until_stopped(1000)
	check("entry_arrival", world.player.global_position.distance_to(Vector2(600, 490)) < 0.1, "Off-road connector joins road and arrives on exact center")

	teleport(Vector2(200, 340))
	world.set_move_target(Vector2(640, 490), true)
	await frames(10)
	world.pause_movement("road test")
	var paused_position := world.player.global_position
	var paused_route := world.player.movement_route.duplicate()
	await frames(6)
	var held := world.player.global_position == paused_position and world.player.movement_route == paused_route
	world.resume_movement()
	await frames(5)
	check("route_pause", held and world.player.global_position != paused_position, "Pause/resume retains centerline route and progresses after resume")
	world.set_move_target(Vector2(120, 220), true)
	var reversed := world.player.movement_target == Vector2(120, 220) and not world.player.movement_route.has(Vector2(640, 490))
	await until_stopped(1000)
	check("route_retarget", reversed and world.player.global_position.distance_to(Vector2(120, 220)) < 0.1, "New road command replaces old route, including reverse travel")
	world.set_move_target(Vector2(550, 490), true)
	world.cancel_movement("road test")
	check("route_cancel", world.player.movement_route.is_empty() and world.player.path_line.points.is_empty() and not world.player.has_target, "Cancel clears centerline waypoints and path display")

	var crossing_road := WorldMapRoad.new()
	crossing_road.center_line = PackedVector2Array([Vector2(150, 600), Vector2(400, 600)])
	world.get_node("Roads").add_child(crossing_road)
	world.roads.register_road(crossing_road)
	teleport(Vector2(350, 600))
	var crossing_started := world.set_move_target(Vector2(330, 895), true)
	check("interior_junction", crossing_started and world.player.movement_route.has(Vector2(227.5, 600)), "Crossings split segment interiors into proper road junctions")
	world.cancel_movement()
	world.roads.unregister_road(crossing_road)
	crossing_road.queue_free()

	var blocked := WorldMapRoad.new()
	blocked.center_line = PackedVector2Array([Vector2(350, 300), Vector2(650, 300)])
	world.get_node("Roads").add_child(blocked)
	world.roads.register_road(blocked)
	teleport(Vector2(350, 300))
	var destination_reachable := not world.navigation.legal_path(world.player.global_position, Vector2(650, 300)).is_empty()
	check("blocked_centerline", destination_reachable and not world.set_move_target(Vector2(650, 300), true), "A road through a mountain is rejected even when ordinary Navigation can detour to its end")
	world.roads.unregister_road(blocked)
	blocked.queue_free()
	await frames(3)

func center_distance(point: Vector2) -> float:
	var distance := INF
	for road in world.roads.registry:
		if is_instance_valid(road):
			var nearest := road.nearest_center_point(point)
			if not nearest.is_empty():
				distance = minf(distance, float(nearest.distance))
	return distance

func teleport(point: Vector2) -> void:
	world.player.cancel_movement()
	world.player.global_position = point
	world.fog.update_vision(point)
	world.camera.focus_on_player()

func click_ground(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_canvas_transform() * point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event.pressed = false
	root.push_input(event, true)

func frames(count: int) -> void:
	for _frame in count:
		await physics_frame

func until_stopped(maximum: int) -> void:
	for _frame in maximum:
		if not world.player.has_target:
			return
		await physics_frame

func check(id: String, passed: bool, description: String) -> void:
	results[id] = {"status": "PASS" if passed else "FAIL", "description": description}
	if not passed:
		failures += 1
	print("ROAD ", id, " ", results[id].status, ": ", description)
