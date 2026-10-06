extends SceneTree
const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")
var failed := false
func check(value: bool,message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
	for index: int in range(count): await physics_frame
func run() -> void:
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100,1,100)
	shape.shape = box
	floor.add_child(shape)
	floor.position.y = -0.5
	root.add_child(floor)
	var bird := BIRD.instantiate()
	bird.generate_on_ready = false
	bird.position.y = 5.0
	root.add_child(bird)
	var generator := bird.get_node("BirdGenerator")
	var full_size := "--full-size" in OS.get_cmdline_user_args()
	generator.overall_scale = 4.0 if full_size else 1.0
	if "--scale=1.5" in OS.get_cmdline_user_args(): generator.overall_scale = 1.5
	generator.unsymmetrie = 0.0
	generator.inhomogeneity = 0.0
	if not full_size and "--scale=1.5" not in OS.get_cmdline_user_args():
		generator.feather_spacing = 0.6
		generator.wing_root_length = 0.5
		generator.wing_middle_length = 0.5
		generator.wing_tip_length = 0.5
	check(bird.generate_creature(),"Flight bird must generate")
	var flight := bird.get_node("BirdFlightController3D")
	flight.diagnostic_logging_enabled = true
	var movement := bird.get_node("GeneratedLegStepMovementController3D")
	var original_geometry: Dictionary = {}
	for foot: RigidBody3D in movement._chains:
		original_geometry[foot] = {"length":movement._chains[foot].length,"anchor":movement._chains[foot].anchor}
	var recovery := bird.get_node("CreatureRecoveryStateMachine3D")
	var initial_standing_height: float = recovery._reference_height
	await frames(180)
	check(flight.is_airborne(),"An air-spawned bird must enter airborne state")
	check(flight._fold_ratio>0.95,"Legs must fold while airborne")
	for leg: Dictionary in flight._legs:
		var actual: Vector3 = leg.support.global_transform.affine_inverse()*leg.body.global_position
		var target: Vector3 = leg.support.global_transform.affine_inverse()*flight.get_leg_tuck_target(leg)
		print("[flight_test] tucked_foot_y=",actual.y," initial_y=",leg.rest_center.y," target_y=",target.y)
		check(actual.y>leg.rest_center.y+0.1,"Airborne feet must lift toward their torso")
		check(actual.y<0.0 and target.y<0.0,"Tucked feet must stay below their torso")
	check(not flight.has_standing_leg_contacts(),"Nearby terrain rays cannot count as real foot contacts")
	check(not movement.is_burst_requested(),"Flight Space must not trigger a walking jump")
	var torso: PhysicalBodyPart3D = flight._torso
	var y := torso.global_position.y
	await frames(120)
	print("[flight_test] hover_delta=",torso.global_position.y-y)
	check(absf(torso.global_position.y-y)<0.5,"No-input flight must hover")
	Input.action_press("Space")
	y = torso.global_position.y
	await frames(120)
	Input.action_release("Space")
	print("[flight_test] ascent_delta=",torso.global_position.y-y)
	check(torso.global_position.y-y>3.0,"Held Space must raise the whole bird")
	Input.action_press("Right")
	var x := torso.global_position.x
	await frames(120)
	Input.action_release("Right")
	check(torso.global_position.x-x>5.0,"Airborne horizontal movement must respond")
	check(movement._active_steps.is_empty(),"Airborne movement must not start foot steps")
	await frames(120)
	x = torso.global_position.x
	await frames(120)
	check(absf(torso.global_position.x-x)<0.5,"Releasing input must stop horizontal drift")
	Input.action_press("Ctrl")
	y = torso.global_position.y
	await frames(120)
	check(torso.global_position.y-y < -3.0,"Held Ctrl must descend")
	for frame: int in range(900):
		await physics_frame
		if not flight.is_airborne(): break
	Input.action_release("Ctrl")
	print("[flight_test] landed=",not flight.is_airborne()," clearance=",flight._ground_clearance())
	check(not flight.is_airborne(),"Descending near terrain must land")
	check(flight.has_standing_leg_contacts(),"Landing must be backed by actual standable foot contacts")
	for foot: RigidBody3D in original_geometry:
		check(is_equal_approx(movement._chains[foot].length,original_geometry[foot].length),"Landing must preserve original chain length")
		check(movement._chains[foot].anchor.is_equal_approx(original_geometry[foot].anchor),"Landing must preserve local attachments")
	check(is_equal_approx(recovery._reference_height,initial_standing_height),"Landing must preserve recovery standing height")
	check(flight.get_ground_control_blend()<0.1,"Ground control must start with a gradual handoff")
	check(not movement.try_start_step(Vector3.RIGHT),"Landing must initially block new steps")
	var walking_time: float = movement._physics_elapsed
	await frames(60)
	check(not flight.is_airborne(),"Landed bird must remain grounded without input")
	check(movement.is_physics_processing(),"Landing must restore walking controller processing")
	check(movement._physics_elapsed>walking_time+0.5,"Landing must actually resume gait updates")
	check(is_equal_approx(flight.get_ground_control_blend(),1.0),"Landing must restore full control")
	Input.action_press("Space")
	await frames(30)
	Input.action_release("Space")
	check(flight.is_airborne(),"Grounded Space must take off again")
	flight.set_character_control_enabled(false)
	check(not flight.is_airborne(),"Death must stop flight")
	bird.queue_free()
	floor.queue_free()
	await process_frame
	print("BIRD_FLIGHT_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
