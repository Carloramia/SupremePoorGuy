extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Human.tscn")
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")

func _initialize() -> void: call_deferred("run")
func run() -> void:
	var actor: Node3D = CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator: Node = actor.get_node("HumanGenerator")
	var reference_data: Dictionary = generator.REFERENCE_CALIBRATION.get_meta("calibration")
	assert(reference_data.version == 2 and is_equal_approx(float(reference_data.source_pixel_unit),0.01))
	for source_set: Dictionary in reference_data.sets.values():
		assert(is_equal_approx(float(source_set.source_units_x),float(source_set.source_units_y)))
	assert(generator._get_defaults_path().ends_with("HumanGeneratorDefaults.tres"))
	assert(actor.generate_character_button.is_valid() and generator.generate_torso_button.is_valid() and generator.save_defaults_button.is_valid())
	var saved_parts := {}
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D:
			saved_parts[str(part.name)] = [part.transform, part.get_node("Model").transform, GEOMETRY.bounds(part)]
	assert(saved_parts.size() == 14 and actor.generate_creature())
	for key: String in saved_parts:
		var part: PhysicalBodyPart3D = actor.get_node("GeneratedParts/" + key)
		assert(part.transform.is_equal_approx(saved_parts[key][0]))
		assert(part.get_node("Model").transform.is_equal_approx(saved_parts[key][1]))
		assert(GEOMETRY.bounds(part).is_equal_approx(saved_parts[key][2]))
	assert(generator.generate_torso_button.call())
	for set_index: int in [1,2,3,4,5]:
		generator.human_set = set_index
		for multiplier: float in [1.0, 1.5]:
			generator.overall_scale = multiplier
			assert(actor.generate_creature())
			var parts: Node = actor.get_node("GeneratedParts")
			var counts := {"Torso":0, "Head":0, "Leg":0, "Limb":0, "Arm":0, "ArmLimb":0}
			for part: Node in parts.get_children():
				if not part is PhysicalBodyPart3D: continue
				counts[str(part.get_meta("generated_role"))] += 1
				assert(part.scale.is_equal_approx(Vector3.ONE) and not part.is_broken)
				assert(str(part.get_meta("generated_scene_path")).contains("Human%d" % set_index))
				assert(is_equal_approx(GEOMETRY.bounds(part).size.z, 0.08 * multiplier * 2.0))
				var source := load(str(part.get_meta("generated_scene_path"))).instantiate() as PhysicalBodyPart3D
				source.prepare_generated_geometry()
				var native_size := GEOMETRY.bounds(source).size
				var rule: GeneratedPartSceneRule = generator.get_part_scene_rule(str(part.get_meta("generated_part_type")),str(part.name),str(part.name))
				assert(is_equal_approx(GEOMETRY.bounds(part).size.x, native_size.x * multiplier * rule.size_multiplier))
				assert(is_equal_approx(GEOMETRY.bounds(part).size.y, native_size.y * multiplier * rule.size_multiplier))
				var reference: Dictionary = generator.reference_for(str(part.name))
				if reference.fit == "joint_span":
					assert(is_equal_approx(part.get_node("JointIn").position.distance_to(part.get_node("JointOut").position),float(reference.target)*multiplier))
				elif reference.fit == "outline":
					check_outline(part.get_node("Model"),reference,multiplier)
				source.free()
				if part.get_meta("generated_role") == "ArmLimb":
					assert(PhysicalBodyPart3D.BodyPartTag.ArmLimb in part.tags)
					assert(PhysicalBodyPart3D.BodyPartTag.Arm not in part.tags and PhysicalBodyPart3D.BodyPartTag.LegLimb not in part.tags)
					var direction: Vector3 = (part.transform.basis*(part.get_node("JointOut").position-part.get_node("JointIn").position)).normalized()
					assert(direction.angle_to(generator.reference_direction(str(part.name))) < 0.001)
				if part.get_meta("generated_role") == "Arm": assert(part.basis.is_equal_approx(Basis.IDENTITY))
				if PhysicalBodyPart3D.BodyPartTag.Leg in part.tags:
					assert(absf((part.transform * GEOMETRY.bounds(part)).position.y) < 0.001)
				for other: Node in parts.get_children():
					if other is PhysicalBodyPart3D and other != part: assert(other in part.get_collision_exceptions())
			assert(counts == {"Torso":1,"Head":1,"Leg":2,"Limb":4,"Arm":2,"ArmLimb":4})
			assert(parts.get_node("Joints").get_child_count() == 13)
			for side: String in ["L", "R"]:
				var upper: Node3D = parts.get_node("Leg_"+side+"_Limb_2")
				var lower: Node3D = parts.get_node("Leg_"+side+"_Limb_1")
				var first: Vector3 = upper.basis*(upper.get_node("JointOut").position-upper.get_node("JointIn").position)
				var second: Vector3 = lower.basis*(lower.get_node("JointOut").position-lower.get_node("JointIn").position)
				var expected: float = generator.reference_direction(str(upper.name)).cross(generator.reference_direction(str(lower.name))).z
				assert(first.cross(second).z*expected > 0.0)
				assert(parts.get_node("Leg_"+side).basis.is_equal_approx(Basis.IDENTITY))
			for joint: Generic6DOFJoint3D in parts.get_node("Joints").get_children():
				var a: Node3D = joint.get_node(joint.node_a)
				var b: Node3D = joint.get_node(joint.node_b)
				var first: Transform3D = a.transform * Transform3D(joint.get_meta("generated_joint_frame_a"))
				var second: Transform3D = b.transform * Transform3D(joint.get_meta("generated_joint_frame_b"))
				assert(first.origin.distance_to(second.origin) < 0.001)
				var rest: Quaternion = joint.get_meta("generated_rest_b_relative_a")
				var relative := a.basis.orthonormalized().get_rotation_quaternion().inverse()*b.basis.orthonormalized().get_rotation_quaternion()
				assert(absf(rest.normalized().dot(relative.normalized())) > 0.999999)
				assert(second.origin.distance_to(b.transform * b.get_node("JointIn").position) < 0.001)
				if str(a.get_meta("generated_role")) in ["Limb", "ArmLimb"]:
					assert(first.origin.distance_to(a.transform*a.get_node("JointOut").position) < 0.001)
				if a.name == &"Torso":
					var expected := Vector3.ZERO
					if str(b.name).begins_with("Arm_"):
						expected = a.transform * generator.reference_port(a,"Torso","shoulder_R" if str(b.name).begins_with("Arm_R") else "shoulder_L")
					elif b.name == &"Head": expected = a.transform * generator.reference_port(a,"Torso","head")
					else:
						var waist: Node3D = a.get_node("WaistVisual")
						var calibration: Dictionary = generator.reference_for("WaistVisual")
						var pixel: Array = calibration.ports["hip_R" if str(b.name).begins_with("Leg_R") else "hip_L"]
						var raw := Vector3((float(pixel[0])-float(calibration.pivot[0]))*float(calibration.pixel_unit),(float(calibration.pivot[1])-float(pixel[1]))*float(calibration.pixel_unit),0.0)
						expected = a.transform * waist.transform * raw
					assert(Vector2(expected.x,expected.y).distance_to(Vector2(second.origin.x,second.origin.y)) < 0.001)
				assert(is_zero_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)))
			assert(parts.get_node("Leg_R").position.x > parts.get_node("Leg_L").position.x)
			assert(parts.has_node("Arm_R/ItemSocket3D") and parts.has_node("Torso/WaistVisual"))
			assert(parts.get_node("Torso/WaistVisual").find_children("*", "CollisionShape3D", true, false).is_empty())
			check_outline(parts.get_node("Torso/WaistVisual"),generator.reference_for("WaistVisual"),multiplier)
			var swing := actor.get_node("LimbSwingController3D") as LimbSwingController3D
			assert(swing.get_group_member_count(0) == 1)
			assert(swing._states[0].members[0].body == parts.get_node("Arm_R_Limb_2"))
			assert(swing._states[0].members[0].followers.size() == 2)
			assert(actor.get_node("InventoryController3D")._arm == parts.get_node("Arm_R"))
			print("HUMAN_STRUCTURE_PASS set=",set_index," scale=",multiplier)
	# Optional forward-facing boots and the former uniform arm layout remain usable.
	generator.use_reference_pose = false
	generator.feet_face_forward = true
	generator.human_set = 1
	assert(actor.generate_creature())
	var legacy: Node3D = actor.get_node("GeneratedParts/Arm_L_Limb_2")
	var legacy_axis: Vector3 = (legacy.basis*(legacy.get_node("JointOut").position-legacy.get_node("JointIn").position)).normalized()
	assert(legacy_axis.angle_to(Vector3(sin(deg_to_rad(8.0)),-cos(deg_to_rad(8.0)),0.0)) < 0.001)
	assert(actor.get_node("GeneratedParts/Leg_L").basis.x.dot(Vector3.RIGHT) < -0.99)
	generator.human_set = 5
	assert(actor.generate_creature())
	for side: String in ["L", "R"]:
		var foot: Node3D = actor.get_node("GeneratedParts/Leg_"+side)
		var toe: Vector3 = foot.basis*(foot.get_node("JointOut").position-foot.get_node("JointIn").position)
		assert(toe.x > 0.0, "Human5's already-forward boots must not be reversed")
	generator.use_reference_pose = true
	generator.feet_face_forward = false
	# Save a translation and a child-model transform, then rebuild from the snapshot.
	generator.human_set = 1
	generator.overall_scale = 1.0
	assert(actor.generate_creature())
	var parts: Node = actor.get_node("GeneratedParts")
	var poses := {}
	for part: Node in parts.get_children():
		if part is PhysicalBodyPart3D:
			part.position += Vector3(0.4,0.2,0.0)
			poses[str(part.name)] = part.transform
	parts.get_node("Arm_R/Model").position.x += 0.03
	var model_pose: Transform3D = parts.get_node("Arm_R/Model").transform
	assert(actor._capture_manual_layout())
	assert(actor.generate_creature())
	for key: String in poses: assert(actor.get_node("GeneratedParts/" + key).transform.is_equal_approx(poses[key]))
	assert(actor.get_node("GeneratedParts/Arm_R/Model").transform.is_equal_approx(model_pose))
	assert(actor.get_node("LimbSwingController3D").get_group_member_count(0) == 1)
	var packed := PackedScene.new()
	assert(packed.pack(actor) == OK)
	var restored: Node3D = packed.instantiate()
	restored.generate_on_ready = false
	root.add_child(restored)
	assert(restored.generate_creature())
	for key: String in poses: assert(restored.get_node("GeneratedParts/" + key).transform.is_equal_approx(poses[key]))
	assert(restored.get_node("GeneratedParts/Arm_R/Model").transform.is_equal_approx(model_pose))
	assert(restored.get_node("GeneratedParts/Torso").get_child_count() == actor.get_node("GeneratedParts/Torso").get_child_count())
	restored.free()
	actor.free()
	await process_frame
	print("PASS: Human source arm poses, knee bends, grounded feet, rest frames, scale, 14/13 assembly and manual pose roundtrip.")
	quit()

func check_outline(model: Node3D, reference: Dictionary, multiplier: float) -> void:
	var box: Array = reference.visual_bounds
	var width: float = (float(box[2])-float(box[0]))*float(reference.pixel_unit)*model.basis.x.length()
	var height: float = (float(box[3])-float(box[1]))*float(reference.pixel_unit)*model.basis.y.length()
	var target: Array = reference.target_size
	assert(is_equal_approx(width/(float(target[0])*multiplier)+height/(float(target[1])*multiplier),2.0))
	assert(is_equal_approx(model.basis.x.length(),model.basis.y.length()))
