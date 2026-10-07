extends SceneTree
const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var birds: Array[Node3D] = []
	var results: Array[Dictionary] = []
	for scale_value: float in [1.5,4.0]:
		var bird := BIRD.instantiate() as Node3D
		bird.generate_on_ready = false
		bird.mass_limits_enabled = false
		bird.position = Vector3(birds.size()*200.0,50.0,0.0)
		root.add_child(bird)
		var generator := bird.get_node("BirdGenerator")
		generator.overall_scale = scale_value
		generator.unsymmetrie = 0.0
		generator.inhomogeneity = 0.0
		generator._random.seed = 43
		check(bird.generate_creature(),"Sway fixture must generate")
		bird.get_node("NPCStateMachine3D").enabled = false
		var commands := preload("res://Tests/InputMovementCommandSource.gd").new()
		bird.add_child(commands)
		bird.get_node("GeneratedLegStepMovementController3D").command_source = commands
		bird.get_node("WingPoseController3D").set_diagnostic_tracking_enabled(true)
		birds.append(bird)
		results.append({"sum":0.0,"count":0,"peak":0.0,"root_min":INF,"root_max":-INF})
	for frame: int in range(900):
		await physics_frame
		if frame == 180: Input.action_press("Right")
		if frame == 720: Input.action_release("Right")
		if frame<360 or frame>=720: continue
		for index: int in range(birds.size()):
			var wing := birds[index].get_node("WingPoseController3D")
			check(wing._sway_blend>0.95,"Flying movement must enable sway")
			for binding: Dictionary in wing.bindings:
				var command: Dictionary = binding.get("command",{})
				if command.is_empty(): continue
				results[index].sum += float(command.error_degrees)
				results[index].count += 1
				results[index].peak = maxf(results[index].peak,float(command.error_degrees))
				check(not command.target_limited,"Default sway/elevation must fit within joint limits")
				if binding.parent_section_index<0:
					var actual: float = (binding.a.global_basis.orthonormalized().inverse()*binding.b.global_basis.orthonormalized()).get_euler().z
					results[index].root_min = minf(results[index].root_min,actual)
					results[index].root_max = maxf(results[index].root_max,actual)
	for index: int in range(birds.size()):
		var wing := birds[index].get_node("WingPoseController3D")
		check(wing._sway_blend<0.01,"Stopped flight must smoothly stop sway")
		var result: Dictionary = results[index]
		var mean_error := float(result.sum)/maxi(result.count,1)
		var span := rad_to_deg(float(result.root_max)-float(result.root_min))
		print("[wing_sway_test] scale=",birds[index].get_node("BirdGenerator").overall_scale," mean_error=",mean_error," peak_error=",result.peak," actual_root_span=",span)
		check(result.count>0 and mean_error<3.0,"Sway targets must remain trackable")
		check(span>4.0,"Actual wings must sway, not only their target values")
		for binding: Dictionary in wing.bindings:
			wing._get_expanded_relative_pose(binding)
			var expected: float = wing.segment_elevation_degrees if binding.has_wing_parent else 0.0
			check(absf(absf(binding.pose_offset_degrees)-expected)<0.01,"Every internal wing joint must retain its upward angle while stationary")
		wing._sway_blend = 1.0
		wing._sway_phase = 0.7
		for section: int in range(3):
			var expected: float = deg_to_rad(wing.flight_sway_amplitude_degrees)*sin(0.7-section*deg_to_rad(wing.flight_sway_phase_difference_degrees))
			check(absf(wing._section_sway_angle(section)-expected)<0.00001,"Wing sections must share frequency and use successive phase delays")
		birds[index].queue_free()
	print("WING_SWAY_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
