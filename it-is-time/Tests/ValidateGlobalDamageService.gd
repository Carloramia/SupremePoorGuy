extends SceneTree

const DAMAGE_RULES_SCRIPT: Script = preload("res://Scripts/Damage/DamageRules.gd")

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var service := root.get_node_or_null("DamageService")
	assert(service != null, "DamageService must be available in every level through Autoload")
	var default_rules: Resource = service.get_active_rules()
	assert(default_rules != null)
	assert(default_rules.resource_path == "res://Resources/Damage/DefaultDamageRules.tres")
	assert(is_zero_approx(service.calculate_raw_damage(5.0)))
	assert(is_equal_approx(service.calculate_raw_damage(20.0), 30.0))
	assert(is_equal_approx(service.calculate_damage(20.0, 8.0), 22.0))
	assert(is_equal_approx(service.calculate_raw_damage(100.0), 100.0))

	assert(is_zero_approx(service.calculate_weapon_damage(1.0, 8.0, true)))
	assert(is_equal_approx(service.calculate_weapon_damage(2.7, 15.0, true), 95.0))
	assert(is_equal_approx(service.calculate_weapon_damage(2.7, 10.0, true), 100.0))
	assert(is_equal_approx(service.calculate_weapon_damage(20.0, 8.0, false), 1.1))
	assert(service.calculate_weapon_damage(10000.0, 0.0, false) <= 2.0)

	var alternate_rules: Resource = DAMAGE_RULES_SCRIPT.new()
	alternate_rules.impulse_threshold = 10.0
	alternate_rules.impulse_multiplier = 3.0
	alternate_rules.maximum_damage_per_hit = 50.0
	assert(service.set_active_rules(alternate_rules))
	assert(is_zero_approx(service.calculate_raw_damage(10.0)))
	assert(is_equal_approx(service.calculate_raw_damage(20.0), 30.0))
	assert(is_equal_approx(service.calculate_raw_damage(100.0), 50.0))
	assert(is_equal_approx(service.calculate_damage(20.0, 12.0), 18.0))
	service.reset_active_rules()
	assert(service.get_active_rules() == default_rules)
	print("GLOBAL_DAMAGE_SERVICE_VALIDATION_PASSED")
	quit()
