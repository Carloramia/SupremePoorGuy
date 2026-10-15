@tool
extends SceneTree

const DATA = preload("res://Scripts/Creatures/GeneratedCreatureDensityData.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	for species: String in ["Beast", "Bird", "HornedBeast", "Wolf", "Spider", "Ratkin", "Human"]:
		var preset: Resource = load("res://Resources/Creatures/%sDensity.tres" % species)
		assert(preset != null and preset.is_valid(), "%s density preset must be valid" % species)
		for kind: String in DATA.TYPE_PROPERTIES:
			var stored: Variant = preset.get(DATA.TYPE_PROPERTIES[kind])
			assert(stored is float)
			assert(is_equal_approx(preset.get_density(kind, 3.0), stored if stored > 0.0 else 3.0))
		assert(preset.get_density("Unknown", 3.0) == 3.0)
	var preset := DATA.new()
	assert(preset.get_density("Arm", 3.0) == 3.0 and preset.get_density("ArmLimb", 3.0) == 3.0)
	for invalid: float in [-1.0, NAN, INF]:
		preset.arm_limb = invalid
		assert(not preset.is_valid())
		assert(preset.get_density("ArmLimb", 3.0) == 3.0)
	preset.arm_limb = 2.0
	assert(preset.is_valid() and preset.get_density("ArmLimb", 3.0) == 2.0)
	# Reproduce a density field missing from an older editor resource instance.
	var incomplete := GDScript.new()
	var density_script: GDScript = DATA
	var lines := PackedStringArray()
	for line: String in density_script.source_code.split("\n"):
		if not line.contains("var arm_limb: float"):
			lines.append(line)
	incomplete.source_code = "\n".join(lines)
	assert(incomplete.reload() == OK)
	var missing: Resource = incomplete.new()
	assert(missing.get(&"arm_limb") == null)
	var validation: Variant = missing.is_valid()
	assert(typeof(validation) == TYPE_BOOL and validation == false, "Missing density must fail validation without a Nil-to-float error")
	assert(missing.get_density("ArmLimb", 3.0) == 3.0)
	if Engine.is_editor_hint(): check_hot_reload()
	print("PASS: all density presets, arm defaults, invalid values, missing properties and editor hot-reload restoration")
	quit()

func check_hot_reload() -> void:
	var current: GDScript = DATA
	var lines := PackedStringArray()
	for line: String in current.source_code.split("\n"):
		if line.contains("var arm: float") or line.contains("var arm_limb: float") or line.contains('"Arm": &"arm"'):
			continue
		lines.append(line)
	var script := GDScript.new()
	script.source_code = "\n".join(lines)
	assert(script.reload() == OK)
	var stale: Resource = script.new()
	stale.set(&"torso", 9.0)
	var fixture_path := "res://.godot/density_hot_reload_%d.tres" % stale.get_instance_id()
	var saved := DATA.new()
	saved.arm = 1.7
	saved.arm_limb = 2.3
	assert(ResourceSaver.save(saved, fixture_path) == OK)
	stale.resource_path = fixture_path
	script.source_code = current.source_code
	assert(script.reload(true) == OK)
	assert(stale.get(&"arm") == null and stale.get(&"arm_limb") == null, "Reproduce actual hot-reload Nil fields")
	assert(stale.is_valid(), "Generation validation must recover hot-reloaded fields")
	assert(stale.get(&"arm") == 1.7 and stale.get(&"arm_limb") == 2.3, "Restore saved preset values, not the zero defaults")
	assert(stale.get(&"torso") == 9.0, "Preserve existing unsaved edits")
	stale.set(&"torso", -1.0)
	assert(not stale.is_valid(), "Do not conceal invalid edited values")
	var unsaved: Resource = script.new()
	script.source_code = "\n".join(lines)
	assert(script.reload(true) == OK)
	script.source_code = current.source_code
	assert(script.reload(true) == OK)
	assert(unsaved.get(&"arm") == null)
	assert(unsaved.get_density("Arm", 3.0) == 3.0 and unsaved.is_valid(), "Unsaved presets restore defaults before density lookup")
	assert(DirAccess.remove_absolute(fixture_path) == OK)
	print("PASS: actual editor hot reload restores saved Arm/ArmLimb values and unsaved defaults without overwriting edits")
