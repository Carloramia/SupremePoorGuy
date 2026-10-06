extends SceneTree

const CHARACTER = preload("res://Scripts/Creatures/GeneratedCreatureCharacter3D.gd")
const DATA = preload("res://Scripts/Creatures/GeneratedCreatureDensityData.gd")
const BEAST = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var beast := BEAST.instantiate()
	var bird := BIRD.instantiate()
	assert(beast.density_data != null and bird.density_data != null)
	assert(beast.density_data != bird.density_data, "Species must have separate presets")
	beast.free()
	bird.free()
	var actor := CHARACTER.new()
	actor.minimum_part_mass = 0.001
	actor.maximum_part_mass = 1000.0
	actor.mass_density = 3.0
	var preset := DATA.new()
	actor.density_data = preset
	var types := ["Torso", "SubTorso", "Leg", "ForeLeg", "LegLimb", "Neck", "Head", "WingRoot", "WingMiddle", "WingTip"]
	var layouts: Array[Dictionary] = []
	for index: int in range(types.size()):
		var kind: String = types[index]
		preset.set(DATA.TYPE_PROPERTIES[kind], float(index + 1))
		var role := kind
		if kind == "SubTorso": role = "Torso"
		if kind == "LegLimb": role = "Limb"
		if kind.begins_with("Wing"): role = "Wing" if kind == "WingTip" else "WingLimb"
		layouts.append({"name": "UnrelatedName%d" % index, "role": role, "sub_torso": kind == "SubTorso",
			"wing_section": kind.trim_prefix("Wing"), "size": Vector3(2.0, 3.0, 4.0), "transform": Transform3D.IDENTITY})
	var blueprint := {"parts": layouts, "connections": []}
	var container := actor._instantiate_blueprint(blueprint, Transform3D.IDENTITY)
	for index: int in range(types.size()):
		var part := container.get_child(index) as PhysicalBodyPart3D
		assert(part.get_meta("generated_part_type") == types[index])
		assert(is_equal_approx(part.mass, 24.0 * (index + 1)), "Mass must match density by generated type, not the node name")
		if types[index].begins_with("Wing"):
			assert(PhysicalBodyPart3D.BodyPartTag.Wing in part.tags)
			assert(PhysicalBodyPart3D.BodyPartTag.Leg not in part.tags)
	container.free()
	preset.sub_torso = 0.0
	assert(preset.get_density("SubTorso", 3.0) == 3.0)
	assert(preset.get_density("Unknown", 3.0) == 3.0)
	preset.torso = -1.0
	assert(not preset.is_valid())
	preset.torso = NAN
	assert(not preset.is_valid())
	preset.torso = 1.0
	assert(preset.is_valid())
	actor.density_data = null
	layouts.resize(1)
	layouts[0].size = Vector3.ONE
	container = actor._instantiate_blueprint(blueprint, Transform3D.IDENTITY)
	assert(is_equal_approx((container.get_child(0) as RigidBody3D).mass, 3.0), "Missing preset must preserve global density")
	container.free()
	layouts[0].size = Vector3.ONE * 2.0
	container = actor._instantiate_blueprint(blueprint, Transform3D.IDENTITY)
	assert(is_equal_approx((container.get_child(0) as RigidBody3D).mass, 24.0), "Scaled volume must be used once")
	container.free()
	actor.maximum_part_mass = 10.0
	container = actor._instantiate_blueprint(blueprint, Transform3D.IDENTITY)
	assert(is_equal_approx((container.get_child(0) as RigidBody3D).mass, 10.0))
	container.free()
	layouts[0].size = Vector3.ONE * 0.01
	actor.minimum_part_mass = 0.1
	container = actor._instantiate_blueprint(blueprint, Transform3D.IDENTITY)
	assert(is_equal_approx((container.get_child(0) as RigidBody3D).mass, 0.1))
	container.free()
	assert(actor.mass_limits_enabled, "Mass limits must remain enabled by default")
	actor.mass_limits_enabled = false
	container = actor._instantiate_blueprint(blueprint, Transform3D.IDENTITY)
	assert(is_equal_approx((container.get_child(0) as RigidBody3D).mass, 0.000003), "Disabled limits must preserve small positive density mass")
	container.free()
	layouts[0].size = Vector3.ONE * 2.0
	container = actor._instantiate_blueprint(blueprint, Transform3D.IDENTITY)
	assert(is_equal_approx((container.get_child(0) as RigidBody3D).mass, 24.0), "Disabled limits must bypass maximum mass")
	container.free()
	layouts[0].role = "Feather"
	layouts[0].size = Vector3.ONE * 0.01
	container = actor._instantiate_blueprint(blueprint, Transform3D.IDENTITY)
	assert(is_equal_approx((container.get_child(0) as RigidBody3D).mass, 0.000003), "Disabled limits must also bypass feather minimum")
	container.free()
	actor.mass_limits_enabled = true
	container = actor._instantiate_blueprint(blueprint, Transform3D.IDENTITY)
	assert(is_equal_approx((container.get_child(0) as RigidBody3D).mass, actor.minimum_feather_mass), "Re-enabling limits must restore feather minimum")
	container.free()
	actor.free()
	print("PASS: generated density matching, species presets, Wing tags, fallback, scaling and mass limits")
	quit()
