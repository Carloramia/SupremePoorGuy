class_name SpawnPoint3D
extends Marker3D

@export var spawn_id: StringName
@export var metadata: Dictionary = {}

func _ready() -> void:
	add_to_group("scenario_spawn")
