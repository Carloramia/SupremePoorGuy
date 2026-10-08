class_name WorldMapDefinition
extends Resource

@export var map_id: StringName = &"frontier"
@export var display_name: String = "THE FRONTIER"
@export_range(1, 100) var width: int = 16
@export_range(1, 100) var height: int = 12
@export_range(8, 200) var hex_size: float = 64.0
@export var disabled_hexes: Array[Vector2i] = []
@export var default_spawn_id: StringName = &"harbor"
@export var spawns: Dictionary = {"harbor": Vector2(120, 220)}
@export var discovery_radius: float = 240.0
@export var interaction_radius: float = 42.0
@export var vision_radius: float = 210.0
@export var generator_config: Dictionary = {}
@export var editor_data: Dictionary = {} # Initial authoring data; never a runtime save.

func is_valid_hex(hex: Vector2i) -> bool:
	var cell := HexMath.axial_to_cell(hex)
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height and not disabled_hexes.has(hex)

func contains(point: Vector2) -> bool:
	return is_valid_hex(HexMath.world_to_axial(point, hex_size))

func enabled_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for q in width:
		for row in height:
			var hex := HexMath.cell_to_axial(Vector2i(q, row))
			if is_valid_hex(hex):
				result.append(hex)
	return result

func world_rect() -> Rect2:
	return Rect2(Vector2(-hex_size, -hex_size), Vector2((width - 1) * 1.5 * hex_size + 2 * hex_size, (height + 0.5) * sqrt(3.0) * hex_size))

func spawn_position(spawn_id: StringName = &"") -> Vector2:
	var key := spawn_id if not spawn_id.is_empty() else default_spawn_id
	if not spawns.has(String(key)):
		push_warning("Unknown spawn: %s; using default" % key)
		key = default_spawn_id
	return spawns.get(String(key), Vector2.ZERO)
