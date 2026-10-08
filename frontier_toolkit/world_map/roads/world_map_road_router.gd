class_name WorldMapRoadRouter
extends RefCounted

const JOIN_TOLERANCE := 0.05
var points: Array[Vector2] = []
var edges: Array[Dictionary] = []

func find_path(roads: Array[WorldMapRoad], start: Dictionary, destination: Dictionary, navigation: WorldMapNavigation) -> PackedVector2Array:
	points.clear()
	edges.clear()
	var segments: Array[Dictionary] = []
	for road in roads:
		if not is_instance_valid(road) or not road.is_inside_tree():
			continue
		for index in range(road.center_line.size() - 1):
			var a := road.to_global(road.center_line[index])
			var b := road.to_global(road.center_line[index + 1])
			if a.distance_to(b) <= JOIN_TOLERANCE:
				continue
			var cuts: Array[Vector2] = [a, b]
			if start.road == road and int(start.segment_index) == index:
				cuts.append(start.position)
			if destination.road == road and int(destination.segment_index) == index:
				cuts.append(destination.position)
			segments.append({"a": a, "b": b, "cuts": cuts})
	# Split at crossings and T junctions, so changing roads follows their shared center.
	for first in segments.size():
		for second in range(first + 1, segments.size()):
			var a: Dictionary = segments[first]
			var b: Dictionary = segments[second]
			var crossing: Variant = Geometry2D.segment_intersects_segment(a.a, a.b, b.a, b.b)
			if crossing is Vector2:
				a.cuts.append(crossing)
				b.cuts.append(crossing)
			for point: Vector2 in [a.a, a.b, b.a, b.b]:
				if _on_segment(point, a) and _on_segment(point, b):
					a.cuts.append(point)
					b.cuts.append(point)
	for segment in segments:
		var direction: Vector2 = segment.b - segment.a
		var cuts: Array[Vector2] = segment.cuts
		cuts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return direction.dot(a - Vector2(segment.a)) < direction.dot(b - Vector2(segment.a)))
		for index in range(cuts.size() - 1):
			var a := cuts[index]
			var b := cuts[index + 1]
			if a.distance_to(b) <= JOIN_TOLERANCE:
				continue
			# A road cannot grant passage through a hole or an obstacle.
			if not navigation.is_segment_walkable(a, b):
				continue
			var first := _node(a)
			var second := _node(b)
			edges[first][second] = a.distance_to(b)
			edges[second][first] = a.distance_to(b)
	return _shortest_path(_node(start.position), _node(destination.position))

func _on_segment(point: Vector2, segment: Dictionary) -> bool:
	return point.distance_to(Geometry2D.get_closest_point_to_segment(point, segment.a, segment.b)) <= JOIN_TOLERANCE

func _node(point: Vector2) -> int:
	for index in points.size():
		if points[index].distance_to(point) <= JOIN_TOLERANCE:
			return index
	points.append(point)
	edges.append({})
	return points.size() - 1

func _shortest_path(start: int, destination: int) -> PackedVector2Array:
	var distance: Array[float] = []
	var previous: Array[int] = []
	var visited: Array[bool] = []
	for _index in points.size():
		distance.append(INF)
		previous.append(-1)
		visited.append(false)
	distance[start] = 0.0
	for _iteration in points.size():
		var current := -1
		var best := INF
		for index in points.size():
			if not visited[index] and distance[index] < best:
				current = index
				best = distance[index]
		if current < 0:
			break
		if current == destination:
			var reverse: Array[Vector2] = []
			while current >= 0:
				reverse.append(points[current])
				current = previous[current]
			reverse.reverse()
			return PackedVector2Array(reverse)
		visited[current] = true
		for neighbour: int in edges[current]:
			var candidate: float = distance[current] + float(edges[current][neighbour])
			if candidate < distance[neighbour]:
				distance[neighbour] = candidate
				previous[neighbour] = current
	return PackedVector2Array()
