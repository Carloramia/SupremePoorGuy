extends SceneTree

const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
const BODY = preload("res://Scripts/Creatures/PhysicalBodyParts.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.neck_number = 0
	generator._random.seed = 43
	assert(actor.generate_creature())
	var found := 0
	for node: Node in actor.get_node("GeneratedParts/Joints").get_children():
		if not node is Generic6DOFJoint3D or node.has_method("get_constraint_diagnostics"): continue
		var a: Node = node.get_node(node.node_a)
		var b: Node = node.get_node(node.node_b)
		var both: bool = BODY.BodyPartTag.LegLimb in a.tags and BODY.BodyPartTag.LegLimb in b.tags
		for index: int in range(3):
			var axis: String = ["x","y","z"][index]
			var expected: float = actor.limb_joint_linear_slack[index] if both else 0.0
			assert(is_equal_approx(node.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT),expected))
			assert(is_equal_approx(node.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT),-expected))
		if actor._is_limb_subtorso_pair(a,b):
			assert(node.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT))
			assert(is_zero_approx(node.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)))
			assert(is_zero_approx(node.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)))
		if both:
			found += 1
			assert(node.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT))
			assert(is_zero_approx(node.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)))
	assert(found > 0)
	actor.limb_joint_linear_slack = Vector3(0.01,0.02,0.0)
	actor.get_node("GeneratedLegStepMovementController3D").refresh_physics_query_cache()
	# Save/load must apply new limits to already-generated joints as well.
	var packed := PackedScene.new()
	assert(packed.pack(actor) == OK)
	var restored = packed.instantiate()
	root.add_child(restored)
	for joint: Node in restored.get_node("GeneratedParts/Joints").get_children():
		if not joint is Generic6DOFJoint3D or joint.has_method("get_constraint_diagnostics"): continue
		var a: Node = joint.get_node(joint.node_a)
		var b: Node = joint.get_node(joint.node_b)
		if restored._is_limb_subtorso_pair(a,b):
			assert(is_zero_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)))
		if BODY.BodyPartTag.LegLimb in a.tags and BODY.BodyPartTag.LegLimb in b.tags:
			assert(is_equal_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT),0.02))
			assert(is_zero_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)))
	restored.free()
	# Isolate the native physical constraint: translation must move and then stop at its limit.
	var fixture := Node3D.new()
	root.add_child(fixture)
	var a := RigidBody3D.new()
	a.name = "A"
	a.freeze = true
	fixture.add_child(a)
	var b := RigidBody3D.new()
	b.name = "B"
	b.position.x = 2.0
	b.gravity_scale = 0.0
	b.collision_layer = 0
	b.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	b.add_child(collision)
	fixture.add_child(b)
	var joint := Generic6DOFJoint3D.new()
	joint.position.x = 1.0
	joint.node_a = NodePath("../A")
	joint.node_b = NodePath("../B")
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,-0.6)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,0.6)
	actor._configure_limb_joint_sliding(joint)
	fixture.add_child(joint)
	await physics_frame
	b.apply_central_impulse(Vector3(0,0.2,0))
	b.apply_torque_impulse(Vector3.UP * 5.0)
	var largest_shift := 0.0
	var largest_y_rotation := 0.0
	for frame: int in range(180):
		await physics_frame
		largest_shift = maxf(largest_shift,absf(b.to_global(Vector3.LEFT).y))
		largest_y_rotation = maxf(largest_y_rotation,absf(b.global_rotation.y))
	print("LIMB_SLIDING_PHYSICS shift=",largest_shift," max_y_degrees=",rad_to_deg(largest_y_rotation))
	assert(largest_shift > 0.003 and largest_shift < 0.04,"Native joint must slide within a small bounded distance")
	assert(largest_y_rotation < deg_to_rad(3.0),"Y rotation lock must resist yaw impulse")
	fixture.free()
	actor.free()
	print("LIMB_JOINT_SLIDING_PASSED")
	quit()
