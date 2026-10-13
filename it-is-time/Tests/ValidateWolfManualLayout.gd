extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var actor = load("res://Scenes/Creatures/Characters/Generate_Wolf.tscn").instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	assert(actor._capture_manual_layout(), "Saved Wolf anchors must already coincide")
	actor.get_node("GeneratedParts/Torso").position.x += 3.01
	var poses := {}
	for body: Node in actor.get_node("GeneratedParts").get_children():
		if body is PhysicalBodyPart3D: poses[body.name] = body.transform
	assert(actor._align_manual_connections())
	for key: StringName in poses:
		assert(actor.get_node("GeneratedParts").get_node(NodePath(key)).transform.is_equal_approx(poses[key]))
	assert(actor._capture_manual_layout())
	assert(actor.generate_creature())
	for key: StringName in poses:
		assert(actor.get_node("GeneratedParts").get_node(NodePath(key)).transform.is_equal_approx(poses[key]))
	actor.free()
	await process_frame
	print("PASS: Wolf saved anchors, alignment without body movement, capture and pose regeneration.")
	quit()
