extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Wolf.tscn")
const NPC = preload("res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn")
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var actor := CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator := actor.get_node("WolfGenerator")
	assert(generator._get_defaults_path().ends_with("WolfGeneratorDefaults.tres"))
	var original_positions := {}
	for multiplier: float in [1.0, 2.0]:
		generator.overall_scale = multiplier
		assert(actor.generate_creature())
		var bodies := actor.get_node("GeneratedParts")
		var poses := {}
		var feet := 0
		var limbs := 0
		var supports := 0
		for body: Node in bodies.get_children():
			if not body is PhysicalBodyPart3D: continue
			poses[body.name] = body.transform
			assert(body.scale.is_equal_approx(Vector3.ONE))
			assert(body.position.is_finite() and not body.is_broken)
			assert(str(body.get_meta("generated_scene_path")).contains("/Wolf/"))
			assert(is_equal_approx(GEOMETRY.bounds(body).size.z, 0.08*multiplier*2.0))
			var rule: GeneratedPartSceneRule = generator.get_part_scene_rule(str(body.get_meta("generated_part_type", "")),str(body.name),str(body.name))
			assert(rule.size_mode == GeneratedPartSceneRule.SizeMode.FIT_UNIFORM)
			var source := rule.part_scene.instantiate() as PhysicalBodyPart3D
			source.prepare_generated_geometry()
			var native_size := GEOMETRY.bounds(source).size
			var generated_size := GEOMETRY.bounds(body).size
			var part_factor: float = generator.rear_middle_size_scale if str(body.name).begins_with("Leg_") and str(body.name).ends_with("_Limb_2") else 1.0
			assert(is_equal_approx(generated_size.x,native_size.x*multiplier*part_factor))
			assert(is_equal_approx(generated_size.y,native_size.y*multiplier*part_factor))
			source.free()
			if multiplier == 1.0: original_positions[body.name] = body.position
			else: assert(body.position.is_equal_approx(original_positions[body.name]*multiplier))
			if PhysicalBodyPart3D.BodyPartTag.Leg in body.tags or PhysicalBodyPart3D.BodyPartTag.ForeLeg in body.tags:
				feet += 1
				assert(absf((body.transform*GEOMETRY.bounds(body)).position.y) < 0.0001)
			if PhysicalBodyPart3D.BodyPartTag.LegLimb in body.tags: limbs += 1
			if PhysicalBodyPart3D.BodyPartTag.SubTorso in body.tags: supports += 1
			for other: Node in bodies.get_children():
				if other is PhysicalBodyPart3D and other != body: assert(other in body.get_collision_exceptions())
		assert(poses.size() == 22 and feet == 4 and limbs == 10 and supports == 4)
		assert(bodies.get_node("Head").basis.x.y < 0.0)
		assert(bodies.get_node("Torso").basis.x.y > 0.0)
		for index: int in [1, 2]:
			assert(bodies.has_node("Leg_%d_Limb_3" % index))
			assert(not bodies.has_node("ForeLeg_%d_Limb_3" % index))
			var middle := bodies.get_node("Leg_%d_Limb_2" % index) as PhysicalBodyPart3D
			assert(str(middle.get_meta("generated_scene_path")).ends_with("Hind_%d/Wolf2UpperLeg.tscn" % (3-index)))
			var fore_length := 0.0
			var rear_length := 0.0
			for segment: int in [1,2,3]:
				var rear := bodies.get_node("Leg_%d_Limb_%d" % [index,segment])
				rear_length += rear.get_node("JointIn").position.distance_to(rear.get_node("JointOut").position)
				if segment <= 2:
					var fore := bodies.get_node("ForeLeg_%d_Limb_%d" % [index,segment])
					fore_length += fore.get_node("JointIn").position.distance_to(fore.get_node("JointOut").position)
			assert(absf(fore_length-[3.52097964,4.05663919][index-1]*multiplier) < 0.005*multiplier)
			print("WOLF_LIMB_LENGTH pair=",index," fore=",fore_length," rear=",rear_length)
			var fore_root := bodies.get_node("ForeLeg_%d_Limb_2" % index) as Node3D
			var rear_root := bodies.get_node("Leg_%d_Limb_3" % index) as Node3D
			var fore_foot := bodies.get_node("ForeLeg_%d" % index) as Node3D
			var rear_foot := bodies.get_node("Leg_%d" % index) as Node3D
			var fore_delta: Vector3 = fore_foot.transform*fore_foot.get_node("JointIn").position-fore_root.transform*fore_root.get_node("JointIn").position
			var rear_delta: Vector3 = rear_foot.transform*rear_foot.get_node("JointIn").position-rear_root.transform*rear_root.get_node("JointIn").position
			assert(is_equal_approx(fore_delta.x/fore_length,generator.fore_foot_forward_ratios[index-1]))
			assert(is_equal_approx(rear_delta.x/rear_length,generator.rear_foot_forward_ratios[index-1]))
			print("WOLF_REFERENCE_POSE pair=",index," fore_ankle_from_root=",fore_delta," rear_ankle_from_root=",rear_delta)
		var joints := bodies.get_node("Joints")
		assert(joints.get_child_count() == 21)
		for joint: Joint3D in joints.get_children():
			var a := joint.get_node(joint.node_a) as PhysicalBodyPart3D
			var b := joint.get_node(joint.node_b) as PhysicalBodyPart3D
			var frame_a: Transform3D = a.transform*Transform3D(joint.get_meta("generated_joint_frame_a"))
			var frame_b: Transform3D = b.transform*Transform3D(joint.get_meta("generated_joint_frame_b"))
			assert(frame_a.origin.distance_to(frame_b.origin) < 0.0001)
		assert(actor.generate_creature())
		for key: StringName in poses: assert(actor.get_node("GeneratedParts").get_node(NodePath(key)).transform.is_equal_approx(poses[key]))
		print("WOLF_STRUCTURE_PASS scale=",multiplier)
	generator.tail_enabled = false
	generator.jaw_enabled = false
	assert(actor.generate_creature())
	assert(not actor.has_node("GeneratedParts/Tail") and not actor.has_node("GeneratedParts/LowerJaw"))
	actor.free()
	var npc := NPC.instantiate()
	npc.generate_on_ready = false
	root.add_child(npc)
	assert(npc.generate_creature())
	var machine := npc.get_node("NPCStateMachine3D")
	assert(machine.behavior.attacks.size() == 2)
	assert(not npc.get_node("CreatureActionController3D").has_npc_attack(&"foreleg_stomp"))
	for action_id: StringName in [&"wolf_pounce",&"wolf_bite"]:
		assert(npc.get_node("WolfAttackController3D").has_npc_attack(action_id))
	assert(npc.get_node("GeneratedLegStepMovementController3D").get_leg_parts().size() == 4)
	assert(npc.faction_id == 1)
	npc.free()
	await process_frame
	print("PASS: Wolf deterministic structure, scale, grounded feet, joint anchors, internal collision exceptions, optional parts and NPC attack wiring.")
	quit()
