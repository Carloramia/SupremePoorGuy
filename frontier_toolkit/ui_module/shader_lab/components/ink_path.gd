@tool
extends "res://ui_module/shader_lab/components/visual_base.gd"
const InkShader = preload("res://ui_module/shader_lab/shaders/ink.gdshader")
## Frame, separator, or authored normalized path. Centerline remains fixed.
@export_enum("Rounded frame", "Separator", "Editable path") var shape: int = 0:
	set(value):
		shape = value
		_refresh()
@export var path := PackedVector2Array([Vector2(0.1, 0.5), Vector2(0.9, 0.5)]):
	set(value):
		path = value
		_refresh()
@export var closed := false:
	set(value):
		closed = value
		_refresh()
@export_range(0.0, 64.0) var corner_radius := 12.0:
	set(value):
		corner_radius = value
		_refresh()
@export var inset := 5.0:
	set(value):
		inset = value
		_refresh()
## Disable companion strokes for dense icons and accurate ritual input lines.
@export var allow_repeat := true:
	set(value):
		allow_repeat = value
		_refresh()
@export var protect_centerline := true:
	set(value):
		protect_centerline = value
		_refresh()

func _refresh() -> void:
	if not is_inside_tree() or profile == null:
		return
	if material == null:
		material = ShaderMaterial.new()
		material.shader = InkShader
	var mat := material as ShaderMaterial
	mat.set_shader_parameter("seed", profile.seed)
	mat.set_shader_parameter("grain_size", profile.grain_size)
	mat.set_shader_parameter("ink_loss", profile.ink_loss if profile.s1_enabled or profile.s3_enabled else 0.0)
	mat.set_shader_parameter("edge_roughness", minf(1.0, profile.edge_size / 4.0) if profile.s1_enabled or profile.s3_enabled else 0.0)
	mat.set_shader_parameter("edge_coverage", profile.edge_coverage if profile.s1_enabled or profile.s3_enabled else 0.0)
	mat.set_shader_parameter("protected_core", 0.6 if protect_centerline else 0.3)
	queue_redraw()

func centerline() -> PackedVector2Array:
	var points := PackedVector2Array()
	if shape == 1:
		return PackedVector2Array([Vector2(inset, size.y * 0.5), Vector2(size.x - inset, size.y * 0.5)])
	if shape == 2:
		for p in path:
			points.append(p * size)
		if closed and points.size() > 1:
			points.append(points[0])
		return points
	var r := minf(corner_radius, minf(size.x, size.y) * 0.5 - inset)
	r = maxf(0.1, r)
	var centers := [Vector2(size.x - inset - r, inset + r), Vector2(size.x - inset - r, size.y - inset - r), Vector2(inset + r, size.y - inset - r), Vector2(inset + r, inset + r)]
	for corner in 4:
		for step_index in 9:
			var angle := -PI * 0.5 + corner * PI * 0.5 + step_index * PI / 16.0
			points.append(centers[corner] + Vector2(cos(angle), sin(angle)) * r)
	points.append(points[0])
	return points

func _draw() -> void:
	if profile == null:
		return
	var points := centerline()
	if points.size() < 2:
		return
	var length_sum := 0.0
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var distance := a.distance_to(b)
		var tangent := (b - a).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var steps := maxi(1, ceili(distance / 4.0))
		for j in steps:
			var t0 := float(j) / steps
			var t1 := float(j + 1) / steps
			var s0 := length_sum + distance * t0
			var s1 := length_sum + distance * t1
			var p0 := a.lerp(b, t0)
			var p1 := a.lerp(b, t1)
			var w0 := _width(s0)
			var w1 := _width(s1)
			# Offset is bounded by protected ink core; authored input path is untouched.
			var offset0 := _offset(s0)
			var offset1 := _offset(s1)
			p0 += normal * offset0
			p1 += normal * offset1
			_ribbon(p0, p1, normal, w0, w1, profile.ink_color, s0, s1)
			if profile.s1_enabled and allow_repeat and sin(s0 * 0.043 + profile.seed) > 0.5:
				var echo := profile.ink_color as Color
				echo.a *= profile.repeat_strength
				_ribbon(p0 + normal * (w0 + 1.4), p1 + normal * (w1 + 1.4), normal, w0 * 0.28, w1 * 0.28, echo, s0, s1)
		length_sum += distance
	# Adjacent ribbons overlap across the protected authored centerline.

func _width(s: float) -> float:
	var pressure := 1.0
	if profile.s1_enabled:
		pressure += profile.width_variation * (sin(s * 0.071 + profile.seed) * 0.65 + sin(s * 0.153) * 0.35)
	return maxf(0.25, profile.line_width * 0.5 * pressure)

func _offset(s: float) -> float:
	if not profile.s1_enabled:
		return 0.0
	return sin(s * 0.092 + profile.seed) * minf(profile.irregularity, profile.line_width * 0.18)

func _ribbon(a: Vector2, b: Vector2, n: Vector2, wa: float, wb: float, color: Color, s0: float, s1: float) -> void:
	draw_polygon(PackedVector2Array([a - n * wa, b - n * wb, b + n * wb, a + n * wa]), PackedColorArray([color]), PackedVector2Array([Vector2(s0, 0), Vector2(s1, 0), Vector2(s1, 1), Vector2(s0, 1)]))

