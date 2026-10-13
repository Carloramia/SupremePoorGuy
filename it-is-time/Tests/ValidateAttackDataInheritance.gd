extends SceneTree

const COMMON = preload("res://Scripts/Creatures/CreatureAttackData.gd")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void:
	var defaults := {"WolfAttackData": 1.2, "SpiderPounceData": 2.0, "CreatureActionData": 0.4, "ChargeAttackData": 5.0, "BirdDiveAttackData": 2.5}
	for label: String in defaults:
		var script: Script = load("res://Scripts/Creatures/%s.gd" % label)
		check(script.is_tool(), "Inherited preset defaults must also initialize in the editor: %s" % label)
		var data: Resource = script.new()
		check(data is COMMON and data.enabled and is_equal_approx(data.cooldown, defaults[label]), "Shared attack inheritance must preserve defaults for %s" % label)
		check(data.property_can_revert(&"cooldown") and is_equal_approx(data.property_get_revert(&"cooldown"), defaults[label]), "Inspector reset must use the species default for %s" % label)
	var presets := {"Attacks/WolfPounce": 2.5, "Attacks/WolfBite": 0.8, "Actions/SpiderPounce": 2.0, "Actions/ForeLegStomp": 0.4, "Actions/StumpBeastForeLegStomp": 0.4, "Actions/HornedBeastForeLegStomp": 0.4, "Actions/WolfForeLegStomp": 0.4, "Actions/GroundCharge": 5.0, "Actions/BirdDiveAttack": 2.5}
	for label: String in presets:
		var data: Resource = load("res://Resources/%s.tres" % label)
		check(data is COMMON and data.enabled and is_equal_approx(data.cooldown, presets[label]), "Existing preset must retain its authored availability and cooldown: %s" % label)
		var copy: Resource = data.duplicate(true)
		copy.enabled = false
		copy.cooldown = 0.35
		check(data.enabled and is_equal_approx(copy.cooldown, 0.35), "Inherited fields must remain independently editable on copied resources")
	var bite: Resource = load("res://Resources/Attacks/WolfBite.tres")
	check(is_equal_approx(bite.jaw_open_degrees, 40.0) and is_equal_approx(bite.bite_plant_timeout, 8.0), "Shared fields must not alter species-specific action settings")
	print("ATTACK_DATA_INHERITANCE ", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
