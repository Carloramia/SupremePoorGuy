extends Node3D
## Flight forces are mass-scaled and distributed across living parts, without teleporting.
const PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")
enum State { GROUNDED, AIRBORNE }
signal state_changed(previous: int, current: int)
@export var enabled: bool = true
@export var ascend_action: StringName = &"Space"
@export var descend_action: StringName = &"Ctrl"
@export_group("Flight Motion")
@export_range(0.0, 30.0, 0.1) var horizontal_speed: float = 5.0
@export_range(0.0, 30.0, 0.1) var ascent_speed: float = 3.0
@export_range(0.0, 30.0, 0.1) var descent_speed: float = 3.0
@export_range(0.1, 30.0, 0.1) var velocity_response: float = 5.0
@export_range(0.1, 100.0, 0.1) var maximum_acceleration: float = 15.0
@export_group("Initial Flight State")
## Only used when spawning, never as the Ctrl landing condition.
@export_range(0.01, 2.0, 0.01) var initial_ground_clearance: float = 0.15
@export_range(0.01, 2.0, 0.01) var airborne_confirmation_time: float = 0.2
@export_group("Landing")
@export_range(0.1, 1.0, 0.05) var minimum_standing_leg_ratio: float = 0.5
@export_range(0.0, 60.0, 1.0) var maximum_standing_slope_degrees: float = 45.0
@export_range(0.0, 1.0, 0.01) var standing_contact_confirmation_time: float = 0.1
@export_flags_3d_physics var ground_collision_mask: int = 1
@export_group("Landing Transition")
@export_range(0.0, 3.0, 0.05) var landing_transition_time: float = 0.5
@export_range(10.0, 720.0, 5.0) var joint_limit_recovery_speed_degrees: float = 180.0
@export_range(0.0, 20.0, 1.0) var joint_limit_safety_margin_degrees: float = 5.0
@export_group("Airborne Leg Pose")
@export_range(0.1, 5.0, 0.1) var leg_fold_time: float = 0.6
## Fraction of the initial vertical distance lifted toward the leg's own supporting Torso.
@export_range(0.0, 0.9, 0.01) var leg_tuck_height_ratio: float = 0.65
## Minimum gap below the support shell, as a fraction of its height.
@export_range(0.0, 1.0, 0.01) var leg_tuck_clearance_ratio: float = 0.1
@export_range(0.0, 200.0, 0.1) var leg_position_strength: float = 40.0
@export_range(0.0, 50.0, 0.1) var leg_position_damping: float = 12.0
@export_range(0.0, 10000.0, 1.0) var maximum_leg_tuck_force: float = 2000.0
@export_range(0.0, 100.0, 0.1) var pose_strength: float = 30.0
@export_range(0.0, 50.0, 0.1) var pose_damping: float = 10.0
## Desired angular acceleration, converted through the foot/support inertia tensors.
@export_range(0.0, 500.0, 1.0, "or_greater") var maximum_leg_pose_acceleration: float = 100.0
@export_range(0.0, 10000.0, 1.0) var maximum_pose_torque: float = 1000.0
@export var diagnostic_logging_enabled: bool = false
var _diagnostic_tracking := false
var _last_command: Dictionary = {}
var state: State = State.GROUNDED
var _character_enabled := true
var _parts: Array[PhysicalBodyPart3D] = []
var _legs: Array[Dictionary] = []
var _joints: Array[Dictionary] = []
var _excluded: Array[RID] = []
var _torso: PhysicalBodyPart3D
var _movement: Node
var _landing_transition := false
var _landing_elapsed := 0.0
var _elapsed := 0.0
var _fold_ratio := 0.0
var _initial_state_pending := true
var _standing_contact_elapsed := 0.0

func _ready() -> void:
	add_to_group(&"bird_physics_diagnostics")
	var console := get_node_or_null("/root/RuntimeConsole")
	if console != null: _diagnostic_tracking = console.is_bird_physics_tracking_enabled()
	process_physics_priority = -10
	refresh_physics_query_cache()

