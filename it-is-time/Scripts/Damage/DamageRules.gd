class_name DamageRules
extends Resource

## Active attacks scale with naked body mass; passive impacts retain their weak impulse profile.

const BALANCE_REVISION := 2
@export_group("Active Attack And Health")
@export_range(0.0, 1000.0, 0.1, "or_greater") var base_attack_damage: float = 35.0
@export_range(0.0, 1000.0, 0.1, "or_greater") var hp_per_mass: float = 40.0
@export_range(0.001, 100.0, 0.01, "or_greater") var reference_impact_speed: float = 3.0
@export_range(0.0, 1.0, 0.001) var minimum_relative_impulse: float = 0.001
@export_range(0.0, 2.0, 0.01) var minimum_hit_quality: float = 0.95
@export_range(0.0, 2.0, 0.01) var maximum_hit_quality: float = 1.05

@export_group("Passive Impulse Conversion")
@export_range(0.0, 1000.0, 0.1, "or_greater") var impulse_threshold: float = 5.0
@export_range(0.0, 100.0, 0.1, "or_greater") var impulse_multiplier: float = 2.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var maximum_damage_per_hit: float = 100.0

@export_group("Passive Impacts")
@export_range(0.0, 1.0, 0.01) var passive_damage_multiplier: float = 0.05
@export_range(0.0, 1000.0, 0.1, "or_greater") var maximum_passive_damage_per_hit: float = 2.0

func calculate_weapon_raw_damage(impulse: float, swinging: bool) -> float:
	if not swinging:
		return calculate_raw_damage(impulse)
	return calculate_attack_raw_damage(impulse, {"mass":1.0,"multiplier":1.0})

func health_for_mass(mass: float) -> float:
	return mass * hp_per_mass if is_finite(mass) and mass > 0.0 else 0.0

func hit_quality(impulse: float, contact_mass: float) -> float:
	if not is_finite(impulse) or not is_finite(contact_mass) or impulse <= 0.0 or contact_mass <= 0.0: return 0.0
	var reference := contact_mass * reference_impact_speed
	if reference <= 0.0 or impulse <= reference * minimum_relative_impulse: return 0.0
	return clampf(impulse / reference, minimum_hit_quality, maxf(maximum_hit_quality, minimum_hit_quality))

func calculate_attack_raw_damage(impulse: float, context: Dictionary, contact_mass: float = 1.0) -> float:
	var body_mass := float(context.get("mass",0.0))
	var multiplier := float(context.get("multiplier",1.0))
	if not is_finite(body_mass) or not is_finite(multiplier) or body_mass <= 0.0 or multiplier < 0.0: return 0.0
	return base_attack_damage * pow(body_mass,1.0/3.0) * multiplier * hit_quality(impulse,contact_mass)

## Resilience has no gameplay clamp; malformed or negative data is rejected.
func apply_defenses(raw_damage: float, armor: float, resilience: float = 0.0) -> float:
	if not is_finite(raw_damage) or not is_finite(armor) or not is_finite(resilience) or raw_damage < 0.0 or armor < 0.0 or resilience < 0.0: return 0.0
	return maxf(raw_damage * (100.0 / (100.0 + resilience)) - armor, 0.0)

func apply_weapon_defenses(raw_damage: float, armor: float, resilience: float, swinging: bool) -> float:
	var damage := apply_defenses(raw_damage,armor,resilience)
	return damage if swinging else minf(damage * passive_damage_multiplier,maximum_passive_damage_per_hit)

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
	return apply_defenses(raw_damage,armor)

func calculate_damage(impulse: float, armor: float) -> float:
	return apply_armor(calculate_raw_damage(impulse), armor)
