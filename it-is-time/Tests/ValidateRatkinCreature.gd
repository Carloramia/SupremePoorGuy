extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Ratkin.tscn")
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var actor := CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator := actor.get_node("RatkinGenerator")
	assert(generator._get_defaults_path().ends_with("RatkinGeneratorDefaults.tres"))
	assert(not actor.planar_constraints_enabled)
	var leg_width: float = generator.leg_pair_width
	var arm_width: float = generator.arm_pair_width
	generator.leg_pair_width = 0.55
	generator.arm_pair_width = 0.7
	assert(actor.generate_creature())
	var old_poses := {}
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D: old_poses[str(part.name)] = part.transform
	generator.leg_pair_width = leg_width
	generator.arm_pair_width = arm_width
	# KEEP_SIZE retains source XY dimensions; validate the native-size layout.
	for multiplier: float in [1.0]:
		generator.overall_scale = multiplier
		assert(actor.generate_creature())
		var bodies := actor.get_node("GeneratedParts")
		var counts := {"feet":0, "legs":0, "arms":0, "tail":0, "parts":0}
		var poses := {}
		for body: Node in bodies.get_children():
			if not body is PhysicalBodyPart3D: continue
			counts.parts += 1
			poses[body.name] = body.transform
			assert(body.scale.is_equal_approx(Vector3.ONE))
			var old_pose: Transform3D = old_poses[str(body.name)]
			assert(is_equal_approx(body.position.x, old_pose.origin.x) and is_equal_approx(body.position.y, old_pose.origin.y))
			assert(body.basis.is_equal_approx(old_pose.basis))
			var name_string := str(body.name)
			if name_string.begins_with("Leg_") or name_string.begins_with("Arm_"):
				var parent_body := bodies.get_node("Torso" if name_string.begins_with("Arm_") else "Pelvis") as PhysicalBodyPart3D
				var parent_bounds: AABB = parent_body.transform * GEOMETRY.bounds(parent_body)
				var limb_bounds: AABB = body.transform * GEOMETRY.bounds(body)
				var negative_side := name_string.begins_with("Leg_1") or name_string.begins_with("Arm_1")
				assert(is_equal_approx(limb_bounds.end.z if negative_side else limb_bounds.position.z, parent_bounds.position.z if negative_side else parent_bounds.end.z))
			assert(not body.is_broken and body.get_meta("generated_scene_path").contains("/Ratkin/"))
			var rule = generator.get_part_scene_rule(str(body.get_meta("generated_part_type", "")), str(body.name), str(body.name))
			if body.name in [&"EarLeft", &"EarRight"]:
				assert(body.basis.is_equal_approx(Basis.IDENTITY))
				var tip: Vector3 = body.get_node("JointOut").position - body.get_node("JointIn").position
				assert(tip.y > 0.0)
				assert(tip.x < 0.0)
			var fitted: bool = rule.size_mode == GeneratedPartSceneRule.SizeMode.FIT_UNIFORM
			if body.name == &"Torso": assert(fitted)
			var source := rule.part_scene.instantiate() as PhysicalBodyPart3D
			source.prepare_generated_geometry()
			var original := GEOMETRY.bounds(source)
			if fitted:
				var heights := {"Torso":generator.torso_height, "Head":generator.head_height, "EarLeft":generator.ear_heights.x, "EarRight":generator.ear_heights.y}
				assert(is_equal_approx(GEOMETRY.bounds(body).size.y, heights[str(body.name)]))
				assert(is_equal_approx(GEOMETRY.bounds(body).size.x / GEOMETRY.bounds(body).size.y, original.size.x / original.size.y))
			else:
				assert(is_equal_approx(GEOMETRY.bounds(body).size.x, original.size.x) and is_equal_approx(GEOMETRY.bounds(body).size.y, original.size.y))
			source.free()
			assert(is_equal_approx(GEOMETRY.bounds(body).size.z, 0.08 * multiplier))
			if PhysicalBodyPart3D.BodyPartTag.Leg in body.tags:
				counts.feet += 1
				assert(absf((body.transform * GEOMETRY.bounds(body)).position.y) < 0.0001)
			if PhysicalBodyPart3D.BodyPartTag.LegLimb in body.tags: counts.legs += 1
			if PhysicalBodyPart3D.BodyPartTag.Arm in body.tags:
				counts.arms += 1
				assert(PhysicalBodyPart3D.BodyPartTag.LegLimb not in body.tags)
			if PhysicalBodyPart3D.BodyPartTag.Tail in body.tags: counts.tail += 1
			for other: Node in bodies.get_children():
				if other is PhysicalBodyPart3D and other != body: assert(other in body.get_collision_exceptions())
		assert(counts == {"feet":2, "legs":4, "arms":6, "tail":1, "parts":21})
		assert(str(bodies.get_node("Arm_1").get_meta("generated_scene_path")).ends_with("/Arms/Right/Hand.tscn"))
		assert(str(bodies.get_node("Arm_2").get_meta("generated_scene_path")).ends_with("/Arms/Left/Hand.tscn"))
		assert(bodies.get_node("EarLeft").get_meta("generated_scene_path") == bodies.get_node("EarRight").get_meta("generated_scene_path"))
		assert(str(bodies.get_node("Torso").get_meta("generated_scene_path")).ends_with("/Torso/TorsoNoJointCaps.tscn"))
		assert(bodies.get_node("Leg_1").get_meta("generated_scene_path") == bodies.get_node("Leg_2").get_meta("generated_scene_path"))
		var joints := bodies.get_node("Joints")
		assert(joints.get_child_count() == 20)
		for joint: Joint3D in joints.get_children():
			var a := joint.get_node(joint.node_a) as PhysicalBodyPart3D
			var b := joint.get_node(joint.node_b) as PhysicalBodyPart3D
			var frame_a: Transform3D = a.transform * Transform3D(joint.get_meta("generated_joint_frame_a"))
			var frame_b: Transform3D = b.transform * Transform3D(joint.get_meta("generated_joint_frame_b"))
			assert(frame_a.origin.distance_to(frame_b.origin) < 0.0001)
			if b.get_meta("generated_role") in ["Limb", "ArmLimb", "Arm", "Leg", "Tail"]:
				assert(frame_b.origin.distance_to(b.transform * b.get_node("JointIn").position) < 0.0001)
		assert(actor.generate_creature())
		for key: StringName in poses: assert(bodies != actor.get_node("GeneratedParts") and actor.get_node("GeneratedParts").get_node(NodePath(key)).transform.is_equal_approx(poses[key]))
		print("RATKIN_STRUCTURE_PASS scale=", multiplier, " ", counts)
	generator.tail_enabled = false
	assert(actor.generate_creature() and not actor.has_node("GeneratedParts/Tail"))
	actor.free()
	await process_frame
	print("PASS: Ratkin 2-link legs, 2-link arms, grounded feet, tail, marker anchors, scale, collision exceptions and deterministic rebuild.")
	quit()