func _alive(body: PhysicalBodyPart3D) -> bool:
	return is_instance_valid(body) and not body.is_broken and not body.is_queued_for_deletion()

func is_airborne() -> bool:
	return enabled and _character_enabled and state == State.AIRBORNE and _alive(_torso) and not get_parent().is_planar_mode_active()

func set_character_control_enabled(value: bool) -> void:
	_character_enabled = value
	if not value:
		_set_state(State.GROUNDED)
		_landing_transition = false
		_restore_ground_limits()

func refresh_physics_query_cache() -> void:
	_landing_transition = false
	_landing_elapsed = 0.0
	_parts.clear(); _legs.clear(); _joints.clear(); _excluded.clear()
	_torso = null
	state = State.GROUNDED
	_elapsed = 0.0
	_fold_ratio = 0.0
	_initial_state_pending = true
	_standing_contact_elapsed = 0.0
	_character_enabled = true
	_movement = get_parent().get_node_or_null("GeneratedLegStepMovementController3D")
	var container := get_parent().get_node_or_null("GeneratedParts")
	if container == null: return
	for node: Node in container.get_children():
		var body := node as PhysicalBodyPart3D
		if not _alive(body): continue
		_parts.append(body)
		_excluded.append(body.get_rid())
		if _torso == null and PhysicalBodyPart3D.BodyPartTag.Torso in body.tags: _torso = body
	if _torso == null: return
	for body: PhysicalBodyPart3D in _parts:
		if PhysicalBodyPart3D.BodyPartTag.Leg in body.tags:
			var size: Vector3 = body.get_meta("generated_size", Vector3.ONE)
			_legs.append({"body":body,"rest_sole":_torso.global_transform.affine_inverse()*(body.global_position-Vector3.UP*size.y*0.5),"half_height":size.y*0.5,"lock_z":body.axis_lock_angular_z})
	for node: Node in container.find_children("*","Generic6DOFJoint3D",true,false):
		var joint := node as Generic6DOFJoint3D
		var a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
		var b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
		if not _alive(a) or not _alive(b): continue
		var foot := PhysicalBodyPart3D.BodyPartTag.Leg in b.tags
		if not foot and PhysicalBodyPart3D.BodyPartTag.LegLimb not in b.tags: continue
		_joints.append({"joint":joint,"a":a,"b":b,
			"lower":joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),"upper":joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)})
	for leg: Dictionary in _legs:
		var queue: Array[PhysicalBodyPart3D] = [leg.body]
		var visited: Dictionary = {leg.body:true}
		var mass := 0.0
		while not queue.is_empty():
			var body: PhysicalBodyPart3D = queue.pop_front()
			if PhysicalBodyPart3D.BodyPartTag.Torso in body.tags:
				leg["support"] = body
				leg["rest_center"] = body.global_transform.affine_inverse()*leg.body.global_position
				leg["rest_rotation"] = body.global_basis.orthonormalized().get_rotation_quaternion().inverse()*leg.body.global_basis.orthonormalized().get_rotation_quaternion()
				break
			mass += body.mass
			for binding: Dictionary in _joints:
				var other: PhysicalBodyPart3D = binding.b if binding.a == body else (binding.a if binding.b == body else null)
				if other != null and not visited.has(other):
					visited[other] = true
					queue.append(other)
		leg["chain_mass"] = mass

