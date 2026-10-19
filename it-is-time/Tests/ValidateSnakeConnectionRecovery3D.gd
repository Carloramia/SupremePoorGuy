extends SceneTree

func _initialize() -> void: call_deferred("run")
func run() -> void:
	var actor := preload("res://Scenes/Creatures/Characters/Generate_Snake_NPC.tscn").instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	var movement := actor.get_node("SnakeMovementController3D")
	for body: Node in actor.get_node("GeneratedParts").get_children():
		if body is RigidBody3D: body.freeze = true
	var row: Dictionary = movement._parts[2]
	var joint: Generic6DOFJoint3D = row.incoming_joint
	var rest: Transform3D = row.body.transform
	movement._set_path_slide_limits(true)
	var x: float = joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
	var z: float = joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
	row.body.position += Vector3(20,0,20)
	movement._path_slides_expanded = false
	movement._set_path_slide_limits(true)
	assert(is_equal_approx(x,joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)))
	assert(is_equal_approx(z,joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)),"A stretched body cannot enlarge the next route's joint limits")
	row.body.transform = rest
	var poses: Dictionary = {}
	for item: Dictionary in movement._parts: poses[item.body] = item.rest
	var invalid: Transform3D = poses[row.body]
	invalid.origin += Vector3(20,0,20)
	poses[row.body] = invalid
	var constrained: Dictionary = movement._constrain_connection_poses(poses,true)
	var a: Dictionary = movement._parts[1]
	var fa: Transform3D = Transform3D(constrained[a.body])*Transform3D(joint.get_meta(&"generated_joint_frame_a"))
	var fb: Transform3D = Transform3D(constrained[row.body])*Transform3D(joint.get_meta(&"generated_joint_frame_b"))
	var offset: Vector3 = fa.affine_inverse()*fb.origin
	assert(absf(offset.x)<=x+0.0001 and absf(offset.z)<=z+0.0001,"Pose targets fit the same structural bounds as the joints")
	assert(Transform3D(constrained[a.body]).origin.distance_to(Transform3D(constrained[row.body]).origin)<=row.rest_gap*1.15+0.0001,"Reversal travel cannot separate neighboring ground pieces")
	movement._start_ground_path(5.0)
	var history: Array = movement._ground_path.points.duplicate(true)
	row.body.position += Vector3(10,0,10)
	movement._update_connections(1.0/60.0)
	assert(not movement.get_attack_connection_diagnostics().ready,"Locomotion reports real connection failure")
	assert(movement.is_connection_recovering(),"Excess travel starts a controlled rejoin")
	assert(not movement.get_snake_motion_diagnostics(false).drive_allowed,"A rejoin cannot propel the body")
	var owner := Node.new()
	actor.add_child(owner)
	assert(not movement.set_attack_control(owner,{},Vector3.ZERO,Vector3.RIGHT,40,40),"Recovery cannot be preempted by another attack")
	for item: Dictionary in movement._parts:
		item.body.global_transform = movement.get_pose_reference()*movement._connection_pose(item)
		item.body.linear_velocity = Vector3.ZERO
		item.body.angular_velocity = Vector3.ZERO
	for frame: int in 100: movement._update_connections(1.0/60.0)
	assert(not movement.is_connection_recovering() and movement.get_attack_connection_diagnostics().ready,"Stable connections release recovery without a timeout")
	assert(movement._path_ready and movement._ground_path.points==history,"Locomotion resumes the visited route instead of replacing its history")
	movement._path_progress = 3.0
	movement._ground_path.ensure(3.0,10.0,Vector3.BACK,3.0)
	history = movement._ground_path.points.duplicate(true)
	var corners: Array = movement._ground_path.corners.duplicate(true)
	var distances: Array = movement._parts.map(func(item: Dictionary): return item.path_distance)
	var phase: float = movement._spacing_phase
	var head: Dictionary = movement._parts[-1]
	var attack_pose: Transform3D = head.rest
	attack_pose.origin += Vector3.RIGHT*2.0
	assert(movement.set_attack_control(owner,{},Vector3.ZERO,Vector3.RIGHT,40,40))
	for frame: int in 45:
		assert(movement.set_attack_control(owner,{head.body:attack_pose},Vector3.ZERO,Vector3.RIGHT,40,40,60,0.1,1.0/60.0,1.0,frame>=15))
		movement._update_ground_path(1.0/60.0,5.0,movement._update_anchor())
		assert(movement._path_ready and not movement._uses_ground_path(),"Attack retains the route without letting it own physical targets")
	assert(movement._ground_path.points==history and movement._ground_path.corners==corners,"Attack freezes visited route points and corners")
	assert(is_equal_approx(movement._path_progress,3.0) and is_equal_approx(movement._spacing_phase,phase),"Attack freezes route progress and spacing phase")
	assert(movement._parts.map(func(item: Dictionary): return item.path_distance)==distances,"Attack retains each follower's route distance")
	assert(not movement.get_ground_path_debug_snapshot().is_empty(),"Paused routes remain visible in path diagnostics")
	movement._support_blend = 1.0
	movement._apply_pose(movement._update_anchor(),1.0/60.0)
	var expected: Vector3 = (movement.get_pose_reference()*Transform3D(movement._attack_poses[head.body])).origin-head.body.global_position
	assert(Vector3(head.pose_error).is_equal_approx(expected),"Retained path cannot overwrite the attacking Head target")
	movement.end_attack_control(owner)
	assert(movement.is_connection_recovering(),"Attack cancellation hands motion to rejoining rather than directly to travel")
	assert(movement._connection_recovery_resume_path,"Attack recovery remembers the route despite idle pose ownership")
	assert(not movement.get_ground_path_debug_snapshot().is_empty(),"Connection recovery preserves the displayed route")
	for frame: int in 100: movement._update_connections(1.0/60.0)
	assert(not movement.is_connection_recovering() and movement._path_ready,"Attack recovery returns control to the existing path")
	assert(movement._ground_path.points==history and movement._ground_path.corners==corners and is_equal_approx(movement._path_progress,3.0),"Attack recovery cannot reset route history or progress")
	assert(movement.set_attack_control(owner,{},Vector3.ZERO,Vector3.RIGHT,40,40))
	movement.end_attack_control(owner)
	movement._ground_path.points.clear()
	for frame: int in 100: movement._update_connections(1.0/60.0)
	assert(not movement._path_ready,"Recovery cannot publish an explicitly cleared route")
	movement.cancel_motion()
	assert(not movement._path_ready and not movement._connection_recovery_resume_path and movement.get_ground_path_debug_snapshot().is_empty(),"Explicit cancellation still invalidates route state")
	actor.free()
	print("SNAKE_CONNECTION_RECOVERY_PASSED")
	quit()
