extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var level := load("res://Scenes/Levels/TestLevel.tscn").instantiate() as Node3D
	root.add_child(level)
	var character := level.get_node("Flat/CharacterTest2") as Node3D
	assert(character.scene_file_path == "res://Scenes/Creatures/Characters/Character_Test_2.tscn")
	var packed := load(character.scene_file_path) as PackedScene
	assert(packed.get_state().get_base_scene_state().get_path() == "res://Scenes/Creatures/Characters/_SampleCharacter.tscn")
	for part_name: String in ["Torso", "Head", "Arm_R", "Arm_L", "Leg_R", "Leg_L"]:
		var part := character.get_node(part_name) as PhysicalBodyPart3D
		assert(part != null)
		part.freeze = true
	for component: String in ["LegStepMovementController3D", "InventoryController3D", "LimbSwingController3D", "CharacterDamageController3D", "PhysicalFacingController3D", "AutoOutline"]:
		assert(character.has_node(component))
	var joints := character.find_children("*", "Joint3D", true, false)
	assert(joints.size() == 5)
	for node: Node in joints:
		var joint := node as Joint3D
		assert(joint.get_node_or_null(joint.node_a) is PhysicalBodyPart3D)
		assert(joint.get_node_or_null(joint.node_b) is PhysicalBodyPart3D)
	await process_frame
	print("CHARACTER_SCENE_INHERITANCE_VALIDATION_PASSED")
	level.queue_free()
	quit()