func _set_state(next: State, reason: String = "control_disabled") -> void:
	if next == state: return
	var previous := state
	var before := get_flight_diagnostics() if _diagnostic_tracking else {}
	state = next
	_initial_state_pending = false
	_elapsed = 0.0
	_standing_contact_elapsed = 0.0
	_landing_transition = next == State.GROUNDED and reason == "confirmed_foot_contacts" and enabled and _character_enabled
	_landing_elapsed = 0.0
	for leg: Dictionary in _legs:
		if _alive(leg.body): leg.body.axis_lock_angular_z = false if next == State.AIRBORNE or _landing_transition else leg.lock_z
	if is_instance_valid(_movement):
		if next == State.AIRBORNE:
			_movement.cancel_step(&"flight")
			_movement.release_all_support_pins()
			_movement._release_all_foot_heading_locks()
		elif _character_enabled:
			_movement.resume_ground_after_flight()
			var recovery := get_parent().get_node_or_null("CreatureRecoveryStateMachine3D")
			if recovery != null: recovery.resume_ground_after_flight()
	for binding: Dictionary in _joints:
		if not is_instance_valid(binding.joint) or _landing_transition: continue
		binding.joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,-PI if next == State.AIRBORNE else binding.lower)
		binding.joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,PI if next == State.AIRBORNE else binding.upper)
	if diagnostic_logging_enabled: print("[bird_flight] character=",get_parent().name," from=",State.keys()[previous]," to=",State.keys()[next])
	if _diagnostic_tracking:
		print("[bird_flight_transition] character=",get_parent().get_path()," physics_frame=",Engine.get_physics_frames()," time_ms=",Time.get_ticks_msec()," from=",State.keys()[previous]," to=",State.keys()[next]," reason=",reason," before=",before," after=",get_flight_diagnostics())
	state_changed.emit(previous,next)

func _ground_clearance(use_rest_pose: bool = true) -> float:
	var clearance := INF
	var space := get_world_3d().direct_space_state
	var soles: Array[Vector3] = []
	for leg: Dictionary in _legs:
		if not _alive(leg.body): continue
		var sole: Vector3 = _torso.global_transform*leg.rest_sole if state == State.AIRBORNE and use_rest_pose else leg.body.global_position-Vector3.UP*leg.half_height
		soles.append(sole)
	# Contact by the body also counts as a landing, so a partially deployed or
	# damaged leg cannot leave the bird pushing downward forever on the ground.
	if state == State.GROUNDED or not use_rest_pose:
		for body: PhysicalBodyPart3D in _parts:
			if not _alive(body) or PhysicalBodyPart3D.BodyPartTag.Torso not in body.tags: continue
			var size: Vector3 = body.get_meta("generated_size",Vector3.ONE)
			var half_height := (absf(body.global_basis.x.y)*size.x+absf(body.global_basis.y.y)*size.y+absf(body.global_basis.z.y)*size.z)*0.5
			soles.append(body.global_position-Vector3.UP*half_height)
	for sole: Vector3 in soles:
		# A virtual unfolded sole may already be below terrain while the leg deploys.
		# Start above the torso so that this cannot turn a nearby ground hit into INF.
		var start := Vector3(sole.x,maxf(sole.y,_torso.global_position.y)+2.0,sole.z)
		var query := PhysicsRayQueryParameters3D.create(start,sole+Vector3.DOWN*1000.0,ground_collision_mask,_excluded)
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and Vector3(hit.normal).dot(Vector3.UP)>0.5: clearance = minf(clearance,sole.y-Vector3(hit.position).y)
	return clearance

