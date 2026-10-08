class_name WorldMapNavigation
extends Node2D

var definition: WorldMapDefinition
var region: NavigationRegion2D
var navigation_map: RID
var obstacles: Array[PackedVector2Array] = []
var ready_for_paths: bool = false

func build(map_definition: WorldMapDefinition, obstacle_root: Node2D) -> void:
	definition = map_definition
	# A private navigation map avoids sharing regions with other WorldMap instances.
	navigation_map = NavigationServer2D.map_create()
	NavigationServer2D.map_set_active(navigation_map, true)
	NavigationServer2D.map_set_use_async_iterations(navigation_map, false)
	region = NavigationRegion2D.new()
	add_child(region)
	region.set_navigation_map(navigation_map)
	var polygon := NavigationPolygon.new()
	polygon.agent_radius = 10.0
	polygon.cell_size = 2.0
	var source := NavigationMeshSourceGeometryData2D.new()
	for hex in definition.enabled_cells():
		source.add_traversable_outline(HexMath.polygon(HexMath.axial_to_world(hex, definition.hex_size), definition.hex_size))
	for child in obstacle_root.get_children():
		if child is Polygon2D:
			var outline := PackedVector2Array()
			for vertex: Vector2 in child.polygon:
				outline.append(to_local(child.to_global(vertex)))
			obstacles.append(outline)
			source.add_obstruction_outline(outline)
			var body := StaticBody2D.new()
			var collision := CollisionPolygon2D.new()
			collision.polygon = outline
			body.add_child(collision)
			add_child(body)
	# One-time static demo bake from editable Polygon2D outlines; no dynamic rebaking.
	NavigationServer2D.bake_from_source_geometry_data(polygon, source)
	region.navigation_polygon = polygon
	# The first map iteration can contain the map but not the region yet.
	# Force synchronization once, after both region and polygon are registered.
	NavigationServer2D.map_force_update(navigation_map)
	await get_tree().physics_frame
	NavigationServer2D.map_force_update(navigation_map)
	ready_for_paths = true

func legal_path(from: Vector2, destination: Vector2) -> PackedVector2Array:
	if not ready_for_paths or not contains_ground(destination):
		return PackedVector2Array()
	var map: RID = region.get_navigation_map()
	# Reject rather than snap user intent to a mesh boundary.
	if NavigationServer2D.map_get_closest_point(map, destination).distance_to(destination) > 0.75:
		return PackedVector2Array()
	var path := NavigationServer2D.map_get_path(map, from, destination, true)
	if path.is_empty() or path[-1].distance_to(destination) > 0.75:
		return PackedVector2Array()
	return path

func contains_ground(world_point: Vector2) -> bool:
	var local_point := to_local(world_point)
	if not definition.contains(local_point):
		return false
	for outline in obstacles:
		if Geometry2D.is_point_in_polygon(local_point, outline):
			return false
	return true

func is_segment_walkable(start: Vector2, end: Vector2) -> bool:
	if legal_path(start, start).is_empty():
		return false
	var path := legal_path(start, end)
	if path.is_empty():
		return false
	# If Navigation must detour, this segment cannot be followed as a road centerline.
	for point in path:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, start, end)) > 0.75:
			return false
	return true

func _exit_tree() -> void:
	if navigation_map.is_valid():
		NavigationServer2D.free_rid(navigation_map)
