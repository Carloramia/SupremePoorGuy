extends SceneTree
const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")
const PLAYER = preload("res://Scenes/Player/Controller.tscn")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func frames(count: int) -> void:
	for frame: int in range(count): await physics_frame

func _initialize() -> void: call_deferred("run")

func pose_error(controller: Node, key: String) -> float:
	var maximum := 0.0
	for binding: Dictionary in controller.bindings:
		if not controller._binding_intact(binding): continue
		var a: PhysicalBodyPart3D = binding.a
		var b: PhysicalBodyPart3D = binding.b
		var relative := a.global_basis.orthonormalized().get_rotation_quaternion().inverse() * b.global_basis.orthonormalized().get_rotation_quaternion()
		maximum = maxf(maximum, relative.angle_to(binding[key]))
	return maximum

func run() -> void:
	var actor := BIRD.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator := actor.get_node("BirdGenerator")
	generator.wing_count = 3
	generator.wing_segment_count = 3
	generator.wing_root_length = 0.5
	generator.wing_middle_length = 0.5
	generator.wing_tip_length = 0.5
	generator.overall_scale = 1.0
	generator.wing_fold_degrees = 90.0
	generator.wing_tip_fold_degrees = 60.0
	check(actor.generate_creature(), "Bird must generate")
	var controller := actor.get_node("WingPoseController3D")
	check(controller.bindings.size() == 9, "All wing joints must be controlled, including the odd wing")
	# Isolate the servo from walking, gravity and terrain. Torso parents stay fixed.
	for node: Node in actor.find_children("*", "", true, false):
		if node != controller: node.set_physics_process(false)
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if not part is PhysicalBodyPart3D: continue
		part.gravity_scale = 0.0
		part.freeze = PhysicalBodyPart3D.BodyPartTag.Wing not in part.tags and PhysicalBodyPart3D.BodyPartTag.Feather not in part.tags
	await frames(20)
	check(pose_error(controller,"closed") < 0.05, "Rest pose must remain stable")
	for binding: Dictionary in controller.bindings:
		check(not binding.joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING), "Default springs must not oppose unfold")
	Input.action_press("Space")
	check(not actor.get_node("GeneratedLegStepMovementController3D").is_burst_requested(), "Wing Space must not also trigger jumping")
	await frames(240)
	print("[wing_test] open_error=", pose_error(controller,"open"))
	check(is_equal_approx(controller.unfold_ratio, 1.0), "Held Space must fully unfold")
	check(pose_error(controller,"open") < 0.2, "Wing joints must physically approach their open orientations")
	Input.action_release("Space")
	await frames(240)
	print("[wing_test] closed_error=", pose_error(controller,"closed"))
	check(is_zero_approx(controller.unfold_ratio), "Released Space must fold")
	check(pose_error(controller,"closed") < 0.2, "Wing joints must physically return to generated orientations")
	controller.set_character_control_enabled(false)
	Input.action_press("Space")
	await frames(3)
	check(is_zero_approx(controller.unfold_ratio), "Disabled characters must not respond")
	Input.action_release("Space")
	controller.set_character_control_enabled(true)
	# Regeneration must replace cached body references and reset the pose transition.
	var old_wing: Node = controller.bindings[0].b
	check(actor.generate_creature(), "Regeneration must succeed")
	check(controller.bindings.size() == 9 and controller.bindings[0].b != old_wing, "Regeneration must refresh bindings")
	var player := PLAYER.instantiate()
	actor.add_child(player)
	await frames(4)
	Input.action_press("Space")
	await frames(5)
	check(controller.unfold_ratio > 0.0, "Attached player's held Space must reach wings")
	player.detach_character()
	await frames(50)
	check(is_zero_approx(controller.unfold_ratio), "An uncontrolled bird must not receive player Space")
	Input.action_release("Space")
	player.queue_free()
	await frames(3)
	generator.wing_segment_count = 6
	generator.wing_fold_degrees = 170.0
	generator.wing_tip_fold_degrees = 160.0
	check(actor.generate_creature(), "Six-block wings must generate")
	check(controller.bindings.size() == 18, "Every subdivided block must have a pose binding")
	for node: Node in actor.find_children("*", "", true, false):
		if node != controller: node.set_physics_process(false)
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D:
			part.gravity_scale = 0.0
			part.freeze = PhysicalBodyPart3D.BodyPartTag.Wing not in part.tags and PhysicalBodyPart3D.BodyPartTag.Feather not in part.tags
	Input.action_press("Space")
	await frames(360)
	print("[wing_test] six_block_open_error=", pose_error(controller,"open"))
	check(pose_error(controller,"open") < 0.3, "Highly folded six-block wings must unfold")
	Input.action_release("Space")
	await frames(360)
	print("[wing_test] six_block_closed_error=", pose_error(controller,"closed"))
	check(pose_error(controller,"closed") < 0.3, "Highly folded six-block wings must refold")
	actor.queue_free()
	await frames(3)
	print("WING_POSE_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
