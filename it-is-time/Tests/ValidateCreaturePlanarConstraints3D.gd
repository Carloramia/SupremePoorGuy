extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(300,1,300)
	collision.shape = shape
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.unsymmetrie = 100.0 if OS.get_cmdline_user_args().has("--asymmetric") else 0.0
	generator.neck_number = 0
	if OS.get_cmdline_user_args().has("--feet=6"): generator.rear_leg_count = 4
	generator._random.seed = 43
	check(actor.generate_creature(),"Planar fixture must generate")
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	var guides = actor.get_node("PlanarConstraints")
	check(actor.planar_constraints_enabled,"Planar mode must default on")
	check(actor.get_internal_collision_diagnostics().missing_pairs == 0,"Planar guides must preserve all internal collision exclusions")
	check(guides.guides.is_empty() and not guides.suspended_joints.is_empty(),"Planar mode must suspend physical joints without auxiliary depth guides")
	for body in guides.saved_locks:
		check(body.axis_lock_angular_x and body.axis_lock_angular_y,"Every block must lock X/Y angular motion")
	var original: Dictionary = guides.saved_locks.duplicate()
	var data = movement.slow_gait_data.duplicate()
	data.target_speed = 5.0
	movement.slow_gait_data = data
	for tick in range(180): await physics_frame
	var start: Vector3 = guides.reference.global_position
	Input.action_press("Right")
	for tick in range(180): await physics_frame
	Input.action_release("Right")
	check(guides.reference.global_position.x > start.x+2.0,"Planar mode must retain X walking")
	var before_z: float = guides.reference.global_position.z
	Input.action_press("Down")
	var max_depth_error := 0.0
	var side_speed := 0.0
	for tick in range(180):
		await physics_frame
		max_depth_error = maxf(max_depth_error,float(guides.get_diagnostics().maximum_depth_error))
		if tick >= 120: side_speed += guides.reference.linear_velocity.z/60.0
		check(guides.reference.axis_lock_angular_x and guides.reference.axis_lock_angular_y,"Side slide must not release angular locks")
	Input.action_release("Down")
	var side_travel: float = guides.reference.global_position.z-before_z
	check(side_travel > 3.0,"All parts must translate collectively along Z")
	check(max_depth_error < 0.08,"Relative depth must remain locked while sliding")
	movement.set_segment_facing_direction(Vector3.LEFT)
	movement._update_layout_turn_steps(1.0/60.0)
	check(not movement._turn_planning_active and movement._layout_turn_status == &"planar_mode","Planar mode must suppress turn commands")
	check(movement._support_pins.is_empty(),"Independent feet must not be connected to terrain pins")
	actor.planar_constraints_enabled = false
	check(guides.guides.is_empty(),"Off switch must remove depth guides")
	for body in original:
		check(body.axis_lock_angular_x == (original[body].x != 0) and body.axis_lock_angular_y == (original[body].y != 0),"Off switch must restore original axis locks")
	actor.planar_constraints_enabled = true
	var damage = actor.get_node("CharacterDamageController3D")
	var foot = movement._legs[0]
	check(damage._get_connected_parts(foot).size() == 1,"Depth guides must not change damage connectivity")
	foot.break_part()
	for tick in range(2): await physics_frame
	check(not guides.saved_locks.has(foot) and not guides.guides.has(foot),"Broken blocks must detach from planar guides")
	check(actor.get_internal_collision_diagnostics().missing_pairs == 0,"Broken guide removal must preserve collision exclusions")
	check(actor.generate_creature(),"Regeneration must succeed with active planar guides")
	check(guides.saved_locks.size() == actor._get_physical_body_parts().size(),"Regeneration must constrain only the new blocks")
	for tick in range(2): await physics_frame
	check(actor.get_internal_collision_diagnostics().missing_pairs == 0,"Regeneration must preserve internal collisions")
	print("PLANAR_RESULT side_travel=",side_travel," side_speed=",side_speed," maximum_depth_error=",max_depth_error)
	print("CREATURE_PLANAR_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
