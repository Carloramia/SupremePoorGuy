extends "res://Scripts/Items/TemporaryAttackHitbox3D.gd"

var head: PhysicalBodyPart3D
var contacted_parts: Dictionary = {}
var peak_impulse := 0.0

func get_attack_debug_shapes() -> Array[Dictionary]:
	if not is_instance_valid(head) or not head.is_inside_tree() or head.is_queued_for_deletion() or head.is_broken: return []
	return super.get_attack_debug_shapes()

func _init() -> void: damage_label = &"snake_bite_hit"
func effective_mass() -> float: return body.mass+head.mass

func apply_contact_damage(other: PhysicalBodyPart3D, impulse: float) -> float:
	contacted_parts[other.get_instance_id()] = true
	peak_impulse = maxf(peak_impulse,impulse)
	return super.apply_contact_damage(other,impulse)

## Keep the mouth volume on the Head, but use the moving Jaw's contact velocity for damage.
func pose() -> Transform3D:
	return Transform3D(head.global_basis.orthonormalized(),head.to_global(center_offset))
