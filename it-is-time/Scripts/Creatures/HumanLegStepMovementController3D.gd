extends "res://Scripts/Creatures/GeneratedLegStepMovementController3D.gd"

@export_group("Human Limb Pose")
@export var human_limb_pose_enabled: bool = true
@export_range(0.0, 5.0, 0.1) var human_pose_frequency: float = 3.0
@export_range(0.0, 3.0, 0.1) var human_pose_damping_ratio: float = 1.1
@export_range(0.0, 400.0, 1.0) var human_pose_acceleration_limit: float = 80.0
@export_range(0.0, 1000.0, 1.0) var human_pose_torque_limit: float = 40.0
@export_range(0.0, 1.0, 0.05) var human_moving_pose_weight: float = 0.2
@export_range(0.0, 1.0, 0.05) var human_swing_knee_weight: float = 0.35
var _human_pose := preload("res://Scripts/Creatures/HumanLimbPose3D.gd").new()

@export_group("Human Speed Control")
@export var human_speed_compensation_enabled: bool = true
@export_range(0.0, 10.0, 0.1) var human_speed_integral_gain: float = 1.5
var _human_speed_integral := 0.0
var _human_speed_target := Vector3.ZERO
var _human_speed_frame := -1
var _human_traction_saturated := false

func refresh_physics_query_cache() -> void:
	_human_speed_integral = 0.0
	_human_speed_target = Vector3.ZERO
	_human_speed_frame = -1
	_human_traction_saturated = false
	super.refresh_physics_query_cache()
	_human_pose.capture(self)

func uses_passive_limb_links() -> bool:
	return not human_limb_pose_enabled or recovery_control_active or _planar_mode_active()

func _apply_passive_limb_damping() -> void:
	if uses_passive_limb_links(): super._apply_passive_limb_damping()
	else: _passive_hinge_rows.clear()

func _apply_stance_stabilization(delta: float) -> void:
	super._apply_stance_stabilization(delta)
	_human_pose.apply(self, delta)

func get_stance_support_diagnostics() -> Dictionary:
	var result := super.get_stance_support_diagnostics()
	var age := Engine.get_physics_frames()-_human_pose.frame
	result["passive_limb_links"] = uses_passive_limb_links()
	result["human_limb_pose"] = {"enabled":human_limb_pose_enabled, "age_frames":age, "joints":_human_pose.rows if age <= 1 else []}
	return result

func _update_layout_turn_steps(delta: float) -> void:
	if _segment_heading_initialized and absf(wrapf(_segment_goal_yaw-_get_physical_heading_yaw(),-PI,PI)) > deg_to_rad(30.0): _turn_command_pending = true
	if _turn_command_pending or recovery_control_active or _planar_mode_active() or not _action_feet.is_empty():
		super._update_layout_turn_steps(delta)
		return
	# Wolf's walking correction keeps ownership of the walking sequence.
	if _layout_turn_owned: set_turn_planning_active(false)
	_layout_turn_owned = false
	_layout_turn_status = &"heading_correction"
	_turn_leg_forces.clear()
	_turn_drive_diagnostics = {"blocked": &"correction_disabled"}
	if segment_layout_enabled and segment_layout_turn_steps_enabled and _motion_setting("turning_speed_degrees",segment_heading_speed_degrees) > 0.0:
		_apply_grounded_turn_traction()

func _turn_traction_control(error: float, actual_rate: float, limit_rate: float) -> Dictionary:
	if _turn_command_pending: return super._turn_traction_control(error, actual_rate, limit_rate)
	var rate_limit := minf(limit_rate, deg_to_rad(30.0))
	var requested := clampf(error*3.0, -rate_limit, rate_limit)
	return {"mode":"heading_correction", "requested_rate":requested, "acceleration":clampf((requested-actual_rate)*8.0,-PI,PI)}

