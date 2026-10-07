extends SceneTree
const BASE_PATH = "res://Scenes/Creatures/Characters/_BaseGeneratedCreature.tscn"
const COMPONENTS = ["GeneratedLegStepMovementController3D","CreatureRecoveryStateMachine3D","CreatureActionController3D"]

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var base_scene: PackedScene = load(BASE_PATH)
	assert(base_scene.get_state().get_base_scene_state().get_path().ends_with("_SampleCharacter.tscn"))
	var base := base_scene.instantiate()
	assert(not base.generate_on_ready)
	assert(not base.has_node("GeneratedParts"))
	assert(base.get_node_or_null(base.generator_path) == null)
	for component: String in COMPONENTS: assert(base.has_node(component))
	base.free()
	for name: String in ["Generate_Creature_Test","Generate_Beast","Generate_Bird","Generate_StumpBeast"]:
		var scene: PackedScene = load("res://Scenes/Creatures/Characters/"+name+".tscn")
		assert(scene.get_state().get_base_scene_state().get_path() == BASE_PATH)
		var actor := scene.instantiate()
		assert(actor.generate_on_ready)
		actor.generate_on_ready = false
		root.add_child(actor)
		for component: String in COMPONENTS:
			var count := 0
			for child: Node in actor.get_children():
				if str(child.name) == component: count += 1
			assert(count == 1,"Inherited component duplicated/missing: "+component)
		assert(actor.has_method("capture_manual_layout") and actor.has_method("align_manual_connections"))
		assert(actor.get_node_or_null(actor.generator_path) != null)
		var gait: Resource = actor.get_node("GeneratedLegStepMovementController3D").slow_gait_data
		assert(gait.resource_path.ends_with("BirdGroundWalk.tres" if name=="Generate_Bird" else "GeneratedMultiLegWalk.tres"))
		if name=="Generate_StumpBeast":
			var generator: Node3D = actor.get_node(actor.generator_path)
			assert(generator.use_manual_layout and generator.manual_layout != null)
			var before: Transform3D = actor.get_node("GeneratedParts/Torso").transform
			assert(actor.generate_creature())
			assert(actor.get_node("GeneratedParts/Torso").transform.is_equal_approx(before))
			assert(actor.get_node("GeneratedParts/SubTorso").get_meta("generated_scene_path").ends_with("01_body_light_plate.tscn"))
		else:
			assert(actor.generate_creature(),"Generation failed after inheriting the common base: "+name)
		if name=="Generate_Bird":
			for component: String in ["WingPoseController3D","BirdFlightController3D","BirdDiveAttackController3D"]: assert(actor.has_node(component))
		actor.free()
	for name: String in ["Generate_Bird_NPC","Generate_Creature_NPC"]:
		var scene: PackedScene = load("res://Scenes/Creatures/Characters/"+name+".tscn")
		var state := scene.get_state()
		var found := false
		while state != null:
			if state.get_path()==BASE_PATH: found = true
			state = state.get_base_scene_state()
		assert(found,"NPC lost inherited generated base")
		var npc := scene.instantiate()
		assert(npc.has_node("NPCStateMachine3D"))
		npc.free()
	print("GENERATED_CREATURE_INHERITANCE_VALIDATION_PASSED")
	quit()
