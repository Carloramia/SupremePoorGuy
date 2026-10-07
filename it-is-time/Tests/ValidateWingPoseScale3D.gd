extends SceneTree
const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var birds: Array[Node3D] = []
	var results: Array[Dictionary] = []
	var mass_limited := "--mass-limits" in OS.get_cmdline_user_args()
	var scales: Array = [1.5,4.0] if mass_limited else [0.75,1.5,2.0,4.0,8.0]
	for scale_value: float in scales:
		var bird := BIRD.instantiate() as Node3D
		bird.generate_on_ready = false
		bird.mass_limits_enabled = mass_limited
		bird.position = Vector3(birds.size()*200.0,50.0,0.0)
		root.add_child(bird)
		var generator := bird.get_node("BirdGenerator")
		generator.overall_scale = scale_value
		generator.unsymmetrie = 0.0
		generator.inhomogeneity = 0.0
		generator._random.seed = 43
		check(bird.generate_creature(),"Wing scale fixture must generate")
		bird.get_node("WingPoseController3D").set_diagnostic_tracking_enabled(true)
		birds.append(bird)
		results.append({"sum":0.0,"count":0,"max":0.0,"speed":0.0})
	for frame: int in range(1200):
		await physics_frame
		if frame < 1020: continue
		for index: int in range(birds.size()):
			var wing := birds[index].get_node("WingPoseController3D")
			for binding: Dictionary in wing.bindings:
				var command: Dictionary = binding.get("command",{})
				if command.is_empty(): continue
				results[index].sum += float(command.error_degrees)
				results[index].count += 1
				results[index].max = maxf(results[index].max,float(command.error_degrees))
				results[index].speed = maxf(results[index].speed,binding.b.angular_velocity.length())
				check(command.effective_hinge_inertia>0.0 and Vector3(command.torque).is_finite(),"Hinge inertia/torque must remain valid")
	for index: int in range(birds.size()):
		var result: Dictionary = results[index]
		var mean_error := float(result.sum)/maxi(int(result.count),1)
		print("[wing_scale_test] scale=",birds[index].get_node("BirdGenerator").overall_scale," mean_error=",mean_error," max_error=",result.max," max_speed=",result.speed)
		check(result.count>0,"Wing diagnostics must contain samples")
		check(result.max<2.0,"Wing posture must converge within two degrees")
		check(result.speed<0.5,"Wings must settle without persistent oscillation")
		var wing := birds[index].get_node("WingPoseController3D")
		check(wing.automatic_load_inertia and wing.joint_motor_pose,"Scale adaptation must be enabled by default")
		wing.set_character_control_enabled(false)
		for binding: Dictionary in wing.bindings:
			check(not binding.joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR),"Disabling control must stop joint motors")
		var bounded: Vector3 = wing._stable_acceleration(Vector3(0.0,0.0,0.5),Vector3.ZERO,10.0,1.0,1.0/15.0)
		check(bounded.is_finite(),"High gains at a long timestep must remain finite")
		birds[index].queue_free()
	print("WING_POSE_SCALE_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
