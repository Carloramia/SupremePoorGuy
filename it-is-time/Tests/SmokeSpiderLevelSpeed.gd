extends SceneTree

class WalkCommands extends Node:
	func get_movement_direction() -> Vector3: return Vector3.RIGHT
	func get_generated_facing_direction(_delta: float) -> Vector3: return Vector3.RIGHT
	func is_jump_requested() -> bool: return false
	func is_fast_requested() -> bool: return false

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if "off" in OS.get_cmdline_user_args():
		load("res://Resources/Settings/PerformanceOptimization.tres").set(&"enabled", false)
	var level: Node3D = load("res://Scenes/Levels/TestLevel.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	await process_frame
	if "walk" in OS.get_cmdline_user_args():
		# Isolate gait from battle impacts while keeping all eight NPC bodies/controllers active.
		for machine: Node in get_nodes_in_group(&"npc_state_machines"): machine.enabled = false
		for facing: Node in get_nodes_in_group(&"physical_facing_controllers_3d"): facing.turning_enabled = false
		for controller: Node in get_nodes_in_group(&"leg_step_movement_controllers"):
			var commands := WalkCommands.new()
			controller.get_parent().add_child(commands)
			controller.command_source = commands
	var actor: Node3D = level.get_node("GenerateSpiderNPC")
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	movement.set_performance_tracking_enabled(true)
	var torso: RigidBody3D = actor.get_node("GeneratedParts/Torso_Front")
	var start := torso.global_position
	var max_root := 0.0
	var max_knee := 0.0
	var max_tilt := 0.0
	var speed_sum := 0.0
	var overall_speed_sum := 0.0
	var planned_sum := 0.0
	var samples := 0
	var failed := false
	var gait: Dictionary = {}
	var tracked_steps: Dictionary = {}
	for tick: int in 1800:
		await physics_frame
		var walking: bool = tick >= 480 and not movement.get_input_movement_direction().is_zero_approx() and movement._startup_drive_blend >= 1.0 and not movement._foot_heading_turn_active()
		if walking:
			for foot: RigidBody3D in movement._legs:
				if not gait.has(foot.name): gait[foot.name] = {"finished": 0, "incomplete": 0, "sliding_samples": 0, "stance_samples": 0}
				var row: Dictionary = gait[foot.name]
				var motion = movement._find_step_motion_for_spider(foot)
				if tracked_steps.has(foot) and (motion == null or motion.sequence != tracked_steps[foot]):
					var touchdown: Dictionary = movement._spider_last_touchdowns.get(foot, {})
					row.finished += 1
					if touchdown.get("sequence", -1) != tracked_steps[foot] or not touchdown.get("completed", false):
						row.incomplete += 1
						if "failtrace" in OS.get_cmdline_user_args(): print("SPIDER_FAILED ", JSON.stringify({"tick": tick, "foot": foot.name, "toe": movement._get_foot_world_position(foot), "rotation": foot.global_rotation_degrees, "touchdown": touchdown}))
					tracked_steps.erase(foot)
				if motion != null and not tracked_steps.has(foot): tracked_steps[foot] = motion.sequence
				if motion == null and movement.is_leg_grounded(foot):
					row.stance_samples += 1
					if movement._get_ground_contact_velocity(foot, {}).slide(Vector3.UP).length() > 0.35: row.sliding_samples += 1
		else:
			tracked_steps.clear()
		if tick >= 480:
			overall_speed_sum += torso.linear_velocity.slide(Vector3.UP).length()
			# Measure sustained commanded walking separately from AI pauses and
			# its deliberate startup acceleration; retain the full-run average.
			if not movement.get_input_movement_direction().is_zero_approx() and movement._startup_drive_blend >= 1.0 and not movement._foot_heading_turn_active():
				speed_sum += torso.linear_velocity.slide(Vector3.UP).length()
				planned_sum += movement.get_expected_horizontal_speed()
				samples += 1
		if "trace" in OS.get_cmdline_user_args() and tick % 120 == 0:
			print("TEST_LEVEL_TRACE ", JSON.stringify({"tick": tick, "position": torso.global_position, "velocity": torso.linear_velocity, "planned": movement.get_expected_horizontal_speed(), "direction": movement.get_input_movement_direction(), "contact_drive": movement.get_contact_drive_diagnostics(), "budget": movement.get_automatic_motion_diagnostics().spider_motion_budget}))
		max_tilt = maxf(max_tilt, rad_to_deg(torso.global_basis.y.angle_to(Vector3.UP)))
		for joint: Generic6DOFJoint3D in actor.get_node("GeneratedParts/Joints").get_children():
			if not joint.has_meta(&"spider_axial_slide"): continue
			var a: RigidBody3D = joint.get_node(joint.node_a)
			var b: RigidBody3D = joint.get_node(joint.node_b)
			var fa: Transform3D = joint.get_meta(&"generated_joint_frame_a")
			var fb: Transform3D = joint.get_meta(&"generated_joint_frame_b")
			var gap := a.to_global(fa.origin).distance_to(b.to_global(fb.origin))
			if joint.get_meta(&"spider_axial_slide").connection == "root": max_root = maxf(max_root, gap)
			else: max_knee = maxf(max_knee, gap)
			if not a.global_transform.is_finite() or not b.global_transform.is_finite(): failed = true
	var mean_speed := speed_sum / maxi(samples, 1)
	var budget: Dictionary = movement.get_automatic_motion_diagnostics()
	print("TEST_LEVEL_SPIDER_PERFORMANCE ", movement.consume_performance_stats())
	print("TEST_LEVEL_SPIDER_GAIT ", JSON.stringify(gait), " timeouts=", movement._failed_step_count)
	if gait.size() != 8:
		failed = true
		push_error("TestLevel gait verification must sample all eight Spider legs")
	for name: StringName in gait:
		var row: Dictionary = gait[name]
		if row.finished < 5 or float(row.incomplete) / maxf(row.finished, 1) > 0.05 or row.sliding_samples > row.stance_samples * 0.02:
			failed = true
			push_error("TestLevel Spider must finish its steps and keep planted contact stable: " + str(name))
	var console := root.get_node("RuntimeConsole")
	var summary: String = "\n".join(console._collect_motion_summary(actor))
	failed = failed or not "spider_motion_budget=" in summary
	print("TEST_LEVEL_SPIDER mean_commanded_speed=", mean_speed, " overall_mean=", overall_speed_sum / 1320.0, " commanded_samples=", samples, " planned_mean=", planned_sum / maxi(samples, 1), " target=", movement._get_gait_data().target_speed, " root_gap=", max_root, " knee_gap=", max_knee, " maximum_tilt=", max_tilt, " distance=", torso.global_position.distance_to(start), " steps=", movement._step_sequence, " budget=", budget.spider_motion_budget)
	failed = failed or samples < 1000 or mean_speed < 2.85 or max_root > 0.2 or max_knee > 0.15 or max_tilt > 20.0
	level.free()
	await process_frame
	if not failed: print("PASS: TestLevel Spider NPC reaches 95 percent of target speed with bounded joints and motion-budget logging.")
	quit(1 if failed else 0)
