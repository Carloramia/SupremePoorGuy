class_name WorldMapRoadManager
extends RefCounted

var registry: Array[WorldMapRoad] = []

func register_children(container: Node) -> void:
	if container == null:
		return
	for child in container.get_children():
		if child is WorldMapRoad:
			register_road(child)

func register_road(road: WorldMapRoad) -> void:
	if not registry.has(road):
		registry.append(road)

func unregister_road(road: WorldMapRoad) -> void:
	registry.erase(road)

func snap_destination(world_point: Vector2) -> Vector2:
	var candidate := snap_candidate(world_point)
	return candidate.position if not candidate.is_empty() else world_point

func snap_candidate(world_point: Vector2) -> Dictionary:
	var nearest_distance := INF
	var candidate: Dictionary = {}
	for road in registry:
		if not is_instance_valid(road) or not road.is_inside_tree():
			continue
		var nearest := road.nearest_center_point(world_point)
		if nearest.is_empty():
			continue
		var distance: float = nearest.distance
		if distance <= road.snap_radius() and distance < nearest_distance:
			nearest_distance = distance
			candidate = nearest
	return candidate

func plan_route(from: Vector2, destination: Dictionary, navigation: WorldMapNavigation) -> PackedVector2Array:
	var start: Dictionary = {}
	var distance := INF
	for road in registry:
		if not is_instance_valid(road) or not road.is_inside_tree():
			continue
		var candidate := road.nearest_center_point(from)
		if not candidate.is_empty() and float(candidate.distance) < distance:
			distance = candidate.distance
			start = candidate
	if start.is_empty():
		return PackedVector2Array()
	var destination_road: WorldMapRoad = destination.road
	var start_road: WorldMapRoad = start.road
	if float(start.distance) > start_road.snap_radius():
		start = destination_road.nearest_center_point(from)
	var router := WorldMapRoadRouter.new()
	var center_path := router.find_path(registry, start, destination, navigation)
	if center_path.is_empty() and start.road != destination_road:
		# Disconnected roads use a normal Navigation connector to the target road.
		start = destination_road.nearest_center_point(from)
		center_path = router.find_path(registry, start, destination, navigation)
	if center_path.is_empty():
		return PackedVector2Array()
	var entry := navigation.legal_path(from, start.position)
	if entry.is_empty():
		return PackedVector2Array()
	var result := PackedVector2Array([from])
	for point in entry:
		if result[-1].distance_to(point) > 0.01:
			result.append(point)
	# Navigation may return a slightly rounded endpoint. The road section begins
	# at its exact projection, while the first route point remains the real player position.
	if result.size() > 1:
		result[-1] = start.position
	elif result[0].distance_to(start.position) > 0.0001:
		result.append(start.position)
	for point in center_path:
		if result[-1].distance_to(point) > 0.01:
			result.append(point)
	return result
