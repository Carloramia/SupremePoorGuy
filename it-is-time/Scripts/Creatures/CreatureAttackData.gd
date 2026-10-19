@tool
extends Resource

@export var enabled: bool = true
@export_range(0.0, 20.0, 0.01, "or_greater") var damage_multiplier: float = 1.0
@export_range(0.0, 20.0, 0.01, "or_greater") var cooldown: float = 1.2

func _init() -> void:
	cooldown = _default_cooldown()

func _default_cooldown() -> float: return 1.2

func _property_can_revert(property: StringName) -> bool:
	return property == &"cooldown"

func _property_get_revert(_property: StringName) -> Variant:
	return _default_cooldown()
