extends SceneTree

const PARTS = ["ForeLeg_1_Limb_1", "ForeLeg_2_Limb_1"]

func _initialize() -> void:
	call_deferred("run")

func geometry(actor: Node) -> Dictionary:
	var result := {}
	for body in actor.get_node("GeneratedParts").get_children():
		if not body is RigidBody3D: continue
		result[str(body.name)] = body.transform
		for node in body.find_children("*", "MeshInstance3D", true, false):
			result[str(body.name)+"/"+str(body.get_path_to(node))] = node.transform
	for joint in actor.get_node("GeneratedParts/Joints").get_children():
		result["Joints/"+str(joint.name)] = joint.transform
	return result

func run() -> void:
	for scene in ["Generate_Wolf", "Generate_Wolf_NPC"]:
		var actor = load("res://Scenes/Creatures/Characters/"+scene+".tscn").instantiate()
		actor.generate_on_ready = false
		var expected := {}
		for part in PARTS:
			expected[part] = actor.get_node("GeneratedParts/"+part+"/CollisionShape3D").transform
		root.add_child(actor)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		var original := geometry(actor)
		for repeat in 3:
			if repeat > 0: assert(actor.generate_creature())
			for part in PARTS:
				assert(actor.get_node("GeneratedParts/"+part+"/CollisionShape3D").transform.is_equal_approx(expected[part]), scene+" "+part)
			var actual := geometry(actor)
			assert(actual.size() == original.size())
			for key in original: assert(actual[key].is_equal_approx(original[key]), scene+" "+key)
			for body in actor.get_node("GeneratedParts").get_children():
				if body is PhysicalBodyPart3D and PhysicalBodyPart3D.BodyPartTag.LegLimb in body.tags:
					assert(not body.ignore_limb_terrain)
		actor.free()
	print("PASS: Wolf/NPC collider positions and rotation survive loading and two regenerations; body, visual and joint transforms unchanged; limb terrain collisions enabled.")
	quit()