func _apply_grounded_turn_traction() -> void:
	# The humanoid turn controller counts the limbs and equipment in yaw inertia.
	var root_body := get_node_or_null(torso_path) as RigidBody3D
	var base_scale := turn_effective_inertia_scale
	if is_instance_valid(root_body):
		var torso_inverse := _stance_inverse_inertia(root_body)
		var torso_inertia := Vector3.UP.dot(torso_inverse.inverse()*Vector3.UP) if absf(torso_inverse.determinant()) > 1e-18 else 0.0
		var total := 0.0
		for body: RigidBody3D in _character_body_cache:
			if not is_instance_valid(body) or _is_body_broken(body): continue
			var inverse := _stance_inverse_inertia(body)
			if absf(inverse.determinant()) < 1e-18: continue
			total += Vector3.UP.dot(inverse.inverse()*Vector3.UP)+body.mass*(body.global_position-root_body.global_position).slide(Vector3.UP).length_squared()
		if torso_inertia > 0.0001: turn_effective_inertia_scale = maxf(base_scale, total/torso_inertia)
	super._apply_grounded_turn_traction()
	turn_effective_inertia_scale = base_scale

func _apply_turn_swing_orientation() -> void:
	# A walking foot also needs the shared facing frame before planting again.
	if _segment_heading_initialized and not recovery_control_active:
		_current_step.extra["turn_swing_yaw"] = _segment_target_yaw
	super._apply_turn_swing_orientation()

func get_leg_motion_profile(leg: RigidBody3D) -> Dictionary:
	var profile := super.get_leg_motion_profile(leg)
	if not profile.is_empty() and _turn_command_pending:
		# Short turn steps use the configured cadence budget instead of a full walking cycle.
		var frequency := _get_gait_data().maximum_step_frequency
		if frequency>0.0:
			profile.total_frequency = frequency
			profile.cycle = float(_legs.size())/frequency
	return profile

func _begin_leg_motion(leg: RigidBody3D, target: Vector3, normal: Vector3 = Vector3.UP, direction: Vector3 = Vector3.ZERO) -> void:
	super._begin_leg_motion(leg, target, normal, direction)
	var data := _get_gait_data()
	if data == null or not data.automatic_motion or _gallop_active(): return
	_active_step_duration = maxf(_active_step_duration, (target-leg.global_position).slide(Vector3.UP).length()/maxf(data.target_speed*3.0,1.0))
	var profile: Dictionary = _current_step.extra.get("automatic_profile",{})
	if profile.is_empty(): return
	profile.position_gain = clampf(16.0/(_active_step_duration*_active_step_duration),20.0,4000.0)
	profile.velocity_gain = 2.0*sqrt(profile.position_gain)
	profile.step_acceleration = clampf(8.0*maxf((target-leg.global_position).length(),_get_effective_step_height())/(_active_step_duration*_active_step_duration)+9.8,30.0,2000.0)
	_current_step.extra["human_swing_duration"] = _active_step_duration

func _is_landing_point_valid(leg: RigidBody3D, current_foot: Vector3, hit: Dictionary) -> bool:
	if not super._is_landing_point_valid(leg,current_foot,hit): return false
	var ankle := _body_position_for_ground_contact(leg,hit.position)+leg.global_basis*_human_pose._frame(_chains[leg].joints[0],leg).origin
	if not _human_pose.KNEE.solve(_chains[leg],ankle,_human_landing_prediction()).reachable:
		_last_landing_rejection_reason = &"human_joint_reach_exceeded"
		return false
	return true

func _human_landing_prediction() -> Vector3:
	if _turn_command_pending or _turn_planning_active: return Vector3.ZERO
	var direction := get_input_movement_direction().limit_length(1.0)
	var speed := get_expected_horizontal_speed()
	if is_instance_valid(_torso) and absf(direction.dot(_torso.global_basis.z))>0.5:
		speed = clampf(_torso.linear_velocity.dot(direction),0.0,speed)
	return direction*speed*(_motion_setting("swing_duration",slow_step_duration)+0.05)