func _physics_process(delta: float) -> void:
	if not enabled or not _character_enabled or not _alive(_torso) or get_parent().is_planar_mode_active():
		if state == State.AIRBORNE: _set_state(State.GROUNDED)
		if _landing_transition:
			_landing_transition = false
			_restore_ground_limits()
		return
	var ascend := InputMap.has_action(ascend_action) and PLAYER_CONTEXT.action_pressed(self,ascend_action)
	var descend := InputMap.has_action(descend_action) and PLAYER_CONTEXT.action_pressed(self,descend_action) and not ascend
	var clearance := _ground_clearance()
	_elapsed += delta
	if state == State.GROUNDED:
		if ascend or (_initial_state_pending and clearance>initial_ground_clearance*3.0 and _elapsed>=airborne_confirmation_time): _set_state(State.AIRBORNE, "ascend_input" if ascend else "initial_air_spawn")
		else:
			if _elapsed>=airborne_confirmation_time: _initial_state_pending = false
			_update_landing_transition(delta)
			return
	_standing_contact_elapsed = _standing_contact_elapsed+delta if descend and has_standing_leg_contacts() else 0.0
	if descend and _elapsed>0.3 and _standing_contact_elapsed>=maxf(standing_contact_confirmation_time,delta):
		_set_state(State.GROUNDED, "confirmed_foot_contacts")
		_fold_ratio = 0.0
		return
	var direction: Vector3 = _movement.get_input_movement_direction() if is_instance_valid(_movement) else Vector3.ZERO
	var target_velocity := direction.slide(Vector3.UP).limit_length(1.0)*horizontal_speed
	target_velocity.y = ascent_speed if ascend else (-descent_speed if descend else 0.0)
	var acceleration := ((target_velocity-_torso.linear_velocity)*velocity_response).limit_length(maximum_acceleration)
	if _diagnostic_tracking:
		_last_command = {"frame":Engine.get_physics_frames(),"target_velocity":target_velocity,"acceleration":acceleration,"clearance":clearance,"ascend":ascend,"descend":descend,"submitted_force_total":Vector3.ZERO,"gravity_compensation_total":Vector3.ZERO,"torso_torque_total":Vector3.ZERO}
	for body: PhysicalBodyPart3D in _parts:
		if not _alive(body) or body.freeze or body.custom_integrator: continue
		var direct := PhysicsServer3D.body_get_direct_state(body.get_rid())
		if direct == null: continue
		body.apply_central_force((acceleration-direct.total_gravity)*body.mass)
		if _diagnostic_tracking:
			_last_command["submitted_force_total"] += (acceleration-direct.total_gravity)*body.mass
			_last_command["gravity_compensation_total"] += -direct.total_gravity*body.mass
		if PhysicalBodyPart3D.BodyPartTag.Torso in body.tags:
			var correction := body.global_basis.y.normalized().cross(Vector3.UP)*pose_strength-body.angular_velocity.slide(Vector3.UP)*pose_damping
			body.apply_torque((correction*body.mass).limit_length(maximum_pose_torque))
			if _diagnostic_tracking: _last_command["torso_torque_total"] += (correction*body.mass).limit_length(maximum_pose_torque)
	# Ctrl deploys the legs regardless of altitude; actual foot contacts decide landing.
	var fold_target := 0.0 if descend else 1.0
	_fold_ratio = move_toward(_fold_ratio,fold_target,delta/maxf(leg_fold_time,0.1))
	_apply_leg_tuck(delta)

func get_leg_tuck_target(leg: Dictionary) -> Vector3:
	var support: PhysicalBodyPart3D = leg.support
	var rest: Vector3 = leg.rest_center
	var size: Vector3 = support.get_meta("generated_size",Vector3.ONE)
	var minimum_depth := size.y*(0.5+leg_tuck_clearance_ratio)+float(leg.half_height)
	var raised_y := minf(rest.y*(1.0-leg_tuck_height_ratio),-minimum_depth)
	var offset := Vector3(rest.x,lerpf(rest.y,raised_y,_fold_ratio),rest.z)
	return support.global_transform*offset

