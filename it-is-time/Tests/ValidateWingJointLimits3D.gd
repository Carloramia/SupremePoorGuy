extends SceneTree
const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var actor := BIRD.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	actor.wing_root_limit_margin_degrees = 5.0
	actor.wing_middle_limit_margin_degrees = 10.0
	actor.wing_tip_limit_margin_degrees = 15.0
	check(actor.generate_creature(), "Bird must generate with wing limits")
	for binding: Dictionary in actor.get_node("WingPoseController3D").bindings:
		var joint: Generic6DOFJoint3D = binding.joint
		check(joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT), "Wing Z limits enabled by default")
		var relative := Basis(binding.closed.inverse()*binding.open)
		var angle := -atan2(relative.x.y,relative.x.x)
		var section: String = binding.b.get_meta("generated_part_type")
		var margin := deg_to_rad(5.0 if section == "WingRoot" else (10.0 if section == "WingMiddle" else 15.0))
		check(is_equal_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),maxf(-PI,minf(0.0,angle)-margin)), "Section lower margin matches")
		check(is_equal_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT),minf(PI,maxf(0.0,angle)+margin)), "Section upper margin matches")
	actor.queue_free()
	await process_frame
	# Isolate one physical hinge: no pose servo may hide an ineffective hard limit.
	var parent := RigidBody3D.new()
	parent.freeze = true
	root.add_child(parent)
	var body := RigidBody3D.new()
	body.gravity_scale = 0.0
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	root.add_child(body)
	var joint := Generic6DOFJoint3D.new()
	joint.set_meta("generated_rest_b_relative_a",Quaternion.IDENTITY)
	joint.set_meta("wing_open_relative_a",Quaternion(Vector3.BACK,deg_to_rad(60.0)))
	var settings := BIRD.instantiate()
	settings.wing_root_limit_margin_degrees = 5.0
	settings._configure_wing_joint_limits(joint,"Root")
	root.add_child(joint)
	joint.node_a = joint.get_path_to(parent)
	joint.node_b = joint.get_path_to(body)
	for direction: float in [1.0,-1.0]:
		for frame: int in range(120):
			await physics_frame
			body.apply_torque(Vector3.BACK*direction*5.0)
		var angle := rad_to_deg(atan2(body.global_basis.x.y,body.global_basis.x.x))
		print("[wing_limit_test] torque_direction=",direction," actual_degrees=",angle)
		check(absf(angle-(65.0 if direction>0.0 else -5.0))<3.0,"External torque must stop at the physical angular limit")
	settings.wing_joint_limits_enabled = false
	settings._configure_wing_joint_limits(joint,"Root")
	check(not joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT),"Switch disables Z limit")
	settings.free()
	joint.queue_free()
	body.queue_free()
	parent.queue_free()
	await process_frame
	print("WING_JOINT_LIMITS_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
