extends SceneTree
const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var birds: Array[Node3D] = []
	var results: Array[Dictionary] = []
	var scales: Array = [0.5] if "--small-scale" in OS.get_cmdline_user_args() else [0.5,1.0,1.5,4.0,8.0]
	for scale_value: float in scales:
		var bird := BIRD.instantiate() as Node3D
		bird.generate_on_ready = false
		bird.mass_limits_enabled = "--mass-limits" in OS.get_cmdline_user_args()
		bird.position = Vector3(birds.size()*300.0,100.0,0.0)
		root.add_child(bird)
		var generator := bird.get_node("BirdGenerator")
		generator.overall_scale = scale_value
		generator.unsymmetrie = 0.0
		generator.inhomogeneity = 0.0
		generator._random.seed = 43
		check(bird.generate_creature(),"Flight fixture must generate")
		bird.get_node("NPCStateMachine3D").enabled = false
		var source := preload("res://Tests/InputMovementCommandSource.gd").new()
		bird.add_child(source)
		bird.get_node("GeneratedLegStepMovementController3D").command_source = source
		bird.get_node("BirdFlightController3D").set_diagnostic_tracking_enabled(true)
		birds.append(bird)
		results.append({"sum":0.0,"count":0,"max":0.0,"speed_error":0.0,"peak_frame":0,"settled_peak":0.0})
	for frame: int in range(1200):
		await physics_frame
		if frame == 300: Input.action_press("Right")
		if frame == 600: Input.action_release("Right"); Input.action_press("Up")
		if frame == 900: Input.action_release("Up")
		if frame<180: continue
		for index: int in range(birds.size()):
			var flight := birds[index].get_node("BirdFlightController3D")
			var command: Dictionary = flight._last_command
			check(flight.is_airborne(),"Bird must remain airborne")
			for body: Node in birds[index].get_node("GeneratedParts").get_children():
				if not body is PhysicalBodyPart3D or PhysicalBodyPart3D.BodyPartTag.Torso not in body.tags: continue
				var angle := rad_to_deg(acos(clampf(body.global_basis.y.normalized().dot(Vector3.UP),-1.0,1.0)))
				results[index].sum += angle
				results[index].count += 1
				if angle>float(results[index].max):
					results[index].max = angle
					results[index].peak_frame = frame
				if frame>1000: results[index].settled_peak = maxf(results[index].settled_peak,angle)
			for row: Dictionary in birds[index].get_node("HeadPositionSupport3D").diagnostics:
				check(row.gravity_compensation_owner=="flight","Flight must exclusively own Head gravity compensation")
			check(Vector3(command.torso_torque_total).is_finite(),"Flight torque must be finite")
			if frame>1050: results[index].speed_error = maxf(results[index].speed_error,Vector3(command.structure_velocity).length())
	for index: int in range(birds.size()):
		var r: Dictionary = results[index]
		print("[flight_scale_test] scale=",birds[index].get_node("BirdGenerator").overall_scale," mean_tilt=",r.sum/maxi(r.count,1)," peak_tilt=",r.max," idle_speed=",r.speed_error," peak_frame=",r.peak_frame," settled_peak=",r.settled_peak)
		var peak_limit := 9.0
		check(r.count>0 and r.max<peak_limit and r.sum/maxi(r.count,1)<3.0,"Flight Torso must remain upright across scale and direction changes")
		check(r.speed_error<0.1,"Stopped flight must settle without drift")
		birds[index].queue_free()
	print("FLIGHT_POSTURE_SCALE_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
