@tool
extends RigidBody3D

const OUTLINE_SHADER: Shader = preload("res://Shaders/BodyPartOutline.gdshader")
const MIN_SIZE: float = 0.001

enum BodyPartTag {
	Torso,
	Leg,
	Arm,
	Head,
}

@export_group("Classification")
## A part may carry more than one classification tag.
@export var tags: Array[BodyPartTag] = []

@export_group("BodyPart Edges")
## Distances from the Sprite3D's local origin, in Godot 3D units.
@export_range(0.001, 100.0, 0.01, "or_greater") var left_distance: float = 1.28
@export_range(0.001, 100.0, 0.01, "or_greater") var right_distance: float = 1.28
@export_range(0.001, 100.0, 0.01, "or_greater") var top_distance: float = 1.28
@export_range(0.001, 100.0, 0.01, "or_greater") var bottom_distance: float = 1.28

@export_group("Collision")
## Collision depth perpendicular to the Sprite3D plane.
@export_range(0.001, 100.0, 0.01, "or_greater") var collision_thickness: float = 0.2

@onready var _sprite: Sprite3D = $Sprite3D
@onready var _collision: CollisionShape3D = $CollisionShape3D

var _material: ShaderMaterial
var _last_signature: Array = []

func _ready() -> void:
	_sync_geometry()

func _process(_delta: float) -> void:
	_sync_geometry()

func get_outline_edge_distances() -> Vector4:
	return Vector4(
		maxf(left_distance, MIN_SIZE),
		maxf(right_distance, MIN_SIZE),
		maxf(top_distance, MIN_SIZE),
		maxf(bottom_distance, MIN_SIZE)
	)

func _sync_geometry() -> void:
	if not is_instance_valid(_sprite) or not is_instance_valid(_collision):
		return
	var edges := get_outline_edge_distances()
	var safe_thickness := maxf(collision_thickness, MIN_SIZE)
	var signature := [edges, safe_thickness, _sprite.axis, _sprite.texture]
	if signature == _last_signature:
		return
	_last_signature = signature

	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = OUTLINE_SHADER
		_sprite.material_override = _material
	_material.set_shader_parameter(&"sprite_texture", _sprite.texture)
	_material.set_shader_parameter(&"sprite_axis", _sprite.axis)
	_material.set_shader_parameter(&"edge_distances", edges)
	_sprite.extra_cull_margin = maxf(edges.x + edges.y, edges.z + edges.w)

	var width := edges.x + edges.y
	var height := edges.z + edges.w
	var horizontal_center := (edges.y - edges.x) * 0.5
	var vertical_center := (edges.z - edges.w) * 0.5
	var shape := _collision.shape as BoxShape3D
	if shape == null:
		shape = BoxShape3D.new()
		_collision.shape = shape
	match _sprite.axis:
		Vector3.AXIS_X:
			shape.size = Vector3(safe_thickness, height, width)
			_collision.position = Vector3(0.0, vertical_center, -horizontal_center)
		Vector3.AXIS_Y:
			shape.size = Vector3(width, safe_thickness, height)
			_collision.position = Vector3(horizontal_center, 0.0, -vertical_center)
		_:
			shape.size = Vector3(width, height, safe_thickness)
			_collision.position = Vector3(horizontal_center, vertical_center, 0.0)
