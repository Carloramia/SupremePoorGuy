class_name InteractableDefinition
extends Resource

@export var object_id: StringName
@export var display_name: String
@export var interaction_type: StringName = &"inspect"
@export_multiline var description: String
@export var icon: Texture2D
@export var tags: PackedStringArray = []
@export var metadata: Dictionary = {}