func _landing_reach_attachment(leg: RigidBody3D) -> Vector3:
	return super._landing_reach_attachment(leg)+_human_landing_prediction()

func _get_projected_landing_rest_position(leg: RigidBody3D, direction: Vector3) -> Vector3:
	var rest := super._get_projected_landing_rest_position(leg,direction)
	if not _chains.has(leg) or not _chains[leg].has("human_knee"): return rest
	var chain: Dictionary = _chains[leg]
	var hip := _landing_reach_attachment(leg)
	var offset := leg.global_basis*_human_pose._frame(chain.joints[0],leg).origin
	var length: float = chain.human_knee.upper_length+chain.human_knee.lower_length
	var drop := hip.y-rest.y-offset.y
	var reach := sqrt(maxf(length*length-drop*drop,0.0))*0.55
	var local_lead: Vector3 = chain.root.global_basis.inverse()*(direction*reach)
	var hip_joint: Generic6DOFJoint3D = chain.joints[2]
	var lateral_reach := float(chain.human_knee.upper_length)*sin(absf(hip_joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)))*0.5
	local_lead.z = clampf(local_lead.z,-lateral_reach,lateral_reach)
	if absf(direction.dot(chain.root.global_basis.z))>0.5:
		var local_rest: Vector3 = chain.root.global_basis.inverse()*(rest+offset-hip)
		local_lead.x = clampf(local_rest.x,-reach,reach)
	var desired: Vector3 = hip-offset+chain.root.global_basis*local_lead
	desired.y = rest.y
	# The shared ray sampler adds stride; its first sample is the reachable leading point.
	return desired-direction*get_leg_step_distance(leg)

func _contact_velocity_force(velocity: Vector3, mass: float, up: Vector3) -> Vector3:
	var force := super._contact_velocity_force(velocity,mass,up)
	if mass<=0.001: return force
	var target: Vector3 = _contact_drive_diagnostics.get("target_velocity",Vector3.ZERO)
	var swing := get_parent().get_node_or_null("LimbSwingController3D")
	var attacking := false
	if swing != null:
		for link: Dictionary in _human_pose._arms:
			if not is_instance_valid(link.child): continue
			if link.child.has_meta(&"equipment_bow_pose_driver"):
				var bow_driver: Variant = link.child.get_meta(&"equipment_bow_pose_driver")
				if is_instance_valid(bow_driver) and bow_driver.is_npc_attack_active(): attacking = true; break
			elif swing.is_body_driven(link.child): attacking = true; break
	var supported := not _contact_drive_supports(get_leg_parts()).is_empty()
	var charge := get_parent().get_node_or_null("ChargeAttackController3D")
	var charge_owns: bool = charge != null and charge.owns_velocity()
	var enabled := human_speed_compensation_enabled and input_enabled and not target.is_zero_approx() and supported and not recovery_control_active and not _planar_mode_active() and not _turn_command_pending and not _turn_planning_active and _action_owners.is_empty() and not attacking and not charge_owns and _startup_drive_blend>=0.99
	if not enabled or (target-_human_speed_target).length()>0.5: _human_speed_integral = 0.0
	var direction := target.normalized()
	var error := (target-velocity.slide(up)).dot(direction)
	var cap := _motion_setting("contact_acceleration",contact_maximum_acceleration)
	var saturated := (force/mass+direction*_human_speed_integral).length()>=cap*0.99 or _human_traction_saturated
	if enabled and _human_speed_frame != Engine.get_physics_frames():
		if not saturated or error*_human_speed_integral<0.0:
			_human_speed_integral = clampf(_human_speed_integral+error*human_speed_integral_gain*_support_delta,-cap*0.5,cap*0.5)
	_human_speed_frame = Engine.get_physics_frames()
	_human_speed_target = target
	_contact_drive_diagnostics["human_speed_control"] = {"enabled":enabled,"grounded":supported,"attacking":attacking,"error":error,"integral_acceleration":_human_speed_integral,"saturated":saturated}
	return (force/mass+direction*_human_speed_integral).limit_length(cap)*mass if enabled else force

