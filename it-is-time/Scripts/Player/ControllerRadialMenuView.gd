extends Node2D

var menu: CanvasLayer

func _draw() -> void:
	if menu == null or menu.options.is_empty(): return
	var count: int = menu.options.size()
	var span := TAU / count
	var font := ThemeDB.fallback_font
	for index: int in range(count):
		var option: ControllerWheelOption = menu.options[index]
		if option == null: continue
		var middle := -PI * 0.5 + span * index
		var start := middle - span * 0.5
		var subdivisions := maxi(8, ceili(64.0 / count))
		var color: Color = menu.highlight_color if index == menu.hovered_index else menu.background_color
		if not option.enabled: color.a *= 0.4
		# Draw convex annular cells; a full-circle option must not triangulate a polygon with a hole.
		for cell: int in range(subdivisions):
			var a := Vector2.from_angle(start + span * cell / subdivisions)
			var b := Vector2.from_angle(start + span * (cell + 1) / subdivisions)
			draw_colored_polygon(PackedVector2Array([a * menu.outer_radius, b * menu.outer_radius, b * menu.inner_radius, a * menu.inner_radius]), color)
		draw_arc(Vector2.ZERO, menu.outer_radius, start, start + span, subdivisions + 1, Color(1, 1, 1, 0.65), 1.5, true)
		draw_line(Vector2.from_angle(start) * menu.inner_radius, Vector2.from_angle(start) * menu.outer_radius, Color(1, 1, 1, 0.4), 1.0, true)
		var center: Vector2 = Vector2.from_angle(middle) * ((menu.inner_radius + menu.outer_radius) * 0.5)
		var text_size := font.get_string_size(option.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, menu.font_size)
		var text_color: Color = menu.text_color
		if not option.enabled: text_color.a *= 0.4
		if option.icon != null:
			draw_texture_rect(option.icon, Rect2(center - Vector2(16, 36), Vector2(32, 32)), false)
		draw_string(font, center - Vector2(text_size.x * 0.5, -menu.font_size * 0.35), option.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, menu.font_size, text_color)
