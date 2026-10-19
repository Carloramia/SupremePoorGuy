extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var actor = load("res://Scenes/Creatures/Characters/Generate_Wolf.tscn").instantiate()
	root.add_child(actor)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	for body in actor.get_node("GeneratedParts").get_children():
		if body is RigidBody3D: body.freeze = true
	actor.wolf_physics = actor.wolf_physics.duplicate()
	actor.wolf_physics.hind_lower_spring_strength = 1.0
	actor.wolf_physics.hind_lower_spring_damping = 0.0
	actor.wolf_physics.hind_lower_spring_maximum_torque = 100.0
	for foot: RigidBody3D in movement._chains:
		var chain: Dictionary = movement._chains[foot]
		if not movement._has_body_tag(foot,movement.FORELEG_TAG):
			var child: RigidBody3D = chain.bodies[1]
			var parent_body: RigidBody3D = chain.bodies[2]
			var saved := child.transform
			child.freeze = false
			parent_body.freeze = false
			var magnitudes: Array[float] = []
			for degrees: float in [10.0,30.0]:
				child.global_basis = Basis(Vector3.BACK,deg_to_rad(degrees))*parent_body.global_basis*Basis(chain.rest_rotations[1])
				child.angular_velocity = Vector3.ZERO
				parent_body.angular_velocity = Vector3.ZERO
				movement._apply_passive_limb_damping()
				assert(movement._wolf_joint_torques.size()==1)
				var row: Dictionary = movement._wolf_joint_torques[0]
				assert(row.mode=="hind_lower_spring" and row.foot==foot.name)
				assert(row.child_torque.z<0.0,"Spring must oppose positive pose error")
				assert(Vector3(row.child_torque+row.parent_torque).is_zero_approx())
				magnitudes.append(row.child_torque.length())
			assert(magnitudes[0]<magnitudes[1],"Restoring torque must weaken near rest")
			movement._action_feet[foot] = true
			movement._apply_passive_limb_damping()
			assert(movement._wolf_joint_torques.is_empty())
			movement._action_feet.erase(foot)
			child.transform = saved
			child.freeze = true
			parent_body.freeze = true
		var source: Generic6DOFJoint3D = chain.joints[1]
		var prefix := "wolf_elbow" if movement._has_body_tag(foot,movement.FORELEG_TAG) else "wolf_hind_lower"
		var fixture := Node3D.new()
		root.add_child(fixture)
		var bodies: Array[RigidBody3D] = []
		for path: NodePath in [source.node_a,source.node_b]:
			var original: RigidBody3D = source.get_node(path)
			var body := RigidBody3D.new()
			body.name = "A" if bodies.is_empty() else "B"
			body.gravity_scale = 0.0
			body.collision_layer = 0
			body.collision_mask = 0
			var collider := CollisionShape3D.new()
			collider.shape = BoxShape3D.new()
			body.add_child(collider)
			fixture.add_child(body)
			body.global_transform = original.global_transform
			bodies.append(body)
		bodies[0].freeze = true
		var joint := Generic6DOFJoint3D.new()
		fixture.add_child(joint)
		joint.global_transform = source.global_transform
		joint.node_a = joint.get_path_to(bodies[0])
		joint.node_b = joint.get_path_to(bodies[1])
		for axis: String in ["x","y","z"]:
			joint.call("set_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT,true)
			joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,0.0)
			joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,0.0)
			joint.call("set_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,true)
			joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,source.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT))
			joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,source.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT))
		var frame_a: Transform3D = source.get_meta(&"generated_joint_frame_a")
		var frame_b: Transform3D = source.get_meta(&"generated_joint_frame_b")
		var side: float = source.get_meta(prefix+"_allowed_sign")
		var straight: float = source.get_meta(prefix+"_straight")
		var minimum_bend: float = source.get_meta(prefix+"_minimum_bend")
		for frame: int in range(180):
			bodies[1].apply_torque(Vector3.BACK*-side*2.0)
			await physics_frame
		var world_a := bodies[0].global_transform*frame_a
		var world_b := bodies[1].global_transform*frame_b
		var angle := (world_a.basis.inverse()*world_b.basis).get_euler().z
		var distance := wrapf(angle-straight,-PI,PI)*side
		print("ELBOW_PHYSICS ",foot.name," distance_from_straight_degrees=",rad_to_deg(distance))
		assert(distance>=minimum_bend-deg_to_rad(3.0) and distance<minimum_bend+deg_to_rad(10.0),"Limb must stop at its anatomical extension limit")
		fixture.free()
	actor.free()
	print("PASS: Wolf hind spring direction, falloff, equal reactions, action exclusion and both physical elbow stops")
	quit()
