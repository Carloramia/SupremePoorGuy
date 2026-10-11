extends SceneTree

const GEOMETRY = preload("res://Scripts/Creatures/SpiderStrideGeometry.gd")
var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func original_clearance(pose: Dictionary, toe: Vector3, corners: PackedVector3Array, floor_y: float) -> float:
	var lowest := INF
	for corner: Vector3 in corners:
		lowest = minf(lowest, (Vector3(pose.point) + Basis(pose.foot_basis) * (corner - toe)).y - floor_y)
	return lowest

func run() -> void:
	var actor = load("res://Scenes/Creatures/Characters/Generate_Spider.tscn").instantiate()
	root.add_child(actor)
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	movement.set_physics_process(false)
	var original_count := 0
	var reduced_count := 0
	var naive_usec := 0
	var optimized_usec := 0
	for foot: RigidBody3D in movement.get_leg_parts():
		var collision: CollisionShape3D = movement._find_leg_collision_shape(foot)
		var points := PackedVector3Array()
		for point: Vector3 in collision.shape.points: points.append(collision.transform * point)
		var reduced := GEOMETRY.clearance_vertices(points)
		original_count += points.size()
		reduced_count += reduced.size()
		var toe := Vector3(0.1, -0.2, 0.03)
		for index: int in 100:
			var pose := {"point": Vector3(0.1, 2.0, -0.3), "foot_basis": Basis.from_euler(Vector3(index * 0.07, index * 0.11, index * 0.13))}
			var started := Time.get_ticks_usec()
			var expected := original_clearance(pose, toe, points, 0.3)
			naive_usec += Time.get_ticks_usec() - started
			started = Time.get_ticks_usec()
			var actual: float = GEOMETRY.clearance(pose, toe, reduced, 0.3)
			optimized_usec += Time.get_ticks_usec() - started
			check(absf(expected - actual) < 0.00001, "Reduced hull must preserve clearance for arbitrary 3D rotation")
		var contact: Vector3 = movement._planning_contact(foot)
		var far_contact: Vector3 = contact + Vector3.RIGHT * 10.0
		var reach: Dictionary = movement._spider_live_reach(foot, far_contact)
		check(reach.reachable and reach.get("free_slide", false), "Free slider must not be clipped by the old live reach sphere")
	var torso := RigidBody3D.new()
	var upper := RigidBody3D.new()
	var foot := RigidBody3D.new()
	var hip := Generic6DOFJoint3D.new()
	var knee := Generic6DOFJoint3D.new()
	for node: Node3D in [torso, upper, foot, hip, knee]: actor.add_child(node)
	hip.set_meta("generated_joint_frame_a", Transform3D.IDENTITY)
	hip.set_meta("generated_joint_frame_b", Transform3D.IDENTITY)
	knee.set_meta("generated_joint_frame_a", Transform3D(Basis.IDENTITY, Vector3.UP))
	knee.set_meta("generated_joint_frame_b", Transform3D.IDENTITY)
	hip.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -PI)
	hip.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, PI)
	knee.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -PI)
	knee.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, PI)
	knee.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, -0.1)
	knee.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.1)
	knee.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	var target := Vector3(0.0, 3.9, 0.0)
	check(not GEOMETRY.landing_pose(hip, knee, upper, foot, torso, target, Vector3.UP, 0.0).valid, "Limited slider must reject out-of-range goal")
	knee.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, false)
	var free_pose: Dictionary = GEOMETRY.landing_pose(hip, knee, upper, foot, torso, target, Vector3.UP, 0.0)
	check(free_pose.valid, "Free slider must not retain the old 10% planning bound")
	if free_pose.valid:
		var local_pose := {"upper_basis": free_pose.upper_basis, "foot_basis": free_pose.foot_basis, "slide": free_pose.slide}
		check(Vector3(GEOMETRY.world_pose(local_pose, hip, knee, torso, Vector3.UP).point).distance_to(target) < 0.0001, "Free slider IK must reach the requested point")
	print("SPIDER_CLEARANCE_BENCH original_vertices=", original_count, " reduced_vertices=", reduced_count, " original_usec=", naive_usec, " optimized_usec=", optimized_usec)
	actor.free()
	if not failed: print("PASS: Exact hull clearance and free/limited slider IK.")
	quit(1 if failed else 0)
