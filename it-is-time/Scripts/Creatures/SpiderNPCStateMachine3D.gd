extends "res://Scripts/Creatures/NPCStateMachine3D.gd"

## Spiders currently have no ForeLeg attack. Keep pursuit usable until an
## applicable attack receiver is configured; configured attacks use the base logic.
func _plan_attack_distance(distance: float, attacks: Array[ATTACK]) -> bool:
	if not attacks.is_empty(): return super._plan_attack_distance(distance, attacks)
	_distance_attack = null
	_distance_error = 0.0
	if behavior == null or not is_instance_valid(_target): return false
	var desired := maxf(behavior.preferred_distance, arrival_distance)
	_distance_error = distance - desired
	if distance <= desired + arrival_distance: return false
	var away := (_get_navigation_origin_position() - _target.global_position).slide(Vector3.UP).normalized()
	if away.is_zero_approx(): return false
	_set_agent_target(_target.global_position + away * desired)
	return true
