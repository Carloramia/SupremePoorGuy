class_name LocationDefinition
extends Resource

enum CompletionBehavior { KEEP, HIDE_SESSION, REMOVE_PERMANENTLY, RESPAWNABLE }

@export var type_id: StringName = &"settlement"
@export var display_name: String = "Location"
@export_multiline var short_description: String = ""
@export var icon: Texture2D
@export var marker_color: Color = Color("e7bd76")
@export var marker_glyph: String = "S"
@export var repeatable: bool = false
@export var completion_behavior: CompletionBehavior = CompletionBehavior.KEEP
@export var interaction_ui_scene: PackedScene
@export var scenario_scene: PackedScene
@export var encounter_data: Dictionary = {}
