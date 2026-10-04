extends RefCounted

const EDGES := [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0), Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4), Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7)]

static func box(size: Vector3, transform: Transform3D) -> Dictionary:
	var half := size * 0.5
	var vertices := PackedVector3Array()
	for point: Vector3 in [Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,1,-1), Vector3(-1,1,-1), Vector3(-1,-1,1), Vector3(1,-1,1), Vector3(1,1,1), Vector3(-1,1,1)]:
		vertices.append(transform * (point * half))
	return {"size": size, "half": half, "transform": transform, "inverse": transform.affine_inverse(), "vertices": vertices, "aabb": transform * AABB(-half, size)}

static func overlaps(a: Dictionary, b: Dictionary) -> bool:
	var axes: Array[Vector3] = []
	var first: Basis = a.transform.basis
	var second: Basis = b.transform.basis
	for index: int in range(3):
		axes.append(first[index])
		axes.append(second[index])
		for other: int in range(3):
			axes.append(first[index].cross(second[other]))
	for axis: Vector3 in axes:
		if axis.length_squared() < 0.00000001:
			continue
		axis = axis.normalized()
		var ra := 0.0
		var rb := 0.0
		for index: int in range(3):
			ra += absf(axis.dot(first[index])) * a.half[index]
			rb += absf(axis.dot(second[index])) * b.half[index]
		if absf(axis.dot(b.transform.origin - a.transform.origin)) > ra + rb + 0.000001:
			return false
	return true

## Diameter of the convex intersection, not the diameter of its axis-aligned bounds.
## Positive-volume overlap is required; touching faces/edges return zero.
static func overlap_diameter(a: Dictionary, b: Dictionary) -> float:
	if not a.aabb.intersects(b.aabb):
		return 0.0
	var first: Basis = a.transform.basis
	var second: Basis = b.transform.basis
	var axes: Array[Vector3] = [first.x, first.y, first.z, second.x, second.y, second.z]
	for i: int in range(3):
		for j: int in range(3):
			axes.append(first[i].cross(second[j]))
	for axis: Vector3 in axes:
		if axis.length_squared() < 0.00000001:
			continue
		axis = axis.normalized()
		var radius := 0.0
		for i: int in range(3):
			radius += absf(axis.dot(first[i])) * a.half[i] + absf(axis.dot(second[i])) * b.half[i]
		if radius - absf(axis.dot(b.transform.origin - a.transform.origin)) <= 0.000001:
			return 0.0
	var points := PackedVector3Array()
	for pair: Array in [[a, b], [b, a]]:
		var source: Dictionary = pair[0]
		var target: Dictionary = pair[1]
		var half: Vector3 = target.half
		for vertex: Vector3 in source.vertices:
			var local: Vector3 = target.inverse * vertex
			if _inside_box(local, half):
				points.append(vertex)
		for edge: Vector2i in EDGES:
			var start: Vector3 = target.inverse * source.vertices[edge.x]
			var end: Vector3 = target.inverse * source.vertices[edge.y]
			var direction := end - start
			for axis: int in range(3):
				if absf(direction[axis]) < 0.00000001:
					continue
				for sign_value: float in [-1.0, 1.0]:
					var t := (half[axis] * sign_value - start[axis]) / direction[axis]
					if t < 0.0 or t > 1.0:
						continue
					var local := start + direction * t
					if _inside_box(local, half):
						points.append(target.transform * local)
	var diameter_squared := 0.0
	for i: int in range(points.size()):
		for j: int in range(i):
			diameter_squared = maxf(diameter_squared, points[i].distance_squared_to(points[j]))
	return sqrt(diameter_squared)

static func _inside_box(point: Vector3, half: Vector3) -> bool:
	return absf(point.x) <= half.x + 0.000001 and absf(point.y) <= half.y + 0.000001 and absf(point.z) <= half.z + 0.000001

static func connected(a: Dictionary, b: Dictionary, threshold: float) -> bool:
	# AABB distance is only a lower bound; rotated boxes still need the exact test.
	var aa: AABB = a.aabb
	var bb: AABB = b.aabb
	var gap := Vector3.ZERO
	for axis: int in range(3):
		gap[axis] = maxf(maxf(aa.position[axis] - bb.end[axis], bb.position[axis] - aa.end[axis]), 0.0)
	if gap.length() > maxf(threshold, 0.0) + 0.000001:
		return false
	if overlaps(a, b):
		return true
	if threshold <= 0.0:
		return false
	return distance(a, b, threshold) < threshold

static func distance(a: Dictionary, b: Dictionary, stop_below: float = -1.0) -> float:
	if overlaps(a, b):
		return 0.0
	var best := INF
	for pair: Array in [[a, b], [b, a]]:
		for vertex: Vector3 in pair[0].vertices:
			var local: Vector3 = pair[1].inverse * vertex
			var half: Vector3 = pair[1].half
			best = minf(best, local.distance_to(local.clamp(-half, half)))
			if best < stop_below:
				return best
	# Disjoint convex boxes can attain their minimum between two edge interiors.
	for first: Vector2i in EDGES:
		for second: Vector2i in EDGES:
			best = minf(best, _segment_distance(a.vertices[first.x], a.vertices[first.y], b.vertices[second.x], b.vertices[second.y]))
			if best < stop_below:
				return best
	return best

static func _segment_distance(p: Vector3, q: Vector3, r: Vector3, u: Vector3) -> float:
	var d1 := q - p
	var d2 := u - r
	var offset := p - r
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var b := d1.dot(d2)
	var c := d1.dot(offset)
	var f := d2.dot(offset)
	var denominator := a * e - b * b
	var s := clampf((b * f - c * e) / denominator, 0.0, 1.0) if denominator > 0.000000000001 else 0.0
	var t := (b * s + f) / e
	if t < 0.0:
		t = 0.0
		s = clampf(-c / a, 0.0, 1.0)
	elif t > 1.0:
		t = 1.0
		s = clampf((b - c) / a, 0.0, 1.0)
	return (p + d1 * s).distance_to(r + d2 * t)
