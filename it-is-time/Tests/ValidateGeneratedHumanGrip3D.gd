extends "res://Tests/ValidateBodyPartVisualStates3D.gd"

const SPEAR = preload("res://Scenes/Items/Weapons/Human/Human1Spear.tscn")

func verify_grips(actor: Node3D) -> void:
	var joints := actor.get_node("GeneratedParts/Joints").get_children()
	var poses: Array[Transform3D] = []
	for joint: Node3D in joints: poses.append(joint.transform)
	for name: String in ["Arm_R","Arm_L"]:
		var hand := actor.get_node("GeneratedParts/"+name) as PhysicalBodyPart3D
		assert(hand.set_visual_state(&""))
		var visual := hand.get_node("Model/PaperVolume") as MeshInstance3D
		var original := visual.transform
		var mesh := visual.mesh
		var before := physics_snapshot(hand)
		var socket := hand.get_node("ItemSocket3D") as Marker3D
		var socket_pose := socket.transform
		var grip: BodyPartVisualState3D = hand.visual_states.filter(func(state): return state.state_name == &"grip")[0]
		var open: BodyPartVisualState3D = hand.visual_states.filter(func(state): return state.state_name == &"open")[0]
		assert(grip.resource_path.contains("GenerateHuman4Hand"))
		assert(open.anchor_path == ^"JointIn")
		var joint: Generic6DOFJoint3D
		for candidate: Joint3D in joints:
			if candidate.get_node_or_null(candidate.node_b) == hand: joint = candidate
		assert(joint != null)
		var physical := hand.global_transform*(joint.get_meta(&"generated_joint_frame_b") as Transform3D).origin
		var open_pose := Transform3D.IDENTITY
		for state: StringName in [&"open",&"grip",&"open",&""]:
			assert(hand.set_visual_state(state))
			assert_same(physics_snapshot(hand),before)
			assert(socket.transform == socket_pose)
			for index: int in joints.size(): assert(joints[index].transform == poses[index])
			if state == &"grip":
				var error := visual.to_global(grip.mesh_anchor).distance_to(physical)
				print("GENERATED_HUMAN_GRIP_ALIGNMENT actor=",actor.name," hand=",name," error=",error)
				assert(error < 0.00001)
			elif state == &"open":
				assert(visual.global_position.is_equal_approx(hand.get_node("JointIn").global_position))
				if open_pose == Transform3D.IDENTITY: open_pose = visual.transform
				else: assert(visual.transform == open_pose)
			else:
				assert(visual.transform == original and visual.mesh == mesh)

func run() -> void:
	PhysicsServer3D.set_active(false)
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var audio := root.get_node("CombatAudio")
	audio.settings = audio.settings.duplicate()
	audio.settings.enabled = false
	for file: String in ["Generate_Human.tscn","Generate_Human_NPC.tscn","Human/Armed/Generate_Human_Spear1_NPC.tscn"]:
		var actor := load("res://Scenes/Creatures/Characters/"+file).instantiate() as Node3D
		actor.generate_on_ready = false
		actor.initial_weapon_scene = null
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(actor)
		verify_grips(actor)
		assert(actor.generate_creature())
		await process_frame
		verify_grips(actor)
		var inventory := actor.get_node("InventoryController3D")
		assert(inventory.equip_initial_weapon(SPEAR))
		for name: String in ["Arm_R","Arm_L"]:
			var hand := actor.get_node("GeneratedParts/"+name) as PhysicalBodyPart3D
			assert(hand.get_visual_state() == &"grip")
			var grip: BodyPartVisualState3D = hand.visual_states.filter(func(state): return state.state_name == &"grip")[0]
			assert(hand.get_node("Model/PaperVolume").to_global(grip.mesh_anchor).is_equal_approx(hand.get_node(grip.anchor_path).global_position))
		inventory._unequip_current_item()
		for name: String in ["Arm_R","Arm_L"]: assert(actor.get_node("GeneratedParts/"+name).get_visual_state() == &"")
		actor.queue_free()
		await process_frame
		await process_frame
		print("GENERATED_HUMAN_GRIP_SCENE_PASSED ",file)
	# Standalone hand assets retain their original shared states and wrist markers.
	for side: String in ["Right","Left"]:
		var part := load("res://Scenes/Creatures/Bodyparts/Human/Arms/"+side+"/Human4Hand"+side+".tscn").instantiate() as PhysicalBodyPart3D
		var grip: BodyPartVisualState3D = part.visual_states.filter(func(state): return state.state_name == &"grip")[0]
		assert(grip.anchor_path == ^"JointIn" and not grip.resource_path.contains("GenerateHuman4"))
		part.free()
	print("GENERATED_HUMAN_GRIP_PASSED")
	quit()
