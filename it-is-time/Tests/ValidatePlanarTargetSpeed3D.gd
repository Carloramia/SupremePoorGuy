extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
var failed := false
func check(value: bool,message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func velocity(movement: Node) -> float:
	var total := 0.0
	var mass := 0.0
	for body: RigidBody3D in movement.get_torso_parts():
		total += body.linear_velocity.z*body.mass
		mass += body.mass
	return total/maxf(mass,0.001)
func run() -> void:
	var ground := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(500,1,500)
	shape_node.shape = box
	ground.add_child(shape_node)
	ground.position.y = -0.5
	root.add_child(ground)
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	actor.planar_constraints_enabled = true
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.unsymmetrie = 0.0
	generator.neck_number = 0
	generator._random.seed = 43
	check(actor.generate_creature(),"Slide fixture must generate")
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	var data = movement.slow_gait_data.duplicate()
	movement.slow_gait_data = data
	for frame in range(180): await physics_frame
	for target: float in [1.0,3.0,5.0]:
		data.target_speed = target
		data.gallop_enabled = target != 1.0
		data.automatic_motion = target != 3.0
		for action: String in ["Down","Up","Right","Left"]:
			Input.action_press(action)
			var mean := 0.0
			for frame in range(240):
				await physics_frame
				if frame >= 180:
					var sum := 0.0
					var mass := 0.0
					for body: RigidBody3D in movement.get_torso_parts():
						sum += (body.linear_velocity.z if action in ["Down","Up"] else body.linear_velocity.x)*body.mass
						mass += body.mass
					mean += sum/maxf(mass,0.001)/60.0
			var expected := target if action in ["Down","Right"] else -target
			check(absf(mean-expected) <= maxf(target*0.12,0.12),"Slide speed must track TargetSpeed action=%s target=%s actual=%s" % [action,expected,mean])
			check(is_equal_approx(float(movement._contact_drive_diagnostics.target_velocity.z if action in ["Down","Up"] else movement._contact_drive_diagnostics.target_velocity.x),expected),"Desired slide speed must use TargetSpeed in walking/manual/gallop modes")
			check(movement._active_steps.is_empty(),"Planar movement must never start physical stepping")
			var animated := false
			for row: Dictionary in actor.get_node("PlanarConstraints").part_diagnostics:
				if row.step_offset.length()>0.001: animated = true
			check(animated,"Actual movement must animate physical leg parts")
			check(movement._support_pins.is_empty(),"Planar movement must not create ground pins")
			check(movement._last_torso_response_force == Vector3.ZERO,"Planar gait must not drive Torso through feet")
			check(actor.get_node("PlanarConstraints").get_diagnostics().maximum_depth_error < 0.08,"Z sliding must retain depth constraints")
			Input.action_release(action)
			for frame in range(90): await physics_frame
			check(absf(velocity(movement)) < 0.3,"Release must brake rather than retain accumulated drive")
			check(is_zero_approx(movement._planar_slide_integral),"Release must reset the integral")
			print("PLANAR_SPEED action=",action," target=",expected," mean=",mean)
	data.target_speed = 2.0
	Input.action_press("Down")
	Input.action_press("Right")
	var command: Vector3 = movement._planar_target_velocity()
	check(is_equal_approx(command.z,2.0/sqrt(2.0)),"Diagonal inputs must preserve normalized movement")
	Input.action_release("Down")
	Input.action_release("Right")
	actor.planar_constraints_enabled = false
	for foot: RigidBody3D in movement.get_leg_parts():
		check(foot.has_node("Sprite3D") and foot.has_node("MeshInstance3D"),"Off switch must restore original render nodes")
	check(movement._planar_slide_diagnostics.is_empty(),"Off switch must clear slide control state")
	print("PLANAR_TARGET_SPEED_", "FAILED" if failed else "PASSED")
	actor.queue_free()
	await process_frame
	await process_frame
	quit(1 if failed else 0)
