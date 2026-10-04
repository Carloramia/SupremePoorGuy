class_name DamageRules
extends Resource

## Project-wide weapon impact profiles. Only effective swing contacts use the minimum swing damage.

@export_group("Passive Impulse Conversion")
@export_range(0.0, 1000.0, 0.1, "or_greater") var impulse_threshold: float = 5.0
@export_range(0.0, 100.0, 0.1, "or_greater") var impulse_multiplier: float = 2.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var maximum_damage_per_hit: float = 100.0

@export_group("Swing Impacts")
@export_range(0.0, 1000.0, 0.1, "or_greater") var swing_impulse_threshold: float = 1.0
@export_range(0.0, 100.0, 0.1, "or_greater") var swing_impulse_multiplier: float = 12.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var minimum_swing_raw_damage: float = 110.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var maximum_swing_raw_damage: float = 145.0

@export_group("Passive Impacts")
@export_range(0.0, 1.0, 0.01) var passive_damage_multiplier: float = 0.05
@export_range(0.0, 1000.0, 0.1, "or_greater") var maximum_passive_damage_per_hit: float = 2.0

func calculate_weapon_raw_damage(impulse: float, swinging: bool) -> float:
	if not swinging:
		return calculate_raw_damage(impulse)
	if impulse <= swing_impulse_threshold:
		return 0.0
	return minf(maxf((impulse - swing_impulse_threshold) * swing_impulse_multiplier, minimum_swing_raw_damage), maximum_swing_raw_damage)

func apply_weapon_armor(raw_damage: float, armor: float, swinging: bool) -> float:
	var damage := apply_armor(raw_damage, armor)
	return damage if swinging else minf(damage * passive_damage_multiplier, maximum_passive_damage_per_hit)

func calculate_raw_damage(impulse: float) -> float:
	if impulse <= impulse_threshold:
		return 0.0
	return minf(
		maxf(impulse - impulse_threshold, 0.0) * impulse_multiplier,
		maximum_damage_per_hit
	)

func apply_armor(raw_damage: float, armor: float) -> float:
	return maxf(raw_damage - maxf(armor, 0.0), 0.0)

func calculate_damage(impulse: float, armor: float) -> float:
	return apply_armor(calculate_raw_damage(impulse), armor)
