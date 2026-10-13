extends SceneTree

const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func validate(actor: Node) -> void:
	var generator = actor.get_node("SpiderGenerator")
	check(not generator.use_manual_layout and generator.manual_layout == null, "Post-import manual layouts must be cleared")
	check(not generator.has_method("_authored_markers") and not generator.has_method("_align_spider_leg_depths"), "Imported holes must not override the restored frame")
	check(generator.rear_torso_size.is_equal_approx(Vector3(2, 2.0 * 963.0 / 1490.0, 1.6)), "Rear torso frame must preserve its width and source art proportions")
	var rear_model: Node3D = actor.get_node("GeneratedParts/Torso_Rear/Model")
	check(is_equal_approx(rear_model.scale.x, rear_model.scale.y), "Rear torso source art must use uniform XY scaling")
	check(is_equal_approx(generator.upper_limb_length, 2.0) and is_equal_approx(generator.lower_leg_length, 2.8), "Original leg lengths must be restored")
	var mapping: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Spider/Metadata/generator_part_mapping.json"))
	check(generator.part_scene_rules.size() == 19, "All nineteen imported Part associations must survive")
	var plan: Dictionary = generator._build_spider_blueprint()
	for layout: Dictionary in plan.parts:
		var part = actor.get_node("GeneratedParts/" + str(layout.name))
		var expected: Transform3D = layout.transform
		expected.origin *= generator.overall_scale
		check(part.transform.is_equal_approx(generator.transform * expected), "Saved and regenerated body placement must match the restored frame: " + str(layout.name))
		check(GEOMETRY.bounds(part).size.is_equal_approx(layout.size * generator.overall_scale), "Imported meshes/colliders must fit the original frame size: " + str(layout.name))
		var collision := part.get_node("CollisionShape3D") as CollisionShape3D
		check(collision.shape is BoxShape3D, "Every Part must use the original box collider: " + str(layout.name))
		check(collision.transform.is_equal_approx(Transform3D.IDENTITY), "Legacy colliders must remain centered without local rotation or scaling")
		check(is_equal_approx(part.collision_thickness, layout.size.z * generator.overall_scale), "Inspector collision depth must match the original box")
		if layout.role == "Limb":
			var model := part.get_node("Model") as Node3D
			check(is_equal_approx(model.scale.x, model.scale.y), "Upper-limb visuals must retain their source aspect ratio")
		check(part.get_meta(&"generated_scene_path", "") == mapping[str(layout.name)], "Imported Part reference must be preserved: " + str(layout.name))
		var rule = generator.get_part_scene_rule(str(part.get_meta(&"generated_part_type")), str(part.name), str(part.name))
		check(not rule.use_joint_markers and not rule.align_connectors_to_frame, "Imported markers must not move procedural joints")
		if layout.role == "Leg" or layout.role == "Limb":
			var factor := 2.0 if layout.role == "Leg" else 1.0
			check(is_equal_approx(absf(part.position.z), generator.part_width * generator.overall_scale * factor), "Restore separate torso/upper/lower Z layers")
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	movement.set_physics_process(false)
	check(not movement.has_method("_build_spider_joint_path"), "Post-import joint-space swing search must be removed")
	check(not movement.has_method("_update_spider_constraint_guards"), "Post-import constraint-release control must be removed")
	check(is_equal_approx(actor.spider_root_slide_ratio, 0.02) and is_equal_approx(actor.spider_knee_slide_ratio, 0.03), "Pre-import slider tuning must be restored")
	check(movement.get_leg_parts().size() == 8, "All imported legs must remain available")
	var count := 0
	for joint: Generic6DOFJoint3D in actor.get_node("GeneratedParts/Joints").get_children():
		if not joint.has_meta("spider_axial_slide"): continue
		count += 1
		var slide: Dictionary = joint.get_meta("spider_axial_slide")
		var knee: bool = slide.connection == "knee"
		check(joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT), "Both root and knee travel must remain bounded")
		check(joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING) == not knee, "Only bounded root travel uses an axial spring")
		check(is_equal_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), 0.0 if knee else float(slide.upper_length) * 0.02), "Knee holes must pivot without translation; root tuning must remain unchanged")
		check(is_zero_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)) and is_zero_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)), "Out-of-plane rotations must retain their hinge limits")
	check(count == 16, "All sixteen original physical joints must remain configured")
	for foot: RigidBody3D in movement.get_leg_parts():
		check(movement.get_spider_stride_limits(foot).valid, "Restored box feet must have valid bidirectional structural stride planning")
		check(movement.get_leg_motion_profile(foot).stride > 0.0, "Restored controller must produce nonzero walking strides")

func run() -> void:
	for name: String in ["Generate_Spider", "Generate_Spider_NPC"]:
		var actor = load("res://Scenes/Creatures/Characters/" + name + ".tscn").instantiate()
		actor.generate_on_ready = false
		root.add_child(actor)
		actor._activate_parts(actor.get_node("GeneratedParts"))
		for body: Node in actor.get_node("GeneratedParts").get_children():
			if body is RigidBody3D: body.freeze = true
		validate(actor)
		check(actor.generate_creature(), "Imported Spider must still regenerate")
		validate(actor)
		actor.free()
	if not failed: print("PASS: Spider/NPC saved and regenerated legacy box colliders, original joints, valid stride planning and nineteen retained visual Part references.")
	quit(1 if failed else 0)
