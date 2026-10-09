class_name WorldMapHexDebugOverlay
extends Node2D

var definition: WorldMapDefinition

func _draw() -> void:
	if definition == null:
		return
	var font := ThemeDB.fallback_font
	for hex in definition.enabled_cells():
		var center := HexMath.axial_to_world(hex, definition.hex_size)
		var vertices := HexMath.polygon(center, definition.hex_size)
		draw_polyline(vertices + PackedVector2Array([vertices[0]]), Color(0.8, 0.95, 0.87, 0.8), 1.5, true)
		var label := "(%d, %d)" % [hex.x, hex.y]
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var baseline := center + Vector2(-text_size.x * 0.5, 5)
		draw_string(font, baseline + Vector2.ONE, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("0b1820"))
		draw_string(font, baseline, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e5f5df"))
