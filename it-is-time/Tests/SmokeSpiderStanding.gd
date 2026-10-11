extends SceneTree

const NPC = preload("res://Scenes/Creatures/Characters/Generate_Spider_NPC.tscn")
var failed := false

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(160,1,160)
	collision.shape = shape
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-70,0,-70), Vector3(-70,0,70), Vector3(70,0,70), Vector3(70,0,-70)])
	mesh.add_polygon(PackedInt32Array([0,1,2,3]))
	region.navigation_mesh = mesh
	level.add_child(region)
	var actor := NPC.instantiate()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--scale="):
			actor.get_node(actor.generator_path).overall_scale = argument.trim_prefix("--scale=").to_float()
	actor.position.y = 0.03
	level.add_child(actor)
	await process_frame
	var torso := actor.get_node("GeneratedParts/Torso_Front") as RigidBody3D
	var initial_height := torso.global_position.y
	for tick: int in 180: await physics_frame
	print("SPIDER_STAND height=", torso.global_position.y, " initial=", initial_height, " up=", torso.global_basis.y.dot(Vector3.UP))
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	print("SPIDER_SCALE ", actor.get_node(actor.generator_path).overall_scale, " profile=", movement.get_leg_motion_profile(movement.get_leg_parts()[0]))
	var brain := actor.get_node("NPCStateMachine3D")
	if "--performance" in OS.get_cmdline_user_args():
		movement.set_performance_tracking_enabled(true)
		movement.set_control_performance_tracking_enabled(true)
	brain.move_to_position(torso.global_position + Vector3(60,0,2))
	var start := torso.global_position
	var last_window_start := start
	var seen_steps: Dictionary = {}
	var starts_by_foot: Dictionary = {}
	var unbalanced_frames := 0
	var touchdown_sequences: Dictionary = {}
	var interior_touchdowns := 0
	var outside_touchdowns := 0
	var diagnostics := "--diagnostics" in OS.get_cmdline_user_args()
	var previous_steps: Dictionary = {}
	var previous_failures: int = movement._failed_step_count
	var phases: Dictionary = {}
	for tick: int in 1200:
		if tick == 900: last_window_start = torso.global_position
		await physics_frame
		for foot: RigidBody3D in movement._spider_last_touchdowns:
			var touchdown: Dictionary = movement._spider_last_touchdowns[foot]
			if touchdown_sequences.get(foot, -1) == touchdown.sequence: continue
			touchdown_sequences[foot] = touchdown.sequence
			if touchdown.inside_interval: interior_touchdowns += 1
			else: outside_touchdowns += 1
		if diagnostics:
			var current_steps: Dictionary = {}
			for motion in movement._active_steps:
				var hit: Dictionary = movement._get_surface_below_leg(motion.leg, movement.surface_adhesion_probe_distance)
				var gap: float = -1.0 if hit.is_empty() else (movement._get_foot_world_position(motion.leg) - Vector3(hit.position)).dot(Vector3(hit.normal))
				var phase := "touchdown" if motion.extra.has("spider_touchdown") else ("travel" if motion.extra.get("_step_has_lifted", false) else "lift")
				phases[phase] = int(phases.get(phase, 0)) + 1
				current_steps[motion.sequence] = {"foot": motion.leg.name, "phase": phase, "elapsed": motion.elapsed, "landing_elapsed": motion.landing_elapsed, "gap": gap, "start_gap": motion.extra.get("_step_start_clearance", -1.0), "velocity": motion.leg.linear_velocity, "lift": motion.extra.get("spider_liftoff", {}).duplicate(), "error": motion.extra.get("_tracking_position_error", Vector3.ZERO), "force": motion.extra.get("_tracking_force", Vector3.ZERO), "gravity": motion.extra.get("_tracking_gravity_force", Vector3.ZERO), "target_error": motion.target - motion.leg.global_position}
			if movement._failed_step_count > previous_failures:
				var removed: Array = []
				for sequence in previous_steps:
					if not current_steps.has(sequence): removed.append(previous_steps[sequence])
				print("SPIDER_FAILURE tick=", tick, " reason=", movement._last_step_failure, " previous=", removed)
			previous_steps = current_steps
			previous_failures = movement._failed_step_count
		for motion in movement._active_steps:
			if seen_steps.has(motion.sequence): continue
			seen_steps[motion.sequence] = true
			starts_by_foot[motion.leg.name] = int(starts_by_foot.get(motion.leg.name, 0)) + 1
		if not movement._stance_support_balanced: unbalanced_frames += 1
		if tick % 180 == 179: print("SPIDER_PROGRESS tick=",tick," x=",torso.global_position.x," steps=",movement._step_sequence," failed=",movement._failed_step_count)
	print("SPIDER_WALK delta=", torso.global_position-start, " state=", brain.current_state, " direction=", brain.get_movement_direction())
	print("SPIDER_SUPPORT starts=", starts_by_foot, " unbalanced_frames=", unbalanced_frames, " failed=", movement._failed_step_count)
	if "--performance" in OS.get_cmdline_user_args():
		print("SPIDER_MOVEMENT_PERF ", movement.consume_performance_stats())
		print("SPIDER_MOVEMENT_PHASES ", movement.consume_control_performance_stats())
	print("SPIDER_INTERIOR_TOUCHDOWNS inside=", interior_touchdowns, " outside=", outside_touchdowns)
	if diagnostics: print("SPIDER_PHASE_FRAMES ", phases)
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D and (not part.position.is_finite() or part.is_broken): failed = true
	if torso.global_position.x-start.x <= 0.2: failed = true
	if torso.global_position.x-last_window_start.x <= 0.2: failed = true
	if torso.global_position.y <= initial_height*0.5: failed = true
	var tested_stall := false
	for foot: RigidBody3D in movement.get_leg_parts():
		if movement.is_leg_stepping(foot) or not movement.is_leg_grounded(foot): continue
		var root_body: RigidBody3D = movement._chains[foot].root
		var saved_velocity := root_body.linear_velocity
		var saved_time: float = movement._physics_elapsed
		var saved_stances: Dictionary = movement._spider_stances.duplicate(true)
		# Even in the first 0.01 seconds, an exhausted stance must request a
		# new step. No stall timer or previous-cycle cooldown may block it.
		movement._physics_elapsed = 0.01
		root_body.linear_velocity = Vector3.RIGHT * movement.get_expected_horizontal_speed()
		movement._spider_stall_since.erase(foot)
		movement._get_spider_stance_travel(foot, Vector3.RIGHT)
		movement._spider_stances[foot].root_offset -= Vector3.RIGHT * movement._stance_budget(foot) * 3.0
		var immediate: Dictionary = movement._get_extension_step_demand(foot, Vector3.RIGHT)
		if not immediate.requested or immediate.reason != "spider_stance_limit" or immediate.retry_in != 0.0:
			failed = true
			push_error("Exhausted Spider stance must request a step immediately, without a retry cooldown")
		movement._physics_elapsed = saved_time
		movement._spider_stances = saved_stances
		root_body.linear_velocity = Vector3.ZERO
		movement._spider_stall_since[foot] = movement._physics_elapsed - 2.0
		var demand: Dictionary = movement._get_extension_step_demand(foot, Vector3.RIGHT)
		if not demand.requested or demand.reason != "spider_stall_recovery": failed = true
		var limits: Dictionary = movement.get_spider_stride_limits(foot)
		if limits.valid:
			if not is_equal_approx(float(demand.get("stance_travel_budget", INF)), float(limits.half_travel)): failed = true
		elif float(demand.get("stance_travel_budget", INF)) >= float(movement._chains[foot].length) * 0.1: failed = true
		root_body.linear_velocity = saved_velocity
		movement._spider_stall_since.erase(foot)
		tested_stall = true
		break
	if not tested_stall: failed = true
	brain.move_to_position(torso.global_position + Vector3(-30,0,0))
	for tick: int in 600: await physics_frame
	print("SPIDER_TURN height=", torso.global_position.y, " up=", torso.global_basis.y.dot(Vector3.UP), " startup_pending=", movement._walk_start_pending.size())
	print("SPIDER_PENDING ",movement.get_automatic_motion_diagnostics().get("total_step_frequency")," ",movement._turn_landing_rejections)
	if not torso.global_position.is_finite() or torso.global_basis.y.dot(Vector3.UP) < 0.8: failed = true
	if not movement._walk_start_pending.is_empty(): failed = true
	level.free()
	await process_frame
	if not failed: print("PASS: Spider stays intact and responds to NPC navigation with physical movement.")
	quit(1 if failed else 0)
