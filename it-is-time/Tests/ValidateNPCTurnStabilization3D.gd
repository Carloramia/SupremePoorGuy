extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var npc := load("res://Scenes/Creatures/Characters/Character_Test_NPC.tscn").instantiate() as Node3D
	root.add_child(npc)
	var brain := npc.get_node("NPCStateMachine3D")
	var facing := npc.get_node("PhysicalFacingController3D") as PhysicalFacingController3D
	var movement := npc.get_node("NPCLegStepMovementController3D")
	var torso := npc.get_node("Torso") as RigidBody3D
	brain.set_physics_process(false)
	facing.set_physics_process(false)
	movement.set_physics_process(false)
	for body: Node in npc.find_children("*", "RigidBody3D", true, false):
		body.freeze = true
	facing.diagnostic_logging = false
	brain.current_state = brain.State.MOVE_TO_TARGET
	assert(facing.request_facing(facing.FacingDirection.LEFT))
	facing._unwrapped_yaw = deg_to_rad(165.0)
	facing._update_npc_stabilization(0.016)
	facing._update_movement_lead()
	assert(facing._npc_stabilizing and is_zero_approx(movement._turn_movement_multiplier))
	assert(facing._movement_lead.is_zero_approx(), "Final correction must exclude chase translation")
	facing._unwrapped_yaw = deg_to_rad(155.0)
	facing._update_npc_stabilization(0.016)
	assert(facing._npc_stabilizing, "Hysteresis must avoid phase flicker")
	facing._unwrapped_yaw = deg_to_rad(145.0)
	facing._update_npc_stabilization(0.016)
	assert(not facing._npc_stabilizing)
	facing._best_error = 0.01
	facing._recent_error = deg_to_rad(60.0)
	facing._unwrapped_yaw = deg_to_rad(130.0)
	facing._no_progress_elapsed = 1.9
	facing._update_turn_watchdog(0.016)
	assert(facing.is_turning() and facing._no_progress_elapsed < 0.1, "Recovery after overshoot is progress even above the historical best")
	facing._unwrapped_yaw = deg_to_rad(142.0)
	facing._turn_elapsed = facing.maximum_turn_duration
	facing._update_turn_watchdog(0.016)
	assert(not facing.is_turning() and facing._npc_retry_correction, "Timeout below the old 45 degree threshold must permit a retry")
	brain.current_state = brain.State.ATTACK
	facing._physics_process(0.016)
	assert(not facing.is_turning() and not movement._turn_planning_active, "Attack must not start a corrective body turn")
	brain.current_state = brain.State.MOVE_TO_TARGET
	assert(facing.request_facing(facing.FacingDirection.LEFT))
	facing._unwrapped_yaw = 0.0
	facing._update_movement_lead()
	assert(movement._turn_movement_multiplier <= facing.npc_large_turn_movement_multiplier, "Large NPC turns must cap chase movement rather than accelerate at ninety degrees")
	facing._unwrapped_yaw = deg_to_rad(170.0)
	torso.angular_velocity = Vector3.ZERO
	facing._update_npc_stabilization(0.05)
	facing._check_turn_completion()
	assert(facing.is_turning(), "A single quiet frame must not complete the turn")
	facing._update_npc_stabilization(facing.npc_stable_confirmation_time)
	facing._update_movement_lead()
	facing._check_turn_completion()
	assert(not facing.is_turning())
	torso.global_basis = Basis(Vector3.UP, PI)
	for body: RigidBody3D in facing._yaw_bodies:
		if body != torso: body.angular_velocity = Vector3.UP * 10.0
	facing._update_npc_stabilization(facing.npc_movement_resume_time * 0.5)
	assert(movement._turn_movement_multiplier > 0.0 and movement._turn_movement_multiplier < 1.0)
	facing._update_npc_stabilization(facing.npc_movement_resume_time)
	assert(is_equal_approx(movement._turn_movement_multiplier, 1.0))
	for body: RigidBody3D in facing._yaw_bodies: body.angular_velocity = Vector3.ZERO
	# Small drift uses the walking planner and cannot restart a full turn.
	torso.global_basis = Basis(Vector3.UP, deg_to_rad(190.0))
	facing._update_npc_stabilization(0.016)
	assert(not facing.is_turning() and not movement._turn_planning_active)
	assert(is_equal_approx(movement._turn_movement_multiplier, facing.npc_walking_correction_multiplier))
	assert(facing.is_npc_facing_ready(Vector3.LEFT), "Ten degrees of drift must be handed to Arm aiming")
	torso.angular_velocity = Vector3.UP
	assert(not facing.is_npc_facing_ready(Vector3.LEFT), "Fast residual rotation must still block attack handoff")
	torso.angular_velocity = Vector3.ZERO
	facing._last_raw_yaw = facing._get_raw_yaw()
	facing._unwrapped_yaw = deg_to_rad(190.0)
	assert(facing.request_facing(facing.FacingDirection.LEFT))
	facing._update_npc_stabilization(0.016)
	assert(facing.is_npc_facing_ready(Vector3.LEFT), "A small correction may hand over between foot swings")
	movement._step_state = movement.StepState.MOVING
	assert(not facing.is_npc_facing_ready(Vector3.LEFT), "Do not interrupt a corrective foot swing to start attacking")
	movement._step_state = movement.StepState.IDLE
	# An out-of-range leg must not be trapped by restoring narrower limits.
	var leg := npc.get_node("Leg_R") as RigidBody3D
	var joint := movement._hip_joints_by_leg[leg] as Generic6DOFJoint3D
	var limits: Vector4 = movement._hip_joint_base_limits[joint]
	var before := leg.global_position
	var geometry: Dictionary = movement._hip_geometry(leg)
	leg.global_position += Basis(geometry.frame) * Vector3(20.0, 0.0, 0.0)
	joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, limits.y + 30.0)
	movement.restore_base_hip_joint_limits()
	assert(movement._hip_restore_pending)
	assert(is_equal_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), limits.y + 30.0))
	leg.global_position = before
	# The player/generic branch retains its original movement blend.
	brain.humanoid_xz_positioning = false
	facing._unwrapped_yaw = deg_to_rad(15.0)
	assert(facing.request_facing(facing.FacingDirection.RIGHT))
	facing._update_movement_lead()
	assert(movement._turn_movement_multiplier > 0.9)
	print("NPC_TURN_STABILIZATION_3D_VALIDATION_PASSED")
	quit()