func is_fast_speed_active() -> bool:
	var source := get_player_command_source()
	if source != null:
		if source.has_method("is_fast_requested"): return source.is_fast_requested()
		return source.is_fast_movement_requested() if source.has_method("is_fast_movement_requested") else false
	return PLAYER_CONTEXT.input_allowed(self) and Input.is_action_pressed("Shift")

func _get_expected_horizontal_speed() -> float:
	var speed := super._get_expected_horizontal_speed()
	var source := get_player_command_source()
	return speed * source.get_npc_movement_speed_scale(speed) if source != null and source.has_method("get_npc_movement_speed_scale") else speed

func try_start_turn_step(leg: RigidBody3D, sample_position: Vector3, duration: float, height: float) -> bool:
	if is_instance_valid(leg) and _chains.has(leg):
		var attachment := _landing_reach_attachment(leg)
		var reach: float = float(_chains[leg].length)*chain_reach_ratio
		var drop := leg.global_position.y-attachment.y
		var radius_squared := reach*reach-drop*drop
		if radius_squared > 0.0:
			# Wide source poses need shorter turn arcs inside the chain's grounded reach.
			var offset := (sample_position-attachment).slide(Vector3.UP)
			var fitted := attachment+offset.limit_length(sqrt(radius_squared)*0.98)
			sample_position.x = fitted.x
			sample_position.z = fitted.z
		var chain: Dictionary = _chains[leg]
		if chain.has("human_knee"):
			var ankle_offset := leg.global_basis*_human_pose._frame(chain.joints[0],leg).origin
			var bone_length: float = chain.human_knee.upper_length+chain.human_knee.lower_length
			var ankle_drop := sample_position.y+ankle_offset.y-attachment.y
			var radius := sqrt(maxf(bone_length*bone_length*0.995-ankle_drop*ankle_drop,0.0))
			var relative := (sample_position+ankle_offset-attachment).slide(Vector3.UP).limit_length(radius)
			var local: Vector3 = chain.root.global_basis.inverse()*(relative+Vector3.UP*ankle_drop)
			var hip: Generic6DOFJoint3D = chain.joints[2]
			var lateral := float(chain.human_knee.upper_length)*sin(absf(hip.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)))*0.8
			local.z = clampf(local.z,-lateral,lateral)
			var clipped: Vector3 = attachment+chain.root.global_basis*local-ankle_offset
			sample_position.x = clipped.x
			sample_position.z = clipped.z
	# Long source poses must not chase a multi-unit turn arc in 0.167 seconds.
	var data := _get_gait_data()
	if is_instance_valid(leg) and data != null: duration = maxf(duration, (sample_position-leg.global_position).slide(Vector3.UP).length()/maxf(data.target_speed*3.0, 1.0))
	return super.try_start_turn_step(leg,sample_position,duration,height)

func _apply_torso_response() -> void:
	super._apply_torso_response()
	_human_traction_saturated = false
	for leg: Dictionary in _contact_drive_diagnostics.get("legs",[]):
		if leg.get("limited",false): _human_traction_saturated = true
	# A single Torso carries the hanging head/arms; feet still authorize every force.
	if _contact_drive_supports(get_leg_parts()).is_empty(): return
	var torso := get_node_or_null(torso_path) as PhysicalBodyPart3D
	if torso == null or torso.is_broken or torso.freeze: return
	var suspended_mass := 0.0
	for part: Node in torso.get_parent().get_children():
		if part is PhysicalBodyPart3D and not part.is_broken and PhysicalBodyPart3D.BodyPartTag.Leg not in part.tags and PhysicalBodyPart3D.BodyPartTag.LegLimb not in part.tags:
			suspended_mass += part.mass
	torso.apply_central_force(-_gravity_acceleration() * suspended_mass)
