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
	assert(movement.set_attack_control(owner,{},Vector3.ZERO,Vector3.RIGHT,40,40))
	movement.end_attack_control(owner)
	assert(movement.is_connection_recovering(),"Attack cancellation hands motion to rejoining rather than directly to travel")
	movement._ground_path.points.clear()
	for frame: int in 100: movement._update_connections(1.0/60.0)
	assert(not movement._path_ready,"Recovery cannot publish a route cleared by a whole-body turn")
	actor.free()
	print("SNAKE_CONNECTION_RECOVERY_PASSED")
	quit()
