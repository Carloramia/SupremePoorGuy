extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
var failed: bool = false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	collision.shape = shape
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var actor := CHARACTER.instantiate()
	actor.generate_on_ready = false
	actor.position.y = 30.0
	root.add_child(actor)
	var generator := actor.get_node("CreatureGenerator")
	generator.feets = 4
	generator.overall_scale = 1.0
	generator.unsymmetrie = 0.0
	generator.neck_number = 0
	generator.torso_core_extra_blocks = 0
	generator._random.seed = 42
	check(actor.generate_creature(), "Generation must succeed")
	var machine := actor.get_node("CreatureRecoveryStateMachine3D")
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	check(machine._reference_height > 0.0 and machine._rest_offsets.size() == 4, "Recovery must capture generated standing pose")
	check(machine._is_fallen({"ground_contact": true, "angle": 5.0, "height": machine._reference_height * 0.56, "speed": 0.1}), "Upright collapsed legs must trigger recovery")
	check(not machine._is_fallen({"ground_contact": true, "angle": 5.0, "height": machine._reference_height * 0.56, "speed": 18.0}), "Landing impact must settle before upright collapse recovery")
	check(not machine._is_fallen({"ground_contact": false, "angle": 80.0, "height": 0.0, "speed": 0.1}), "Airborne pose must not trigger ground recovery")
	for frame: int in range(25): await physics_frame
	check(machine.state == machine.State.STANDING and not movement.recovery_control_active, "Airborne spawn must not be classified as fallen")
	machine.set_physics_process(false)
	movement.set_physics_process(false)
	machine._metrics = {"center": movement._torso.global_position, "height": 1.0}
	machine._transition(machine.State.FALLEN, &"test")
	check(movement.recovery_control_active, "Recovery must take movement ownership")
	movement._active_leg = movement.get_leg_parts()[0]
	machine._transition(machine.State.ESTABLISH_SUPPORT, &"test")
	check(machine._attempts == 1, "Recovery attempt must be counted")
	check(machine._targets.size() == 0, "Unreachable airborne targets must be rejected")
	machine._transition(machine.State.RETRY, &"test")
	check(movement.recovery_control_active, "Retry must keep normal gait paused")
	machine.enabled = false
	check(not movement.recovery_control_active, "Disable switch must release movement ownership")
	machine.enabled = true
	check(movement.recovery_control_active, "Re-enable must reclaim active recovery")
	machine._transition(machine.State.STANDING, &"test")
	check(not movement.recovery_control_active and movement.get_active_leg() == null, "Recovered state must release movement and cancel stale steps")
	# Standalone attitude correction must apply finite torque even when upside down.
	var torsos: Array[RigidBody3D] = movement.get_torso_parts()
	for body: RigidBody3D in torsos: body.global_basis = Basis(Vector3.RIGHT, PI)
	machine._right_torso(torsos)
	machine._restore_limbs()
	for frame: int in range(2): await physics_frame
	for body: RigidBody3D in torsos: check(body.angular_velocity.is_finite(), "Recovery torque must remain finite")
	# Exercise automatic fall detection and stable handoff against real ground probes.
	actor.position.y = 0.0
	generator._random.seed = 42
	check(actor.generate_creature(), "Regeneration before ground detection must succeed")
	torsos = movement.get_torso_parts()
	for body: RigidBody3D in actor._get_physical_body_parts():
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	machine.refresh_physics_query_cache()
	machine.set_physics_process(false)
	movement.set_physics_process(false)
	for body: RigidBody3D in torsos: body.global_basis = Basis(Vector3.RIGHT, PI)
	await physics_frame
	await physics_frame
	machine._physics_process(machine.fall_confirmation_duration + 0.01)
	check(machine.state == machine.State.FALLEN, "Grounded upside-down character must trigger automatic fall detection")
	machine._physics_process(machine.fallen_pause_duration + 0.01)
	check(machine.state == machine.State.ESTABLISH_SUPPORT, "Fallen pause must progress to support setup")
	machine._physics_process(0.01)
	check(machine.state == machine.State.RIGHTING, "Confirmed foot support must permit righting")
	for body: RigidBody3D in torsos: body.global_basis = Basis.IDENTITY
	await physics_frame
	machine._physics_process(0.01)
	check(machine.state == machine.State.STABILIZING, "Upright supported pose must enter stabilization")
	machine._physics_process(machine.stable_confirmation_duration + 0.01)
	check(machine.state == machine.State.STANDING and not movement.recovery_control_active, "Stable confirmation must return gait ownership")
	machine.set_character_control_enabled(false)
	check(not machine.is_physics_processing() and not movement.recovery_control_active, "Death must disable recovery")
	actor.queue_free()
	ground.queue_free()
	await process_frame
	if not failed: print("CREATURE_RECOVERY_STATE_MACHINE_VALIDATION_PASSED")
	quit(1 if failed else 0)