func _apply_leg_tuck(delta: float) -> void:
	for leg: Dictionary in _legs:
		var foot: PhysicalBodyPart3D = leg.body
		var support: PhysicalBodyPart3D = leg.get("support")
		if not _alive(foot) or not _alive(support) or foot.freeze: continue
		var target := get_leg_tuck_target(leg)
		var target_velocity := support.linear_velocity+support.angular_velocity.cross(target-support.global_position)
		var acceleration := ((target-foot.global_position)*leg_position_strength+(target_velocity-foot.linear_velocity)*leg_position_damping).limit_length(60.0)
		var force := (acceleration*float(leg.chain_mass)).limit_length(maximum_leg_tuck_force)
		foot.apply_central_force(force)
		if not support.freeze: support.apply_central_force(-force)
		# Keep the sole facing down instead of twisting it sideways while raising it.
		var desired: Quaternion = support.global_basis.orthonormalized().get_rotation_quaternion()*leg.rest_rotation
		var error := desired*foot.global_basis.orthonormalized().get_rotation_quaternion().inverse()
		if error.w<0.0: error = -error
		var pose := _calculate_leg_pose_command(foot, support, error, delta)
		var torque: Vector3 = pose.torque
		if _diagnostic_tracking:
			leg["command"] = {"frame":Engine.get_physics_frames(),"target":target,"position_error":target-foot.global_position,"target_velocity":target_velocity,"force":force,"reaction_on_support":-force if not support.freeze else Vector3.ZERO,"torque":torque,"orientation_error_degrees":rad_to_deg(error.get_angle()),"force_capped":force.length()>=maximum_leg_tuck_force-0.001,"pose_acceleration":pose.acceleration,"pose_torque_capped":pose.torque_capped,"pose_acceleration_capped":pose.acceleration_capped,"pose_step_denominator":pose.step_denominator,"pose_inertia_valid":pose.inertia_valid}
		foot.apply_torque(torque)
		if not support.freeze: support.apply_torque(-torque)

func _calculate_leg_pose_command(foot: RigidBody3D, support: RigidBody3D, error: Quaternion, delta: float) -> Dictionary:
	# Implicit PD gains keep the damping term from reversing angular velocity
	# multiple times per physics step when gains or the timestep are increased.
	var dt := maxf(delta, 0.000001)
	var stiffness := maxf(pose_strength, 0.0)
	var damping := maxf(pose_damping, 0.0)
	var denominator := 1.0 + damping*dt + stiffness*dt*dt
	var requested := (error.get_axis()*error.get_angle()*stiffness
		+ (support.angular_velocity-foot.angular_velocity)*(damping+stiffness*dt))/denominator
	# Body axis locks are world-space constraints. Do not push against a locked
	# foot axis or transmit its impossible correction to the supporting Torso.
	var mask := Vector3(0.0 if foot.axis_lock_angular_x else 1.0,
		0.0 if foot.axis_lock_angular_y else 1.0, 0.0 if foot.axis_lock_angular_z else 1.0)
	requested *= mask
	var acceleration := requested.limit_length(maxf(maximum_leg_pose_acceleration, 0.0))
	var inverse := foot.get_inverse_inertia_tensor()
	if not support.freeze:
		var parent_inverse := support.get_inverse_inertia_tensor()
		inverse = Basis(inverse.x+parent_inverse.x, inverse.y+parent_inverse.y, inverse.z+parent_inverse.z)
	# Solve only the free-axis submatrix; locked rows get an identity diagonal.
	for axis: int in range(3):
		inverse[axis] = inverse[axis]*mask*mask[axis]
		if mask[axis] == 0.0: inverse[axis][axis] = 1.0
	var valid := inverse.is_finite() and absf(inverse.determinant()) > 0.000000000001
	var uncapped := (inverse.inverse()*acceleration)*mask if valid else Vector3.ZERO
	if not uncapped.is_finite(): valid = false; uncapped = Vector3.ZERO
	return {"torque":uncapped.limit_length(maxf(maximum_pose_torque, 0.0)),
		"acceleration":acceleration,"torque_capped":uncapped.length()>maximum_pose_torque,
		"acceleration_capped":requested.length()>maximum_leg_pose_acceleration,
		"step_denominator":denominator,"inertia_valid":valid}

