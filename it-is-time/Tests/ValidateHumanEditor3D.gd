@tool
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	assert(Engine.is_editor_hint(), "Run this test with --editor")
	var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_Human.tscn").instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator: Node = actor.get_node("HumanGenerator")
	generator.human_set = 1
	var original: Dictionary = generator.REFERENCE_CALIBRATION.get_meta("calibration")
	var scale_before: float = generator.reference_for("Head").scale
	var updated := original.duplicate(true)
	updated.sets["1"].parts.Head.scale = scale_before*1.02
	generator.REFERENCE_CALIBRATION.set_meta("calibration",updated)
	assert(is_equal_approx(float(generator.reference_for("Head").scale),scale_before*1.02))
	generator.REFERENCE_CALIBRATION.set_meta("calibration",original)
	for set_index: int in [1,2,3,4,5]:
		generator.use_manual_layout = false
		generator.human_set = set_index
		assert(actor.generate_creature())
		assert(actor.get_node("GeneratedParts/Joints").get_child_count() == 13)
		assert(actor.get_node("GeneratedParts/Arm_R").arm_swing_bindings.size() == 1)
		assert(actor._capture_manual_layout())
		assert(actor.generate_creature())
		assert(str(actor.get_node("GeneratedParts/Head").get_meta("generated_scene_path")).contains("Human%dHead" % set_index))
		print("HUMAN_EDITOR_PASS set=",set_index)
	actor.free()
	await process_frame
	print("PASS: Human generation and manual restore run in editor tool mode.")
	quit()
