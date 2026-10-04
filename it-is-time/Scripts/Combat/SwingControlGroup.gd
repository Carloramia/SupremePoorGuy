class_name SwingControlGroup
extends Resource

@export_group("Identity")
@export var group_name: StringName = &"PrimarySwing"
@export var enabled: bool = true
@export var input_action: StringName = &"MouseLeft"

func _init() -> void:
	resource_local_to_scene = true

