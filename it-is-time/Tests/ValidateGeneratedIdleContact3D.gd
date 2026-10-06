extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
var failed: bool = false
func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ground := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	collider.shape = shape
	ground.add_child(collider)
	ground.position.y = -0.5
	root.add_child(ground)
	var character := CHARACTER.instantiate()
	character.generate_on_ready = false
	root.add_child(character)
	var generator := character.get_node("CreatureGenerator")
	generator.rear_leg_count = maxi((6) - 2, 0)
	generator.foreleg_count = mini((6), 2)
	generator.unsymmetrie = 60.0
	generator.overall_scale = 4.0
	generator.neck_number = 1

	var generated := false
	for seed_value: int in range(43, 49):
		generator._random.seed = seed_value
		if character.generate_creature():
			generated = true
			break
	if not generated:
		push_error("Could not generate a dense six-foot fixture")
		quit(1)
		return
	var controller := character.get_node("GeneratedLegStepMovementController3D")
	var count: int = character._get_physical_body_parts().size()
	for frame: int in range(600): await physics_frame
	var maximum_angular := 0.0
	var maximum_vertical := 0.0
	var airborne := 0
	for frame: int in range(300):
		await physics_frame
		for foot: RigidBody3D in controller.get_leg_parts():
			maximum_angular = maxf(maximum_angular, foot.angular_velocity.length())
			maximum_vertical = maxf(maximum_vertical, absf(foot.linear_velocity.y))
			if not controller.is_leg_grounded(foot): airborne += 1
	print("[idle_contact_test] parts=%d angular_max=%.4f vertical_max=%.4f airborne=%d/1800" % [count, maximum_angular, maximum_vertical, airborne])
	check(maximum_angular < 3.0, "Idle feet must not spin violently")
	check(maximum_vertical < 2.0, "Idle feet must not repeatedly bounce")
	check(airborne < 180, "Idle feet must retain support contact")
	check(controller.get_step_state_name() == "IDLE", "Idle test must not secretly start stepping")
	Input.action_press("Right")
	for frame: int in range(180): await physics_frame
	Input.action_release("Right")
	for frame: int in range(480): await physics_frame
	maximum_angular = 0.0
	maximum_vertical = 0.0
	airborne = 0
	for frame: int in range(300):
		await physics_frame
		for foot: RigidBody3D in controller.get_leg_parts():
			maximum_angular = maxf(maximum_angular, foot.angular_velocity.length())
			maximum_vertical = maxf(maximum_vertical, absf(foot.linear_velocity.y))
			if not controller.is_leg_grounded(foot): airborne += 1
	print("[post_walk_idle_test] angular_max=%.4f vertical_max=%.4f airborne=%d/1800" % [maximum_angular, maximum_vertical, airborne])
	check(maximum_angular < 3.0 and maximum_vertical < 2.0 and airborne < 180, "Feet must settle again after walking stops")
	character.queue_free()
	ground.queue_free()
	await process_frame
	print("GENERATED_IDLE_CONTACT_VALIDATION_%s" % ("FAILED" if failed else "PASSED"))
	quit(1 if failed else 0)
