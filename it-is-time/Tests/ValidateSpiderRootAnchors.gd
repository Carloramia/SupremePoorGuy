extends SceneTree

var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func check_anchors(actor: Node3D) -> void:
	check(not actor._spider_root_anchors.is_empty(), "Independent support needs a one-way physical root anchor")
	for torso: RigidBody3D in actor._spider_root_anchors:
		var anchor: RID = actor._spider_root_anchors[torso]
		check(PhysicsServer3D.body_get_mode(anchor) == PhysicsServer3D.BODY_MODE_KINEMATIC, "Root anchors must not receive leg reaction forces")
		check(PhysicsServer3D.body_get_collision_layer(anchor) == 0 and PhysicsServer3D.body_get_collision_mask(anchor) == 0, "Root anchors must never add collisions")
	var count := 0
	for joint: Generic6DOFJoint3D in actor.get_node("GeneratedParts/Joints").get_children():
		if not joint.get_meta(&"spider_independent_root", false): continue
		count += 1
		check(joint.get_node(joint.node_a) is PhysicalBodyPart3D and joint.get_node(joint.node_b) is PhysicalBodyPart3D, "Logical Part connections must survive for damage and chain discovery")
		check(joint.get_meta(&"spider_root_anchor", false), "Every root must use the one-way physical constraint")
		for axis: int in 3:
			check(PhysicsServer3D.generic_6dof_joint_get_flag(joint.get_rid(), axis, PhysicsServer3D.G6DOF_JOINT_FLAG_ENABLE_LINEAR_LIMIT), "Rebound physics joints must retain all positional limits")
	check(count == 8, "All eight leg roots must remain connected")

func run() -> void:
	var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_Spider.tscn").instantiate()
	root.add_child(actor)
	await process_frame
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	movement.set_physics_process(false)
	actor.get_node("CreatureRecoveryStateMachine3D").set_physics_process(false)
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is RigidBody3D:
			part.freeze = true
			part.linear_velocity = Vector3.ZERO
			part.angular_velocity = Vector3.ZERO
	check_anchors(actor)
	var foot := actor.get_node("GeneratedParts/Leg_1") as RigidBody3D
	var force: Vector3 = movement._calculate_leg_adhesion_force(foot, {"normal": Vector3.UP, "position": movement._get_foot_world_position(foot)}, 1.0)
	check(force.length() <= foot.mass * movement.maximum_adhesion_acceleration + 0.001 and force.y <= 0.0, "Released foot adhesion must remain mass-scaled and pull-only")
	var torso := actor.get_node("GeneratedParts/Torso_Front") as RigidBody3D
	torso.position += Vector3(2, 1, -3)
	torso.rotation.y = PI
	actor.set_physics_process(false)
	actor._update_spider_root_anchors(1.0 / 60.0)
	await physics_frame
	await physics_frame
	var target: Transform3D = PhysicsServer3D.body_get_state(actor._spider_root_anchors[torso], PhysicsServer3D.BODY_STATE_TRANSFORM)
	check(target.is_equal_approx(torso.global_transform), "A stationary root anchor must follow both Torso translation and facing")
	actor.planar_constraints_enabled = true
	check(actor._spider_root_anchors.is_empty(), "Planar mode must release the extra anchor bodies")
	actor.planar_constraints_enabled = false
	check_anchors(actor)
	for repeat: int in 2:
		check(actor.generate_creature(), "Regeneration must succeed")
		check_anchors(actor)
		await process_frame
	actor.get_node("GeneratedParts/Torso_Front").break_part(null)
	for frame: int in 4: await process_frame
	actor._update_spider_root_anchors(1.0 / 60.0)
	check(actor._spider_root_anchors.is_empty(), "Broken Torso must not retain physical root anchors")
	actor.free()
	await process_frame
	if not failed: print("PASS: Spider root anchors preserve logical joints, follow facing, survive regeneration, and clean up on planar mode, breakage and exit.")
	quit(1 if failed else 0)
