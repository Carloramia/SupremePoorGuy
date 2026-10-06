extends SceneTree
const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")
var failed := false
func check(value: bool,message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var bird := BIRD.instantiate()
	bird.generate_on_ready = false
	root.add_child(bird)
	var generator := bird.get_node("BirdGenerator")
	generator.overall_scale = 4.0
	generator.unsymmetrie = 0.0
	generator.inhomogeneity = 0.0
	check(bird.generate_creature(),"Bird must generate")
	var movement := bird.get_node("GeneratedLegStepMovementController3D")
	var flight := bird.get_node("BirdFlightController3D")
	var before: Dictionary = {}
	for foot: RigidBody3D in movement._chains:
		before[foot] = {"length":movement._chains[foot].length,"anchor":movement._chains[foot].anchor}
	for body: Node in bird.get_node("GeneratedParts").get_children():
		if body is RigidBody3D:
			body.freeze = true
			body.global_position += Vector3(17,-21,30)
	# Joint nodes deliberately stay at their generated visual positions.
	movement.refresh_physics_query_cache()
	for foot: RigidBody3D in before:
		check(is_equal_approx(movement._chains[foot].length,before[foot].length),"Full cache rebuild must ignore world travel")
		check(movement._chains[foot].anchor.is_equal_approx(before[foot].anchor),"Full cache rebuild must preserve local root anchors")
	flight._set_state(flight.State.AIRBORNE,"test")
	flight._set_state(flight.State.GROUNDED,"confirmed_foot_contacts")
	check(flight._landing_transition and is_zero_approx(flight.get_ground_control_blend()),"Landing starts gradual control")
	check(not movement.try_start_step(Vector3.RIGHT),"Early landing must block stepping")
	for binding: Dictionary in flight._joints:
		check(binding.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)>3.0,"Landing must not snap joint limits")
	flight._update_landing_transition(0.1)
	check(flight.get_ground_control_blend()>0.0 and flight.get_ground_control_blend()<0.5,"Control blend increases gradually")
	flight._set_state(flight.State.AIRBORNE,"ascend_input")
	check(not flight._landing_transition and is_zero_approx(flight.get_ground_control_blend()),"Takeoff interrupts transition")
	flight._set_state(flight.State.GROUNDED,"confirmed_foot_contacts")
	for index: int in range(120): flight._update_landing_transition(1.0/60.0)
	check(not flight._landing_transition,"Settled joints finish transition")
	for binding: Dictionary in flight._joints:
		check(is_equal_approx(binding.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT),binding.upper),"Limits return to original settings")
	flight._set_state(flight.State.AIRBORNE,"test")
	flight._set_state(flight.State.GROUNDED,"confirmed_foot_contacts")
	flight.set_character_control_enabled(false)
	check(not flight._landing_transition,"Disabled character immediately cancels transition")
	bird.queue_free()
	await process_frame
	print("BIRD_LANDING_CACHE_PASSED" if not failed else "BIRD_LANDING_CACHE_FAILED")
	quit(1 if failed else 0)
