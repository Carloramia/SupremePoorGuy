extends SceneTree
const ACTOR = preload("res://Scenes/Creatures/Characters/Generate_HornedBeast.tscn")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var actor := ACTOR.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	assert(actor.generate_creature())
	var parts := actor.get_node("GeneratedParts")
	var move := actor.get_node("GeneratedLegStepMovementController3D")
	assert(not move.slow_gait_data.gallop_enabled)
	assert(move.slow_gait_data.minimum_support_feet == 2)
	assert(move.get_maximum_stepping_feet() <= 2)
	for name: String in ["Leg_1","Leg_2","ForeLeg_1","ForeLeg_2"]:
		var foot := parts.get_node(name) as PhysicalBodyPart3D
		var support := parts.get_node("SubTorso_"+name) as PhysicalBodyPart3D
		assert(foot.mass >= 0.15 and foot.mass <= 0.25)
		assert(support.mass >= 0.15 and support.mass <= 0.25)
		var lower := parts.get_node(name+"_Limb_1") as PhysicalBodyPart3D
		var upper := parts.get_node(name+"_Limb_2") as PhysicalBodyPart3D
		assert(maxf(lower.mass,upper.mass)/minf(lower.mass,upper.mass) <= 4.0)
		var offset: float = foot.position.x-support.get_node("JointIn").global_position.x
		assert(absf(offset-(0.45 if name.begins_with("Fore") else -0.8)) < 0.02)
	assert(parts.get_node("Tail").mass >= 0.35 and parts.get_node("Tail").mass <= 0.5)
	for joint: Generic6DOFJoint3D in parts.get_node("Joints").get_children():
		var a := joint.get_node(joint.node_a) as PhysicalBodyPart3D
		var b := joint.get_node(joint.node_b) as PhysicalBodyPart3D
		var hip := (PhysicalBodyPart3D.BodyPartTag.SubTorso in a.tags or PhysicalBodyPart3D.BodyPartTag.SubTorso in b.tags) and (PhysicalBodyPart3D.BodyPartTag.LegLimb in a.tags or PhysicalBodyPart3D.BodyPartTag.LegLimb in b.tags)
		var knee := PhysicalBodyPart3D.BodyPartTag.LegLimb in a.tags and PhysicalBodyPart3D.BodyPartTag.LegLimb in b.tags
		var ankle := (PhysicalBodyPart3D.BodyPartTag.Leg in a.tags or PhysicalBodyPart3D.BodyPartTag.ForeLeg in a.tags or PhysicalBodyPart3D.BodyPartTag.Leg in b.tags or PhysicalBodyPart3D.BodyPartTag.ForeLeg in b.tags)
		if hip or knee or ankle:
			print(joint.name, " limits=", joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), ",", joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT))
			assert(is_equal_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT),deg_to_rad(45.0 if hip else 50.0 if knee else 30.0)))
			assert(is_equal_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT),deg_to_rad(12.0 if hip else 0.0)))
	var action_feet: Array[RigidBody3D] = [parts.get_node("ForeLeg_1"), parts.get_node("ForeLeg_2")]
	actor.set_limb_action_limits(action_feet, true)
	assert(not actor._action_joint_limits.is_empty())
	for joint: Generic6DOFJoint3D in actor._action_joint_limits:
		assert(is_equal_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), deg_to_rad(60.0)))
	actor.set_limb_action_limits(action_feet, false)
	for joint: Generic6DOFJoint3D in parts.get_node("Joints").get_children():
		if joint.has_meta(&"authored_walk_limits"):
			var limits: Vector3 = joint.get_meta(&"authored_walk_limits")
			assert(is_equal_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), limits.z))
	actor.free()
	await process_frame
	print("PASS: HornedBeast masses, pose offsets, joint limits and two-foot stance capacity.")
	quit()


