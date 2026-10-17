extends SceneTree

const GENERATOR = preload("res://Scenes/Creatures/Generators/SnakeGenerator.tscn")
const ACTOR = preload("res://Scenes/Creatures/Characters/Generate_Snake.tscn")
const NPC = preload("res://Scenes/Creatures/Characters/Generate_Snake_NPC.tscn")
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")

func _initialize() -> void:
	call_deferred("run")

func check_plan(plan: Dictionary, width: float) -> void:
	assert(not plan.is_empty())
	assert(plan.parts.size() >= 5)
	assert(plan.connections.size() == plan.parts.size() - 1)
	var torso_count: int = plan.grounded_count + plan.raised_count
	assert(plan.parts[torso_count].role == "Head")
	assert(plan.parts[torso_count].transform.basis.is_equal_approx(Basis.IDENTITY))
	var backwards := false
	for index: int in plan.parts.size():
		var part: Dictionary = plan.parts[index]
		assert(part.role == ("Torso" if index < torso_count else ("Head" if index == torso_count else "Jaw")))
		assert(is_equal_approx(part.size.z, width))
		assert(is_zero_approx(part.transform.origin.z))
		assert(part.transform.basis.z.is_equal_approx(Vector3.BACK))
		assert(part.transform.basis.get_scale().is_equal_approx(Vector3.ONE))
		if index < plan.grounded_count:
			var bounds: AABB = part.transform * AABB(-part.size * 0.5, part.size)
			assert(absf(bounds.position.y) < 0.00001)
		elif index < torso_count:
			backwards = backwards or part.transform.basis.x.x < 0.0
		if index > 0:
			var edge: Dictionary = plan.connections[index - 1]
			assert(edge.a == index - 1 and edge.b == index)
			assert(is_zero_approx(edge.anchor.z))
	assert(backwards, "Raised Torso chain must bend back in XY, forming an S.")
	assert(plan.parts[torso_count].transform.origin.y > plan.parts[0].transform.origin.y)
	if plan.parts.size() > torso_count + 1:
		var head_hinge: Vector3 = plan.parts[torso_count].transform * plan.parts[torso_count].mouth_hinge_offset
		var jaw_hinge: Vector3 = plan.parts[-1].transform * plan.parts[-1].mouth_hinge_offset
		assert(Vector2(head_hinge.x, head_hinge.y).is_equal_approx(Vector2(jaw_hinge.x, jaw_hinge.y)))
		assert(plan.connections[-1].kind == "SnakeJaw")
		assert(Vector2(head_hinge.x, head_hinge.y).is_equal_approx(Vector2(plan.connections[-1].anchor.x, plan.connections[-1].anchor.y)))

