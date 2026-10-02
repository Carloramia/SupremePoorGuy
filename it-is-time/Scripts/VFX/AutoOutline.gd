@tool
extends Node3D

const BASE_SCENES: Array[String] = [
	"res://Scenes/Creatures/Bodyparts/_SampleBodyParts.tscn",
	"res://Scenes/Creatures/Bodyparts/_PhysicalSampleBodyParts.tscn",
]

@export var outline_color: Color = Color.BLACK
## Full stroke width in world units, independent of target and parent scale.
@export_range(0.0, 1.0, 0.001, "or_greater") var outline_width: float = 0.04
## Moves the outline behind its Sprite3D to prevent coplanar depth conflicts.
@export_range(0.0, 0.1, 0.0001, "or_greater") var depth_offset: float = 0.003
@export_range(0.0, 1.0, 0.01) var alpha_threshold: float = 0.1
@export_range(0.1, 10.0, 0.1) var contour_simplification: float = 1.0

var _entries: Dictionary = {}
var _scene_matches: Dictionary = {}
var _contours: Dictionary = {}
var _material: StandardMaterial3D

func _ready() -> void:
	process_priority = 10
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func _process(_delta: float) -> void:
	if get_parent() == null or _material == null:
		return
	_material.albedo_color = outline_color
	var targets: Dictionary = {}
	for sibling in get_parent().get_children():
		if sibling != self:
			_find_parts(sibling, targets)
	for sprite in _entries.keys():
		if not is_instance_valid(sprite) or not targets.has(sprite):
			_entries[sprite].container.queue_free()
			_entries.erase(sprite)
	for sprite: Sprite3D in targets:
		_update_outline(sprite, targets[sprite])

func _is_body_scene(path: String) -> bool:
	if path.is_empty():
		return false
	if _scene_matches.has(path):
		return _scene_matches[path]
	var packed := load(path) as PackedScene
	var matches := false
	if packed != null:
		var state := packed.get_state()
		while state != null:
			if state.get_path() in BASE_SCENES:
				matches = true
				break
			state = state.get_base_scene_state()
	_scene_matches[path] = matches
	return matches

func _find_parts(node: Node, targets: Dictionary, body: Node = null) -> void:
	if _is_body_scene(node.scene_file_path):
		body = node
	if body != null and node is Sprite3D:
		targets[node] = body
	for child in node.get_children():
		_find_parts(child, targets, body)

func _update_outline(sprite: Sprite3D, body: Node) -> void:
	if not _entries.has(sprite):
		var container := Node3D.new()
		container.name = "Outline_" + str(sprite.get_instance_id())
		add_child(container)
		container.top_level = true
		container.global_transform = Transform3D.IDENTITY
		var mesh_node := MeshInstance3D.new()
		mesh_node.name = "OutlineMesh"
		mesh_node.material_override = _material
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		container.add_child(mesh_node)
		_entries[sprite] = {"container": container, "mesh": mesh_node, "signature": []}
	var entry: Dictionary = _entries[sprite]
	entry.container.visible = sprite.is_visible_in_tree() and outline_width > 0.0
	var distances := Vector4.ZERO
	var custom_edges: bool = body.has_method("get_outline_edge_distances")
	if custom_edges:
		distances = body.get_outline_edge_distances()
	var signature := [sprite.global_transform, sprite.texture, sprite.axis, sprite.get_item_rect(),
		sprite.flip_h, sprite.flip_v, sprite.region_enabled, sprite.region_rect, sprite.frame,
		sprite.hframes, sprite.vframes, distances, custom_edges, outline_width, depth_offset,
		alpha_threshold, contour_simplification]
	if entry.signature == signature:
		return
	entry.signature = signature
	for child in entry.container.get_children():
		if child is Path3D:
			child.free()
	entry.mesh.mesh = null
	if sprite.texture == null:
		return
	var region := Rect2i(Vector2i.ZERO, Vector2i(sprite.texture.get_size()))
	if sprite.region_enabled:
		region = Rect2i(sprite.region_rect)
	var frame_size := region.size / Vector2i(sprite.hframes, sprite.vframes)
	region = Rect2i(region.position + sprite.frame_coords * frame_size, frame_size)
	var key := [sprite.texture, region, alpha_threshold, contour_simplification]
	if not _contours.has(key):
		var image := sprite.texture.get_image()
		if image == null or image.is_empty():
			return
		if image.is_compressed():
			image.decompress()
		image = image.get_region(region)
		var bitmap := BitMap.new()
		bitmap.create_from_image_alpha(image, alpha_threshold)
		_contours[key] = bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, image.get_size()), contour_simplification)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 0
	# Local outline coordinates use positive Y as up, unlike Vector2.UP (0, -1).
	var normal := _to_axis(Vector2.RIGHT, sprite.axis).cross(_to_axis(Vector2.DOWN, sprite.axis))
	normal = (sprite.global_basis.inverse().transposed() * normal).normalized()
	for polygon: PackedVector2Array in _contours[key]:
		var points := PackedVector3Array()
		for pixel in polygon:
			var uv := pixel / Vector2(frame_size)
			if sprite.flip_h:
				uv.x = 1.0 - uv.x
			if sprite.flip_v:
				uv.y = 1.0 - uv.y
			var point: Vector2
			if custom_edges:
				point = Vector2(lerpf(-distances.x, distances.y, uv.x), lerpf(distances.z, -distances.w, uv.y))
			else:
				var rect := sprite.get_item_rect()
				point = (rect.position + uv * rect.size) * sprite.pixel_size
				point.y = -point.y
			var world_point := sprite.global_transform * _to_axis(point, sprite.axis)
			# The sprite faces along its positive local normal. Move the outline
			# slightly in the opposite direction so the sprite wins depth testing.
			world_point -= normal * depth_offset
			points.append(world_point)
		var path := Path3D.new()
		path.name = "OutlinePath" if count == 0 else "OutlinePath_%d" % count
		path.curve = Curve3D.new()
		for point in points:
			path.curve.add_point(point)
		path.curve.add_point(points[0])
		entry.container.add_child(path)
		_stroke(surface, points, normal)
		count += 1
	if count > 0 and outline_width > 0.0:
		entry.mesh.mesh = surface.commit()

func _to_axis(point: Vector2, axis: int) -> Vector3:
	if axis == Vector3.AXIS_X:
		return Vector3(0.0, point.y, -point.x)
	if axis == Vector3.AXIS_Y:
		return Vector3(point.x, 0.0, -point.y)
	return Vector3(point.x, point.y, 0.0)

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)

func _stroke(surface: SurfaceTool, points: PackedVector3Array, normal: Vector3) -> void:
	var radius := outline_width * 0.5
	if radius <= 0.0:
		return
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var direction := (b - a).normalized()
		if direction.is_zero_approx():
			continue
		var side := normal.cross(direction).normalized()
		var delta := side * radius
		_triangle(surface, a - delta, b - delta, b + delta)
		_triangle(surface, a - delta, b + delta, a + delta)
		# Rounded joins keep sharp corners from leaving gaps.
		for segment in 12:
			var angle_a := TAU * float(segment) / 12.0
			var angle_b := TAU * float(segment + 1) / 12.0
			_triangle(surface, a,
				a + radius * (side * cos(angle_a) + direction * sin(angle_a)),
				a + radius * (side * cos(angle_b) + direction * sin(angle_b)))
