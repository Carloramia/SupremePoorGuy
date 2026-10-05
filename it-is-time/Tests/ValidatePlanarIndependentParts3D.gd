extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
var failed := false
func check(value: bool,message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200,1,200)
	collision.shape = box
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	actor.planar_constraints_enabled = true
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.unsymmetrie = 0
	generator.neck_number = 0
	generator._random.seed = 43
	check(actor.generate_creature(),"Fixture generates")
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	movement.slow_gait_data = movement.slow_gait_data.duplicate()
	movement.slow_gait_data.target_speed = 2
	var planar = actor.get_node("PlanarConstraints")
	check(planar.guides.is_empty(),"No planar auxiliary joint may remain")
	check(not planar.suspended_joints.is_empty(),"Physical joints must be suspended")
	for joint: Joint3D in planar.suspended_joints:
		check(PhysicsServer3D.joint_get_type(joint.get_rid()) == PhysicsServer3D.JOINT_TYPE_MAX,"Joint RID must be cleared")
	for spring: Node in planar.suspended_springs: check(not spring.is_physics_processing(),"Spring must stop applying force")
	for frame in range(240): await physics_frame
	var supported := 0
	for row: Dictionary in planar.part_diagnostics:
		if row.supported:
			supported += 1
			check(row.support_force.y >= 0,"Reaction force must never pull toward terrain")
	check(supported == planar.rest.size(),"All independently supported parts must settle above ground")
	var torso: RigidBody3D = movement.get_torso_parts()[0]
	var resting_angle := torso.global_rotation.z
	torso.global_rotation.z += 0.3
	var corrective_torque := false
	for frame in range(120):
		await physics_frame
		for row: Dictionary in planar.part_diagnostics:
			if row.part == torso.name and absf(row.balance_torque.z)>0.01: corrective_torque = true
	check(corrective_torque and absf(wrapf(torso.global_rotation.z-resting_angle,-PI,PI))<0.05,"Independent balance torque must restore a disturbed part")
	var foot: RigidBody3D = movement.get_leg_parts()[0]
	var foot_y := foot.global_position.y
	var amplitude := 0.0
	var animated := false
	Input.action_press("Right")
	for frame in range(240):
		await physics_frame
		amplitude = maxf(amplitude,absf(foot.global_position.y-foot_y))
		for row: Dictionary in planar.part_diagnostics:
			if row.step_offset.length()>0.01 and row.gait_force.length()>0.01: animated = true
	Input.action_release("Right")
	check(animated and amplitude>0.03,"Physical foot must rise through independent gait force")
	check(movement._active_steps.is_empty() and movement._support_pins.is_empty(),"Legacy gait and foot pins must remain inactive")
	check(foot.has_node("Sprite3D") and foot.has_node("MeshInstance3D"),"Render nodes must stay on the physical foot")
	for frame in range(120): await physics_frame
	print("INDEPENDENT supported=",supported," foot_amplitude=",amplitude," suspended_joints=",planar.suspended_joints.size())
	# Place the entire creature well outside ground support range.
	for body: RigidBody3D in planar.rest:
		body.global_position.y += 20
		body.linear_velocity = Vector3.ZERO
	for frame in range(5): await physics_frame
	for row: Dictionary in planar.part_diagnostics:
		check(not row.supported and row.support_force == Vector3.ZERO and row.balance_torque == Vector3.ZERO,"Airborne parts must get neither ground reaction nor balance torque")
	var joints: Array = planar.suspended_joints.keys()
	actor.planar_constraints_enabled = false
	for joint: Joint3D in joints:
		check(PhysicsServer3D.joint_get_type(joint.get_rid()) != PhysicsServer3D.JOINT_TYPE_MAX,"Off switch must restore native joint")
	check(planar.suspended_springs.is_empty(),"Off switch must restore spring state")
	print("PLANAR_INDEPENDENT_", "FAILED" if failed else "PASSED")
	actor.queue_free()
	await process_frame
	await process_frame
	quit(1 if failed else 0)
