class_name DamageNumber3D
extends "res://Scripts/VFX/SampleFloatingText3D.gd"

@export_group("Damage Number")
@export var damage_color: Color = Color(1.0, 0.22, 0.12, 1.0)
@export_range(0, 3, 1) var decimal_places: int = 1

var damage_amount: float = 0.0

func setup_damage(amount: float) -> void:
	damage_amount = maxf(amount, 0.0)
	setup_text(_format_damage(damage_amount), damage_color)

func _format_damage(amount: float) -> String:
	var rounded_amount := roundf(amount)
	if is_equal_approx(amount, rounded_amount):
		return str(int(rounded_amount))
	return ("%.*f" % [decimal_places, amount])
