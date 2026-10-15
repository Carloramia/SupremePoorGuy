extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100,1,100)
	collider.shape = box
	floor_body.add_child(collider)
	level.add_child(floor_body)
	floor_body.position.y = -0.5
	var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_Human.tscn").instantiate()
	actor.generate_on_ready = false
	level.add_child(actor)
	actor.position.y = 0.03
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--human-set="):
			actor.get_node("HumanGenerator").human_set = int(argument.trim_prefix("--human-set="))
	assert(actor.generate_creature())
	var torso := actor.get_node("GeneratedParts/Torso") as PhysicalBodyPart3D
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	var initial_y := torso.global_position.y
	for tick: int in 240:
		await physics_frame
		if tick % 60 == 59: print("HUMAN_STAND tick=",tick," y=",torso.global_position.y," up=",torso.global_basis.y.dot(Vector3.UP))
	assert(torso.global_position.y > initial_y * 0.75 and torso.global_basis.y.dot(Vector3.UP) > 0.8)
	var start := torso.global_position
	Input.action_press("Right")
	for tick: int in 180: await physics_frame
	Input.action_release("Right")
	print("HUMAN_WALK displacement=",torso.global_position-start)
	assert(torso.global_position.x > start.x + 0.3)
	Input.action_press("Shift")
	assert(movement.is_fast_speed_active())
	assert(movement._get_gait_data().target_speed > movement.slow_gait_data.target_speed)
	Input.action_release("Shift")
	var swing := actor.get_node("LimbSwingController3D") as LimbSwingController3D
	var upper := actor.get_node("GeneratedParts/Arm_R_Limb_2") as PhysicalBodyPart3D
	var hand := actor.get_node("GeneratedParts/Arm_R") as PhysicalBodyPart3D
	var rest := upper.global_basis.get_rotation_quaternion()
	var hand_y := hand.global_position.y
	Input.action_press("MouseLeft")
	for tick: int in 45: await physics_frame
	assert(swing.get_group_state(0) == LimbSwingController3D.SwingState.CHARGING)
	var lift := rest.angle_to(upper.global_basis.get_rotation_quaternion())
	print("HUMAN_CHARGE shoulder_angle=",rad_to_deg(lift)," hand_rise=",hand.global_position.y-hand_y)
	assert(lift > deg_to_rad(10.0) and hand.global_position.y > hand_y+0.1)
	Input.action_release("MouseLeft")
	for tick: int in 100: await physics_frame
	for tick: int in 180:
		if swing.get_group_state(0) == LimbSwingController3D.SwingState.IDLE: break
		await physics_frame
	assert(swing.get_group_state(0) == LimbSwingController3D.SwingState.IDLE)
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D: assert(part.position.is_finite() and not part.is_broken)
	print("HUMAN_SWING state=",swing.get_group_state(0)," torso_up=",torso.global_basis.y.dot(Vector3.UP))
	level.free()
	await process_frame
	print("PASS: Human standing, input walking, speed preset and shoulder-driven charge/release.")
	quit()
