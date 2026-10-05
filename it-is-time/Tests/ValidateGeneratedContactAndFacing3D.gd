extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
const PLAYER = preload("res://Scenes/Player/Controller.tscn")
const CURSOR = preload("res://Scenes/Input/TerrainCursor3D.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(300, 1, 300)
	collision.shape = shape
	ground.add_child(collision)
	ground.position.y = -0.5
	world.add_child(ground)
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	world.add_child(actor)
	var generator = actor.get_node("CreatureGenerator")
	generator.rear_leg_count = maxi((6) - 2, 0)
	generator.foreleg_count = mini((6), 2)
	generator.unsymmetrie = 60.0
	generator.overall_scale = 4.0
	generator.neck_number = 0

	generator._random.seed = 43
	check(actor.generate_creature(), "Generation must succeed")
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	for frame: int in range(300): await physics_frame
	var cursor = CURSOR.instantiate()
	cursor.input_enabled = false
	world.add_child(cursor)
	var player = PLAYER.instantiate()
	player.terrain_cursor = cursor
	actor.add_child(player)
	await process_frame
	check(player.get_controlled_character() == actor, "Player must attach to generated creature")
	var center := Vector3.ZERO
	var mass := 0.0
	for body: RigidBody3D in movement.get_torso_parts():
		center += body.global_position * body.mass
		mass += body.mass
	center /= mass
	cursor.follow_anchor_translation = false
	cursor.set_cursor_world_position(center + Vector3.LEFT * 30.0)
	var turning := false
	var lost_support := false
	for frame: int in range(7200):
		await physics_frame
		turning = turning or movement._layout_turn_owned
		lost_support = lost_support or movement.recovery_control_active
		if frame % 600 == 0:
			print("TURN_PROGRESS seconds=", frame / 60.0, " body=", movement._torso.global_rotation_degrees.y, " layout=", rad_to_deg(movement._segment_layout_yaw), " forces=", movement._turn_leg_forces.values(), " foot_yaw=", movement._legs[0].global_rotation_degrees.y, " recovery=", movement.recovery_control_active)
	check(absf(absf(movement._segment_goal_yaw) - PI) < 0.01, "Cursor must command left-facing through Player Controller")
	check(turning, "Cursor command must start the generated turn-step planner")
	var worst_heading := 0.0
	for body: RigidBody3D in movement.get_torso_parts():
		worst_heading = maxf(worst_heading, absf(rad_to_deg(wrapf(body.global_rotation.y - PI, -PI, PI))))
	print("CURSOR_TURN heading_error=", worst_heading, " status=", movement._layout_turn_status, " failures=", movement._failed_step_count, " target=", movement._layout_turn_target, " rejected=", movement._last_landing_rejection_reason)
	check(worst_heading < 10.0, "Actual cursor-driven turn must complete")
	check(not lost_support, "Cursor turn must preserve standing support")
	check(not movement._layout_turn_owned and not movement._turn_planning_active, "Finished cursor turn must release gait ownership")
	# An airborne command may remain queued, but no turn step or leg traction may run.
	movement.set_physics_process(false)
	movement.cancel_step(&"airborne_test")
	var saved_positions: Dictionary = {}
	for body: Node in actor.get_node("GeneratedParts").get_children():
		if body is RigidBody3D:
			saved_positions[body] = body.global_position
			body.global_position += Vector3.UP * 30.0
	movement._begin_ground_probe_frame()
	movement._update_layout_turn_steps(1.0 / 60.0)
	check(movement._layout_turn_status == &"waiting_for_ground", "Airborne turn must wait for a grounded sole")
	check(not movement._layout_turn_owned and movement._turn_leg_forces.is_empty(), "Airborne turn must release step ownership and traction")
	for link: Dictionary in movement._get_segment_spring_diagnostics():
		check(not link.layout_enabled, "Generated springs must not act as independent turn motors")
	for body: RigidBody3D in saved_positions: body.global_position = saved_positions[body]
	movement._begin_ground_probe_frame()
	# Reproduce a tilted selection followed by an upright foot. The terrain point must stay fixed.
	movement.set_physics_process(false)
	var foot: RigidBody3D = movement.get_leg_parts()[0]
	var original_basis := foot.global_basis
	foot.global_basis = Basis(Vector3.FORWARD, 0.5) * original_basis
	var terrain := Vector3(foot.global_position.x, 0.0, foot.global_position.z)
	var target: Vector3 = movement._body_position_for_ground_contact(foot, terrain)
	movement._begin_leg_motion(foot, target, Vector3.UP)
	foot.global_basis = original_basis
	movement._step_state = movement.StepState.LANDING
	movement._update_active_step(1.0 / 60.0)
	var expected: Vector3 = movement._body_position_for_ground_contact(foot, terrain)
	check(movement._step_target.distance_to(expected) < 0.001, "Landing center must follow current collision-box pose")
	check(movement._tracking_gravity_force.is_zero_approx(), "Landing must remove upward gravity feedforward")
	movement.cancel_step()
	movement.set_physics_process(true)
	player.wheel.visible = true
	check(player.get_generated_facing_direction(1.0).is_zero_approx(), "UI must block new generated heading commands")
	player.wheel.visible = false
	world.queue_free()
	await process_frame
	print("GENERATED_CONTACT_FACING_VALIDATION_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
