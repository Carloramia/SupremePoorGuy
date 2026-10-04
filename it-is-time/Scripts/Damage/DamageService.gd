extends Node

signal active_rules_changed(rules: Resource)

const DEFAULT_RULES: Resource = preload("res://Resources/Damage/DefaultDamageRules.tres")

var active_rules: Resource = DEFAULT_RULES

func calculate_raw_damage(impulse: float) -> float:
	if active_rules == null or not active_rules.has_method("calculate_raw_damage"):
		return 0.0
	return float(active_rules.call("calculate_raw_damage", impulse))

func apply_armor(raw_damage: float, armor: float) -> float:
	if active_rules == null or not active_rules.has_method("apply_armor"):
		return 0.0
	return float(active_rules.call("apply_armor", raw_damage, armor))

func calculate_damage(impulse: float, armor: float) -> float:
	return apply_armor(calculate_raw_damage(impulse), armor)

func set_active_rules(rules: Resource) -> bool:
	if rules == null:
		return false
	if not rules.has_method("calculate_raw_damage") or not rules.has_method("apply_armor"):
		push_warning("Damage rules must implement calculate_raw_damage() and apply_armor().")
		return false
	active_rules = rules
	active_rules_changed.emit(active_rules)
	return true

func reset_active_rules() -> void:
	active_rules = DEFAULT_RULES
	active_rules_changed.emit(active_rules)

func get_active_rules() -> Resource:
	return active_rules

## Context-aware weapon damage; legacy custom rules retain their existing conversion behavior.
func calculate_weapon_raw_damage(impulse: float, swinging: bool) -> float:
	if active_rules != null and active_rules.has_method("calculate_weapon_raw_damage"):
		return float(active_rules.call("calculate_weapon_raw_damage", impulse, swinging))
	return calculate_raw_damage(impulse)

func apply_weapon_armor(raw_damage: float, armor: float, swinging: bool) -> float:
	if active_rules != null and active_rules.has_method("apply_weapon_armor"):
		return float(active_rules.call("apply_weapon_armor", raw_damage, armor, swinging))
	return apply_armor(raw_damage, armor)

func calculate_weapon_damage(impulse: float, armor: float, swinging: bool) -> float:
	return apply_weapon_armor(calculate_weapon_raw_damage(impulse, swinging), armor, swinging)
