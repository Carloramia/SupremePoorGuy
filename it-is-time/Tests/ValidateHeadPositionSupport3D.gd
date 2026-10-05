extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
var failed := false
func check(value: bool,message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for segments: int in [0,1,2,3,10]:
		var actor = CHARACTER.instantiate()
		actor.generate_on_ready = false
		actor.planar_constraints_enabled = false
		root.add_child(actor)
		var generator = actor.get_node("CreatureGenerator")
		generator.neck_number = 1
		generator.neck_segment_count = segments
		generator.unsymmetrie = 0
		generator._random.seed = 43
		check(actor.generate_creature(),"Head fixture must generate segments=%s" % segments)
		var controller = actor.get_node("HeadPositionSupport3D")
		check(controller.bindings.size() == 1,"One Head must bind to its Torso")
		if controller.bindings.is_empty():
			actor.queue_free()
			await process_frame
			continue
		var binding: Dictionary = controller.bindings[0]
		check(bool(binding.has_neck) == (segments>0),"Neck path must be identified")
		for component: Node in actor.get_children():
			if component != controller and component != actor.get_node("GeneratedParts"): component.set_physics_process(false)
		for body: Node in actor.get_node("GeneratedParts").get_children():
			if body is PhysicalBodyPart3D and PhysicalBodyPart3D.BodyPartTag.Torso in body.tags: body.freeze = true
		var head: PhysicalBodyPart3D = binding.head
		var torso: PhysicalBodyPart3D = binding.torso
		if segments == 0:
			var joint: Generic6DOFJoint3D = binding.joints[0]
			for axis: String in ["x","y","z"]:
				check(is_equal_approx(joint.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT),0.06),"Direct Head must permit small linear sliding")
		var internal_neck_joints := 0
		for joint: Generic6DOFJoint3D in binding.joints:
			var a := joint.get_node_or_null(joint.node_a)
			var b := joint.get_node_or_null(joint.node_b)
			if a.get_meta(&"generated_role","")=="Neck" and b.get_meta(&"generated_role","")=="Neck":
				internal_neck_joints += 1
				for axis: String in ["x","y","z"]:
					check(joint.call("get_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING),"Neck-Neck joints must have linear springs")
					check(is_equal_approx(joint.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT),0.06),"Neck-Neck joints must allow bounded translation")
		check(internal_neck_joints == maxi(segments-1,0),"Only internal Neck links should use new sliding springs")
		for frame in range(5): await physics_frame
		# Verify exact PD demand, including rotating Torso point velocity.
		controller.set_physics_process(false)
		head.gravity_scale = 0
		head.global_position += Vector3(0.02,0.02,0)
		head.linear_velocity = Vector3(0.2,0.1,0)
		head.global_rotation.z += 0.15
		head.angular_velocity = Vector3(0,0,1)
		torso.linear_velocity = Vector3(0.1,0,0)
		torso.angular_velocity = Vector3(0,0.05,0)
		controller._physics_process(1.0/60)
		check(controller.diagnostics.size()==1,"Head gets independent support")
		var row: Dictionary = controller.diagnostics[0]
		var gain := head.head_position_gain if segments>0 else head.head_no_neck_position_gain
		var damping := head.head_position_damping if segments>0 else head.head_no_neck_position_damping
		var expected: Vector3 = (Vector3(row.position_error)*gain+Vector3(row.velocity_error)*damping).limit_length(head.head_maximum_support_acceleration)*head.mass
		check(Vector3(row.force).is_equal_approx(expected),"Servo must use relative position/velocity with mass scaling")
		var angular_request: Vector3 = (Vector3(row.rotation_error_degrees)*(PI/180.0)*head.head_posture_gain+Vector3(row.angular_velocity_error)*head.head_posture_damping).limit_length(head.head_maximum_angular_acceleration)
		var inertia := head.get_inverse_inertia_tensor().inverse()
		var expected_torque := (inertia*angular_request).limit_length(head.head_maximum_posture_torque)
		check(Vector3(row.posture_torque).is_equal_approx(expected_torque) and expected_torque.length()>0.01,"Head posture must use inertia-scaled restoring torque and relative angular damping")
		var previous_torque_cap := head.head_maximum_posture_torque
		head.head_maximum_posture_torque = 0.01
		controller._physics_process(1.0/60)
		check(Vector3(controller.diagnostics[0].posture_torque).length()<=0.010001,"Posture torque must respect cap")
		head.head_maximum_posture_torque = previous_torque_cap
		head.head_posture_damping_enabled = false
		controller._physics_process(1.0/60)
		check(Vector3(controller.diagnostics[0].posture_torque)==Vector3.ZERO,"Posture can be disabled independently")
		head.head_posture_damping_enabled = true
		head.angular_velocity = Vector3.ZERO
		torso.linear_velocity = Vector3.ZERO
		torso.angular_velocity = Vector3.ZERO
		head.gravity_scale = 1
		head.linear_velocity = Vector3.ZERO
		controller.set_physics_process(true)
		for frame in range(240): await physics_frame
		var error: float = head.global_position.distance_to(torso.global_position+torso.global_basis*Vector3(binding.rest_offset))
		check(error < 0.15,"Head must stay near Torso rest offset segments=%s error=%s" % [segments,error])
		var desired_orientation: Quaternion = torso.global_basis.orthonormalized().get_rotation_quaternion()*Quaternion(binding.rest_rotation)
		var difference: Quaternion = desired_orientation*head.global_basis.orthonormalized().get_rotation_quaternion().inverse()
		if difference.w<0: difference = -difference
		var posture_error := difference.get_angle()
		check(posture_error<0.3,"Head posture must recover from angular disturbance")
		actor.planar_constraints_enabled = true
		controller._physics_process(1.0/60)
		check(controller.diagnostics.is_empty(),"Normal Head servo must stop during planar mode")
		actor.neck_joint_linear_slack = Vector3.ONE*0.08
		actor.planar_constraints_enabled = false
		for joint: Generic6DOFJoint3D in binding.joints:
			var a := joint.get_node_or_null(joint.node_a)
			var b := joint.get_node_or_null(joint.node_b)
			if a.get_meta(&"generated_role","")=="Neck" and b.get_meta(&"generated_role","")=="Neck":
				check(is_equal_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT),0.08),"Returning to normal mode must apply settings changed while planar")
		controller.set_character_control_enabled(false)
		controller._physics_process(1.0/60)
		check(controller.diagnostics.is_empty(),"Character death must stop head control")
		controller.set_character_control_enabled(true)
		if segments>0:
			var neck: PhysicalBodyPart3D = binding.bodies[1]
			neck.break_part(null)
		else: head.break_part(null)
		controller._physics_process(1.0/60)
		check(controller.diagnostics.is_empty(),"Broken Head/Neck chain must stop servo")
		print("HEAD_SUPPORT segments=",segments," error=",error," posture_degrees=",rad_to_deg(posture_error))
		actor.queue_free()
		await process_frame
		await process_frame
	print("HEAD_POSITION_SUPPORT_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
