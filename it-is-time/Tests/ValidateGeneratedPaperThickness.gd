extends SceneTree
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const RULE = preload("res://Scripts/Creatures/Generators/GeneratedPartSceneRule.gd")
const CHARACTER = preload("res://Scripts/Creatures/GeneratedCreatureCharacter3D.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var cases := {
		"ForeLeg": "res://Scenes/Creatures/Bodyparts/StumpParts/RightLeg/04_foot.tscn",
		"Limb": "res://Scenes/Creatures/Bodyparts/StumpParts/LeftLeg/03_lower_leg.tscn",
		"Head": "res://Scenes/Creatures/Bodyparts/StumpParts/Base/05_head.tscn",
		"Torso": "res://Scenes/Creatures/Bodyparts/PaperParts/ToSplit_1/Base/02_body_main.tscn"
	}
	var checks := 0
	for role: String in cases:
		for mode: int in [RULE.SizeMode.KEEP_SIZE, RULE.SizeMode.FIT_UNIFORM, RULE.SizeMode.FIT_BOX]:
			for overall: float in [0.5, 1.0, 4.0]:
				var previous := AABB()
				var markers: Dictionary = {}
				var rule := RULE.new()
				rule.size_mode = mode
				rule.size_multiplier = 1.3
				rule.align_connectors_to_frame = role != "Torso"
				for thickness: float in [0.08, 0.401]:
					var part := load(cases[role]).instantiate() as PhysicalBodyPart3D
					part.paper_volume_thickness = thickness
					var actual := GEOMETRY.fit(part, Vector3(0.6, 0.8, 0.08) * overall, rule, role, 0.12 * overall)
					assert(is_equal_approx(actual.size.z, 0.12 * overall), "Final depth must equal Part Width * Overall Scale regardless of authored thickness or Size Multiplier")
					if thickness != 0.08:
						assert(Vector2(actual.size.x,actual.size.y).is_equal_approx(Vector2(previous.size.x,previous.size.y)), "Depth changed front-face size")
						assert(Vector2(actual.position.x,actual.position.y).is_equal_approx(Vector2(previous.position.x,previous.position.y)), "Depth changed front-face position")
					for key: String in ["JointIn", "JointOut"]:
						var marker := part.get_node_or_null(key) as Marker3D
						if marker == null: continue
						if thickness == 0.08: markers[key] = marker.position
						else: assert(marker.position.is_equal_approx(markers[key]), "Depth changed connector position")
					previous = actual
					part.free()
					checks += 1
	# Manual blueprints also use the current generator width instead of source thickness.
	var actor := CHARACTER.new()
	actor.mass_limits_enabled = false
	var rule := RULE.new()
	rule.part_scene = load(cases.ForeLeg)
	var source := rule.part_scene.instantiate() as PhysicalBodyPart3D
	source.paper_volume_thickness = 0.123
	var temporary_scene := PackedScene.new()
	assert(temporary_scene.pack(source) == OK)
	source.free()
	rule.part_scene = temporary_scene
	var parts: Array[Dictionary] = [{"name":"Foot", "role":"ForeLeg", "part_key":"Foot", "size":Vector3(0.6,0.3,0.08)*2, "transform":Transform3D.IDENTITY, "scene_rule":rule}]
	var stage := actor._instantiate_blueprint({"parts":parts,"connections":[],"overall_scale":2.0,"paper_depth":0.09*2.0,"manual_layout":true},Transform3D.IDENTITY)
	assert(stage != null)
	var body := stage.get_node("Foot") as PhysicalBodyPart3D
	assert(is_equal_approx(GEOMETRY.bounds(body).size.z,0.18))
	assert(is_equal_approx(body.mass,GEOMETRY.bounds(body).size.x*GEOMETRY.bounds(body).size.y*0.18))
	stage.free()
	actor.free()
	# Exercise the real inherited NPC generation signal with disparate source thicknesses.
	var npc: Node3D = load("res://Scenes/Creatures/Characters/Generate_StumpBeast_NPC.tscn").instantiate()
	npc.generate_on_ready = false
	npc.get_node("NPCStateMachine3D").enabled = false
	root.add_child(npc)
	var generator: Node3D = npc.get_node(npc.generator_path)
	generator.part_width = 0.11
	for overall: float in [0.5,2.0,6.0]:
		generator.overall_scale = overall
		assert(npc.generate_creature())
		for node: Node in npc.get_node("GeneratedParts").get_children():
			var part := node as PhysicalBodyPart3D
			if part == null or not part.paper_volume_enabled: continue
			assert(is_equal_approx(GEOMETRY.bounds(part).size.z,0.11*overall),"Real generated parts have unequal depth: "+str(part.name))
	npc.free()
	print("PAPER_THICKNESS_VALIDATION_PASSED cases=%d" % checks)
	quit()
