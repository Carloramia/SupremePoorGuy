extends SceneTree
var failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func joint_settings(joint: Generic6DOFJoint3D) -> Array:
	var result: Array = []
	for axis: String in ["x","y","z"]:
		for flag: int in [Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT]: result.append(joint.call("get_flag_"+axis,flag))
		for parameter: int in [Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT]: result.append(joint.call("get_param_"+axis,parameter))
	return result

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	for size: float in [1.0,2.0]:
		for facing: float in [0.0,PI]:
			await measure(size,facing)
	print("WOLF_HEAD_AIM_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func measure(size: float, facing: float) -> void:
	var actor = load("res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn").instantiate()
	actor.generate_on_ready = false
	actor.rotation.y = facing
	actor.get_node("WolfGenerator").overall_scale = size
	root.add_child(actor)
	check(actor.generate_creature(),"Wolf fixture generates")
	var attacks = actor.get_node("WolfAttackController3D")
	var bite = attacks.get_node("Bite")
	bite.data = bite.data.duplicate()
	var support = actor.get_node("HeadPositionSupport3D")
	for component: Node in actor.get_children():
		if component != support and component != actor.get_node("GeneratedParts"): component.set_physics_process(false)
	for part: RigidBody3D in actor._get_physical_body_parts(): part.freeze = part != bite.head and part != bite.jaw
	var binding: Dictionary = support.bindings[0]
	var neck: Generic6DOFJoint3D = binding.joints[0]
	var original := joint_settings(neck)
	var spring := neck.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING)
	var motor := neck.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR)
	var rest: Transform3D = bite.head.global_transform
	var pivot: Vector3 = rest*Vector3(binding.head_pivot)
	var axis: Vector3 = binding.torso.global_basis.z.normalized()
	var mouth_local: Vector3 = bite._jaw_rest_pose*(Vector3(bite.jaw.get_meta(&"generated_size",Vector3.ONE))*bite.data.box_center_ratio)
	var direction: Vector3 = (rest.basis*(mouth_local-Vector3(binding.head_pivot))).slide(axis).normalized()
	for degrees: float in [-30.0,30.0]:
		bite.active = true
		bite._phase = &"charging"
		bite._head_aim_point = pivot+direction.rotated(axis,deg_to_rad(degrees))*size*8.0
		bite._claim_head_aim()
		var goal: Dictionary = bite.get_head_posture_request()
		check(not goal.is_empty() and signf(goal.angle)==signf(degrees),"Aim follows target height in character-local plane")
		check(absf(rad_to_deg(goal.angle))<=18.01,"Aim stays inside the existing joint Z stop")
		check(joint_settings(neck)==original,"Aiming preserves all angular and linear limits")
		check(not neck.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING),"Standing spring yields to the aim servo")
		check((Transform3D(goal.pose)*Vector3(binding.head_pivot)).distance_to(pivot)<0.001,"Predicted head rotation preserves its joint pivot")
		for tick: int in 180: await physics_frame
		var arrived: Dictionary = bite.get_head_posture_request()
		check(absf(float(arrived.servo_error_degrees))<5.0,"Physical head reaches requested pitch within five degrees size=%s facing=%s angle=%s error=%s" % [size,facing,degrees,arrived.servo_error_degrees])
		var relative: Basis = rest.basis.inverse()*bite.head.global_basis
		check(absf(relative.get_euler().x)<0.03 and absf(relative.get_euler().y)<0.03,"Head aiming does not introduce X/Y twisting")
		var pose: Transform3D = arrived.pose
		var target_pose: Transform3D = bite._closure_pose(1.0,true,pose)
		check((pose.affine_inverse()*target_pose).is_equal_approx(bite._jaw_rest_pose),"Admission predicts the closed jaw under the aimed head")
		var locked: Vector3 = bite._head_aim_point
		check(bite.diagnostics().head_aim.locked_point==locked,"Tracking logs expose the committed world point")
		attacks.cancel_action(&"test_interrupt")
		check(bite.get_head_posture_request().is_empty(),"Interrupt releases Head ownership")
		check(neck.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING)==spring and neck.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR)==motor,"Interrupt restores standing spring and motor")
		for tick: int in 180: await physics_frame
		var error: float = rest.basis.get_rotation_quaternion().angle_to(bite.head.global_basis.get_rotation_quaternion())
		check(rad_to_deg(error)<3.0,"Head smoothly returns to rest after interruption")
		print("WOLF_HEAD_AIM_SAMPLE scale=",size," facing=",facing," requested=",degrees," pitch=",rad_to_deg(goal.angle)," servo_error=",arrived.servo_error_degrees," recovery_error=",rad_to_deg(error))
	# A disabled preset retains the original head and jaw admission poses.
	bite.data.bite_head_aim_enabled = false
	bite.active = true
	check(bite.get_head_posture_request().is_empty(),"Resource switch disables head aiming")
	attacks.cancel_action()
	check(joint_settings(neck)==original,"Completion leaves joint limits unchanged")
	actor.free()
	await process_frame
