extends SceneTree
const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")
const PART = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCreature_Part.tscn")
var failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func frames(count: int) -> void:
	for frame: int in range(count): await physics_frame

func pose_error(controller: Node, key: String) -> float:
	var result := 0.0
	for binding: Dictionary in controller.bindings:
		if not controller._binding_intact(binding): continue
		var a: PhysicalBodyPart3D = binding.a
		var b: PhysicalBodyPart3D = binding.b
		var relative := a.global_basis.orthonormalized().get_rotation_quaternion().inverse() * b.global_basis.orthonormalized().get_rotation_quaternion()
		result = maxf(result, relative.angle_to(binding[key]))
	return result

func run() -> void:
	var actor := BIRD.instantiate()
	actor.generate_on_ready = false
	actor.position.y = 100.0
	root.add_child(actor)
	check(actor.generate_creature(), "Current full-size bird must generate")
	var controller := actor.get_node("WingPoseController3D")
	check(controller.gravity_compensation_enabled and controller.gravity_compensation_ratio == 1.0, "Compensation must default to full strength")
	for node: Node in actor.find_children("*", "", true, false):
		if node != controller: node.set_physics_process(false)
	# Fixed torso isolates gravity load on the actual saved long wings. Wing gravity stays enabled.
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D:
			part.freeze = PhysicalBodyPart3D.BodyPartTag.Wing not in part.tags and PhysicalBodyPart3D.BodyPartTag.Feather not in part.tags
	await frames(240)
	var error := pose_error(controller, "closed")
	print("[wing_gravity_test] compensated_closed_error_degrees=", rad_to_deg(error))
	check(error < 0.15, "Full-size wings must hold their pose under gravity")
	Input.action_press("Space")
	await frames(600)
	error = pose_error(controller, "open")
	print("[wing_gravity_test] compensated_open_error_degrees=", rad_to_deg(error))
	check(error < 0.3, "Full-size wings must unfold under gravity")
	Input.action_release("Space")
	await frames(600)
	error = pose_error(controller, "closed")
	print("[wing_gravity_test] compensated_refold_error_degrees=", rad_to_deg(error))
	check(error < 0.3, "Full-size wings must refold under gravity")
	# Isolate compensation from the new hard stops, which otherwise also prevent sag.
	actor.wing_joint_limits_enabled = false
	for binding: Dictionary in controller.bindings:
		actor._configure_wing_joint_limits(binding.joint, "Root")
	controller.gravity_compensation_enabled = false
	await frames(240)
	var unsupported_error := pose_error(controller, "closed")
	print("[wing_gravity_test] uncompensated_error_degrees=", rad_to_deg(unsupported_error))
	check(unsupported_error > 0.3, "Disabling compensation must reproduce gravity sag")
	controller.gravity_compensation_enabled = true
	var wing: PhysicalBodyPart3D = controller.bindings[0].b
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	check(controller._get_gravity_compensation_force(wing).is_equal_approx(Vector3.UP * wing.mass * gravity), "Force must equal the actual weight")
	controller.gravity_compensation_ratio = 0.5
	check(controller._get_gravity_compensation_force(wing).is_equal_approx(Vector3.UP * wing.mass * gravity * 0.5), "Ratio must scale force")
	controller.gravity_compensation_ratio = 1.0
	wing.gravity_scale = 0.0
	await frames(2)
	check(controller._get_gravity_compensation_force(wing).is_zero_approx(), "Zero gravity must produce zero compensation")
	wing.gravity_scale = 2.0
	await frames(2)
	check(controller._get_gravity_compensation_force(wing).is_equal_approx(Vector3.UP * wing.mass * gravity * 2.0), "Gravity Scale must be counted exactly once")
	wing.freeze = true
	check(controller._get_gravity_compensation_force(wing).is_zero_approx(), "Frozen wings must not receive compensation")
	wing.freeze = false
	# A detached broken part must retain gravity and fall normally.
	var detached := PART.instantiate() as PhysicalBodyPart3D
	detached.position = Vector3(100.0, 100.0, 0.0)
	root.add_child(detached)
	detached.break_part()
	await frames(2)
	check(controller._get_gravity_compensation_force(detached).is_zero_approx(), "Broken parts must not receive compensation")
	await frames(20)
	check(detached.linear_velocity.y < -1.0, "Broken wings must fall normally")
	detached.queue_free()
	actor.queue_free()
	await frames(3)
	print("WING_GRAVITY_COMPENSATION_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
