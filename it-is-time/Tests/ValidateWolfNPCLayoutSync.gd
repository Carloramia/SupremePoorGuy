extends "res://Tests/ValidateManualPartSnapshot.gd"

func joint_poses(actor: Node) -> Dictionary:
	var result := {}
	for joint in actor.get_node("GeneratedParts/Joints").get_children():
		result[str(joint.name)] = joint.transform
		for pair in [[joint.node_a, "generated_joint_frame_a"], [joint.node_b, "generated_joint_frame_b"]]:
			var body = joint.get_node(pair[0])
			assert(actor._capture_joint_anchor(body, joint, pair[1]).distance_to(joint.global_position) < 0.0001)
	return result

func run() -> void:
	var wolf = load("res://Scenes/Creatures/Characters/Generate_Wolf.tscn").instantiate()
	var npc = load("res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn").instantiate()
	for actor in [wolf, npc]:
		actor.generate_on_ready = false
		root.add_child(actor)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	var expected := inspect(wolf)
	var expected_joints := joint_poses(wolf)
	assert(expected.size() == 22 and expected_joints.size() == 21)
	for iteration in 3:
		if iteration > 0:
			assert(wolf.generate_creature())
			assert(npc.generate_creature())
		for actor in [wolf, npc]:
			compare(inspect(actor), expected, 1.0)
			var joints := joint_poses(actor)
			assert(joints.size() == expected_joints.size())
			for key in expected_joints: assert(joints[key].is_equal_approx(expected_joints[key]), key)
		assert(npc.faction_id == 1)
		var ai = npc.get_node("NPCStateMachine3D")
		assert(ai.behavior.resource_path == "res://Resources/AI/WolfAI.tres")
		assert(ai.attack_execution_enabled and ai.generated_x_axis_facing)
		assert(is_equal_approx(ai.facing_x_dead_zone, 1.0))
		print("WOLF_NPC_LAYOUT_SYNC_PASS iteration=", iteration)
	wolf.free()
	npc.free()
	print("PASS: NPC inherits all 22 current body/visual/collision snapshots and 21 joint anchors across loading and two regenerations; faction/AI retained.")
	quit()