func has_standing_leg_contacts() -> bool:
	var available := 0
	var standing := 0
	var minimum_up := cos(deg_to_rad(maximum_standing_slope_degrees))
	for leg: Dictionary in _legs:
		var foot: PhysicalBodyPart3D = leg.body
		if not _alive(foot) or not _alive(leg.get("support")): continue
		available += 1
		if foot.global_basis.y.normalized().dot(Vector3.UP)<minimum_up: continue
		var direct := PhysicsServer3D.body_get_direct_state(foot.get_rid())
		if direct == null: continue
		for index: int in range(direct.get_contact_count()):
			var collider := direct.get_contact_collider_object(index) as PhysicsBody3D
			if collider == null or _excluded.has(collider.get_rid()) or collider.collision_layer & ground_collision_mask == 0: continue
			if direct.get_contact_local_normal(index).dot(Vector3.UP)>=minimum_up:
				standing += 1
				break
	return available>0 and standing>=maxi(1,ceili(available*minimum_standing_leg_ratio))

func set_diagnostic_tracking_enabled(value: bool) -> void:
	_diagnostic_tracking = value
	_last_command.clear()
	for leg: Dictionary in _legs: leg.erase("command")

func get_flight_diagnostics() -> Dictionary:
	var rows: Array[Dictionary] = []
	var minimum_up := cos(deg_to_rad(maximum_standing_slope_degrees))
	for leg: Dictionary in _legs:
		var foot: PhysicalBodyPart3D = leg.body
		if not _alive(foot): continue
		var contacts: Array[Dictionary] = []
		var direct := PhysicsServer3D.body_get_direct_state(foot.get_rid())
		if direct != null:
			for index: int in range(direct.get_contact_count()):
				var collider := direct.get_contact_collider_object(index) as PhysicsBody3D
				if not is_instance_valid(collider): continue
				var normal := direct.get_contact_local_normal(index)
				contacts.append({"collider":str(collider.get_path()),"normal":normal,"ground_eligible":not _excluded.has(collider.get_rid()) and collider.collision_layer & ground_collision_mask != 0 and normal.dot(Vector3.UP)>=minimum_up})
		var row := {"foot":str(foot.name),"position":foot.global_position,"velocity":foot.linear_velocity,"sole_up_dot":foot.global_basis.y.normalized().dot(Vector3.UP),"lock_z":foot.axis_lock_angular_z,"contacts":contacts,"command":leg.get("command",{}),"command_age_frames":Engine.get_physics_frames()-int(leg.get("command",{}).get("frame",Engine.get_physics_frames()))}
		if _alive(leg.get("support")):
			row["support"] = str(leg.support.name)
			row["rest_center"] = leg.rest_center
			row["actual_relative_center"] = leg.support.global_transform.affine_inverse()*foot.global_position
			row["tuck_target"] = get_leg_tuck_target(leg)
		if is_instance_valid(_movement) and _movement._chains.has(foot):
			var chain: Dictionary = _movement._chains[foot]
			row["cached_chain_length"] = chain.length
			row["cached_anchor"] = chain.anchor
			var geometry_length := 0.0
			for body: PhysicalBodyPart3D in chain.bodies:
				if _alive(body) and PhysicalBodyPart3D.BodyPartTag.LegLimb in body.tags:
					var size: Vector3 = body.get_meta("generated_size",Vector3.ONE)
					geometry_length += size.y
			row["limb_geometry_length"] = geometry_length
		rows.append(row)
	var joints: Array[Dictionary] = []
	for binding: Dictionary in _joints:
		if not is_instance_valid(binding.joint) or not _alive(binding.a) or not _alive(binding.b): continue
		joints.append({"joint":str(binding.joint.name),"a":str(binding.a.name),"b":str(binding.b.name),"visual_position":binding.joint.global_position,"distance_to_a":binding.joint.global_position.distance_to(binding.a.global_position),"distance_to_b":binding.joint.global_position.distance_to(binding.b.global_position),"z_lower":binding.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),"z_upper":binding.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)})
	return {"state":State.keys()[state],"airborne":is_airborne(),"enabled":enabled,"character_enabled":_character_enabled,"elapsed":_elapsed,"fold_ratio":_fold_ratio,"standing_contact_elapsed":_standing_contact_elapsed,"landing_transition":_landing_transition,"landing_elapsed":_landing_elapsed,"ground_control_blend":get_ground_control_blend(),"contact_confirmation_required":standing_contact_confirmation_time,"gait_paused_by_flight":is_airborne(),"recovery_paused_by_flight":is_airborne(),"standing_contacts":has_standing_leg_contacts(),"minimum_standing_ratio":minimum_standing_leg_ratio,"raw_space":InputMap.has_action(ascend_action) and Input.is_action_pressed(ascend_action),"raw_ctrl":InputMap.has_action(descend_action) and Input.is_action_pressed(descend_action),"gated_space":InputMap.has_action(ascend_action) and PLAYER_CONTEXT.action_pressed(self,ascend_action),"gated_ctrl":InputMap.has_action(descend_action) and PLAYER_CONTEXT.action_pressed(self,descend_action),"force_semantics":"submitted commands, not solver impulses; only active in AIRBORNE","last_command":_last_command,"command_age_frames":Engine.get_physics_frames()-int(_last_command.get("frame",Engine.get_physics_frames())),"legs":rows,"joints":joints}