func check_actor(actor: Node3D, expected: Dictionary, overall: float) -> void:
	assert(actor.generate_character_button.is_valid())
	assert(actor.generate_creature())
	var container := actor.get_node("GeneratedParts")
	assert(container.get_child_count() == expected.parts.size() + 1)
	assert(container.get_node("Joints").get_child_count() == expected.connections.size())
	assert(not actor.planar_constraints_enabled)
	for forbidden: String in ["GeneratedLegStepMovementController3D", "CreatureRecoveryStateMachine3D", "CreatureActionController3D", "HeadPositionSupport3D", "PlanarConstraints"]:
		assert(not actor.has_node(NodePath(forbidden)))
	for layout: Dictionary in expected.parts:
		var part := container.get_node(NodePath(layout.name)) as PhysicalBodyPart3D
		assert(part != null and not part.freeze and not part.is_broken)
		assert(part.tags.is_empty() if layout.role == "Jaw" else part.tags == ([3] if layout.role == "Head" else [0]))
		var pose: Transform3D = layout.transform
		pose.origin *= overall
		assert(part.transform.is_equal_approx(pose))
		assert(GEOMETRY.bounds(part, false).size.is_equal_approx(layout.size * overall))
		assert(part.get_meta("generated_scene_path").contains("/Snake/"))
		var model := part.get_node("Model") as Node3D
		assert(is_equal_approx(model.scale.x, model.scale.y), "XY texture must remain proportional.")
		assert(part.mass > 0.0)
	for joint: Generic6DOFJoint3D in container.get_node("Joints").get_children():
		assert(joint.get_node_or_null(joint.node_a) != null and joint.get_node_or_null(joint.node_b) != null)
		for axis: String in ["x", "y", "z"]:
			assert(joint.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT))
			var width: float = joint.get_meta("snake_slide_width", 0.0)
			var slack: float = joint.get_meta("snake_slide_" + axis, 0.0) if axis != "z" else 0.0
			assert(is_equal_approx(joint.call("get_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT), -width if axis == "z" else -slack))
			assert(is_equal_approx(joint.call("get_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), width if axis == "z" else slack))
			assert(joint.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT))
			var angle := deg_to_rad(actor.snake_bend_limit_degrees) if axis == "z" and joint.get_meta("generated_connection_kind", "") != "SnakeJaw" else 0.0
			assert(is_equal_approx(joint.call("get_param_" + axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), angle))
			assert(not joint.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING))
			assert(not joint.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR))
	assert(actor.get_internal_collision_diagnostics().missing_pairs == 0)
	var jaw := container.get_node_or_null("Jaw") as PhysicalBodyPart3D
	if jaw != null:
		var head := container.get_node("Head") as PhysicalBodyPart3D
		var head_inlet: Vector3 = head.transform * head.get_node("JointIn").position
		var jaw_inlet: Vector3 = jaw.transform * jaw.get_node("JointIn").position
		assert(Vector2(head_inlet.x, head_inlet.y).is_equal_approx(Vector2(jaw_inlet.x, jaw_inlet.y)), "Mouth holes must coincide after fitting and Overall Scale.")
		assert(is_zero_approx(head_inlet.z-jaw_inlet.z))
		assert(head.get_meta("generated_scene_path").ends_with("Snake3UpperJaw.tscn"))
		assert(jaw.get_meta("generated_scene_path").ends_with("Snake3LowerJaw.tscn"))

func run() -> void:
	# Saved editor previews and inherited NPCs must match the new centered generation baseline.
	for scene: PackedScene in [ACTOR,NPC]:
		var preview := scene.instantiate()
		assert(is_equal_approx(preview.snake_joint_x_slack_ratio, 0.15))
		assert(is_equal_approx(preview.snake_joint_y_slack_ratio, 0.05))
		for joint: Generic6DOFJoint3D in preview.get_node("GeneratedParts/Joints").get_children():
			if joint.get_meta("generated_connection_kind", "") == "SnakeJaw":
				assert(is_zero_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)) and is_zero_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)), "Idle Jaw must not sag open when attacks are disabled.")
				continue
			if joint.get_meta("generated_connection_kind", "") not in ["SnakeSpine", "SnakeHead"]: continue
			var length := minf(GEOMETRY.bounds(joint.get_node(joint.node_a)).size.x, GEOMETRY.bounds(joint.get_node(joint.node_b)).size.x)
			assert(is_equal_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), length * 0.15), "Saved previews use 15 percent X travel.")
			assert(is_equal_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), length * 0.05), "Saved previews retain 5 percent Y travel.")
		for body: Node in preview.get_node("GeneratedParts").get_children():
			if body is RigidBody3D: assert(is_zero_approx(body.position.z))
		var jaw: Node3D = preview.get_node("GeneratedParts/Jaw")
		var head: Node3D = preview.get_node("GeneratedParts/Head")
		var closed: Basis = Basis(Vector3.BACK, deg_to_rad(preview.get_node("SnakeGenerator").jaw_closed_angle_degrees))
		assert((head.basis.inverse() * jaw.basis).is_equal_approx(closed), "Saved character and NPC previews must start with a closed Jaw.")
		preview.free()
	var generator := GENERATOR.instantiate()
	root.add_child(generator)
	assert(generator._get_defaults_path().ends_with("SnakeGeneratorDefaults.tres"))
	assert(is_equal_approx(generator.overall_scale, 1.0))
	var plan: Dictionary = generator._build_snake_blueprint()
	assert(plan.parts[-1].role == "Jaw")
	assert(plan.parts[-1].transform.basis.is_equal_approx(Basis(Vector3.BACK, deg_to_rad(generator.jaw_closed_angle_degrees))))
	assert(is_equal_approx(generator._capture_default_parameters().jaw_closed_angle_degrees, generator.jaw_closed_angle_degrees))
	var closed_angle: float = generator.jaw_closed_angle_degrees
	generator.jaw_closed_angle_degrees = 20.0
	var mouth_adjusted: Dictionary = generator._build_snake_blueprint()
	check_plan(mouth_adjusted, generator.part_width)
	assert(mouth_adjusted.parts[-1].transform.basis.is_equal_approx(Basis(Vector3.BACK, deg_to_rad(20.0))))
	for index: int in plan.parts.size() - 1:
		assert(plan.parts[index] == mouth_adjusted.parts[index], "Closing the Jaw must not move or resize Head/Torso.")
	generator.jaw_closed_angle_degrees = INF
	assert(generator._build_snake_blueprint().is_empty())
	generator.jaw_closed_angle_degrees = closed_angle
	check_plan(plan, generator.part_width)
	assert(generator._build_snake_blueprint() == plan, "Repeated generation must be deterministic.")
	assert(generator.generate_torso_button.is_valid() and generator.save_defaults_button.is_valid())
	assert(plan.body_path_length >= generator.body_length)
	assert(plan.body_path_length - generator.body_length < plan.parts[0].size.x)
	var old_length: float = generator.body_length
	generator.body_length *= 1.5
	var longer: Dictionary = generator._build_snake_blueprint()
	assert(longer.parts.size() > plan.parts.size())
	assert(longer.parts[0].size.is_equal_approx(plan.parts[0].size))
	generator.body_length = old_length
	# Torso scaling preserves XY aspect, fixed depth and Head size; empty curves use native size.
	var flat_curve: Curve = generator.segment_size_curve
	assert(generator._property_can_revert(&"segment_size_curve"))
	generator.segment_size_curve = Curve.new()
	var empty_curve_plan: Dictionary = generator._build_snake_blueprint()
	assert(empty_curve_plan.parts.size() == plan.parts.size())
	for index: int in plan.parts.size():
		assert(empty_curve_plan.parts[index].size.is_equal_approx(plan.parts[index].size))
		assert(empty_curve_plan.parts[index].transform.is_equal_approx(plan.parts[index].transform))
	generator.segment_size_curve = null
	assert(generator._build_snake_blueprint() == empty_curve_plan)
	var taper := Curve.new()
	taper.max_value = 2.0
	taper.resource_local_to_scene = true
	taper.add_point(Vector2(0, 0.5))
	taper.add_point(Vector2(1, 1.5))
	generator.segment_size_curve = taper
	var tapered: Dictionary = generator._build_snake_blueprint()
	check_plan(tapered, generator.part_width)
	var distance := 0.0
	for index: int in tapered.grounded_count + tapered.raised_count:
		var size: Vector3 = tapered.parts[index].size
		var factor := taper.sample_baked(clampf(distance / old_length, 0.0, 1.0))
		assert(is_equal_approx(size.x / plan.parts[0].size.x, factor))
		assert(is_equal_approx(size.y / plan.parts[0].size.y, factor))
		distance += size.x * (1.0 - generator.torso_overlap_percent / 100.0)
	assert(tapered.parts[-1].size.is_equal_approx(plan.parts[-1].size))
	assert(tapered.parts[-2].size.is_equal_approx(plan.parts[-2].size))
	assert(tapered.parts[-3].size.x > plan.parts[0].size.x)
	var defaults: Dictionary = generator._capture_default_parameters()
	var captured_curve: Curve = defaults.segment_size_curve
	assert(captured_curve != taper and is_equal_approx(captured_curve.sample_baked(0.5), taper.sample_baked(0.5)))
	var saved := PackedScene.new()
	assert(saved.pack(generator) == OK)
	var restored := saved.instantiate()
	assert(restored._build_snake_blueprint() == tapered, "Packed scene must retain the Torso curve.")
	restored.free()
	generator.segment_size_curve = flat_curve
	generator.part_width = 0.12
	var thinner: Dictionary = generator._build_snake_blueprint()
	check_plan(thinner, 0.12)
	for index: int in plan.parts.size():
		assert(Vector2(plan.parts[index].size.x, plan.parts[index].size.y).is_equal_approx(Vector2(thinner.parts[index].size.x, thinner.parts[index].size.y)))
		assert(Vector2(plan.parts[index].transform.origin.x, plan.parts[index].transform.origin.y).is_equal_approx(Vector2(thinner.parts[index].transform.origin.x, thinner.parts[index].transform.origin.y)))
	generator.part_width = 0.4
	assert(generator.generate_torso())
	var preview := generator.get_node("ManualLayout")
	generator.body_length = -1.0
	assert(not generator.generate_torso())
	assert(generator.get_node("ManualLayout") == preview)
	generator.free()
	for scale_value: float in [0.5, 1.0, 2.0]:
		var actor := ACTOR.instantiate()
		actor.generate_on_ready = false
		root.add_child(actor)
		var settings := actor.get_node("SnakeGenerator")
		settings.overall_scale = scale_value
		check_actor(actor, settings._build_snake_blueprint(), scale_value)
		# Existing manual-layout capture preserves models, collisions, ports and regenerated pose.
		assert(actor._capture_manual_layout())
		assert(settings.use_manual_layout)
		var before: Transform3D = actor.get_node("GeneratedParts/Head").transform
		var jaw_before: Transform3D = actor.get_node("GeneratedParts/Jaw").transform
		assert(actor.generate_creature())
		assert(actor.get_node("GeneratedParts/Head").transform.is_equal_approx(before))
		assert(actor.get_node("GeneratedParts/Jaw").transform.is_equal_approx(jaw_before))
		actor.free()
	# A size curve, mixed Head source and explicit rule multiplier still fit XY uniformly once.
	var variant := ACTOR.instantiate()
	variant.generate_on_ready = false
	root.add_child(variant)
	var settings := variant.get_node("SnakeGenerator")
	settings.snake_head_scene = load("res://Scenes/Creatures/Bodyparts/Snake/Head/Snake1Head.tscn")
	settings.snake_jaw_scene = null
	settings.segment_size_curve = Curve.new()
	settings.segment_size_curve.add_point(Vector2(0, 0.8))
	settings.segment_size_curve.add_point(Vector2(1, 1.0))
	var rule := preload("res://Scripts/Creatures/Generators/GeneratedPartSceneRule.gd").new()
	rule.part_key = "Torso_001"
	rule.part_scene = settings.torso_part_scene
	rule.size_multiplier = 1.2
	rule.size_mode = rule.SizeMode.FIT_BOX
	settings.part_scene_rules.assign([rule])
	check_plan(settings._build_snake_blueprint(), settings.part_width)
	check_actor(variant, settings._build_snake_blueprint(), settings.overall_scale)
	assert(is_equal_approx(rule.size_multiplier, 1.2) and rule.size_mode == rule.SizeMode.FIT_BOX, "Source rules must remain unchanged.")
	variant.free()
	var npc := NPC.instantiate()
	npc.generate_on_ready = false
	root.add_child(npc)
	var npc_settings := npc.get_node("SnakeGenerator")
	check_actor(npc, npc_settings._build_snake_blueprint(), npc_settings.overall_scale)
	var independent := ACTOR.instantiate()
	var npc_curve: Curve = npc.get_node("SnakeGenerator").segment_size_curve
	var other_curve: Curve = independent.get_node("SnakeGenerator").segment_size_curve
	assert(npc_curve != other_curve, "Editing one character's Torso curve must not change another instance.")
	var other_value := other_curve.sample_baked(0.0)
	npc_curve.set_point_value(0, 0.75)
	assert(is_equal_approx(other_curve.sample_baked(0.0), other_value))
	independent.free()
	assert(npc.faction_id == 1)
	assert(npc.get_node("NPCStateMachine3D").enabled)
	assert(npc.get_node("NPCStateMachine3D").attack_execution_enabled)
	assert(npc.get_node("SnakeMovementController3D").locomotion_enabled)
	assert(npc.get_node("SnakeBiteAttackController3D").enabled)
	assert(npc.has_node("SnakeBiteAttackController3D"))
	# Disabled attacks still keep the mouth closed under gravity and an external disturbance.
	npc.get_node("SnakeBiteAttackController3D").enabled = false
	var idle_head: RigidBody3D = npc.get_node("GeneratedParts/Head")
	var idle_jaw: RigidBody3D = npc.get_node("GeneratedParts/Jaw")
	var closed_basis := idle_head.global_basis.inverse() * idle_jaw.global_basis
	idle_jaw.apply_torque_impulse(Vector3.BACK * idle_jaw.mass * 0.1)
	var largest_error := 0.0
	for tick: int in 120:
		await physics_frame
		var relative := idle_head.global_basis.inverse() * idle_jaw.global_basis
		largest_error = maxf(largest_error, (relative * closed_basis.inverse()).get_rotation_quaternion().get_angle())
	assert(largest_error < deg_to_rad(2.0), "Idle Jaw must stay closed with its attack component disabled.")
	print("SNAKE_IDLE_JAW maximum_closed_pose_error_degrees=", rad_to_deg(largest_error))
	npc.free()
	assert(ACTOR.get_state().get_base_scene_state().get_path().ends_with("/_SampleCharacter.tscn"))
	assert(NPC.get_state().get_base_scene_state().get_path().ends_with("/Generate_Snake.tscn"))
	await process_frame
	print("PASS: Snake deterministic chain, Torso curve/save/isolation, grounded rear, raised XY S, centered Z bodies/sliders, proportional textures, scale/width, independent Jaw/mouth hinge, optional Jaw, passive joints, capture/regeneration and inherited NPC.")
	quit()
