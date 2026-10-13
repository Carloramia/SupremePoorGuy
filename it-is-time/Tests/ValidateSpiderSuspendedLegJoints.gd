extends SceneTree

var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	for scene: String in ["Generate_Spider", "Generate_Spider_NPC"]:
		var actor = load("res://Scenes/Creatures/Characters/" + scene + ".tscn").instantiate()
		actor.spider_leg_joints_suspended = true
		actor.spider_knee_free_sliding = false
		root.add_child(actor)
		await process_frame
		var movement = actor.get_node("GeneratedLegStepMovementController3D")
		movement.set_physics_process(false)
		for body: Node in actor.get_node("GeneratedParts").get_children():
			if body is RigidBody3D: body.freeze = true
		movement.refresh_physics_query_cache()
		check(movement._chains.size() == 8, "Suspension must preserve all eight logical leg chains")
		var knees: Array[Generic6DOFJoint3D] = []
		for foot: RigidBody3D in movement._chains:
			var knee: Generic6DOFJoint3D = movement._chains[foot].joints[0]
			var hip: Generic6DOFJoint3D = movement._chains[foot].joints[1]
			knees.append(knee)
			check(knee.get_meta("spider_joint_suspended", false), "Leg-LegLimb joint must be suspended")
			check(not hip.get_meta("spider_joint_suspended", false), "LegLimb-Torso joint must remain connected")
			check(hip.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT), "Hip position constraint must remain enabled")
			for axis: String in ["x", "y", "z"]:
				for flag: int in [Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_MOTOR]:
					check(not knee.call("get_flag_" + axis, flag), "Suspended joint must have no active limits, springs or motors")
		actor.spider_leg_joints_suspended = false
		for knee: Generic6DOFJoint3D in knees:
			check(knee.get_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT), "Re-enabling must restore position constraints")
			check(knee.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT), "Re-enabling must restore hinge limits")
		actor.spider_leg_joints_suspended = true
		await physics_frame
		for knee: Generic6DOFJoint3D in knees:
			check(not knee.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING), "Suspension must persist after physics update")
		actor.free()
	if not failed: print("PASS: Spider/NPC knee suspension, retained hips/topology, refresh and restoration.")
	quit(1 if failed else 0)
