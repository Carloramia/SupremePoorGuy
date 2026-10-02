extends Button

signal build_requested

func _ready() -> void:
	pressed.connect(_on_pressed)

func _on_pressed() -> void:
	build_requested.emit()

func set_build_available(available: bool) -> void:
	disabled = not available
