extends SceneTree

func _initialize() -> void:
	var definition := WorldMapDefinition.new()
	for q in range(-10, 10):
		for r in range(-10, 10):
			var hex := Vector2i(q, r)
			assert(HexMath.world_to_axial(HexMath.axial_to_world(hex, 64), 64) == hex)
			assert(HexMath.cell_to_axial(HexMath.axial_to_cell(hex)) == hex)
	assert(HexMath.cells_in_range(Vector2i.ZERO, 2).size() == 19)
	assert(HexMath.distance(Vector2i.ZERO, Vector2i(2, -3)) == 3)
	definition.disabled_hexes = [Vector2i(2, 2)]
	assert(not definition.contains(HexMath.axial_to_world(Vector2i(2, 2), 64)))
	var state := WorldMapRuntimeState.new()
	state.map_id = &"validation"
	state.player_position = Vector2(14, 27)
	var roundtrip := WorldMapRuntimeState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert(roundtrip.player_position == state.player_position)
	print("DATA VALIDATION PASS: 400 axial/world/cell roundtrips, range, distance, disabled bounds, JSON")
	quit(0)
