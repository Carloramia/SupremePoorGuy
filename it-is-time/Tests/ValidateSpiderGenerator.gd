extends SceneTree
const GENERATOR = preload("res://Scenes/Creatures/Generators/SpiderGenerator.tscn")
const CHARACTER = preload("res://Scenes/Creatures/Characters/_BaseGeneratedCreature.tscn")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var generator := GENERATOR.instantiate()
	root.add_child(generator)
	assert(generator._get_defaults_path().ends_with("SpiderGeneratorDefaults.tres"))
	var plan: Dictionary = generator._build_spider_blueprint()
	assert(plan.parts.size() == 19 and plan.connections.size() == 18)
	assert(plan.parts[0].transform.origin.x > plan.parts[1].transform.origin.x)
	assert(plan.parts[0].size.x < plan.parts[1].size.x)
	assert(plan.parts[-1].transform.origin.x > plan.parts[0].transform.origin.x)
	var original_offset: float = generator.rear_torso_y_offset
	generator.rear_torso_y_offset = original_offset + 0.2
	var raised: Dictionary = generator._build_spider_blueprint()
	assert(raised.parts[1].transform.origin.is_equal_approx(plan.parts[1].transform.origin + Vector3.UP * 0.2))
	for index: int in range(plan.parts.size()):
		if index != 1: assert(raised.parts[index] == plan.parts[index])
	var front_center: float = raised.parts[0].transform.origin.y
	var rear_center: float = raised.parts[1].transform.origin.y
	var anchor_y: float = raised.connections[0].anchor.y
	assert(anchor_y >= maxf(front_center - generator.front_torso_size.y * 0.5, rear_center - generator.rear_torso_size.y * 0.5))
	assert(anchor_y <= minf(front_center + generator.front_torso_size.y * 0.5, rear_center + generator.rear_torso_size.y * 0.5))
	generator.rear_torso_y_offset = original_offset
	for part: Dictionary in plan.parts:
		assert(is_equal_approx(part.size.z, generator.part_width))
		assert(part.transform.basis.z.is_equal_approx(Vector3.BACK))
		assert(is_equal_approx(part.transform.basis.determinant(), 1.0))
	for side: int in 2:
		for pair: int in 4:
			var index := 2 + (side * 4 + pair) * 2
			var upper: Dictionary = plan.parts[index]
			var lower: Dictionary = plan.parts[index + 1]
			assert(upper.role == "Limb" and lower.role == "Leg" and lower.size.y > upper.size.y)
			var start: Vector3 = upper.transform * Vector3(0, -upper.size.y * 0.5, 0)
			var knee: Vector3 = upper.transform * Vector3(0, upper.size.y * 0.5, 0)
			assert(knee.y > start.y)
			var leg_root: Vector3 = lower.transform * Vector3(0, -lower.size.y * 0.5, 0)
			assert(Vector2(knee.x, knee.y).is_equal_approx(Vector2(leg_root.x, leg_root.y)))
			assert(is_equal_approx(knee.z, start.z))
			var sign_z := -1.0 if side == 0 else 1.0
			assert(is_equal_approx(start.z, sign_z * generator.part_width))
			assert(is_equal_approx(leg_root.z, sign_z * generator.part_width * 2.0))
			var torso_anchor: Vector3 = plan.connections[1 + (side * 4 + pair) * 2].anchor
			var knee_anchor: Vector3 = plan.connections[2 + (side * 4 + pair) * 2].anchor
			assert(torso_anchor.is_equal_approx(start - Vector3(0, 0, sign_z * generator.part_width * 0.5)))
			assert(knee_anchor.is_equal_approx((knee + leg_root) * 0.5))
			# Adjacent sheet intervals touch at the shared surface, with zero Z overlap.
			assert(is_equal_approx(absf(start.z) - upper.size.z * 0.5, plan.parts[0].size.z * 0.5))
			assert(is_equal_approx(absf(leg_root.z) - lower.size.z * 0.5, absf(knee.z) + upper.size.z * 0.5))
			var bounds: AABB = lower.transform * AABB(-lower.size * 0.5, lower.size)
			assert(absf(bounds.position.y) < 0.0001)
			var opposite: Dictionary = plan.parts[2 + ((1-side) * 4 + pair) * 2]
			assert(is_equal_approx(upper.transform.origin.z, -opposite.transform.origin.z))
	var received: Array[Dictionary] = []
	generator.framework_generated.connect(func(value: Dictionary): received.append(value))
	for scale_value: float in [0.5, 1.0, 2.0]:
		generator.overall_scale = scale_value
		assert(generator.generate_torso())
		assert(generator.get_node("ManualLayout").get_child_count() == 19)
		var scaled: Dictionary = received[-1].manual_blueprint
		assert(scaled.parts[0].size.is_equal_approx(plan.parts[0].size * scale_value))
		assert(scaled.connections[0].anchor.is_equal_approx(plan.connections[0].anchor * scale_value))
	# Width overrides body Z settings and is scaled exactly once, including captured layouts.
	generator.front_torso_size.z = 9.0
	generator.rear_torso_size.z = 0.0
	generator.spider_head_size.z = -1.0
	for width: float in [0.08, 0.3]:
		generator.part_width = width
		assert(generator.generate_torso())
		var scaled: Dictionary = received[-1].manual_blueprint
		for part: Dictionary in scaled.parts:
			assert(is_equal_approx(part.size.z, width * generator.overall_scale))
		for index: int in range(scaled.parts.size()):
			var part: Dictionary = scaled.parts[index]
			var original: Dictionary = plan.parts[index]
			assert(is_equal_approx(part.size.x, original.size.x * generator.overall_scale))
			assert(is_equal_approx(part.size.y, original.size.y * generator.overall_scale))
			assert(Vector2(part.transform.origin.x, part.transform.origin.y).is_equal_approx(Vector2(original.transform.origin.x, original.transform.origin.y) * generator.overall_scale))
		assert(is_equal_approx(absf(scaled.connections[1].anchor.z), width * generator.overall_scale * 0.5))
		assert(is_equal_approx(absf(scaled.parts[2].transform.origin.z), width * generator.overall_scale))
		assert(is_equal_approx(absf(scaled.parts[3].transform.origin.z), width * generator.overall_scale * 2.0))
		assert(is_equal_approx(absf(scaled.connections[2].anchor.z), width * generator.overall_scale * 1.5))
	# Leg width changes only Leg cross sections; grounding accounts for the new width.
	generator.leg_width = 0.4
	generator.limb_width = 0.22
	var wider: Dictionary = generator._build_spider_blueprint()
	for part: Dictionary in wider.parts:
		assert(is_equal_approx(part.size.z, generator.part_width))
		if part.role == "Leg":
			assert(is_equal_approx(part.size.x, generator.leg_width))
			var bounds: AABB = part.transform * AABB(-part.size * 0.5, part.size)
			assert(absf(bounds.position.y) < 0.0001)
		elif part.role == "Limb":
			assert(is_equal_approx(part.size.x, generator.limb_width))
	generator.manual_layout = generator.MANUAL_LAYOUT.new()
	generator.manual_layout.blueprint = plan.duplicate(true)
	generator.use_manual_layout = true
	assert(generator.generate_torso())
	for part: Dictionary in received[-1].manual_blueprint.parts:
		assert(is_equal_approx(part.size.z, generator.part_width * generator.overall_scale))
	assert(is_equal_approx(generator.manual_layout.blueprint.parts[0].size.z, plan.parts[0].size.z))
	generator.lower_leg_length = 0.1
	assert(generator._build_spider_blueprint().is_empty())
	generator.free()
	# Verify the existing physical character assembler can consume this generator.
	var actor := CHARACTER.instantiate()
	actor.generate_on_ready = false
	actor.planar_constraints_enabled = false
	actor.generator_path = NodePath("SpiderGenerator")
	var physical_generator := GENERATOR.instantiate()
	physical_generator.part_width = 0.25
	physical_generator.overall_scale = 1.5
	actor.add_child(physical_generator)
	root.add_child(actor)
	assert(actor.generate_creature())
	var parts := actor.get_node("GeneratedParts")
	var legs := 0
	var limbs := 0
	for part: Node in parts.get_children():
		if not part is PhysicalBodyPart3D: continue
		assert(part.basis.z.is_equal_approx(Vector3.BACK))
		assert(is_equal_approx(part.collision_thickness, physical_generator.part_width * physical_generator.overall_scale))
		if PhysicalBodyPart3D.BodyPartTag.Leg in part.tags: legs += 1
		if PhysicalBodyPart3D.BodyPartTag.LegLimb in part.tags: limbs += 1
	assert(legs == 8 and limbs == 8 and parts.get_node("Joints").get_child_count() == 18)
	var depth: float = physical_generator.part_width * physical_generator.overall_scale
	assert(is_equal_approx(absf(parts.get_node("Leg_1_Limb_1").position.z), depth))
	assert(is_equal_approx(absf(parts.get_node("Leg_1").position.z), depth * 2.0))
	actor.free()
	await process_frame
	print("PASS: Spider generator: 2 Torso, 8 ascending Limb + longer grounded Leg, front Head, symmetry, scale, connection data and physical assembly.")
	quit()
