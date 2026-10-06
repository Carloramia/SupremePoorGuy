extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	actor.planar_constraints_enabled = false
	actor.position.y = 50.0
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.rear_leg_count = maxi((6) - 2, 0)
	generator.foreleg_count = mini((6), 2)
	generator.unsymmetrie = 60.0
	generator.overall_scale = 4.0
	generator.neck_number = 0

	generator._random.seed = 43
	check(actor.generate_creature(), "Airborne test generation must succeed")
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	movement.set_physics_process(false)
	movement.set_segment_facing_direction(Vector3.LEFT)
	movement._begin_ground_probe_frame()
	movement._apply_segment_balance(1.0 / 60.0)
	check(movement._layout_turn_status == &"waiting_for_ground", "Airborne heading must wait for terrain contact")
	check(not movement._layout_turn_owned and movement._turn_leg_forces.is_empty(), "No turn step or leg traction may start in air")
	for segment: Dictionary in movement.get_body_segment_diagnostics():
		check(Vector3(segment.balance_torque).length() < 0.001, "A heading request must not actuate an upright airborne Torso")
	for link: Dictionary in movement._get_segment_spring_diagnostics():
		check(not link.layout_enabled, "Airborne springs must not steer the layout")
	# Simulate a lost contact during an already owned turn.
	movement._layout_turn_owned = true
	movement.set_turn_planning_active(true)
	movement._update_layout_turn_steps(1.0 / 60.0)
	check(not movement._turn_planning_active and not movement._layout_turn_owned, "Lost ground contact must release turn ownership")
	print("AIRBORNE_TURN status=", movement._layout_turn_status, " leg_forces=", movement._turn_leg_forces)
	actor.queue_free()
	await process_frame
	print("GENERATED_AIRBORNE_TURN_VALIDATION_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
