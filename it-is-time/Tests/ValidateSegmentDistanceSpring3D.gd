extends SceneTree
const PART = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCreature_Part.tscn")
const SPRING = preload("res://Scripts/Creatures/SegmentDistanceSpring3D.gd")
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var a := PART.instantiate() as PhysicalBodyPart3D
	a.name = "A"
	a.set_meta(&"body_segment_id", 0)
	a.mass = 4.0
	a.gravity_scale = 0.0
	a.freeze = true
	a.collision_layer = 0
	a.collision_mask = 0
	fixture.add_child(a)
	var b := PART.instantiate() as PhysicalBodyPart3D
	b.name = "B"
	b.set_meta(&"body_segment_id", 1)
	b.mass = 4.0
	b.gravity_scale = 0.0
	b.position = Vector3(2.0, 0.0, 0.0)
	b.collision_layer = 0
	b.collision_mask = 0
	fixture.add_child(b)
	var links := Node.new()
	links.name = "Links"
	fixture.add_child(links)
	var spring: Node = SPRING.new()
	spring.node_a = NodePath("../../A")
	spring.node_b = NodePath("../../B")
	links.add_child(spring)
	check(not spring is Joint3D, "Distance spring must not use a rotational physics constraint")
	check(absf(spring.rest_distance - 2.0) < 0.001, "Rest distance must be captured before movement")
	b.position.x = 2.2
	spring._physics_process(1.0 / 60.0)
	check(spring.last_force.x > 0.0, "Separated segments must attract")
	b.position.x = 1.8
	spring._physics_process(1.0 / 60.0)
	check(spring.last_force.x < 0.0, "Compressed segments must repel")
	b.position.x = 2.2
	for frame: int in range(180): await physics_frame
	check(absf(b.position.x - 2.0) < 0.01, "Bidirectional spring must restore its distance")
	check(b.angular_velocity.length() < 0.001, "Central spring force must not generate angular velocity")
	print("DISTANCE_SPRING final_distance=", b.position.x, " angular_speed=", b.angular_velocity.length())
	# The distance limit is a constraint, independent of the spring-force cap.
	spring.maximum_acceleration = 0.0
	spring.maximum_distance_ratio = 1.1
	b.position = Vector3(8, 0, 0)
	b.linear_velocity = Vector3(30, 0, 0)
	spring._physics_process(1.0 / 60.0)
	check(b.position.x <= 2.2001, "Distance lock must project an overstretched segment onto its maximum radius")
	check(spring.get_spring_diagnostics().distance_lock_active, "Distance lock must report activation")
	for frame: int in range(3): await physics_frame
	check(b.position.x <= 2.201, "Distance lock must stop outward motion even with zero spring force")
	a.freeze = false
	a.position = Vector3.ZERO
	b.position = Vector3(8, 0, 0)
	a.linear_velocity = Vector3.ZERO
	b.linear_velocity = Vector3.ZERO
	var constraint_center := (a.position * a.mass + b.position * b.mass) / (a.mass + b.mass)
	spring._physics_process(1.0 / 60.0)
	check(a.position.distance_to(b.position) <= 2.2001, "Maximum distance must also hold for two mobile segments")
	check(((a.position * a.mass + b.position * b.mass) / (a.mass + b.mass)).distance_to(constraint_center) < 0.0001, "Distance projection must preserve pair center of mass")
	a.freeze = true
	a.position = Vector3.ZERO
	spring.maximum_distance_lock_enabled = false
	b.position.x = 4.0
	spring._physics_process(1.0 / 60.0)
	check(b.position.x == 4.0, "Distance lock switch must disable projection")
	spring.maximum_distance_lock_enabled = true
	spring.maximum_acceleration = 50.0
	spring.maximum_distance_ratio = 1.15
	# Restore a sideways offset and an exactly reversed front/back ordering.
	spring.set_layout_reference(0.0, 0.0, true, 1.0, 1.0, 20.0)
	for start: Vector3 in [Vector3(0, 0, 2), Vector3(-2, 0, 0)]:
		b.position = start
		b.linear_velocity = Vector3.ZERO
		for frame: int in range(300): await physics_frame
		check(b.position.distance_to(Vector3(2, 0, 0)) < 0.05, "Layout spring must restore sideways and reversed offsets")
	# Changing the common heading must rotate the layout while preserving momentum.
	a.freeze = false
	a.linear_velocity = Vector3.ZERO
	b.linear_velocity = Vector3.ZERO
	var center := (a.position + b.position) * 0.5
	spring.set_layout_reference(PI * 0.5, 0.0, true, 1.0, 1.0, 20.0)
	for frame: int in range(360): await physics_frame
	check((b.position - a.position).distance_to(Vector3(0, 0, -2)) < 0.05, "Layout must follow a changed shared heading")
	check(((a.position + b.position) * 0.5).distance_to(center) < 0.01, "Layout forces must preserve pair center of mass")
	check(a.angular_velocity.length() < 0.001 and b.angular_velocity.length() < 0.001, "Layout must apply central forces without local body torque")
	print("LAYOUT_SPRING offset=", b.position - a.position, " center_drift=", ((a.position + b.position) * 0.5).distance_to(center))
	b.broken.emit(a)
	check(spring.is_queued_for_deletion() and spring.last_force.is_zero_approx(), "Broken endpoint must remove its logical connection")
	fixture.queue_free()
	await process_frame
	print("SEGMENT_DISTANCE_SPRING_VALIDATION_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