func get_ground_control_blend() -> float:
	if not enabled or not _character_enabled or get_parent().is_planar_mode_active(): return 1.0
	if is_airborne(): return 0.0
	return clampf(_landing_elapsed/maxf(landing_transition_time,0.001),0.0,1.0) if _landing_transition else 1.0

func _restore_ground_limits() -> void:
	for binding: Dictionary in _joints:
		if not is_instance_valid(binding.joint): continue
		binding.joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,binding.lower)
		binding.joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,binding.upper)
	for leg: Dictionary in _legs:
		if _alive(leg.body): leg.body.axis_lock_angular_z = leg.lock_z

func _update_landing_transition(delta: float) -> void:
	if not _landing_transition: return
	_landing_elapsed += delta
	var complete := get_ground_control_blend() >= 1.0
	var speed := deg_to_rad(joint_limit_recovery_speed_degrees)*delta
	var margin := deg_to_rad(joint_limit_safety_margin_degrees)
	for binding: Dictionary in _joints:
		var joint: Generic6DOFJoint3D = binding.joint
		if not is_instance_valid(joint) or not _alive(binding.a) or not _alive(binding.b): continue
		var frame_a: Transform3D = joint.get_meta(&"generated_joint_frame_a",binding.a.global_transform.affine_inverse()*joint.global_transform)
		var frame_b: Transform3D = joint.get_meta(&"generated_joint_frame_b",binding.b.global_transform.affine_inverse()*joint.global_transform)
		var relative: Basis = (binding.a.global_basis*frame_a.basis).orthonormalized().inverse()*(binding.b.global_basis*frame_b.basis).orthonormalized()
		var angle := -atan2(relative.x.y,relative.x.x)
		var lower := move_toward(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),minf(binding.lower,angle-margin),speed)
		var upper := move_toward(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT),maxf(binding.upper,angle+margin),speed)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,lower)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,upper)
		complete = complete and is_equal_approx(lower,binding.lower) and is_equal_approx(upper,binding.upper)
	for leg: Dictionary in _legs:
		if not _alive(leg.body): continue
		if get_ground_control_blend()>=1.0 and absf(leg.body.angular_velocity.z)<0.5:
			leg.body.axis_lock_angular_z = leg.lock_z
		elif leg.lock_z: complete = false
	if complete:
		_landing_transition = false
		if _diagnostic_tracking: print("[bird_landing_settled] character=",get_parent().get_path()," physics_frame=",Engine.get_physics_frames()," elapsed=",_landing_elapsed)
