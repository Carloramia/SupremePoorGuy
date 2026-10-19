extends Node

signal active_rules_changed(rules: Resource)
signal attack_contact(details: Dictionary)

const DEFAULT_RULES: Resource = preload("res://Resources/Damage/DefaultDamageRules.tres")

var active_rules: Resource = DEFAULT_RULES
var _attack_sequence := 0

func create_attack_context(character: Node, action_multiplier: float = 1.0, fallback_mass: float = 1.0) -> Dictionary:
	_attack_sequence += 1
	var body_mass := fallback_mass
	var rune_multiplier := 1.0
	if is_instance_valid(character):
		if character.has_method("get_base_combat_mass"): body_mass = character.get_base_combat_mass()
		rune_multiplier = float(character.get_meta(&"summon_damage_multiplier",1.0))
	return {"id":_attack_sequence,"mass":body_mass,"action_multiplier":action_multiplier,"rune_multiplier":rune_multiplier,"multiplier":action_multiplier*rune_multiplier,"hits":{}}

func register_attack_hit(context: Dictionary, target: Node) -> bool:
	if context.is_empty() or not is_instance_valid(target): return false
	var id := target.get_instance_id()
	if context.hits.has(id): return false
	context.hits[id] = true
	return true

func calculate_attack_raw_damage(impulse: float, context: Dictionary, contact_mass: float = 1.0) -> float:
	if active_rules != null and active_rules.has_method("calculate_attack_raw_damage"):
		return float(active_rules.call("calculate_attack_raw_damage",impulse,context,contact_mass))
	return calculate_weapon_raw_damage(impulse,true) * float(context.get("multiplier",1.0))

func calculate_raw_damage(impulse: float) -> float:
	if active_rules == null or not active_rules.has_method("calculate_raw_damage"):
		return 0.0
	return float(active_rules.call("calculate_raw_damage", impulse))

func apply_armor(raw_damage: float, armor: float, resilience: float = 0.0) -> float:
	if active_rules != null and active_rules.has_method("apply_defenses"):
		return float(active_rules.call("apply_defenses",raw_damage,armor,resilience))
	if active_rules == null or not active_rules.has_method("apply_armor"):
		return 0.0
	if not is_finite(resilience) or resilience < 0.0: return 0.0
	return float(active_rules.call("apply_armor", raw_damage * (100.0/(100.0+resilience)), armor))

func calculate_damage(impulse: float, armor: float, resilience: float = 0.0) -> float:
	return apply_armor(calculate_raw_damage(impulse), armor,resilience)

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

func apply_weapon_armor(raw_damage: float, armor: float, swinging: bool, resilience: float = 0.0) -> float:
	if active_rules != null and active_rules.has_method("apply_weapon_defenses"):
		return float(active_rules.call("apply_weapon_defenses",raw_damage,armor,resilience,swinging))
	if active_rules != null and active_rules.has_method("apply_weapon_armor"):
		if not is_finite(resilience) or resilience < 0.0: return 0.0
		return float(active_rules.call("apply_weapon_armor", raw_damage * (100.0/(100.0+resilience)), armor, swinging))
	return apply_armor(raw_damage, armor,resilience)

func calculate_weapon_damage(impulse: float, armor: float, swinging: bool) -> float:
	return apply_weapon_armor(calculate_weapon_raw_damage(impulse, swinging), armor, swinging)
