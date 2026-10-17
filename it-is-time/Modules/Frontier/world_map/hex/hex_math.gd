class_name HexMath
extends RefCounted

const DIRECTIONS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]

static func axial_to_world(hex: Vector2i, size: float) -> Vector2:
	# Flat top: x = 3s/2*q; y = sqrt(3)*s*(r+q/2).
	return Vector2(1.5 * size * hex.x, sqrt(3.0) * size * (hex.y + hex.x * 0.5))

static func world_to_axial(point: Vector2, size: float) -> Vector2i:
	var q: float = point.x * 2.0 / (3.0 * size)
	var r: float = (-point.x / 3.0 + point.y / sqrt(3.0)) / size
	var cube := Vector3(q, -q - r, r)
	var rounded := cube.round()
	var error := (rounded - cube).abs()
	if error.x > error.y and error.x > error.z:
		rounded.x = -rounded.y - rounded.z
	elif error.y > error.z:
		rounded.y = -rounded.x - rounded.z
	else:
		rounded.z = -rounded.x - rounded.y
	return Vector2i(int(rounded.x), int(rounded.z))

static func axial_to_cell(hex: Vector2i) -> Vector2i:
	# Godot flat-top half-offset, odd columns offset downward.
	return Vector2i(hex.x, hex.y + (hex.x - posmod(hex.x, 2)) / 2)

static func cell_to_axial(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x, cell.y - (cell.x - posmod(cell.x, 2)) / 2)

static func neighbour(hex: Vector2i, direction: int) -> Vector2i:
	return hex + DIRECTIONS[posmod(direction, 6)]

static func distance(a: Vector2i, b: Vector2i) -> int:
	var delta := a - b
	return (absi(delta.x) + absi(delta.y) + absi(delta.x + delta.y)) / 2

static func cells_in_range(center: Vector2i, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(maxi(-radius, -q - radius), mini(radius, -q + radius) + 1):
			result.append(center + Vector2i(q, r))
	return result

static func polygon(center: Vector2, size: float) -> PackedVector2Array:
	var vertices := PackedVector2Array()
	for i in 6:
		vertices.append(center + Vector2.from_angle(i * PI / 3.0) * size)
	return vertices
