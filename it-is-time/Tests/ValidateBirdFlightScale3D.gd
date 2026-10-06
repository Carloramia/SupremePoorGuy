extends SceneTree
const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var birds: Array[Node3D] = []
	for scale_value: float in [1.5, 4.0]:
		var bird := BIRD.instantiate() as Node3D
		bird.generate_on_ready = false
		bird.position = Vector3(scale_value * 30.0, 25.0, 0.0)
		root.add_child(bird)
		var generator := bird.get_node("BirdGenerator")
		generator.overall_scale = scale_value
		generator.unsymmetrie = 0.0
		generator.inhomogeneity = 0.0
		generator._random.seed = 43
		check(bird.generate_creature(), "Scale test bird must generate")
		bird.get_node("BirdFlightController3D").set_diagnostic_tracking_enabled(true)
		birds.append(bird)
	var results: Array[Dictionary] = []
	for bird: Node3D in birds: results.append({"error_sum":0.0,"samples":0,"max_speed":0.0,"max_position_error":0.0,"passive":false})
	for frame: int in range(720):
		await physics_frame
		if frame == 360:
			for bird: Node3D in birds:
				var flight := bird.get_node("BirdFlightController3D")
				for leg: Dictionary in flight._legs:
					leg.body.angular_velocity = Vector3(0.0, 1.0, -1.0)
		if frame < 540: continue
		for index: int in range(birds.size()):
			var flight := birds[index].get_node("BirdFlightController3D")
			check(flight.is_airborne(), "Scale test must stay airborne")
			for leg: Dictionary in flight._legs:
				var command: Dictionary = leg.get("command", {})
				if command.is_empty(): continue
				results[index].error_sum += float(command.orientation_error_degrees)
				results[index].samples += 1
				results[index].max_speed = maxf(results[index].max_speed, leg.body.angular_velocity.length())
				results[index].max_position_error = maxf(results[index].max_position_error, Vector3(command.position_error).length())
				check(bool(command.get("pose_inertia_valid", false)), "Pose must use a valid inertia solve")
				check(absf(Vector3(command.torque).x)<0.000001, "Pose must not push against the locked X axis")
			var movement := birds[index].get_node("GeneratedLegStepMovementController3D")
			for row: Dictionary in movement._passive_hinge_rows:
				results[index].passive = results[index].passive or Engine.get_physics_frames()-int(row.get("frame",-100))<=1
	for index: int in range(birds.size()):
		var result: Dictionary = results[index]
		var scale_value: float = birds[index].get_node("BirdGenerator").overall_scale
		var mean_error := float(result.error_sum) / maxi(result.samples, 1)
		print("[flight_scale_test] scale=",scale_value," mean_error_degrees=",mean_error," maximum_angular_speed=",result.max_speed," maximum_position_error=",result.max_position_error," passive_damping=",result.passive)
		check(result.samples > 0, "Pose diagnostics must have fresh samples")
		check(mean_error < 15.0, "Airborne foot orientation must converge at scale " + str(scale_value))
		check(result.max_speed < 3.0, "Airborne feet must not keep oscillating at scale " + str(scale_value))
		check(result.max_position_error < 0.15 * scale_value, "Tuck position must converge at scale " + str(scale_value))
		check(result.passive, "Airborne chains must retain passive damping")
		var flight := birds[index].get_node("BirdFlightController3D")
		var leg: Dictionary = flight._legs[0]
		flight.pose_strength = 100.0
		flight.pose_damping = 50.0
		var guarded: Dictionary = flight._calculate_leg_pose_command(leg.body, leg.support, Quaternion(Vector3.UP, 0.5), 1.0/15.0)
		check(guarded.inertia_valid and Vector3(guarded.torque).is_finite(), "Large timestep/high gains must remain finite")
		check(guarded.step_denominator>4.0, "High gains must receive timestep compensation")
		birds[index].queue_free()
	print("BIRD_FLIGHT_SCALE_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
