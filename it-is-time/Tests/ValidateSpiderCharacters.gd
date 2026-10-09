extends SceneTree

const ACTOR = preload("res://Scenes/Creatures/Characters/Generate_Spider.tscn")
const NPC = preload("res://Scenes/Creatures/Characters/Generate_Spider_NPC.tscn")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func freeze_actor(actor: Node3D) -> void:
	actor.get_node("GeneratedLegStepMovementController3D").set_physics_process(false)
	actor.get_node("CreatureRecoveryStateMachine3D").set_physics_process(false)
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is RigidBody3D: part.freeze = true

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-80,0,-80), Vector3(-80,0,80), Vector3(80,0,80), Vector3(80,0,-80)])
	mesh.add_polygon(PackedInt32Array([0,1,2,3]))
	region.navigation_mesh = mesh
	level.add_child(region)
	var player := ACTOR.instantiate()
	player.position.x = 25.0
	level.add_child(player)
	var npc := NPC.instantiate()
	npc.get_node(npc.generator_path).overall_scale = 4.0
	level.add_child(npc)
	await process_frame
	for actor: Node3D in [player, npc]:
		check(actor.is_in_group(&"physical_characters_3d"), "Actor must inherit the shared character registration")
		check(not actor.planar_constraints_enabled, "Spider must use normal joint physics")
		check(actor.get_node_or_null("GeneratedParts") != null, "Spider must generate automatically")
		var parts := actor.get_node("GeneratedParts")
		var feet := 0
		var limbs := 0
		var bodies: Array[PhysicalBodyPart3D] = []
		for part: Node in parts.get_children():
			if not part is PhysicalBodyPart3D: continue
			bodies.append(part)
			check(not part.freeze, "Saved editor preview must be replaced with active physics")
			if PhysicalBodyPart3D.BodyPartTag.Leg in part.tags: feet += 1
			if PhysicalBodyPart3D.BodyPartTag.LegLimb in part.tags: limbs += 1
		check(bodies.size() == 19 and feet == 8 and limbs == 8, "Spider must assemble 19 bodies with 8 feet and 8 limb links")
		check(parts.get_node("Joints").get_child_count() == 18, "Spider must assemble 18 joints")
		var leg_mass := 0.0
		var torso_mass := 0.0
		for body: PhysicalBodyPart3D in bodies:
			if PhysicalBodyPart3D.BodyPartTag.Leg in body.tags:
				check(not body.axis_lock_angular_x and not body.axis_lock_angular_z, "Long legs must bend instead of keeping a world-space foot lock")
			if PhysicalBodyPart3D.BodyPartTag.Leg in body.tags or PhysicalBodyPart3D.BodyPartTag.LegLimb in body.tags: leg_mass += body.mass
			if PhysicalBodyPart3D.BodyPartTag.Torso in body.tags: torso_mass += body.mass
		check(leg_mass < torso_mass, "Spider extremities must not outweigh the whole torso")
		var hinges := 0
		for joint: Generic6DOFJoint3D in parts.get_node("Joints").get_children():
			if not joint.has_meta(&"authored_walk_limits"): continue
			hinges += 1
			check(is_zero_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)) and is_zero_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)), "Spider hinges must lock out-of-sheet rotation")
			check(joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING), "Spider hinges must maintain the resting bend")
			var upper := joint.get_node(joint.node_a) as PhysicalBodyPart3D
			check(PhysicalBodyPart3D.BodyPartTag.LegLimb in upper.tags, "Both slider frames must follow their upper limb endpoint")
			check(joint.global_basis.y.normalized().dot(upper.global_basis.y.normalized()) > 0.999, "Slide axis must align with upper-limb length")
			check(joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT) > 0.0, "Both root and knee must allow bounded axial travel")
			for axis: String in ["x", "y", "z"]:
				var independent: bool = joint.get_meta(&"spider_independent_root", false)
				check(bool(joint.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT)) != independent, "Root joints must release linear load while knees retain their limits")
				if independent: check(not joint.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING), "Independent roots must not transmit spring load")
			check(is_zero_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)) and is_zero_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)), "Transverse travel must remain locked")
			var spring: Vector2 = actor.get_spider_joint_spring(joint)
			var inertia: float = joint.get_meta(&"spider_effective_inertia", 0.0)
			check(inertia > 0.0 and spring.is_finite(), "Every hinge needs finite positive geometry-based inertia")
			check(is_equal_approx(spring.x / inertia, actor.spider_leg_spring_stiffness), "Spring frequency must be invariant under actual inertia scaling")
			check(is_equal_approx(spring.y / inertia, actor.spider_leg_spring_damping), "Damping ratio must be invariant under actual inertia scaling")
		check(hinges == 16, "All sixteen Spider leg joints need authored hinge limits")
		for a: PhysicalBodyPart3D in bodies:
			for b: PhysicalBodyPart3D in bodies:
				if a != b: check(a.get_collision_exceptions().has(b), "Internal body collisions must be ignored")
		var movement := actor.get_node("GeneratedLegStepMovementController3D")
		check(not movement.align_support_feet_to_surface, "Spider long legs must not use upright sole alignment")
		check(not movement.foot_heading_lock_enabled, "Spider bent legs must not receive upright-foot yaw correction")
		check(movement.get_script().resource_path.ends_with("SpiderLegStepMovementController3D.gd"), "Spider must use its independent bent-chain planner")
		check(movement.get_leg_parts().size() == 8, "Movement must discover all eight legs")
		check(movement.slow_gait_data.resource_path.ends_with("SpiderWalk.tres"), "Spider must use its independent gait preset")
		for foot: RigidBody3D in movement.get_leg_parts():
			var profile: Dictionary = movement.get_leg_motion_profile(foot)
			check(is_equal_approx(float(profile.stride), movement.get_leg_step_distance(foot)), "Spider automatic planning and landing must use the same stride")
			check(is_equal_approx(profile.length, movement._chains[foot].length) and profile.stride > 0.0 and profile.stride < profile.length * 2.0, "Structural planning must preserve actual chain length and a finite stride")
			var limits: Dictionary = movement.get_spider_stride_limits(foot)
			print("SPIDER_STRUCTURE foot=", foot.name, " limits=", limits, " planned_stride=", profile.stride)
			check(limits.valid, "Every generated Spider leg needs a valid structural ground-contact range")
			var geometry: Dictionary = movement._spider_reach_geometry[foot]
			for sample: Dictionary in geometry.samples:
				check(sample.root_angle >= geometry.root_range.x - 0.00001 and sample.root_angle <= geometry.root_range.y + 0.00001 and sample.knee_angle >= geometry.knee_range.x - 0.00001 and sample.knee_angle <= geometry.knee_range.y + 0.00001, "Reach samples must respect both joint margins")
				check(absf((Transform3D(geometry.capture_transform) * Vector3(sample.point)).y - geometry.ground_height) < 0.001, "Reach samples must put the real toe on its ground plane")
			movement.structural_stride_enabled = false
			var legacy: float = movement._stance_budget(foot) * 2.0
			movement.structural_stride_enabled = true
			check(float(limits.stride_limit) > legacy, "Structural reach must replace the old overly short fixed ratio")
			movement.structural_stride_safety_ratio = 0.4
			check(is_equal_approx(movement.get_spider_stride_limits(foot).stride_limit, limits.stride_limit * 0.5), "Safety ratio must reduce usable structural stride")
			movement.structural_stride_safety_ratio = 0.8
			check(profile.total_frequency <= profile.maximum_step_frequency + 0.001, "Spider timing must respect the configured reference frequency")
			check(is_equal_approx(profile.reachable_speed, minf(profile.target_speed, profile.stride / profile.stance_duration)), "Only planted time must consume the stance reach budget")
			check(is_equal_approx(profile.cycle_travel, profile.reachable_speed * profile.cycle), "Cycle travel must include airborne body travel")
			check(profile.reachable_speed <= profile.target_speed + 0.001, "A feasible speed cap must never exceed the requested speed")
			var saved_delay: float = movement.liftoff_assist_delay
			movement.liftoff_assist_delay = 0.9
			check(is_equal_approx(movement.get_leg_motion_profile(foot).occupied_step_duration, profile.occupied_step_duration), "Assist ramp delay must not be charged as mandatory slot occupancy")
			movement.liftoff_assist_delay = saved_delay
			movement._spider_step_times[foot] = 0.8
			var observed_profile: Dictionary = movement.get_leg_motion_profile(foot)
			check(is_equal_approx(observed_profile.occupied_step_duration, 0.88), "Measured full-step time must include 10 percent margin without adding lift and confirmation twice")
			check(observed_profile.cycle >= 8.0 * 0.88 / observed_profile.support_capacity - 0.001, "Slow real steps must still constrain the available step slots")
			check(observed_profile.stride <= observed_profile.usable_stance_stride_limit + 0.001, "Adapted stride must fit the interior landing and rear trigger")
			check(observed_profile.usable_stance_stride_limit <= observed_profile.structural_stride_limit, "Support travel may not spend structural safety margins")
			if observed_profile.usable_stance_stride_limit > profile.stride + 0.001 and observed_profile.required_stance_stride > profile.stride + 0.001:
				check(observed_profile.stride > profile.stride, "Long observed steps must expand stride beyond the old preferred length ratio when reach allows")
			check(is_equal_approx(observed_profile.required_stance_stride, observed_profile.target_speed * 0.88 * (8.0 / observed_profile.support_capacity - 1.0)), "Required support stride must derive from target speed and occupied slots")
			movement._spider_step_times.erase(foot)
			var saved_basis := foot.basis
			foot.global_basis = Basis(Vector3.BACK, deg_to_rad(70.0) + (PI if float(foot.get_meta(&"spider_up_axis_sign")) < 0.0 else 0.0))
			check(movement._get_spider_joint_margin(foot) <= 10.0, "Joint pose must detect approaching the authored Z hinge limit")
			foot.basis = saved_basis
		check(actor.density_data.resource_path.ends_with("SpiderDensity.tres"), "Spider must use its independent density preset")
		var recovery := actor.get_node("CreatureRecoveryStateMachine3D")
		check(not recovery.height_collapse_detection_enabled, "Spider and its NPC must use angle-only fall detection")
		check(is_equal_approx(recovery.fallen_height_ratio, 0.45) and is_equal_approx(recovery.stable_height_ratio, 0.65), "Spider and its NPC must inherit independent low-stance recovery thresholds")
		var metrics := {"ground_contact": true, "maximum_segment_angle": 0.0, "minimum_segment_height_ratio": 0.55, "angle": 0.0, "height": recovery._reference_height * 0.55, "speed": 0.0}
		check(not recovery._is_fallen(metrics), "A low but upright Spider stance must not count as fallen")
		metrics.minimum_segment_height_ratio = 0.4
		check(not recovery._is_fallen(metrics), "Upright height collapse must not trigger Spider recovery")
		metrics.minimum_segment_height_ratio = 0.0
		check(not recovery._is_fallen(metrics), "Even zero height must not trigger angle-only recovery")
		metrics.speed = 1.0
		check(not recovery._is_fallen(metrics), "Moving vertical dips must not trigger collapse recovery")
		metrics.maximum_segment_angle = 65.0
		check(recovery._is_fallen(metrics), "True tipping must still trigger recovery even while moving")
		metrics.ground_contact = false
		check(not recovery._is_fallen(metrics), "An airborne Spider must not enter ground recovery")
		freeze_actor(actor)
	for tick: int in 6: await physics_frame
	var brain := npc.get_node("NPCStateMachine3D")
	check(brain._navigation_map_is_ready(), "NPC must use the level navigation mesh")
	check(brain._enemy == player, "NPC must select the hostile character")
	check(brain.current_state == brain.State.MOVE_TO_TARGET, "NPC must enter pursuit")
	check(brain.get_movement_direction().x > 0.0, "NPC must request movement toward the enemy")
	check(npc.get_node("GeneratedLegStepMovementController3D").get_player_command_source() == brain, "NPC movement must read state-machine commands")
	check(brain.friendly_avoidance_enabled, "NPC must retain friendly avoidance")
	brain.enabled = false
	check(brain.get_movement_direction().is_zero_approx(), "Disabling NPC AI must stop its movement commands")
	check(npc.generate_creature(), "NPC must support regeneration")
	freeze_actor(npc)
	brain.enabled = true
	for tick: int in 6: await physics_frame
	check(brain._navigation_origin == npc.get_combat_anchor(), "Regeneration must refresh the physical navigation origin")
	check(brain.get_movement_direction().x > 0.0, "NPC must resume pursuit after regeneration")
	level.free()
	await process_frame
	if not failed: print("PASS: Spider character inheritance, runtime assembly, 8-leg discovery, collision exceptions, AI pursuit, disable switch and regeneration.")
	quit(1 if failed else 0)
