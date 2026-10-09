extends SceneTree
const NPC = preload("res://Scenes/Creatures/Characters/Generate_HornedBeast_NPC.tscn")
const ACTOR = preload("res://Scenes/Creatures/Characters/Generate_HornedBeast.tscn")
class ChargeGaitProbe extends "res://Scripts/Creatures/GeneratedLegStepMovementController3D.gd":
	var test_contact: Dictionary = {}
	func _ready() -> void: set_physics_process(false)
	func _chain_is_intact(_foot: RigidBody3D) -> bool: return true
	func is_leg_grounded(_foot: RigidBody3D) -> bool: return true
	func _support_surface_contact(_foot: RigidBody3D) -> Dictionary: return test_contact
class MovementStub extends Node:
	var command_source: Node
	var recovery_control_active := false
	var torsos: Array[RigidBody3D] = []
	var supported := true
	var flight_support: Dictionary = {"weight":0.0,"remaining":0.0,"feet":0}
	func get_charge_airborne_support() -> Dictionary: return flight_support
	func get_torso_parts() -> Array[RigidBody3D]: return torsos
	func get_leg_parts() -> Array[RigidBody3D]: return [] as Array[RigidBody3D]
	func get_torso_movement_force_legs(_fast: bool) -> Array[RigidBody3D]: return torsos if supported else [] as Array[RigidBody3D]
	func cancel_step(_reason: StringName) -> void: pass
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-200,0,-200),Vector3(-200,0,200),Vector3(200,0,200),Vector3(200,0,-200)])
	mesh.add_polygon(PackedInt32Array([0,1,2]))
	mesh.add_polygon(PackedInt32Array([0,2,3]))
	region.navigation_mesh = mesh
	root.add_child(region)
	NavigationServer3D.map_set_active(region.get_navigation_map(),true)
	var floor := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(400,1,400)
	floor_shape.shape = floor_box
	floor.position.y = -0.5
	floor.add_child(floor_shape)
	root.add_child(floor)
	await physics_frame
	await physics_frame
	NavigationServer3D.map_force_update(region.get_navigation_map())
	await create_timer(0.2).timeout
	var actor := NPC.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	assert(actor.generate_creature())
	actor.get_node("NPCStateMachine3D").enabled = false
	actor.get_node("NPCStateMachine3D").set_physics_process(false)
	var enemy := ACTOR.instantiate()
	enemy.generate_on_ready = false
	enemy.faction_id = 2
	root.add_child(enemy)
	enemy.position.x = 100.0
	enemy.position.z = 2.0
	assert(enemy.generate_creature())
	for character in [actor,enemy]:
		for part: RigidBody3D in character._get_physical_body_parts(): part.freeze = true
	var charge := actor.get_node("ChargeAttackController3D")
	charge.data = preload("res://Scripts/Creatures/ChargeAttackData.gd").new()
	charge.set_physics_process(false)
	charge.diagnostic_logging = true
	var movement := MovementStub.new()
	actor.add_child(movement)
	movement.torsos.append(actor.get_node("GeneratedParts/Torso"))
	var original := Node.new()
	actor.add_child(original)
	movement.command_source = original
	charge._movement = movement
	var target := enemy.get_node("GeneratedParts/Torso") as PhysicalBodyPart3D
	assert(is_equal_approx(charge.data.get_minimum_distance(),14.0))
	assert(is_equal_approx(charge.data.get_travel_time(14.0),2.0))
	var saved := target.global_position
	target.global_position.x = charge._body.global_position.x + 13.99
	assert(not charge.is_npc_target_in_attack_range(&"ground_charge", target))
	target.global_position.x = charge._body.global_position.x + 14.01
	assert(charge.is_npc_target_in_attack_range(&"ground_charge", target))
	target.global_position = saved
	target.global_position.y += 100.0
	assert(charge.predict_npc_attack(&"ground_charge",target,0.0).hit)
	assert(charge.get_npc_attack_range_diagnostics(&"ground_charge",target).height_check_enabled == false)
	region.enabled = false
	NavigationServer3D.map_force_update(region.get_navigation_map())
	await create_timer(0.2).timeout
	await physics_frame
	await physics_frame
	assert(not charge.predict_npc_attack(&"ground_charge",target,0.0).hit)
	region.enabled = true
	NavigationServer3D.map_force_update(region.get_navigation_map())
	await create_timer(0.2).timeout
	await physics_frame
	await physics_frame
	var machine := actor.get_node("NPCStateMachine3D")
	machine._enemy = enemy
	machine._target = target
	var attack_data = machine.behavior.attacks[0]
	assert(is_inf(machine._attack_maximum_range(attack_data,target)))
	assert(is_equal_approx(machine._attack_minimum_range(attack_data),14.0))
	assert(machine._preferred_attack_distance(attack_data) >= 14.0)
	assert(machine._try_attack(100.0))
	assert(machine._active_attack.action_id == &"ground_charge")
	assert(charge.phase == charge.Phase.ALIGNING)
	target = charge._target as PhysicalBodyPart3D
	assert(charge.get_movement_direction().z > 0.0)
	var delta: float = target.global_position.z-charge._body.global_position.z
	for body: RigidBody3D in actor._get_physical_body_parts(): body.position.z += delta
	charge._physics_process(0.1)
	assert(charge.phase == charge.Phase.CHARGING and is_instance_valid(charge._weapon))
	assert(charge.get_npc_attack_maximum_duration(&"ground_charge") > attack_data.maximum_duration)
	assert(charge._weapon.attached_shape.get_meta(&"equipped_item") == charge._weapon)
	assert(charge._weapon.attached_shape.shape is BoxShape3D)
	assert(charge._weapon.attached_shape.disabled)
	# Head posture has a single servo owner, transitions smoothly, and rotates
	# about the existing connection pivot for either facing direction.
	var head_support := actor.get_node("HeadPositionSupport3D")
	assert(not head_support.bindings.is_empty())
	var head_binding: Dictionary = head_support.bindings[0]
	var charge_head: PhysicalBodyPart3D = head_binding.head
	var head_torso: PhysicalBodyPart3D = head_binding.torso
	var saved_head_basis := charge_head.global_basis
	var saved_head_torso_basis := head_torso.global_basis
	charge_head.freeze = false
	head_support._physics_process(charge.data.head_lower_transition_time*0.5)
	assert(is_equal_approx(head_support.diagnostics[0].charge_pitch_degrees,-7.5))
	head_support._physics_process(charge.data.head_lower_transition_time*0.5)
	assert(is_equal_approx(head_support.diagnostics[0].charge_pitch_degrees,-15.0))
	var pose_row: Dictionary = head_support.diagnostics[0]
	assert(Vector3(pose_row.rotation_error_degrees).dot(head_torso.global_basis.z)<0.0)
	var pose_basis := head_torso.global_basis.orthonormalized()*Basis(Vector3.BACK,deg_to_rad(-15.0))*Basis(Quaternion(head_binding.rest_rotation))
	var rest_head_basis := head_torso.global_basis.orthonormalized()*Basis(Quaternion(head_binding.rest_rotation))
	var pivot: Vector3 = head_binding.head_pivot
	var desired_head_position: Vector3 = charge_head.global_position+Vector3(pose_row.position_error)
	var rest_pivot_position: Vector3 = head_torso.global_position+head_torso.global_basis*Vector3(head_binding.rest_offset)+rest_head_basis*pivot
	assert((desired_head_position+pose_basis*pivot).is_equal_approx(rest_pivot_position))
	head_torso.global_basis = Basis(Vector3.UP,PI)*saved_head_torso_basis
	charge_head.global_basis = Basis(Vector3.UP,PI)*saved_head_basis
	head_support._physics_process(0.01)
	assert(Vector3(head_support.diagnostics[0].rotation_error_degrees).dot(head_torso.global_basis.z)<0.0)
	head_torso.global_basis = saved_head_torso_basis
	charge_head.global_basis = saved_head_basis
	charge.phase = charge.Phase.BRAKING
	head_support._physics_process(charge.data.head_lower_transition_time)
	assert(is_zero_approx(head_support.diagnostics[0].charge_pitch_degrees))
	charge.phase = charge.Phase.CHARGING
	charge.data.lower_head_enabled = false
	assert(is_zero_approx(charge.get_head_posture_request().angle))
	charge.data.lower_head_enabled = true
	charge_head.freeze = true
	var real_movement := actor.get_node("GeneratedLegStepMovementController3D")
	var shared_gait: LegMovementData = real_movement.slow_gait_data
	var shared_speed := shared_gait.target_speed
	var shared_gallop := shared_gait.gallop_enabled
	var effective_gait: LegMovementData = real_movement._get_gait_data()
	assert(effective_gait != shared_gait)
	assert(is_equal_approx(effective_gait.target_speed,charge._speed))
	assert(effective_gait.gallop_allow_all_feet_airborne)
	assert(effective_gait.gallop_enabled and effective_gait.speed_based_gait and effective_gait.automatic_motion)
	assert(effective_gait.gallop_minimum_support_feet == 0)
	charge._speed = 18.0
	effective_gait = real_movement._get_gait_data()
	assert(is_equal_approx(effective_gait.target_speed,18.0))
	assert(is_equal_approx(shared_gait.target_speed,shared_speed))
	var flight_plan := effective_gait.calculate_adaptive_flight_profile(5.0,4,0.0,2.0,3)
	assert(is_equal_approx(flight_plan.budget_speed,18.0))
	assert(is_equal_approx(flight_plan.required_stride,18.0*flight_plan.cycle))
	var probe := ChargeGaitProbe.new()
	probe.slow_gait_data = shared_gait
	probe.command_source = charge
	actor.add_child(probe)
	var foot := actor.get_node("GeneratedParts/Leg_1") as RigidBody3D
	probe._legs = real_movement.get_leg_parts().duplicate()
	probe._chains = real_movement._chains.duplicate(true)
	assert(probe._gallop_active())
	assert(probe.get_maximum_stepping_feet() == probe._legs.size())
	charge.data.allow_all_feet_airborne = false
	assert(probe.get_maximum_stepping_feet() <= probe._legs.size()-1)
	assert(probe._get_gait_data().gallop_minimum_support_feet >= 1)
	charge.data.allow_all_feet_airborne = true
	foot.freeze = false
	probe._gallop_contacts[foot] = {"time":0.0,"position":foot.global_position,"normal":Vector3.UP,"duration":0.4}
	assert(probe.get_charge_airborne_support().weight > 0.0)
	probe.walk_start_stagger_enabled = false
	for other: RigidBody3D in probe._legs:
		if other == foot: continue
		var motion = probe.StepMotion.new()
		motion.leg = other
		motion.state = probe.StepState.MOVING
		probe._active_steps.append(motion)
	assert(probe._can_start_step_with_support(foot))
	charge.data.allow_all_feet_airborne = false
	assert(not probe._can_start_step_with_support(foot))
	charge.data.allow_all_feet_airborne = true
	probe._active_steps.clear()
	var contact_time: float = probe._gallop_contacts[foot].time
	probe._physics_elapsed = 0.5
	assert(probe.get_charge_airborne_support().weight == 0.0)
	assert(probe._gallop_contacts[foot].time == contact_time)
	probe._physics_elapsed = 0.0
	# Sliding is independent of reliable contact: require a lifted landing,
	# low normal velocity and continuous physical contact, not a completed step.
	var landing = probe.StepMotion.new()
	landing.leg = foot
	landing.state = probe.StepState.LANDING
	landing.extra["_step_has_lifted"] = true
	var hit := {"position":probe._get_foot_world_position(foot),"normal":Vector3.UP}
	foot.linear_velocity = Vector3(15,0,0)
	assert(not probe._confirm_charge_support_contact(foot,hit,landing))
	probe._physics_elapsed = 0.06
	assert(probe._confirm_charge_support_contact(foot,hit,landing))
	assert(not probe._confirm_charge_support_contact(foot,{},landing))
	assert(not landing.extra.charge_support_contact_confirmed)
	probe._physics_elapsed = 0.07
	assert(not probe._confirm_charge_support_contact(foot,hit,landing))
	foot.linear_velocity = Vector3(15,3,0)
	probe._physics_elapsed = 0.14
	assert(not probe._confirm_charge_support_contact(foot,hit,landing))
	foot.linear_velocity = Vector3.ZERO
	landing.state = probe.StepState.MOVING
	assert(not probe._confirm_charge_support_contact(foot,hit,landing))
	landing.state = probe.StepState.LANDING
	probe._active_steps.append(landing)
	probe.test_contact = hit
	probe._physics_elapsed = 0.2
	probe._update_gallop_contacts()
	var prior_contact: float = probe._gallop_contacts[foot].time
	probe._physics_elapsed = 0.26
	probe._update_gallop_contacts()
	assert(probe._gallop_contacts[foot].time > prior_contact)
	assert(probe._gallop_contacts[foot].source == "confirmed_landing")
	probe.test_contact = {}
	probe._physics_elapsed = 0.27
	probe._update_gallop_contacts()
	assert(is_equal_approx(probe._gallop_contacts[foot].time,0.26))
	probe._active_steps.clear()
	probe._physics_elapsed = 0.0
	# Idle/failed feet must not bypass charge braking by creating a hard pin.
	probe.test_contact = hit
	foot.linear_velocity = Vector3(30,0,0)
	assert(not probe.is_leg_stepping(foot))
	probe._update_support_foot_lock(foot,Vector3.UP)
	assert(not probe._support_pins.has(foot))
	var idle_brake: Vector3 = probe._calculate_leg_adhesion_force(foot,hit,1.0)
	assert(idle_brake.x < 0.0)
	assert(absf(idle_brake.x) <= foot.mass*charge.data.touchdown_maximum_acceleration+0.001)
	assert(probe._charge_idle_brakes.has(foot))
	assert(probe._charge_idle_brakes[foot].margin == 1.25)
	assert(probe._charge_idle_brakes[foot].applied_acceleration > 80.0)
	# Speed and the remaining deadline determine braking. At common physics
	# rates, an isolated foot stops within the window without reversing.
	for tick_rate: float in [60.0,120.0]:
		for initial_speed: float in [40.0,-40.0,50.0,0.1]:
			probe._charge_ground_phases.clear()
			probe._support_delta = 1.0/tick_rate
			probe._physics_elapsed = 0.0
			foot.linear_velocity = Vector3(initial_speed,0,0)
			for tick_index: int in range(int(ceil(charge.data.touchdown_brake_duration*tick_rate))):
				probe._physics_elapsed = tick_index/tick_rate
				var brake: Dictionary = probe._get_charge_touchdown_brake(foot,Vector3.UP)
				assert(brake.applied_acceleration <= charge.data.touchdown_maximum_acceleration+0.001)
				foot.linear_velocity += Vector3(brake.applied_force)/foot.mass/tick_rate
				assert(foot.linear_velocity.x*initial_speed >= -0.0001)
			assert(absf(foot.linear_velocity.x) < 0.001)
	# An insufficient configured cap is respected and exposed in diagnostics.
	probe._charge_ground_phases.clear()
	probe._physics_elapsed = 0.0
	probe._support_delta = 1.0/60.0
	foot.linear_velocity = Vector3(200,0,0)
	var capped_brake: Dictionary = probe._get_charge_touchdown_brake(foot,Vector3.UP)
	assert(capped_brake.acceleration_limited)
	assert(is_equal_approx(capped_brake.applied_acceleration,charge.data.touchdown_maximum_acceleration))
	probe._physics_elapsed = charge.data.touchdown_brake_duration+0.01
	assert(is_zero_approx(probe._calculate_leg_adhesion_force(foot,hit,1.0).x))
	probe._physics_elapsed = 0.0
	probe.test_contact = {}
	var airborne_adhesion: Vector3 = probe._calculate_leg_adhesion_force(foot,hit,1.0)
	assert(is_zero_approx(airborne_adhesion.x))
	assert(not probe._get_charge_touchdown_brake(foot,Vector3.UP).real_contact)
	probe.test_contact = hit
	foot.linear_velocity = Vector3.ZERO
	probe._update_support_foot_lock(foot,Vector3.UP)
	assert(probe._support_pins.has(foot))
	probe._release_support_pin(foot)
	# A lifted, descending real contact completes this foot immediately even
	# at high horizontal speed, without cancelling another foot's active swing.
	probe._begin_leg_motion(foot,foot.global_position+Vector3.RIGHT,Vector3.UP,Vector3.RIGHT)
	assert(probe._charge_ground_phases.has(foot))
	# Beginning a new lift preserves the touchdown deadline and brakes until
	# separation, even if the root is already travelling much faster.
	var transition_root: RigidBody3D = probe._chains[foot].root
	var transition_root_velocity := transition_root.linear_velocity
	transition_root.linear_velocity = Vector3(40,0,0)
	probe._charge_ground_phases[foot].time = -0.02
	foot.linear_velocity = Vector3(20,0,0)
	probe._apply_leg_tracking_force(foot.global_position,Vector3(40,0,0))
	assert(probe._tracking_force.x < 0.0)
	assert(probe._tracking_force.y > 0.0)
	assert(probe._current_step.extra.charge_liftoff_transition.phase == "ground_braking")
	assert(is_equal_approx(probe._charge_ground_phases[foot].time,-0.02))
	probe._physics_elapsed = 0.2
	probe._apply_leg_tracking_force(foot.global_position,Vector3(40,0,0))
	assert(absf(probe._tracking_force.x) < 0.001)
	# Real separation enables a smooth velocity reference, not a sudden pull.
	probe.test_contact = {}
	foot.linear_velocity = Vector3.ZERO
	probe._apply_leg_tracking_force(foot.global_position,Vector3(40,0,0))
	assert(absf(probe._tracking_force.x) < 0.001)
	probe._physics_elapsed += probe.charge_liftoff_follow_blend_time*0.5
	probe._apply_leg_tracking_force(foot.global_position,Vector3(40,0,0))
	assert(probe._tracking_force.x > 0.0)
	assert(is_equal_approx(probe._current_step.extra.charge_liftoff_transition.blend,0.5))
	# Recontact interrupts the blend and never renews the old brake window.
	probe.test_contact = hit
	probe._apply_leg_tracking_force(foot.global_position,Vector3(40,0,0))
	assert(not probe._current_step.extra.has("charge_detach_time"))
	assert(absf(probe._tracking_force.x) < 0.001)
	transition_root.linear_velocity = transition_root_velocity
	probe._physics_elapsed = 0.0
	# Reach relaxes smoothly with actual speed, symmetrically in +/-X.
	var saved_smoothed_velocity := probe._speed_smoothed_velocity
	var saved_maximum_speed: float = charge.data.maximum_speed
	charge.data.maximum_speed = 40.0
	probe._speed_smoothed_velocity = Vector3.ZERO
	assert(is_equal_approx(probe._get_forward_extension_ratio(),0.75))
	probe._speed_smoothed_velocity = Vector3(20,0,0)
	assert(is_equal_approx(probe._get_forward_extension_ratio(),0.85))
	probe._speed_smoothed_velocity = Vector3(-40,0,0)
	assert(is_equal_approx(probe._get_forward_extension_ratio(),0.95))
	probe.speed_adaptive_forward_extension = false
	assert(is_equal_approx(probe._get_forward_extension_ratio(),0.75))
	probe.speed_adaptive_forward_extension = true
	charge.phase = charge.Phase.BRAKING
	assert(is_equal_approx(probe._get_forward_extension_ratio(),0.75))
	charge.phase = charge.Phase.CHARGING
	charge.data.maximum_speed = saved_maximum_speed
	probe._speed_smoothed_velocity = saved_smoothed_velocity
	probe._current_step.extra["liftoff_complete"] = true
	probe._step_has_lifted = true
	foot.linear_velocity = Vector3(30,1,0)
	assert(not probe._try_finish_charge_touchdown())
	foot.linear_velocity = Vector3(30,-1,0)
	probe.test_contact = {}
	assert(not probe._try_finish_charge_touchdown())
	probe.test_contact = hit
	charge.phase = charge.Phase.BRAKING
	assert(not probe._try_finish_charge_touchdown())
	charge.phase = charge.Phase.CHARGING
	var other_step = probe.StepMotion.new()
	other_step.leg = probe._legs[1]
	other_step.state = probe.StepState.MOVING
	probe._active_steps.append(other_step)
	probe._updating_steps = true
	assert(probe._try_finish_charge_touchdown())
	probe._updating_steps = false
	assert(not probe.is_leg_stepping(foot))
	assert(probe._active_steps.has(other_step))
	assert(probe._charge_ground_phases[foot].completed_on_contact)
	assert(probe._gallop_contacts[foot].source == "instant_touchdown")
	assert(not probe._support_pins.has(foot))
	assert(not probe._try_finish_charge_touchdown())
	probe._active_steps.clear()
	probe.test_contact = {}
	foot.linear_velocity = Vector3.ZERO
	foot.freeze = true
	var old_source: Node = real_movement.command_source
	real_movement.command_source = charge
	assert(real_movement._gallop_active())
	real_movement._begin_leg_motion(foot,foot.global_position+Vector3.RIGHT*0.2,Vector3.UP,Vector3.RIGHT)
	assert(real_movement._current_step.extra.gallop_step)
	assert(real_movement._current_step.extra.has("speed_gait"))
	assert(is_equal_approx(real_movement._current_step.extra.speed_gait.budget_speed,18.0))
	assert(real_movement._current_step.extra.has("landing_surface_point"))
	assert(is_equal_approx(real_movement._get_gait_data().touchdown_stop_time,charge.data.touchdown_stop_time))
	# Lift preserves root translation instead of damping the foot to world zero.
	var lift_root: RigidBody3D = real_movement._chains[foot].root
	var lift_test_position := foot.global_position
	foot.global_position.y += 3.0
	lift_root.linear_velocity = Vector3(5,0,0)
	foot.linear_velocity = Vector3(5,0,0)
	real_movement._apply_leg_tracking_force(foot.global_position,Vector3(5,0,0))
	assert(absf(real_movement._tracking_force.x) < 0.001)
	foot.global_position = lift_test_position
	lift_root.linear_velocity = Vector3.ZERO
	foot.linear_velocity = Vector3.ZERO
	charge._speed = 40.0
	real_movement._speed_plan_cache.clear()
	var charge_plan: Dictionary = real_movement._get_speed_leg_plan(foot)
	assert(charge_plan.charge_flight_budget)
	assert(charge_plan.air_duration <= 1.5 and charge_plan.lease_duration <= 3.0)
	assert(charge_plan.lease_duration > charge_plan.air_duration+charge_plan.landing_confirmation)
	assert(charge_plan.charge_liftoff_reserve > 0.0 and charge_plan.charge_braking_reserve > 0.0)
	assert(charge_plan.air_duration >= charge_plan.base_air_duration)
	assert(charge_plan.distance_deficit < charge_plan.required_stride*0.2)
	# A long lift must discard the old world-space target before releasing
	# horizontal pursuit. Both endpoints then follow the root's translation.
	real_movement._step_state = real_movement.StepState.MOVING
	real_movement._current_step.extra["liftoff_complete"] = true
	# This fixture jumps directly into a travelling swing without advancing
	# physics; model the already elapsed separation blend explicitly.
	real_movement._current_step.extra["charge_detach_time"] = real_movement._physics_elapsed-real_movement.charge_liftoff_follow_blend_time
	real_movement._current_step.extra["landing_surface_point"] = foot.global_position-Vector3(100,foot.global_position.y,0)
	real_movement._current_step.extra["gallop_rest_offset"] = Vector3.DOWN
	real_movement._step_start = foot.global_position
	real_movement._step_elapsed = 0.0
	real_movement._replan_charge_swing_after_liftoff()
	assert(real_movement._current_step.extra.charge_swing_target_valid)
	assert(real_movement._step_target.x > foot.global_position.x-10.0)
	var swing_position: Vector3 = real_movement._quadratic_step_position(0.5)
	var saved_root_position := lift_root.global_position
	var saved_swing_foot_position := foot.global_position
	var saved_swing_target: Vector3 = real_movement._current_step.extra.landing_surface_point
	lift_root.global_position += Vector3(30,0,2)
	foot.global_position += Vector3(30,0,2)
	real_movement._retarget_adaptive_landing(1.0/60.0)
	assert(real_movement._current_step.extra.charge_swing_target_valid)
	real_movement._step_target = real_movement._body_position_for_ground_contact(foot,real_movement._current_step.extra.landing_surface_point)
	assert((real_movement._quadratic_step_position(0.5)-swing_position).is_equal_approx(Vector3(30,0,2)))
	lift_root.linear_velocity = Vector3(40,0,0)
	assert(real_movement._quadratic_step_velocity(0.0,1.0).x == 40.0)
	assert(real_movement._quadratic_step_velocity(1.0,1.0).x == 40.0)
	lift_root.linear_velocity = Vector3(-40,0,0)
	assert(real_movement._quadratic_step_velocity(0.0,1.0).x == -40.0)
	lift_root.linear_velocity = Vector3(40,0,0)
	# Flat ground remains legal while the foot itself is high in the swing.
	foot.global_position.y += 3.0
	real_movement._retarget_adaptive_landing(1.0/60.0)
	assert(real_movement._current_step.extra.charge_swing_target_valid)
	foot.global_position.y -= 3.0
	# Rejected terrain must never pull the foot back toward the previous target.
	var saved_mask: int = real_movement.terrain_collision_mask
	real_movement.terrain_collision_mask = 0
	real_movement._retarget_adaptive_landing(1.0/60.0)
	assert(not real_movement._current_step.extra.charge_swing_target_valid)
	assert(real_movement._current_step.extra.charge_swing_retarget_reason == "landing_ray_missed")
	foot.linear_velocity = Vector3(40,0,0)
	real_movement._apply_leg_tracking_force(foot.global_position-Vector3(100,0,0),Vector3.ZERO)
	assert(absf(real_movement._tracking_force.x) < 0.001)
	real_movement.terrain_collision_mask = saved_mask
	# The fixture changes masks within one tick; discard that tick's ground
	# probe cached with mask zero before restoring real terrain queries.
	real_movement._ground_probe_cache.clear()
	real_movement._retarget_adaptive_landing(1.0/60.0)
	assert(real_movement._current_step.extra.charge_swing_target_valid, str(real_movement._current_step.extra.charge_swing_retarget_reason))
	lift_root.global_position = saved_root_position
	foot.global_position = saved_swing_foot_position
	real_movement._current_step.extra.landing_surface_point = saved_swing_target
	lift_root.linear_velocity = Vector3.ZERO
	foot.linear_velocity = Vector3.ZERO
	# A lost touchdown must be rebuilt near today's root, rather than dragging
	# the foot toward a contact point several body lengths behind the charge.
	real_movement._step_state = real_movement.StepState.LANDING
	real_movement._current_step.extra["gallop_target_frozen"] = false
	real_movement._current_step.extra["charge_landing_replan"] = true
	real_movement._current_step.extra["landing_surface_point"] = foot.global_position-Vector3(100,foot.global_position.y,0)
	real_movement._current_step.extra["gallop_rest_offset"] = Vector3.DOWN
	real_movement._step_elapsed = real_movement._active_step_duration
	var stale_target: Vector3 = real_movement._current_step.extra.landing_surface_point
	real_movement._retarget_adaptive_landing(1.0/60.0)
	assert(real_movement._current_step.extra.get("charge_landing_replans",0) == 1)
	assert(Vector3(real_movement._current_step.extra.landing_surface_point).x > stale_target.x+50.0)
	assert(not real_movement._current_step.extra.charge_landing_replan)
	real_movement._current_step.extra["charge_landing_replan"] = true
	lift_root.linear_velocity = Vector3(10,0,0)
	foot.linear_velocity = Vector3(10,0,0)
	real_movement._apply_leg_tracking_force(foot.global_position-Vector3(100,0,0),Vector3.ZERO)
	assert(absf(real_movement._tracking_force.x) < 0.001)
	lift_root.linear_velocity = Vector3.ZERO
	foot.linear_velocity = Vector3.ZERO
	# Even with a valid replacement point, an airborne landing must follow root
	# velocity, rather than damping the foot to zero before it touches terrain.
	real_movement._current_step.extra["charge_landing_replan"] = false
	var ground_foot_position := foot.global_position
	foot.global_position.y += 3.0
	lift_root.linear_velocity = Vector3(20,0,0)
	foot.linear_velocity = Vector3(20,0,0)
	real_movement._current_step.extra["gallop_touchdown_braking"] = true
	real_movement._apply_leg_tracking_force(foot.global_position+Vector3.RIGHT,Vector3.ZERO)
	assert(real_movement._tracking_force.x > 0.0)
	assert(not real_movement._current_step.extra.gallop_touchdown_braking)
	assert(real_movement._current_step.extra.charge_airborne_velocity_reference == Vector3(20,0,0))
	foot.global_position = ground_foot_position
	lift_root.linear_velocity = Vector3.ZERO
	foot.linear_velocity = Vector3.ZERO
	charge._speed = 18.0
	real_movement._speed_plan_cache.clear()
	real_movement.cancel_step(&"test_finished")
	real_movement.command_source = old_source
	var demand: Dictionary = probe._get_extension_step_demand(foot,Vector3.RIGHT)
	assert(demand.requested and demand.reason == "startup")
	probe._charge_start_pending = false
	probe._startup_pending = false
	probe._walk_start_pending.clear()
	var chain: Dictionary = probe._chains[foot]
	var chain_root: RigidBody3D = chain.root
	var saved_foot_position := foot.global_position
	var saved_root_velocity := chain_root.linear_velocity
	var saved_rest: Vector3 = foot.get_meta(&"generated_attachment_rest_offset")
	var attachment: Vector3 = chain_root.to_global(chain.anchor)
	var chain_length: float = chain.length
	foot.set_meta(&"generated_attachment_rest_offset",Basis(Vector3.UP,chain_root.global_rotation.y).inverse()*(attachment+Vector3.DOWN*chain_length*0.5-chain_root.global_position))
	chain_root.linear_velocity = Vector3.RIGHT
	foot.linear_velocity = Vector3.ZERO
	foot.global_position = attachment+Vector3.DOWN*chain_length*0.5
	demand = probe._get_extension_step_demand(foot,Vector3.RIGHT)
	assert(not demand.requested and demand.reason == "holding")
	# A stalled body must still request a step before the theoretical sphere
	# boundary: target-speed preview uses the conservative stance budget.
	chain_root.linear_velocity = Vector3.ZERO
	foot.global_position.x -= chain_length*probe.charge_stance_travel_ratio*0.3
	demand = probe._get_extension_step_demand(foot,Vector3.RIGHT)
	assert(demand.requested and demand.reason == "charge_predicted_limit")
	assert(is_zero_approx(demand.approach_speed) and demand.prediction_speed == 18.0)
	assert(demand.geometric_remaining > demand.remaining_distance)
	chain_root.linear_velocity = Vector3.RIGHT
	# Near the rear boundary: no elapsed-time or complete-cycle waiting.
	foot.global_position.x -= chain_length
	demand = probe._get_extension_step_demand(foot,Vector3.RIGHT)
	assert(demand.requested and demand.reason == "charge_stance_limit")
	assert(demand.remaining_distance == 0.0 and demand.approach_speed > 0.0)
	probe._charge_retry_until[foot] = 0.2
	assert(probe._get_extension_step_demand(foot,Vector3.RIGHT).reason == "charge_retry_wait")
	probe._physics_elapsed = 0.21
	assert(probe._get_extension_step_demand(foot,Vector3.RIGHT).requested)
	# Reversing direction must recompute reach instead of reusing the old demand.
	chain_root.linear_velocity = Vector3.LEFT
	assert(not probe._get_extension_step_demand(foot,Vector3.LEFT).requested)
	foot.set_meta(&"generated_attachment_rest_offset",saved_rest)
	foot.global_position = saved_foot_position
	chain_root.linear_velocity = saved_root_velocity
	probe.free()
	charge._speed = charge.data.starting_speed
	assert(charge._weapon.attached_shape.get_parent() == charge._weapon)
	assert(is_zero_approx(charge._weapon.attached_shape.global_position.y-charge._weapon.attached_shape.shape.size.y*0.5))
	var speed: float = charge._speed
	charge._physics_process(0.1)
	assert(charge._speed > speed)
	var diagnostics: Dictionary = charge.get_charge_diagnostics()
	assert(diagnostics.support_count == 1)
	assert(not diagnostics.force_applied and diagnostics.force_skip_reason == &"no_eligible_torso")
	assert(diagnostics.torso_force_rows[0].reason == &"frozen")
	assert(diagnostics.torso_velocity == Vector3.ZERO)
	# Total-load budgeting includes intact limbs and removes frozen loads.
	var expected_load := 0.0
	for part: RigidBody3D in actor._get_physical_body_parts():
		part.freeze = false
		expected_load += part.mass
	var load: Dictionary = charge._get_load_metrics()
	assert(is_equal_approx(load.budget_mass,expected_load))
	assert(load.budget_mass > load.torso_mass)
	charge._submitted_force = Vector3.ZERO
	charge._force_rows.clear()
	charge._apply_velocity(0.01)
	assert(charge._submitted_force.length() <= expected_load*charge.data.maximum_acceleration+0.01)
	assert(charge._submitted_force.x > load.torso_mass*charge.data.maximum_acceleration)
	assert(is_equal_approx(charge._force_rows[0].budget_mass,expected_load))
	charge.data.use_total_load_mass = false
	assert(is_equal_approx(charge._get_load_metrics().budget_mass,load.torso_mass))
	charge.data.use_total_load_mass = true
	for part: RigidBody3D in actor._get_physical_body_parts(): part.freeze = true
	# A lease does not reset physical airborne age, but the unsupported safety
	# timer starts at expiry, not at takeoff. Expiry still stops propulsion.
	movement.supported = false
	movement.flight_support = {"weight":0.5,"remaining":0.2,"feet":1}
	movement.torsos[0].freeze = false
	charge._physics_process(0.1)
	assert(charge.phase == charge.Phase.CHARGING)
	assert(charge.get_charge_diagnostics().force_applied)
	assert(charge.get_charge_diagnostics().airborne_elapsed > 0.0)
	assert(is_zero_approx(charge.get_charge_diagnostics().unsupported_elapsed))
	charge._airborne = 10.0
	movement.flight_support = {"weight":0.0,"remaining":0.0,"feet":0}
	charge._physics_process(0.1)
	assert(charge.phase == charge.Phase.CHARGING)
	assert(is_equal_approx(charge.get_charge_diagnostics().unsupported_elapsed,0.1))
	assert(not charge.get_charge_diagnostics().force_applied)
	movement.torsos[0].freeze = true
	movement.supported = true
	var locked_x: float = charge._target_x
	target.position.z += 10.0
	target.position.x += 5.0
	assert(charge.get_movement_direction() == Vector3.RIGHT)
	assert(charge._target_x == locked_x)
	charge._physics_process(0.1)
	assert(charge.phase == charge.Phase.CHARGING)
	assert(charge._target_x == target.global_position.x)
	target.armor = 0.0
	target.max_hp = 10000.0
	target.current_hp = 10000.0
	var hp := target.current_hp
	var target_position_before_hit := target.global_position
	target.global_position = charge._weapon.attached_shape.global_position
	await physics_frame
	await physics_frame
	charge._body.linear_velocity = Vector3(100,0,0)
	charge._weapon.update_ground_box(1.0,charge.data.obstacle_mask)
	assert(target.current_hp < hp)
	assert(charge._weapon.apply_contact_damage(target,100.0) == 0.0)
	target.global_position = target_position_before_hit
	charge._body.linear_velocity = Vector3.ZERO
	movement.torsos[0].global_position.x = target.global_position.x+10.0
	charge._physics_process(0.1)
	assert(charge.phase == charge.Phase.BRAKING and charge._weapon == null)
	charge._body.linear_velocity = Vector3.ZERO
	for i in range(40): charge._physics_process(0.1)
	assert(not charge.is_active() and movement.command_source == original)
	assert(real_movement._get_gait_data() == shared_gait)
	assert(shared_gait.gallop_enabled == shared_gallop)
	assert(real_movement._charge_retry_scales.is_empty())
	charge._cooldown = 0.0
	charge._body.global_position.x = target.global_position.x+25.0
	charge._body.global_position.z = target.global_position.z
	assert(charge.try_start_action(&"ground_charge",target))
	charge._physics_process(0.1)
	assert(charge.phase == charge.Phase.CHARGING and charge.get_movement_direction() == Vector3.LEFT)
	assert(charge._weapon.attached_shape.shape is BoxShape3D)
	movement.supported = false
	charge._physics_process(0.1)
	assert(charge.get_charge_diagnostics().force_skip_reason == &"no_contact_or_flight_support")
	for i in range(8): charge._physics_process(0.1)
	assert(not charge.is_active() and charge._reason == &"airborne")
	assert(movement.command_source == original)
	charge._cooldown = 0.0
	enemy.faction_id = actor.faction_id
	assert(not charge.try_start_action(&"ground_charge",target))
	enemy.faction_id = 2
	assert(charge.try_start_action(&"ground_charge",target))
	charge._physics_process(0.1)
	charge.enabled = false
	charge._physics_process(0.1)
	assert(not charge.is_active() and charge._weapon == null and movement.command_source == original)
	var console := root.get_node("RuntimeConsole")
	assert(console.execute_command("trackcharge").contains("enabled"))
	assert(console.is_charge_tracking_enabled())
	assert(console.execute_command("trackcharge").contains("disabled"))
	actor.free()
	enemy.free()
	await process_frame
	print("PASS: navigation gate without height limit, ground query box without solver collisions, locked +/-X with live target X, damage/once-per-part, braking and safety cancellation.")
	quit()
