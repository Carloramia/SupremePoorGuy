extends SceneTree
const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var console := root.get_node("RuntimeConsole")
	check("trackflight" in console.execute_command("help"),"Help must list trackflight")
	check(console.execute_command("trackflight invalid").begins_with("Usage:"),"Invalid arguments must be rejected")
	console.execute_command("trackflight on")
	var bird := BIRD.instantiate()
	bird.generate_on_ready = false
	bird.position.y = 5.0
	root.add_child(bird)
	var generator := bird.get_node("BirdGenerator")
	generator.overall_scale = 1.0
	generator.unsymmetrie = 0.0
	generator.inhomogeneity = 0.0
	generator.feather_spacing = 0.6
	generator.wing_root_length = 0.5
	generator.wing_middle_length = 0.5
	generator.wing_tip_length = 0.5
	check(bird.generate_creature(),"Diagnostic bird must generate")
	console.set_process(false)
	var flight := bird.get_node("BirdFlightController3D")
	var wing := bird.get_node("WingPoseController3D")
	check(flight._diagnostic_tracking and wing._diagnostic_tracking,"New components must inherit console tracking")
	for index: int in range(60): await physics_frame
	var data: Dictionary = flight.get_flight_diagnostics()
	check(data.state == "AIRBORNE" and not data.last_command.is_empty(),"Flight command must be captured")
	check(data.legs.size() == 2 and data.legs[0].has("cached_chain_length"),"Leg contacts and geometry must be captured")
	check(not data.legs[0].command.is_empty(),"Tuck force must be captured")
	var wings: Dictionary = wing.get_wing_diagnostics()
	check(not wings.wings.is_empty() and not wings.wings[0].command.is_empty(),"Wing torque must be captured")
	check(wings.wings[0].sampled_feathers>0,"Feather summary must be captured")
	var lines: Array[String] = console._collect_bird_motion_lines(bird,"[trackflight]")
	check(lines.size()>4,"Console must produce per-leg and per-wing lines")
	console._emit_motion_lines(lines)
	flight._set_state(flight.State.GROUNDED,"diagnostic_test")
	console.execute_command("trackmotion")
	console.execute_command("trackflight off")
	check(flight._diagnostic_tracking,"trackmotion must keep capture active")
	console.execute_command("trackmotion")
	check(not flight._diagnostic_tracking and not wing._diagnostic_tracking,"Both disabled must stop capture")
	check(flight._last_command.is_empty(),"Disabled capture must clear stale commands")
	print("BIRD_DIAGNOSTICS_PASS" if not failed else "BIRD_DIAGNOSTICS_FAILED")
	quit(1 if failed else 0)
