extends SceneTree

const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
const PART = preload("res://Scripts/Creatures/PhysicalBodyParts.gd")

var last_plan: Dictionary = {}

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	assert(PART.BodyPartTag.Torso == 0 and PART.BodyPartTag.Leg == 1)
	assert(PART.BodyPartTag.Arm == 2 and PART.BodyPartTag.Head == 3 and PART.BodyPartTag.ForeLeg == 4)
	assert(CHARACTER.get_state().get_base_scene_state() != null)
	var character := CHARACTER.instantiate() as Node3D
	character.generate_on_ready = false
	root.add_child(character)
	var generator := character.get_node("CreatureGenerator")
	generator.rear_leg_count = maxi((4) - 2, 0)
	generator.foreleg_count = mini((4), 2)
	generator.unsymmetrie = 0.0
	generator.neck_number = 1


	generator.framework_generated.connect(func(plan: Dictionary) -> void: last_plan = plan)
	generator._random.seed = 42
	assert(character.generate_creature(), "Physics generation must succeed")
	var container := character.get_node("GeneratedParts")
	var blueprint: Dictionary = character._build_blueprint(last_plan, generator.torso_connection_distance)
	for layout: Dictionary in blueprint.parts:
		var part := container.get_node(NodePath(layout.name)) as Node3D
		assert(part.transform.is_equal_approx(generator.transform * layout.transform), "Physics boxes must match the source frame")
	var bodies: Array[RigidBody3D] = []
	for child: Node in container.get_children():
		if child is RigidBody3D:
			bodies.append(child)
	var expected: int = last_plan.torsos.size() + last_plan.network_torsos.size()
	for foot: Dictionary in last_plan.layouts:
		expected += foot.limb_points.size()
	for neck: Dictionary in last_plan.necks:
		expected += neck.blocks.size()
	assert(bodies.size() == expected, "Every framework box needs one physics part")
	var joints := container.get_node("Joints")
	assert(blueprint.connections.size() == bodies.size() - 1, "Connected blueprint must have N-1 links")
	var reached: Array[Node] = [bodies[0]]
	for iteration: int in range(bodies.size()):
		for joint: Node in joints.get_children():
			var a := joint.get_node_or_null(joint.node_a)
			var b := joint.get_node_or_null(joint.node_b)
			assert(a in bodies and b in bodies and a != b)
			if joint.has_method("is_segment_spring") or joint.has_method("get_constraint_diagnostics"):
				if a in reached and b not in reached: reached.append(b)
				if b in reached and a not in reached: reached.append(a)
				continue
			assert(joint.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT))
			var expected_slack: float = character.limb_joint_linear_slack.x if PART.BodyPartTag.LegLimb in a.tags and PART.BodyPartTag.LegLimb in b.tags else 0.0
			if a.get_meta("generated_role","")=="Neck" and b.get_meta("generated_role","")=="Neck" and character.neck_linear_springs_enabled:
				expected_slack = character.neck_joint_linear_slack.x
			assert(is_equal_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), expected_slack))
			if str(joint.name).ends_with("Torso"):
				assert(is_zero_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)))
			elif not (PART.BodyPartTag.LegLimb in a.tags and PART.BodyPartTag.LegLimb in b.tags):
				assert(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT) > 0.0)
			if a in reached and b not in reached:
				reached.append(b)
			if b in reached and a not in reached:
				reached.append(a)
	assert(reached.size() == bodies.size(), "All parts must be connected")
	var foreleg_count := 0
	for body: RigidBody3D in bodies:
		assert(not body.freeze)
		assert(body.mass >= character.minimum_part_mass and body.mass <= character.maximum_part_mass)
		assert(body.get_node("CollisionShape3D").shape.size.is_equal_approx(body.get_meta("generated_size")))
		assert((body.get_node("MeshInstance3D").mesh.get_aabb().size * body.get_node("MeshInstance3D").scale).is_equal_approx(body.get_meta("generated_size")))
		assert(not body.get_node("Sprite3D").visible and body.get_node("MeshInstance3D").visible)
		if body.get_meta("generated_role") == "ForeLeg":
			assert(PART.BodyPartTag.ForeLeg in body.tags and PART.BodyPartTag.Arm not in body.tags)
			foreleg_count += 1
		for other: RigidBody3D in bodies:
			if body != other:
				assert(other in body.get_collision_exceptions())
	assert(foreleg_count == 2)
	assert(character.get_node("CharacterDamageController3D")._parts.size() == bodies.size())
	# Real fall onto an external ground collider: internal exceptions must not disable terrain.
	var ground := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	collider.shape = shape
	ground.add_child(collider)
	ground.position.y = -0.5
	root.add_child(ground)
	character.position.y = 3.0
	for body: RigidBody3D in bodies:
		assert(ground not in body.get_collision_exceptions())
	for frame: int in range(240):
		await physics_frame
	for body: RigidBody3D in bodies:
		assert(body.global_position.is_finite() and body.linear_velocity.is_finite() and body.angular_velocity.is_finite())
		assert(body.global_position.y > -1.0, "Physics part fell through ground")
		assert(body.linear_velocity.length() < 30.0, "Joint assembly became unstable")
	# Existing damage behavior applies to generated ForeLegs too.
	var foot := container.get_node("ForeLeg_1") as PhysicalBodyPart3D
	foot.break_part(null)
	await process_frame
	await process_frame
	assert(foot.is_broken)
	for joint: Node in joints.get_children():
		assert(joint.get_node_or_null(joint.node_a) != foot and joint.get_node_or_null(joint.node_b) != foot)
	generator._random.seed = 99
	assert(character.generate_creature(), "Regeneration must replace the physics assembly")
	assert(character.get_node("GeneratedParts") != container)
	await process_frame
	assert(character.get_node("CharacterDamageController3D")._parts.size() == character._get_physical_body_parts().size())
	var regenerated := character.get_node("GeneratedParts")
	character.scale = Vector3(2, 2, 2)
	assert(not character.generate_creature())
	assert(character.get_node("GeneratedParts") == regenerated, "Invalid settings must preserve previous character")
	character.scale = Vector3.ONE
	# Scene persistence must keep generated bodies, their resources, and joint paths.
	character.generate_on_ready = false
	var packed := PackedScene.new()
	assert(packed.pack(character) == OK)
	var restored := packed.instantiate() as Node3D
	root.add_child(restored)
	assert(restored.get_node("GeneratedParts/Joints").get_child_count() == regenerated.get_node("Joints").get_child_count())
	for part: RigidBody3D in restored._get_physical_body_parts():
		assert(not part.freeze)
		assert(part.get_node("CollisionShape3D").shape.size.is_equal_approx(part.get_meta("generated_size")))
	assert(restored.get_node("CharacterDamageController3D")._parts.size() == restored._get_physical_body_parts().size())
	restored.queue_free()
	character.queue_free()
	ground.queue_free()
	await process_frame
	# Normal scene insertion must generate once automatically without a manual call.
	var automatic := CHARACTER.instantiate() as Node3D
	root.add_child(automatic)
	automatic.get_node("CreatureGenerator")._random.seed = 12
	await process_frame
	assert(automatic.has_node("GeneratedParts") and automatic._last_generation_succeeded)
	automatic.queue_free()
	await process_frame
	print("ValidateGeneratedCreatureCharacter3D PASSED")
	quit()
