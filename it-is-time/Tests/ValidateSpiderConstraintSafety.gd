extends SceneTree

const MOVEMENT_BASE = preload("res://Scripts/Creatures/LegStepMovementControllerBase3D.gd")

var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var actor = load("res://Scenes/Creatures/Characters/Generate_Spider.tscn").instantiate()
	actor.spider_leg_joints_suspended = false
	root.add_child(actor)
	await process_frame
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	movement.set_physics_process(false)
	for body: Node in actor.get_node("GeneratedParts").get_children():
		if body is RigidBody3D: body.freeze = true
	var foot: RigidBody3D = movement.get_leg_parts()[0]
	var root_body: RigidBody3D = movement._chains[foot].root
	var toe: Vector3 = movement._get_foot_world_position(foot)
	var reference_frame: Dictionary = movement._structural_landing_frame(foot, Vector3.RIGHT, 0.2)
	var foot_pose := foot.global_transform
	foot.global_position += Vector3(-2.0, 0.0, 0.3)
	var dragged_frame: Dictionary = movement._structural_landing_frame(foot, Vector3.RIGHT, 0.2)
	for recovering: bool in [false, true]:
		for index: int in 4:
			var original: Vector3 = movement._structural_landing_sample(reference_frame, index, 4, recovering)
			check(original.is_equal_approx(movement._structural_landing_sample(dragged_frame, index, 4, recovering)), "Dragged foot must not shift normal or recovery candidates")
			root_body.global_position += Vector3.RIGHT
			var moved_frame: Dictionary = movement._structural_landing_frame(foot, Vector3.RIGHT, 0.2)
			check((original + Vector3.RIGHT).is_equal_approx(movement._structural_landing_sample(moved_frame, index, 4, recovering)), "Landing candidates must follow Torso translation")
			root_body.global_position -= Vector3.RIGHT
	foot.global_transform = foot_pose
	var contact_local: Vector3 = foot.to_local(movement._planning_contact(foot))
	foot.rotate_z(0.1)
	check(contact_local.is_equal_approx(foot.to_local(movement._planning_contact(foot))), "Planning reference must not jump to a new lowest vertex")
	foot.global_transform = foot_pose
	check(movement._spider_live_reach(foot, toe).reachable, "Authored contact must be within live reach")
	check(not movement._spider_live_reach(foot, toe + Vector3.RIGHT * 100).reachable, "Reject unreachable terrain")
	var chain: Dictionary = movement._chains[foot]
	var geometry = preload("res://Scripts/Creatures/SpiderStrideGeometry.gd")
	check(geometry.landing_pose(chain.joints[1], chain.joints[0], chain.bodies[1], foot, root_body, toe, toe, 0.0).valid, "IK must accept authored contact pose")
	check(not geometry.landing_pose(chain.joints[1], chain.joints[0], chain.bodies[1], foot, root_body, toe + Vector3.RIGHT * 100.0, toe, 0.0).valid, "IK must reject targets outside chain reach")
	check(not geometry.landing_pose(chain.joints[1], chain.joints[0], chain.bodies[1], foot, root_body, toe + Vector3.BACK, toe, 0.0).valid, "IK must reject targets outside the joint plane")
	for leg: RigidBody3D in movement.get_leg_parts():
		var leg_chain: Dictionary = movement._chains[leg]
		var contact: Vector3 = movement._get_foot_world_position(leg)
		check(geometry.landing_pose(leg_chain.joints[1], leg_chain.joints[0], leg_chain.bodies[1], leg, leg_chain.root, contact, contact, 0.0).valid, "IK must preserve authored contact for " + str(leg.name))
		var fixed_contact: Vector3 = movement._planning_contact(leg)
		var projected: Vector3 = geometry.project_to_plane(leg_chain.joints[1], leg_chain.joints[0], leg, leg_chain.root, fixed_contact + Vector3.BACK, fixed_contact)
		check(is_equal_approx(projected.y, fixed_contact.y), "Plane projection must preserve terrain height")
		var pose: Dictionary = movement._spider_landing_pose(leg, projected)
		check(pose.valid, "Projected authored contact must solve for " + str(leg.name))
		if pose.valid:
			var ra: Transform3D = leg_chain.joints[1].get_meta("generated_joint_frame_a")
			var rb: Transform3D = leg_chain.joints[1].get_meta("generated_joint_frame_b")
			var ka: Transform3D = leg_chain.joints[0].get_meta("generated_joint_frame_a")
			var kb: Transform3D = leg_chain.joints[0].get_meta("generated_joint_frame_b")
			var anchor: Vector3 = leg_chain.root.to_global(rb.origin)
			var solved: Vector3 = anchor + Basis(pose.upper_basis) * (ka.origin - ra.origin + ka.basis.y * float(pose.slide)) + Basis(pose.foot_basis) * (leg.to_local(fixed_contact) - kb.origin)
			check(solved.distance_to(projected) < 0.001, "IK and forward kinematics must agree for " + str(leg.name))
			check(absf(float(pose.slide)) <= float(leg_chain.joints[0].get_meta("spider_axial_slide").half_travel) + 0.00001, "IK must respect slider range")
		check(leg_chain.joints[0].get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT) and is_zero_approx(leg_chain.joints[0].get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)), "Y rotation stays locked")
	root_body.position += Vector3.RIGHT * 100
	check(not movement._spider_live_reach(foot, toe).reachable, "Reach must follow current torso, not captured pose")
	root_body.position -= Vector3.RIGHT * 100
	movement._update_spider_constraint_guards()
	check(not movement._spider_constraint_release_active(foot), "Authored aligned joints must not trigger guard")
	var knee: Generic6DOFJoint3D = movement._chains[foot].joints[0]
	var upper: RigidBody3D = movement._chains[foot].bodies[1]
	var knee_frame: Transform3D = knee.get_meta("generated_joint_frame_a")
	var axis: Vector3 = (upper.global_basis * knee_frame.basis).y.normalized()
	var travel: float = knee.get_meta("spider_axial_slide").half_travel
	var saved := foot.global_transform
	foot.global_position += axis * travel * 0.5
	movement._update_spider_constraint_guards()
	check(not movement._spider_constraint_release_active(foot), "Legal knee slide must remain available")
	foot.global_position += axis * (travel + 0.15)
	movement._update_spider_constraint_guards()
	check(movement._spider_constraint_release_active(foot), "Excessive joint separation must release ground lock")
	check(movement._calculate_leg_adhesion_force(foot, {"normal": Vector3.UP}, 1.0).is_zero_approx(), "Released foot must not be pulled down by adhesion")
	check(not movement._keep_touchdown_support_pin(foot), "Strained foot must not keep a touchdown pin")
	check(movement.get_support_foot_diagnostics(foot).has("spider_constraint_guard"), "trackmotion must expose guard")
	foot.global_transform = saved
	movement._physics_elapsed += movement.constraint_release_time + 0.01
	movement._update_spider_constraint_guards()
	check(not movement._spider_constraint_release_active(foot), "Aligned foot must recover after release interval")
	var torso_pose := root_body.global_transform
	movement._segment_heading_initialized = true
	movement._segment_goal_yaw = 0.0
	movement._sync_spider_turn_request()
	root_body.global_rotation.y = deg_to_rad(20.0)
	movement._layout_turn_owned = true
	movement._turn_planning_active = true
	check(not movement._foot_heading_turn_active(), "Passive yaw drift must not release all stance pins")
	movement._update_layout_turn_steps(0.016)
	check(not movement._layout_turn_owned and not movement._turn_planning_active, "Passive drift must not retain layout turn ownership")
	movement._segment_goal_yaw = PI
	check(movement._foot_heading_turn_active(), "A real heading command must still allow turning")
	root_body.global_transform = torso_pose
	movement._segment_goal_yaw = 0.0
	movement._sync_spider_turn_request()
	movement._spider_constraint_guards[foot] = {"release_until": movement._physics_elapsed + 10.0}
	movement.update_leg_surface_adhesion()
	check(knee.get_meta("spider_spring_weights").x > 0.0, "Guard must retain weak pose restoration")
	check(is_equal_approx(knee.get_meta("spider_spring_weights").y, 1.0), "Guard must retain full damping")
	movement._begin_leg_motion(foot, foot.global_position + Vector3.RIGHT * 0.2, Vector3.UP, Vector3.RIGHT)
	movement._current_step.extra["liftoff_complete"] = true
	movement._current_step.extra["spider_landing"] = {"invalid": true}
	var saved_target: Vector3 = movement._step_target
	var saved_mask: int = movement.terrain_collision_mask
	movement.terrain_collision_mask = 0
	movement._refresh_structural_landing()
	check(movement._current_step.extra.liftoff_complete, "Failed replan must preserve completed liftoff")
	check(movement._step_target.is_equal_approx(saved_target), "Failed replan must preserve last destination")
	movement.terrain_collision_mask = saved_mask

	var other: RigidBody3D = movement.get_leg_parts()[1]
	movement._current_step = MOVEMENT_BASE.StepMotion.new()
	movement._begin_leg_motion(other, other.global_position + Vector3.RIGHT * 0.2, Vector3.UP, Vector3.RIGHT)
	var other_motion = movement._current_step
	movement._current_step = movement._find_step_motion_for_spider(foot)
	movement._active_leg = foot
	movement._updating_steps = true
	movement._capture_spider_swing_pose()
	movement._current_step.extra["landing_surface_point"] = movement._planning_contact(foot)
	movement._step_elapsed = 0.0
	check(movement._update_direct_spider_swing(0.1), "Authored stance must allow a direct swing command")
	movement._updating_steps = false
	check(is_equal_approx(movement._step_elapsed, 0.1), "Joint strain must not pause the swing timeline")
	check(movement.is_leg_stepping(foot), "Joint strain must not cancel the swing via a pause timeout")
	check(movement._active_steps.has(other_motion), "Continuous swing must preserve other active steps")
	actor.free()
	if not failed: print("PASS: Spider live reach, legal slide, strain release, adhesion and recovery.")
	quit(1 if failed else 0)
