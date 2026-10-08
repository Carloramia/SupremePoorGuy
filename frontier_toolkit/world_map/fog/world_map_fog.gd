class_name WorldMapFog
extends Node2D

enum Visibility { UNEXPLORED, EXPLORED, VISIBLE }
@export var mask_width: int = 512
@export var feather: float = 35.0
var radius: float = 210.0
var bounds: Rect2
var samples: Array[Dictionary] = []
var player_position: Vector2
var map_paused: bool = false
var mask: Image
var texture: ImageTexture
var fog_material: ShaderMaterial
var surface: Sprite2D
var last_position: Vector2
var initialized: bool = false

func setup(map_definition: WorldMapDefinition) -> void:
	radius = map_definition.vision_radius
	bounds = map_definition.world_rect().grow(250.0)
	var height := maxi(1, roundi(mask_width * bounds.size.y / bounds.size.x))
	mask = Image.create(mask_width, height, false, Image.FORMAT_R8)
	mask.fill(Color.BLACK)
	texture = ImageTexture.create_from_image(mask)
	fog_material = ShaderMaterial.new()
	fog_material.shader = preload("res://world_map/fog/fog.gdshader")
	fog_material.set_shader_parameter("explored_mask", texture)
	fog_material.set_shader_parameter("world_origin", bounds.position)
	fog_material.set_shader_parameter("world_size", bounds.size)
	fog_material.set_shader_parameter("vision_radius", radius)
	fog_material.set_shader_parameter("feather", feather)
	var blank := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	blank.fill(Color.WHITE)
	surface = Sprite2D.new()
	surface.texture = ImageTexture.create_from_image(blank)
	surface.position = bounds.get_center()
	surface.scale = bounds.size
	surface.material = fog_material
	add_child(surface)
	z_index = 5

func update_vision(world_point: Vector2) -> void:
	if map_paused:
		return
	var point := to_local(world_point)
	player_position = point
	fog_material.set_shader_parameter("player_position", point)
	if initialized and point.is_equal_approx(last_position):
		return
	var start := last_position if initialized else point
	var sample: Dictionary = {"position": {"x": point.x, "y": point.y}, "from": {"x": start.x, "y": start.y}, "radius": radius}
	# Capsules preserve all continuous travel, unlike dropping every nth circle.
	# Collinear segments are merged only when their union is the same capsule.
	var merged := false
	if not samples.is_empty():
		var previous: Dictionary = samples[-1]
		var old_start := _point(previous.get("from", previous.position))
		var old_end := _point(previous.position)
		var a := old_end - old_start
		var b := point - old_end
		if float(previous.radius) == radius and start.is_equal_approx(old_end) and (a.is_zero_approx() or (absf(a.cross(b)) < 0.0001 and a.dot(b) >= 0)):
			previous.position = sample.position
			merged = true
	if not merged:
		# Exact repeats are redundant. Persistent data never relies on the mask texture.
		if not samples.has(sample):
			samples.append(sample)
	_stamp(start, point, radius)
	texture.update(mask)
	last_position = point
	initialized = true

func restore(history: Array[Dictionary], point: Vector2) -> void:
	samples = history.duplicate(true)
	mask.fill(Color.BLACK)
	for sample in samples:
		_stamp(_point(sample.get("from", sample.position)), _point(sample.position), float(sample.radius))
	texture.update(mask)
	initialized = false
	update_vision(point)

func visibility_at(world_point: Vector2) -> Visibility:
	var point := to_local(world_point)
	if point.distance_to(player_position) <= radius:
		return Visibility.VISIBLE
	for sample in samples:
		var closest := Geometry2D.get_closest_point_to_segment(point, _point(sample.get("from", sample.position)), _point(sample.position))
		if point.distance_to(closest) <= float(sample.radius):
			return Visibility.EXPLORED
	return Visibility.UNEXPLORED

func _stamp(start: Vector2, end: Vector2, stamp_radius: float) -> void:
	var scale_factor := Vector2(mask.get_width(), mask.get_height()) / bounds.size
	var minimum := ((start.min(end) - Vector2.ONE * stamp_radius - bounds.position) * scale_factor).floor()
	var maximum := ((start.max(end) + Vector2.ONE * stamp_radius - bounds.position) * scale_factor).ceil()
	for y in range(maxi(0, int(minimum.y)), mini(mask.get_height(), int(maximum.y) + 1)):
		for x in range(maxi(0, int(minimum.x)), mini(mask.get_width(), int(maximum.x) + 1)):
			var point := bounds.position + Vector2(x + 0.5, y + 0.5) / scale_factor
			var nearest := Geometry2D.get_closest_point_to_segment(point, start, end)
			var strength := 1.0 - smoothstep(stamp_radius - feather, stamp_radius, point.distance_to(nearest))
			if strength > mask.get_pixel(x, y).r:
				mask.set_pixel(x, y, Color(strength, 0, 0))

static func _point(data: Dictionary) -> Vector2:
	return Vector2(float(data.x), float(data.y))
