extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200,1,200)
	collision.shape = box
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	var wolf: Node3D = load("res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn").instantiate()
	wolf.generate_on_ready = false
	root.add_child(wolf)
	wolf.process_mode = Node.PROCESS_MODE_DISABLED
	var total_mass := 0.0
	for body: RigidBody3D in wolf._get_physical_body_parts():
		body.freeze = true
		total_mass += body.mass
	await physics_frame
	var machine: Node = wolf.get_node("CreatureRecoveryStateMachine3D")
	var movement: Node = wolf.get_node("GeneratedLegStepMovementController3D")
	assert(machine.carry_connected_assembly_weight)
	assert(is_equal_approx(machine.stable_height_ratio,0.9))
	machine.refresh_physics_query_cache()
	var torsos: Array[RigidBody3D] = movement.get_torso_parts()
	var feet: Array[RigidBody3D] = movement.get_leg_parts()
	for foot: RigidBody3D in feet: machine._targets[foot] = foot.global_position
	machine._lift_torso(torsos,1.0/60.0)
	var budget_mass := 0.0
	var torso_mass := 0.0
	for row: Dictionary in machine._segment_recovery_diagnostics:
		budget_mass += row.load_mass
		torso_mass += row.torso_mass
	assert(is_equal_approx(budget_mass,total_mass))
	assert(budget_mass > torso_mass)
	var first: Dictionary = machine._segment_recovery_diagnostics[0]
	var previous_lift: float = first.lift_force
	machine._support_lift_by_segment[first.segment] = 10.0
	machine._lift_torso(torsos,0.0)
	assert(is_equal_approx(machine._segment_recovery_diagnostics[0].lift_force,previous_lift-10.0))
	machine._metrics = {"minimum_segment_height_ratio":0.6}
	machine._check_height_progress(feet,0.1)
	machine._check_height_progress(feet,1.01)
	assert(machine._support_replans == 1 and machine._relaxed_feet.size() == 1)
	machine._metrics.minimum_segment_height_ratio = 0.62
	machine._check_height_progress(feet,0.8)
	assert(machine._support_replans == 1 and is_zero_approx(machine._height_stall_time))
	wolf.free()
	var physical: Node3D = load("res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn").instantiate()
	physical.generate_on_ready = false
	root.add_child(physical)
	physical.get_node("NPCStateMachine3D").enabled = false
	var physical_movement: Node = physical.get_node("GeneratedLegStepMovementController3D")
	var recovery: Node = physical.get_node("CreatureRecoveryStateMachine3D")
	var head_support: Node = physical.get_node("HeadPositionSupport3D")
	physical_movement.set_physics_process(false)
	recovery.enabled = false
	head_support.enabled = false
	for body: RigidBody3D in physical._get_physical_body_parts(): body.freeze = false
	for tick: int in 180: await physics_frame
	physical_movement.set_physics_process(true)
	recovery.enabled = true
	head_support.enabled = true
	recovery._transition(recovery.State.ESTABLISH_SUPPORT,&"test_collapsed_load")
	var recovered := false
	for tick: int in 1200:
		await physics_frame
		if tick % 120 == 119: print("WOLF_RECOVERY_PHYSICS ",recovery.get_recovery_diagnostics())
		if recovery.state == recovery.State.STANDING:
			recovered = true
			break
	assert(recovered,"A collapsed real Wolf must regain 90% of standing height and hand off to normal support")
	for tick: int in 180: await physics_frame
	assert(recovery.state == recovery.State.STANDING,"Normal full-load support must maintain the recovered stand height")
	print("WOLF_RECOVERY_FINAL ",recovery.get_recovery_diagnostics())
	physical.free()
	floor_body.free()
	await process_frame
	print("WOLF_RECOVERY_LOAD_PASSED")
	quit()
