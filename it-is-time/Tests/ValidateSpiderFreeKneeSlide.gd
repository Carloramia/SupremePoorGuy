extends SceneTree

var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func validate_actor(actor: Node) -> void:
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	movement.set_physics_process(false)
	for body: Node in actor.get_node("GeneratedParts").get_children():
		if body is RigidBody3D: body.freeze = true
	movement.refresh_physics_query_cache()
	check(movement._chains.size() == 8, "All eight legs must retain their connections")
	for foot: RigidBody3D in movement._chains:
		var chain: Dictionary = movement._chains[foot]
		var knee: Generic6DOFJoint3D = chain.joints[0]
		var upper: RigidBody3D = chain.bodies[1]
		check(is_equal_approx(foot.position.z, upper.position.z), "Leg and upper limb Z positions must match")
		check(not knee.get_meta("spider_joint_suspended", false), "Knee must be physically connected")
		check(not knee.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT), "Knee Y displacement must be unlimited")
		check(not knee.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING), "Free Y slide must have no restoring spring")
		check(not knee.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_MOTOR), "Free Y slide must have no motor")
		for axis: String in ["x", "z"]:
			check(knee.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT), "Transverse displacement must stay locked")
		for axis: String in ["x", "y", "z"]:
			check(knee.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT), "Rotation limits must remain enabled")
		var original := foot.global_position
		foot.global_position += knee.global_basis.y * 3.0
		movement._update_spider_constraint_guards()
		check(float(movement._spider_constraint_guards[foot].joint_error) < movement.joint_error_tolerance, "Free axial travel must not trigger joint separation correction")
		foot.global_position = original

func run() -> void:
	for scene: String in ["Generate_Spider", "Generate_Spider_NPC"]:
		var actor = load("res://Scenes/Creatures/Characters/" + scene + ".tscn").instantiate()
		# Verify saved editor positions before any activation can alter the scene.
		for i: int in range(1, 9):
			var foot = actor.get_node("GeneratedParts/Leg_%d" % i)
			var upper = actor.get_node("GeneratedParts/Leg_%d_Limb_1" % i)
			check(is_equal_approx(foot.position.z, upper.position.z), "Saved scene must already show aligned legs")
		root.add_child(actor)
		validate_actor(actor)
		check(actor.generate_creature(), "Spider regeneration must succeed")
		validate_actor(actor)
		actor.free()
	if not failed: print("PASS: Spider/NPC saved and regenerated Z alignment, connected knees, free Y slide and retained rotation locks.")
	quit(1 if failed else 0)
