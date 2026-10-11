extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_HornedBeast_SegmentedTail.tscn")
const NAMES = ["TailRoot", "TailTransition", "TailMiddle", "TailTip"]
func _initialize() -> void: call_deferred("run")
func run() -> void:
	assert(CHARACTER.get_state().get_base_scene_state().get_path().ends_with("_BaseGeneratedCreature.tscn"))
	var actor := CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator := actor.get_node("HornedBeastGenerator")
	assert(generator.use_segmented_tail)
	for multiplier: float in [0.5, 1.0, 2.0]:
		generator.overall_scale = multiplier
		assert(actor.generate_creature())
		var bodies := actor.get_node("GeneratedParts")
		assert(bodies.get_child_count() == 27)
		assert(bodies.get_node("Joints").get_child_count() == 25)
		for i in range(NAMES.size()):
			var part := bodies.get_node(NAMES[i]) as PhysicalBodyPart3D
			assert(PhysicalBodyPart3D.BodyPartTag.Tail in part.tags)
			assert(part.scale.is_equal_approx(Vector3.ONE))
			assert(part.get_meta("generated_scene_path").contains("/SegmentedTail_v1/"))
			assert(is_equal_approx(part.paper_volume_thickness * part.get_node("Model").basis.z.length(), generator.part_width * multiplier))
			if i > 0:
				var previous := bodies.get_node(NAMES[i-1]) as Node3D
				assert(part.get_node("JointIn").global_position.distance_to(previous.get_node("JointOut").global_position) < 0.0001)
		for joint: Node in bodies.get_node("Joints").get_children():
			var a := joint.get_node(joint.node_a) as PhysicalBodyPart3D
			var b := joint.get_node(joint.node_b) as PhysicalBodyPart3D
			var frame_a: Transform3D = a.transform * Transform3D(joint.get_meta("generated_joint_frame_a"))
			var frame_b: Transform3D = b.transform * Transform3D(joint.get_meta("generated_joint_frame_b"))
			assert(frame_a.origin.distance_to(frame_b.origin) < 0.0001)
			if str(b.name) in NAMES and b.name != &"TailRoot":
				assert(is_zero_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)))
				assert(is_zero_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)))
				assert(is_equal_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), deg_to_rad(actor.tail_joint_angular_limit_degrees)))
				assert(joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING))
		for a: Node in bodies.get_children():
			if not a is PhysicalBodyPart3D: continue
			for b: Node in bodies.get_children():
				if b is PhysicalBodyPart3D and a != b: assert(b in a.get_collision_exceptions())
		print("SEGMENTED_TAIL_PASS scale=", multiplier, " parts=26 joints=25")
	generator.overall_scale = 1.0
	assert(actor._capture_manual_layout())
	assert(actor.generate_creature())
	assert(actor.get_node("GeneratedParts/Joints").get_child_count() == 25)
	generator.use_manual_layout = false
	generator.use_segmented_tail = false
	assert(actor.generate_creature())
	assert(actor.has_node("GeneratedParts/Tail"))
	assert(not actor.has_node("GeneratedParts/TailRoot"))
	actor.free()
	await process_frame
	print("PASS: segmented tail preserves depth, marker continuity, hinge limits and internal collision exceptions.")
	quit()
