extends "res://Scripts/Items/TemporaryAttackHitbox3D.gd"

var head: PhysicalBodyPart3D
var contacted_parts: Dictionary = {}
var peak_impulse := 0.0

func _init() -> void: damage_label = &"snake_bite_hit"
func effective_mass() -> float: return body.mass+head.mass

func apply_contact_damage(other: PhysicalBodyPart3D, impulse: float) -> float:
	contacted_parts[other.get_instance_id()] = true
	peak_impulse = maxf(peak_impulse,impulse)
	return super.apply_contact_damage(other,impulse)

## Keep the mouth volume on the Head, but use the moving Jaw's contact velocity for damage.
func pose() -> Transform3D:
	return Transform3D(head.global_basis.orthonormalized(),head.to_global(center_offset))
