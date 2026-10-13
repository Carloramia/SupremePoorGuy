extends SceneTree

const GEOMETRY = preload("res://Scripts/Creatures/SpiderStrideGeometry.gd")
var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var actor = load("res://Scenes/Creatures/Characters/Generate_Spider.tscn").instantiate()
	root.add_child(actor)
	await process_frame
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	movement.set_physics_process(false)
	var base_budget: float = movement.safe_step_acceleration
	var original_ceiling: float = movement.maximum_dynamic_step_acceleration
	movement.maximum_dynamic_step_acceleration = 1000.0
	var gravity: float = movement._gravity_acceleration().length()
	var slow_budget: float = movement._spider_acceleration_budget(1.6, 0.5)
	var fast_budget: float = movement._spider_acceleration_budget(1.6, 0.25)
	check(is_equal_approx(fast_budget - gravity, (slow_budget - gravity) * 4.0), "Halving swing time must quadruple the travel acceleration budget")
	movement.maximum_dynamic_step_acceleration = 180.0
	check(is_equal_approx(movement._spider_acceleration_budget(100.0, 0.0), 180.0), "Dynamic acceleration must obey its absolute budget ceiling")
	var profile := {"target_speed": 3.0, "step_acceleration": base_budget, "stride": 1.2}
	var dynamic_plan: Dictionary = movement._plan_spider_catch_up(profile, 1.6, 0.27, 0.35, false)
	movement.dynamic_step_acceleration_enabled = false
	var legacy_plan: Dictionary = movement._plan_spider_catch_up(profile, 1.6, 0.27, 0.35, false)
	check(is_equal_approx(legacy_plan.acceleration_budget, base_budget), "Disabling dynamic acceleration must restore the base budget")
	check(is_equal_approx(dynamic_plan.duration, 0.27) and is_equal_approx(legacy_plan.duration, 0.27), "Acceleration budgets must not change the requested swing duration")
	check(is_equal_approx(movement._plan_spider_catch_up(profile, 20.0, 0.27, 0.35, true).duration, 0.27), "Long recovery steps must not extend the swing timeline")
	movement.dynamic_step_acceleration_enabled = true
	movement._current_step.extra["spider_catch_up"] = dynamic_plan
	movement._current_step.extra["automatic_profile"] = {"step_acceleration": 180.0}
	movement._active_movement_scale = 2.0
	check(movement._step_motion_setting("step_acceleration", 60.0) * pow(2.0, 1.5) <= 180.001, "Movement scaling must not bypass the dynamic acceleration ceiling")
	movement._active_movement_scale = 1.0
	movement._current_step.extra.clear()
	movement.maximum_dynamic_step_acceleration = original_ceiling
	print("SPIDER_DYNAMIC_ACCELERATION dynamic=", dynamic_plan, " legacy=", legacy_plan)
	for body: Node in actor.get_node("GeneratedParts").get_children():
		if body is RigidBody3D: body.freeze = true
	var paths := 0
	for foot: RigidBody3D in movement.get_leg_parts():
		var chain: Dictionary = movement._chains[foot]
		var data: Dictionary = movement._spider_reach_geometry[foot]
		var target: Vector3 = movement._planning_contact(foot)
		if foot.name in [&"Leg_2", &"Leg_6"]:
			var ra: Transform3D = chain.joints[1].get_meta("generated_joint_frame_a")
			var rb: Transform3D = chain.joints[1].get_meta("generated_joint_frame_b")
			var ka: Transform3D = chain.joints[0].get_meta("generated_joint_frame_a")
			var kb: Transform3D = chain.joints[0].get_meta("generated_joint_frame_b")
			print("SPIDER_CHAIN_GEOMETRY leg=", foot.name, " root=", chain.root.to_global(rb.origin), " upper_vector=", chain.bodies[1].global_basis * (ka.origin - ra.origin), " lower_vector=", foot.global_basis * (data.toe_local - kb.origin))
		var pose: Dictionary = movement._spider_shape_landing_pose(foot, target)
		check(pose.valid, "Authored foot must have a collision-safe landing: " + str(foot.name))
		if not pose.valid: continue
		check(GEOMETRY.clearance(pose, data.toe_local, data.corners, target.y) >= -0.005, "Whole collision shape must clear floor")
		var start: Dictionary = movement._spider_local_pose(foot, pose)
		var samples: Array[Dictionary] = GEOMETRY.air_samples(chain.joints[1], chain.joints[0], foot, chain.root, data.toe_local, 0.0)
		var path: Array[Dictionary] = GEOMETRY.swing_path(samples, start, start, chain.joints[1], chain.joints[0], chain.root, data.toe_local, data.corners, target.y, float(chain.bodies[1].get_meta("spider_up_axis_sign")), float(foot.get_meta("spider_up_axis_sign")), float(foot.get_meta("spider_world_bend_limit")))
		check(not path.is_empty(), "Authored stance must connect to an airborne pose: " + str(foot.name))
		if path.is_empty(): continue
		paths += 1
		for i: int in range(1, path.size()):
			check(GEOMETRY.pose_distance(path[i - 1], path[i]) < 0.5, "Path must not jump across unreachable configurations")
			for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
				var p := GEOMETRY.world_pose(GEOMETRY.blend_pose(path[i - 1], path[i], fraction), chain.joints[1], chain.joints[0], chain.root, data.toe_local)
				check(GEOMETRY.clearance(p, data.toe_local, data.corners, target.y) >= -0.005, "Interpolated collision shape must not cross floor")
	# Failed attempts must never become a successful-cycle speed estimate.
	var foot: RigidBody3D = movement.get_leg_parts()[0]
	movement._active_leg = foot
	movement._current_step.extra["spider_started_at"] = movement._physics_elapsed - 2.0
	movement._spider_step_times[foot] = 0.5
	movement._handle_step_timeout(false)
	check(is_equal_approx(float(movement._spider_step_times[foot]), 0.5), "Timeout must not lower planner speed via failed-cycle duration")
	print("SPIDER_CONTINUOUS_PATHS ", paths)
	actor.free()
	if not failed: print("PASS: continuous joint paths, whole-foot clearance and successful-cycle timing.")
	quit(1 if failed else 0)
