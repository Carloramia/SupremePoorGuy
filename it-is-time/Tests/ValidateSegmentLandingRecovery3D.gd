extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ground := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(300, 1, 300)
	collider.shape = shape
	ground.add_child(collider)
	ground.position.y = -0.5
	root.add_child(ground)
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	actor.position.y = 30.0
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.rear_leg_count = maxi((6) - 2, 0)
	generator.foreleg_count = mini((6), 2)
	generator.unsymmetrie = 0.0
	generator.overall_scale = 4.0
	generator.neck_number = 1

	generator._random.seed = 43
	check(actor.generate_creature(), "Heavy landing fixture generation must succeed")
	var recovery = actor.get_node("CreatureRecoveryStateMachine3D")
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	for frame: int in range(600): await physics_frame
	var maximum_angle := 0.0
	var minimum_height := INF
	var maximum_layout_error := 0.0
	Input.action_press("Right")
	for frame: int in range(1800):
		await physics_frame
		var data: Dictionary = recovery.get_recovery_diagnostics()
		if floorf(data.metrics.maximum_segment_angle / 10.0) > floorf(maximum_angle / 10.0):
			var worst: RigidBody3D
			var tilt := 0.0
			for body: RigidBody3D in movement.get_torso_parts():
				var angle := rad_to_deg(acos(clampf(body.global_basis.y.normalized().dot(Vector3.UP), -1.0, 1.0)))
				if angle > tilt:
					tilt = angle
					worst = body
			print("HEAVY_PEAK frame=", frame, " body=", worst.name, " rotation=", worst.rotation_degrees, " velocity=", worst.angular_velocity, " segments=", movement.get_body_segment_diagnostics())
		maximum_angle = maxf(maximum_angle, data.metrics.maximum_segment_angle)
		minimum_height = minf(minimum_height, data.metrics.minimum_segment_height_ratio)
		for link: Dictionary in movement._get_segment_spring_diagnostics():
			maximum_layout_error = maxf(maximum_layout_error, absf(link.layout_angle_error_degrees))
		for body: RigidBody3D in movement.get_torso_parts():
			check(body.linear_velocity.is_finite() and body.angular_velocity.is_finite(), "Heavy body motion must remain finite")
	Input.action_release("Right")
	print("HEAVY_SEGMENT_LANDING maximum_segment_angle=", maximum_angle, " minimum_segment_height_ratio=", minimum_height, " recovery=", recovery.get_recovery_diagnostics())
	print("HEAVY_LAYOUT maximum_angle_error=", maximum_layout_error)
	check(maximum_layout_error < 35.0, "Heavy body must preserve cross-segment layout direction")
	check(maximum_angle < 35.0, "Heavy segmented body must keep each region upright after landing")
	check(minimum_height > 0.85, "Heavy segmented body must preserve each region's standing clearance")
	actor.queue_free()
	ground.queue_free()
	await process_frame
	if not failed: print("SEGMENT_LANDING_RECOVERY_VALIDATION_PASSED")
	quit(1 if failed else 0)
