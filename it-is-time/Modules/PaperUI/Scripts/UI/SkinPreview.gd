extends Control
## Standalone visual sandbox. No controller, model, disk IO, or gameplay requests.
@export var preview_preset: Resource = preload("res://Modules/PaperUI/Assets/UI/PaperRelief/DefaultSkin.tres")
func _ready() -> void:
	%Apply.pressed.connect(func(): _apply(true))
	%Restore.pressed.connect(func(): _apply(false))
func _apply(active: bool) -> void:
	for target in [%ShortButton,%LongButton,%PreviewPaper,%Portrait,%Book]:
		var slots = target.get_node("VisualSkin")
		slots.local_preset = preview_preset
		slots.enabled = active
