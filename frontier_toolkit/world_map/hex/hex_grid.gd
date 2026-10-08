class_name HexGrid
extends RefCounted

var definition: WorldMapDefinition
var cells: Dictionary = {}

func _init(map_definition: WorldMapDefinition) -> void:
	definition = map_definition
	for q in definition.width:
		for row in definition.height:
			var hex := HexMath.cell_to_axial(Vector2i(q, row))
			cells[hex] = {"axial": hex, "enabled": definition.is_valid_hex(hex), "terrain": &"grass", "custom": {}}

func contains(point: Vector2) -> bool:
	return definition.contains(point)
