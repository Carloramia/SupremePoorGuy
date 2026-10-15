extends SceneTree

const GEOMETRY = preload("res://Scripts/Creatures/HumanKneeGeometry3D.gd")
class Commands extends Node:
	var direction := Vector3.ZERO
	var facing := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta: float) -> Vector3: return facing
	func is_jump_requested() -> bool: return false
	func is_fast_requested() -> bool: return false

var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(160,1,160)
	collision.shape = shape
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	var set_index := 4
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--human-set="): set_index = int(argument.trim_prefix("--human-set="))
	var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_Human.tscn").instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	actor.get_node("HumanGenerator").human_set = set_index
	check(actor.generate_creature(),"Human knee test must generate")
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	var commands := Commands.new()
	actor.add_child(commands)
	movement.command_source = commands
	var torso := actor.get_node("GeneratedParts/Torso") as RigidBody3D
	var limits := {}
	for foot: RigidBody3D in movement.get_leg_parts():
		var chain: Dictionary = movement._chains[foot]
		var knee: Generic6DOFJoint3D = chain.joints[1]
		limits[foot.name] = Vector2(knee.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),knee.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT))
		check(chain.has("human_knee"),"Every two-link Human leg must receive geometry")
		var too_close := torso.to_global(chain.anchor)+Vector3.DOWN
		check(not GEOMETRY.solve(chain,too_close).reachable,"A target requiring excessive knee folding must be rejected")
	movement.refresh_physics_query_cache()
	for foot: RigidBody3D in movement.get_leg_parts():
		var knee: Generic6DOFJoint3D = movement._chains[foot].joints[1]
		check(limits[foot.name].is_equal_approx(Vector2(knee.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),knee.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT))),"Cache refresh must preserve asymmetric knee limits")
	for tick: int in 240: await physics_frame
	for direction: Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.BACK,Vector3.FORWARD]:
		commands.direction = Vector3.ZERO
		commands.facing = Vector3.LEFT if direction == Vector3.LEFT else Vector3.RIGHT
		for tick: int in 900:
			await physics_frame
			if tick > 60 and not movement._turn_command_pending: break
		print("HUMAN_KNEE_FACING direction=",direction," yaw=",rad_to_deg(movement._get_physical_heading_yaw())," pending=",movement._turn_command_pending)
		commands.direction = direction
		var start := Vector3.ZERO
		var worst := {"Leg_L":180.0,"Leg_R":180.0}
		var pose_seen := false
		for tick: int in 720:
			await physics_frame
			if tick == 360: start = torso.global_position
			if tick < 360: continue
			for foot: RigidBody3D in movement.get_leg_parts():
				var sample := GEOMETRY.diagnostics(movement._chains[foot])
				worst[foot.name] = minf(worst[foot.name],sample.outward_bend_degrees)
			for row: Dictionary in movement._human_pose.rows:
				if row.owner == "swing_knee" and not row.torque.is_zero_approx(): pose_seen = true
		var velocity := (torso.global_position-start)/(359.0/60.0)
		print("HUMAN_KNEE_MOTION set=",set_index," direction=",direction," velocity=",velocity," forward_speed=",velocity.dot(direction)," minimum_outward_bend=",worst," swing_pose=",pose_seen," rejection=",movement._last_landing_rejection_reason)
		check(torso.global_basis.y.dot(Vector3.UP)>.9,"Human must stay upright")
		check(minf(worst.Leg_L,worst.Leg_R)>-5.0,"Human knees must not bend substantially inward")
		check(velocity.dot(direction)>.6,"Human must keep making progress after knee constraints")
		if direction in [Vector3.RIGHT,Vector3.LEFT]: check(absf(velocity.dot(direction)-1.4)<0.14,"Sustained Human walking speed must remain within ten percent of target")
		check(pose_seen,"Swinging knees must retain pose control")
	commands.direction = Vector3.ZERO
	for tick: int in 120: await physics_frame
	check(is_zero_approx(movement._human_speed_integral),"Stopping must clear speed compensation")
	commands.direction = Vector3.RIGHT
	for tick: int in 120: await physics_frame
	var swing := actor.get_node("LimbSwingController3D")
	check(swing.begin_charge(0),"Human attack must remain available")
	movement._contact_velocity_force(torso.linear_velocity,torso.mass,Vector3.UP)
	check(is_zero_approx(movement._human_speed_integral),"Attacking must clear speed compensation")
	swing.cancel_player_actions()
	for gate: String in ["recovery", "disabled", "airborne"]:
		movement._human_speed_integral = 0.4
		movement.recovery_control_active = gate == "recovery"
		movement.human_speed_compensation_enabled = gate != "disabled"
		movement._adhesion_release_time_remaining = 1.0 if gate == "airborne" else 0.0
		movement._contact_velocity_force(torso.linear_velocity,torso.mass,Vector3.UP)
		check(is_zero_approx(movement._human_speed_integral),"Unsupported, recovering or disabled control must clear compensation: "+gate)
	movement.recovery_control_active = false
	movement.human_speed_compensation_enabled = true
	movement._adhesion_release_time_remaining = 0.0
	check(actor.generate_creature(),"Human must regenerate after knee control")
	await physics_frame
	for foot: RigidBody3D in movement.get_leg_parts(): check(movement._chains[foot].has("human_knee"),"Regeneration must replace knee geometry")
	actor.free()
	floor_body.free()
	await process_frame
	print("HUMAN_KNEE_CONTROL_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
