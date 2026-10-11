extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_HornedBeast.tscn")
const GENERATOR = preload("res://Scripts/Creatures/Generators/HornedBeastGenerator.gd")
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var actor := CHARACTER.instantiate()
	assert(CHARACTER.get_state().get_base_scene_state().get_path().ends_with("_BaseGeneratedCreature.tscn"))
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator := actor.get_node("HornedBeastGenerator")
	assert(generator._get_defaults_path().ends_with("HornedBeastGeneratorDefaults.tres"))
	assert(generator.rear_leg_count == 2 and generator.foreleg_count == 2)
	generator.rear_knee_bends_backward = false
	var forward_knees: Dictionary = generator._build_model_blueprint()
	generator.rear_knee_bends_backward = true
	var backward_knees: Dictionary = generator._build_model_blueprint()
	for index: int in range(backward_knees.parts.size()):
		var before: Dictionary = forward_knees.parts[index]
		var after: Dictionary = backward_knees.parts[index]
		var name: String = after.name
		if name.begins_with("Leg_") and name.contains("_Limb_"):
			var native: Dictionary = generator._make_part(name, "Limb")
			var old_vector: Vector3 = before.transform.basis * (native._out - native._in)
			var new_vector: Vector3 = after.transform.basis * (native._out - native._in)
			var old_angle := rad_to_deg(old_vector.angle_to(Vector3.DOWN))
			var new_angle := rad_to_deg(new_vector.angle_to(Vector3.DOWN))
			print("REAR_BEND ", name, " angle_from_vertical=", old_angle, " -> ", new_angle)
			if name.ends_with("_Limb_1"):
				assert(new_angle < old_angle)
			else:
				assert(new_angle > old_angle)
				var knee: Vector3 = after.transform * native._out
				var hip: Vector3 = after.transform * native._in
				assert(knee.x < hip.x)
				assert(knee.x < (before.transform * native._out).x)
		else:
			assert(after.transform.is_equal_approx(before.transform))
	generator.standing_extension_ratio = 0.76
	var previous: Dictionary = generator._build_model_blueprint()
	generator.standing_extension_ratio = 0.82
	var raised: Dictionary = generator._build_model_blueprint()
	for index: int in range(raised.parts.size()):
		var before: Dictionary = previous.parts[index]
		var after: Dictionary = raised.parts[index]
		var name: String = after.name
		if name in ["Torso", "Head", "Tail"]:
			assert(after.transform.origin.y > before.transform.origin.y + 0.1)
		if name.ends_with("_Limb_1"):
			var native: Dictionary = generator._make_part(name, "Limb")
			var old_vector: Vector3 = before.transform.basis * (native._out - native._in)
			var new_vector: Vector3 = after.transform.basis * (native._out - native._in)
			var old_angle := rad_to_deg(old_vector.angle_to(Vector3.DOWN))
			var new_angle := rad_to_deg(new_vector.angle_to(Vector3.DOWN))
			print("RAISED_LOWER_LIMB ", name, " angle_from_vertical=", old_angle, " -> ", new_angle)
			assert(new_angle < old_angle)
	for multiplier: float in [0.5, 1.0, 2.0]:
		generator.overall_scale = multiplier
		assert(actor.generate_creature())
		var bodies := actor.get_node("GeneratedParts")
		var count := 0
		var feet := 0
		for body: Node in bodies.get_children():
			if not body is PhysicalBodyPart3D: continue
			count += 1
			assert(not body.is_broken)
			assert(body.scale.is_equal_approx(Vector3.ONE))
			assert(body.get_meta("generated_scene_path").contains("/HornedBeast/"))
			if body.geometry_mode == body.GeometryMode.BOX_FIT:
				assert(is_equal_approx(GEOMETRY.bounds(body).size.z, 0.08 * multiplier))
			else:
				assert(is_equal_approx(body.paper_volume_thickness * body.get_node("Model").basis.z.length(), 0.08 * multiplier))
			if PhysicalBodyPart3D.BodyPartTag.Leg in body.tags or PhysicalBodyPart3D.BodyPartTag.ForeLeg in body.tags:
				feet += 1
				var shape_bounds := GEOMETRY.bounds(body)
				assert(absf(body.position.y + shape_bounds.position.y) < 0.0001)
		assert(count == 23 and feet == 4)
		var joints := bodies.get_node("Joints")
		assert(joints.get_child_count() == 22)
		for joint: Node in joints.get_children():
			var a := joint.get_node(joint.node_a) as PhysicalBodyPart3D
			var b := joint.get_node(joint.node_b) as PhysicalBodyPart3D
			assert(a != null and b != null)
			var anchor_a: Transform3D = a.transform * Transform3D(joint.get_meta("generated_joint_frame_a"))
			var anchor_b: Transform3D = b.transform * Transform3D(joint.get_meta("generated_joint_frame_b"))
			assert(anchor_a.origin.distance_to(anchor_b.origin) < 0.00001)
		for a: Node in bodies.get_children():
			if not a is PhysicalBodyPart3D: continue
			var exceptions: Array = a.get_collision_exceptions()
			for b: Node in bodies.get_children():
				if b is PhysicalBodyPart3D and b != a: assert(b in exceptions)
		var poses: Dictionary = {}
		for body: Node in bodies.get_children():
			if body is PhysicalBodyPart3D: poses[body.name] = body.transform
		assert(actor.generate_creature())
		for node_name: StringName in poses:
			assert(actor.get_node("GeneratedParts").get_node(NodePath(node_name)).transform.is_equal_approx(poses[node_name]))
		print("HORNED_CREATURE_PASS scale=", multiplier, " parts=", count, " joints=22 feet=", feet)
	generator.overall_scale = 1.0
	assert(actor.generate_creature())
	assert(PhysicalBodyPart3D.BodyPartTag.Feather == 9)
	assert(PhysicalBodyPart3D.BodyPartTag.Tail == 10 and PhysicalBodyPart3D.BodyPartTag.Horn == 11)
	var tail: PhysicalBodyPart3D = actor.get_node("GeneratedParts/Tail")
	assert(PhysicalBodyPart3D.BodyPartTag.Tail in tail.tags)
	var horn: PhysicalBodyPart3D = actor.get_node("GeneratedParts/HornLeft")
	assert(PhysicalBodyPart3D.BodyPartTag.Horn in horn.tags)
	for horn_name: String in ["HornLeft", "HornRight"]:
		var curl: PhysicalBodyPart3D = actor.get_node("GeneratedParts/" + horn_name)
		var direction: Vector3 = curl.basis * (curl.get_node("JointOut").position - curl.get_node("JointIn").position)
		assert(direction.x < 0.0 and direction.y > 0.0)
		assert(curl.basis.determinant() > 0.0)
	assert(tail.get_meta("generated_scene_path").ends_with("/Tail/Tail.tscn"))
	var original_horn_size := GEOMETRY.bounds(horn).size
	generator.tail_length = 2.4
	generator.tail_height = 0.4
	generator.tail_root_offset = Vector3(0.1, 0.3, 0.2)
	generator.tail_angle_degrees = 35.0
	generator.horn_size_scale = 1.5
	generator.horn_left_rotation_degrees = Vector3(0, 0, 25)
	assert(actor.generate_creature())
	tail = actor.get_node("GeneratedParts/Tail")
	horn = actor.get_node("GeneratedParts/HornLeft")
	assert(GEOMETRY.bounds(tail).size.is_equal_approx(Vector3(2.4, 0.4, 0.08)))
	assert(tail.geometry_mode == tail.GeometryMode.CUSTOM_MODEL)
	assert(tail.basis.is_equal_approx(Basis(Vector3.BACK, deg_to_rad(35))))
	var torso: PhysicalBodyPart3D = actor.get_node("GeneratedParts/Torso")
	var torso_bounds := GEOMETRY.bounds(torso)
	var expected_root: Vector3 = torso.transform * (torso_bounds.get_center() + Vector3(-torso_bounds.size.x * 0.5, torso_bounds.size.y * generator.tail_root_height_ratio, 0)) + generator.tail_root_offset
	assert((tail.transform * tail.get_node("JointIn").position).distance_to(expected_root) < 0.0001)
	assert(is_equal_approx(GEOMETRY.bounds(horn).size.x, original_horn_size.x * 1.5))
	assert(is_equal_approx(GEOMETRY.bounds(horn).size.z, 0.08))
	assert(horn.basis.is_equal_approx(Basis(Vector3.BACK, deg_to_rad(25))))
	generator.tail_enabled = false
	generator.curl_horns_enabled = false
	assert(actor.generate_creature())
	assert(not actor.has_node("GeneratedParts/Tail") and not actor.has_node("GeneratedParts/HornLeft"))
	generator.tail_enabled = true
	generator.curl_horns_enabled = true
	assert(actor.generate_creature())
	assert(actor._capture_manual_layout())
	assert(generator.use_manual_layout)
	assert(actor.generate_creature())
	assert(actor.get_node("GeneratedParts").get_child_count() == 24)
	generator.use_manual_layout = false
	assert(not actor.has_node("GeneratedParts/HornFan"))
	var action := actor.get_node("CreatureActionController3D")
	assert(action.actions.size() == 1 and action.actions[0].action_id == &"foreleg_stomp")
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	assert(movement.slow_gait_data.target_speed == 3.0)
	assert(movement.foot_joint_yaw_lock_enabled and movement.action_heading_hold_enabled)
	actor.free()
	await process_frame
	print("PASS: HornedBeast default assembly, scales, deterministic poses, collision exclusions, manual round-trip and movement/action configuration.")
	quit()

