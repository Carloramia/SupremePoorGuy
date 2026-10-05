extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
const DATA = preload("res://Scripts/Creatures/LegMovementData.gd")
const BASE = preload("res://Scripts/Creatures/LegStepMovementControllerBase3D.gd")
var failed: bool = false
func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var data = load("res://Resources/Movement/GeneratedWalk.tres").duplicate()
	data.maximum_simultaneous_steps = 0
	data.maximum_stepping_ratio = 0.5
	data.minimum_support_feet = 3
	data.step_frequency = 6.0
	check(data.is_valid(), "Preset must validate")
	var path := "res://Tests/.movement_gait_roundtrip.tres"
	check(ResourceSaver.save(data, path) == OK, "Preset must save")
	var restored = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(restored.step_frequency == 6.0 and restored.maximum_simultaneous_steps == 0, "Preset fields must survive tres roundtrip")
	DirAccess.remove_absolute(path)
	var peer := BASE.new()
	peer.slow_gait_data = data
	var other := BASE.new()
	other.slow_gait_data = data
	peer._step_elapsed = 0.4
	check(other._step_elapsed == 0.0, "Shared data must not share per-character timers")
	peer.free()
	other.free()
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
	generator.neck_number = 0

	generator._random.seed = 43
	if not character.generate_creature():
		push_error("Generation failed")
		quit(1)
		return
	var controller := character.get_node("GeneratedLegStepMovementController3D")
	controller.slow_gait_data = data
	for frame: int in range(300): await physics_frame
	check(controller.get_maximum_stepping_feet() == 3, "Six feet at half ratio allow three simultaneous steps")
	data.step_frequency = 30.0
	check(controller.get_planned_step_frequency() <= 3.0 / data.swing_duration + 0.001, "Frequency must fit simultaneous swing capacity")
	data.step_frequency = 6.0
	var initial: Vector3 = controller._torso.global_position
	var maximum_count := 0
	var logged_parallel := false
	Input.action_press("Right")
	for frame: int in range(480):
		await physics_frame
		var stepping := 0
		var unique: Array = []
		for foot: RigidBody3D in controller.get_leg_parts():
			if controller.is_leg_stepping(foot):
				stepping += 1
				unique.append(foot)
				check(controller.get_leg_adhesion_surface_normal(foot).is_zero_approx(), "Every stepping foot must release adhesion")
				check(not controller._stance_chain_can_support(foot), "Every stepping foot must release stance torque")
				check(controller.get_support_foot_diagnostics(foot).step_tracking_force.is_finite(), "Per-foot drive must remain finite")
		maximum_count = maxi(maximum_count, stepping)
		check(stepping <= 3, "Concurrent foot cap exceeded")
		if stepping >= 2 and not logged_parallel:
			var console := root.get_node("RuntimeConsole")
			var messages: Array = console._collect_leg_motion_lines(controller)
			var moving_lines := 0
			for message: String in messages:
				if "moving=true" in message: moving_lines += 1
			check(moving_lines == stepping, "trackmotion must report every concurrent foot")
			logged_parallel = true
		if stepping >= 2:
			check(controller.get_leg_step_diagnostics(unique[0]).extra != controller.get_leg_step_diagnostics(unique[1]).extra, "Concurrent feet must have independent drive data")
	Input.action_release("Right")
	var displacement: Vector3 = controller._torso.global_position - initial
	print("[resource_gait_test] concurrent_max=%d displacement=%s failures=%d" % [maximum_count, displacement, controller._failed_step_count])
	check(maximum_count >= 2, "Preset must actually run more than one foot concurrently")
	check(displacement.x > 0.5, "Concurrent gait must move forward")
	check(absf(displacement.y) < 1.5 and absf(displacement.z) < 2.0, "Concurrent gait must not launch or drift excessively")
	# Space clears every per-foot state and releases adhesion together.
	check(controller.try_surface_burst(), "Supported character must accept jump")
	check(controller._active_steps.is_empty() and controller.get_active_leg() == null, "Jump must cancel every stepping foot")
	check(controller._adhesion_release_time_remaining > 0.0, "Jump must release every foot's adhesion")
	controller._adhesion_release_time_remaining = 0.0
	controller.set_turn_planning_active(true)
	check(controller._active_steps.is_empty() and controller.get_active_leg() == null, "Turning must cancel all walking feet")
	controller.set_turn_planning_active(false)
	data.maximum_stepping_ratio = 0.0
	Input.action_press("Right")
	for frame: int in range(60): await physics_frame
	check(controller._active_steps.is_empty(), "Zero stepping ratio must disable starts")
	Input.action_release("Right")
	check(data.step_frequency == 6.0 and data.swing_duration == 0.45, "Controller must not mutate shared resource")
	character.queue_free()
	ground.queue_free()
	await process_frame
	print("MOVEMENT_GAIT_RESOURCE_VALIDATION_%s" % ("FAILED" if failed else "PASSED"))
	quit(1 if failed else 0)
