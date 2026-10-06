extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
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
	shape.size = Vector3(300, 1, 300)
	collision.shape = shape
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var actor := CHARACTER.instantiate()
	actor.generate_on_ready = false
	actor.position.y = 27.65
	root.add_child(actor)
	var generator := actor.get_node("CreatureGenerator")
	generator.rear_leg_count = maxi((6) - 2, 0)
	generator.foreleg_count = mini((6), 2)
	generator.overall_scale = 4.0
	generator.unsymmetrie = 60.0
	generator._random.seed = 42
	check(actor.generate_creature(), "Heavy asymmetric generation must succeed")
	var machine := actor.get_node("CreatureRecoveryStateMachine3D")
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	for frame: int in range(960):
		await physics_frame
		if frame % 60 == 59:
			print("[support_fix] frame=", frame, " recovery=", machine.get_recovery_diagnostics(), " balanced=", movement._stance_support_balanced)
	check(machine.state == machine.State.STANDING and not movement.recovery_control_active, "Heavy creature must return to ordinary standing control")
	check(machine._metrics.height / machine._reference_height >= 0.85, "Heavy creature must retain standing height after recovery")
	check(machine._attempts <= 1, "Heavy creature must not repeatedly collapse after recovery")
	for body: RigidBody3D in actor._get_physical_body_parts():
		check(body.global_position.is_finite() and body.linear_velocity.is_finite(), "Physics must remain finite")
	if not failed: print("GENERATED_HEAVY_SUPPORT_VALIDATION_PASSED")
	quit(1 if failed else 0)
