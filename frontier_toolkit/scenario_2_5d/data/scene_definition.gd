class_name SceneDefinition
extends Resource

@export var scene_id: StringName = &"outpost"
@export var display_name: String = "Paper Outpost"
@export var camera_bounds: Rect2 = Rect2(-18, -14, 36, 28)
@export var default_camera_size: float = 20.0
@export var min_camera_size: float = 10.0
@export var max_camera_size: float = 26.0
@export var camera_drag_smoothing: float = 20.0
@export var camera_zoom_smoothing: float = 12.0
@export var camera_margin: float = 2.0
@export var zoom_step: float = 1.5
@export var default_scene_mode: SceneMode.Mode = SceneMode.Mode.EXPLORE
@export var metadata: Dictionary = {}
