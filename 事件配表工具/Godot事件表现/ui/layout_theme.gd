extends RefCounted
## Wireframe palette only. Replace this file's styles when art direction is settled.
const TEXT := Color("e7e8ea")
const MUTED := Color("a5a9af")
const BORDER := Color("626870")
const PANEL := Color("292d33")
const WELL := Color("1c2025")
const ACCENT := Color("cad2dd")

static func create() -> Theme:
	var result := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "SimHei"])
	result.default_font = font
	result.default_font_size = 18
	return result

static func style(bg: Color = PANEL, border: Color = BORDER, margin := 12) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = bg
	result.border_color = border
	result.set_border_width_all(1)
	result.set_corner_radius_all(4)
	result.content_margin_left = margin
	result.content_margin_right = margin
	result.content_margin_top = margin
	result.content_margin_bottom = margin
	return result

static func label(value: String, font_size := 18, color: Color = TEXT) -> Label:
	var result := Label.new()
	result.text = value
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func button(value: String, primary := false) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size.y = 42
	result.add_theme_font_size_override("font_size", 18)
	result.add_theme_color_override("font_color", Color("20252c") if primary else TEXT)
	result.add_theme_color_override("font_hover_color", Color("20252c") if primary else TEXT)
	result.add_theme_color_override("font_pressed_color", Color("20252c") if primary else TEXT)
	result.add_theme_color_override("font_focus_color", Color("20252c") if primary else TEXT)
	result.add_theme_color_override("font_disabled_color", MUTED)
	result.add_theme_stylebox_override("normal", style(ACCENT if primary else WELL))
	result.add_theme_stylebox_override("hover", style(Color("e3e8ef") if primary else Color("404750"), TEXT))
	result.add_theme_stylebox_override("pressed", style(Color("a3adba") if primary else PANEL, TEXT))
	result.add_theme_stylebox_override("disabled", style(WELL))
	return result

static func panel(bg: Color = WELL, margin := 12) -> PanelContainer:
	var result := PanelContainer.new()
	result.add_theme_stylebox_override("panel", style(bg, BORDER, margin))
	return result
