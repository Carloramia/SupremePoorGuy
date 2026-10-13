extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var level: Node = load("res://Scenes/Levels/TestLevel.tscn").instantiate()
	root.add_child(level)
	var movement: Node
	await process_frame
	for controller: Node in get_nodes_in_group("leg_step_movement_controllers"):
		if controller.get_parent().has_method("get_spider_joint_spring"):
			movement = controller
	if movement == null:
		push_error("Spider controller missing")
		quit(1)
		return
	var actor := movement.get_parent()
	var torso: RigidBody3D = actor.get_node("GeneratedParts/Torso_Front")
	var start := torso.global_position
	var max_error := 0.0
	var max_speed := 0.0
	var max_tilt := 0.0
	var max_heading_error := 0.0
	var failed := false
	var sliding_frames: Dictionary = {}
	var seen: Dictionary = {}
	var successful: Dictionary = {}
	var terminal: Dictionary = {}
	var previous: Dictionary = {}
	var failures: Dictionary = {}
	for tick: int in 1800:
		await physics_frame
		var active: Dictionary = {}
		for motion in movement._active_steps:
			seen[motion.sequence] = true
			active[motion.sequence] = {"leg": motion.leg.name, "lift": motion.extra.get("spider_liftoff", {}), "guide": motion.extra.get("spider_pose_guide", {}), "landing": motion.extra.get("spider_landing", {}), "trajectory": motion.extra.get("spider_contact_trajectory", {}), "pause": motion.extra.get("spider_constraint_pause_elapsed", 0.0)}
		for seq in previous:
			if not active.has(seq): terminal[seq] = previous[seq]
		previous = active
		for row: Dictionary in movement._spider_last_touchdowns.values():
			if row.get("completed", false): successful[row.sequence] = true
		max_tilt = maxf(max_tilt, rad_to_deg(acos(clampf(torso.global_basis.y.normalized().dot(Vector3.UP), -1, 1))))
		max_heading_error = maxf(max_heading_error, rad_to_deg(absf(wrapf(movement._segment_goal_yaw - movement._get_physical_heading_yaw(), -PI, PI))))
		for foot: RigidBody3D in movement.get_leg_parts():
			var row: Dictionary = movement._spider_constraint_guards.get(foot, {})
			max_error = maxf(max_error, float(row.get("joint_error", 0)))
			max_speed = maxf(max_speed, foot.linear_velocity.length())
			if not foot.global_position.is_finite() or foot.is_broken: failed = true
			if not movement.is_leg_stepping(foot) and movement.is_leg_grounded(foot) and not movement._support_pins.has(foot):
				var hit: Dictionary = movement._support_surface_contact(foot)
				if not hit.is_empty() and movement._get_ground_contact_velocity(foot, hit).slide(Vector3.UP).length() > 0.5:
					sliding_frames[foot.name] = int(sliding_frames.get(foot.name, 0)) + 1
		if tick % 240 == 239:
			print("SPIDER_SAFETY_WALK frame=", tick + 1, " travel=", torso.global_position - start, " max_joint_excess=", max_error, " max_foot_speed=", max_speed, " max_tilt=", max_tilt)
	var pending := 0
	for motion in movement._active_steps:
		if seen.has(motion.sequence): pending += 1
	var ended := seen.size() - pending
	for seq in terminal:
		if not successful.has(seq):
			var row: Dictionary = terminal[seq]
			failures[row.leg] = int(failures.get(row.leg, 0)) + 1
			print("SPIDER_FAILED_STEP sequence=", seq, " last=", row)
	print("SPIDER_FAILURES_BY_LEG ", failures)
	print("SPIDER_STEP_OUTCOMES started=", seen.size(), " completed=", successful.size(), " pending=", pending, " ended=", ended, " success_rate=", float(successful.size()) / maxi(ended, 1))
	var releases := 0
	for row: Dictionary in movement._spider_constraint_guards.values(): releases += int(row.get("release_count", 0))
	print("SPIDER_SAFETY_RESULT travel=", torso.global_position - start, " releases=", releases, " max_joint_excess=", max_error, " max_foot_speed=", max_speed, " max_tilt=", max_tilt, " max_heading_error=", max_heading_error)
	for foot: RigidBody3D in movement.get_leg_parts():
		var candidate: Dictionary = movement.find_landing_point(foot, movement.get_input_movement_direction())
		print("SPIDER_CANDIDATE foot=", foot.name, " candidate=", candidate.get("position", Vector3.ZERO), " rejection=", movement._last_landing_rejection_reason)
		print("SPIDER_LANDING_RESULT foot=", foot.name, " sliding_seconds=", float(sliding_frames.get(foot.name, 0)) / 60.0, " recovery=", movement._spider_recovery_steps.get(foot, 0), " touchdown=", movement._spider_last_touchdowns.get(foot, {}), " guard=", movement._spider_constraint_guards.get(foot, {}))
	failed = failed or torso.global_position.x - start.x < 1.0 or max_error > 0.3 or max_tilt > 60.0 or max_heading_error > 20.0
	level.free()
	if not failed: print("PASS: Spider 30-second movement preserves connected upright structure and heading.")
	quit(1 if failed else 0)
