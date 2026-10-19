extends Control
## Screen-space selection affordance, with no extra creature collisions.
var entries: Array[Dictionary] = []
var selected := -1
var hovered: Array[int] = []
var accents: Array[Dictionary] = []

func _draw() -> void:
	for accent: Dictionary in accents:
		var center: Vector2 = accent.center
		var radius: float = accent.radius
		var strength: float = accent.strength
		if accent.kind == "join":
			# Four restrained registration marks: a brief paper-joint lock cue.
			for i: int in 4:
				var direction := Vector2.from_angle(PI * 0.25 + i * PI * 0.5)
				draw_line(center + direction * radius, center + direction * (radius + 4), Color(0.65, 0.88, 0.8, strength), 1.5, true)
		else:
			# Ground contact ticks expand and vanish; no persistent extra shadows.
			for i: int in 6:
				var direction := Vector2.from_angle(i * TAU / 6) * Vector2(1, 0.36)
				draw_line(center + direction * radius, center + direction * (radius + 5), Color(0.32, 0.29, 0.22, strength), 1.5, true)
	for entry: Dictionary in entries:
		if entry.index != selected and not hovered.has(entry.index): continue
		var is_selected: bool = entry.index == selected
		var color := Color("e9bc67") if is_selected else Color(0.55, 0.88, 0.85, 0.65)
		var rect: Rect2 = entry.rect
		draw_rect(rect.grow(4), color, false, 2.0 if is_selected else 1.0)
		if is_selected:
			var font := ThemeDB.fallback_font
			var label := "#%d  %s" % [entry.index + 1, entry.label]
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 16
			draw_style_box(_label_style(), Rect2(rect.position + Vector2(-4, -27), Vector2(width, 24)))
			draw_string(font, rect.position + Vector2(4, -9), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)

func _label_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.11, 0.95)
	return style
