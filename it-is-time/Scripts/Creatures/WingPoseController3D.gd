@tool
extends Node3D
## Relative joint posture servo; joint motors or equal/opposite torques, never teleportation.
const PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")
@export var enabled: bool = true
@export var unfold_action: StringName = &"Space"
@export var suppress_jump: bool = true
@export_range(0.05, 5.0, 0.01, "or_greater") var transition_time: float = 0.6
@export_range(0.05, 5.0, 0.05, "or_greater") var fold_transition_time: float = 1.5
@export var hinge_only_pose: bool = true
@export_range(1.0, 3.0, 0.1) var torque_load_factor_limit: float = 1.5
@export_range(0.1, 10.0, 0.1, "or_greater") var posture_frequency: float = 2.0
@export_range(0.0, 3.0, 0.01, "or_greater") var damping_ratio: float = 1.0
@export_range(0.0, 500.0, 1.0, "or_greater") var maximum_angular_acceleration: float = 60.0
@export_range(0.0, 100000.0, 1.0, "or_greater") var maximum_torque: float = 10000.0
## Use actual mass and hinge load instead of an arbitrary feather multiplier.
@export var automatic_load_inertia: bool = true
## Optional absolute safety cap; the normal cap is inertia * maximum angular acceleration.
@export var absolute_torque_limit_enabled: bool = false
## Articulated descendants do not rotate as one rigid body; bound the approximation's gain.
@export_range(1.0, 10.0, 0.1) var maximum_articulated_load_ratio: float = 1.5
## Let the constraint solver apply the servo along the joint's free hinge axis.
@export var joint_motor_pose: bool = true

@export_group("Expanded Wing Shape")
## Additional upward angle at each wing-to-wing joint; the first root keeps its generated angle.
@export_range(0.0, 20.0, 0.1) var segment_elevation_degrees: float = 2.0

@export_group("Flight Sway")
@export var flight_sway_enabled: bool = true
@export_range(0.0, 2.0, 0.01, "or_greater") var flight_sway_frequency: float = 0.25
@export_range(0.0, 30.0, 0.1) var flight_sway_amplitude_degrees: float = 5.0
## Middle lags Root, and Tip lags Middle by this phase angle.
@export_range(0.0, 90.0, 0.1) var flight_sway_phase_difference_degrees: float = 12.0
@export_range(0.0, 10.0, 0.01) var flight_sway_minimum_speed: float = 0.1
@export_range(0.05, 5.0, 0.05) var flight_sway_blend_time: float = 0.8

@export_group("Gravity Compensation")
## Remove each attached wing block's own gravity load; no extra downward force is transferred to Torso.
@export var gravity_compensation_enabled: bool = true
@export_range(0.0, 1.0, 0.01) var gravity_compensation_ratio: float = 1.0

@export_group("Feather Pose")
@export var feather_control_enabled: bool = true
@export_range(0.1, 10.0, 0.1, "or_greater") var feather_posture_frequency: float = 2.0
@export_range(0.0, 3.0, 0.01, "or_greater") var feather_damping_ratio: float = 1.0
@export_range(0.0, 500.0, 1.0, "or_greater") var feather_maximum_angular_acceleration: float = 100.0
@export_range(0.0, 10000.0, 1.0, "or_greater") var feather_maximum_torque: float = 100.0

var _diagnostic_tracking := false
var bindings: Array[Dictionary] = []
var feather_bindings: Array[Dictionary] = []
var _children_by_body: Dictionary = {}
var unfold_ratio: float = 0.0
var _character_enabled: bool = true
var _sway_phase: float = 0.0
var _sway_blend: float = 0.0
var _flight_horizontal_speed: float = 0.0
var _flight_motion_speed: float = 0.0

func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(&"bird_physics_diagnostics")
		var console := get_node_or_null("/root/RuntimeConsole")
		if console != null: _diagnostic_tracking = console.is_bird_physics_tracking_enabled()
	if get_parent().has_signal(&"creature_generation_finished"):
		get_parent().connect(&"creature_generation_finished", _on_generation_finished)
	refresh_physics_query_cache()

func _on_generation_finished(succeeded: bool) -> void:
	if succeeded:
		_character_enabled = true
		# Runtime activation refreshes optional controllers; editor assembly skips activation.
		if Engine.is_editor_hint(): refresh_physics_query_cache()

func set_character_control_enabled(value: bool) -> void:
	_character_enabled = value
	if not value:
		unfold_ratio = 0.0
		_sway_blend = 0.0
		_stop_pose_motors()

func _stop_pose_motors() -> void:
	for links: Array in [bindings,feather_bindings]:
		for binding: Dictionary in links:
			if is_instance_valid(binding.joint): binding.joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR,false)

func _alive(body: PhysicalBodyPart3D) -> bool:
	return is_instance_valid(body) and not body.is_queued_for_deletion() and not body.is_broken

func _planar_active() -> bool:
	var actor := get_parent()
	return actor != null and actor.has_method("is_planar_mode_active") and actor.is_planar_mode_active()

func refresh_physics_query_cache() -> void:
	_stop_pose_motors()
	bindings.clear()
	feather_bindings.clear()
	_children_by_body.clear()
	unfold_ratio = 0.0
	_sway_phase = 0.0
	_sway_blend = 0.0
	_flight_horizontal_speed = 0.0
	_flight_motion_speed = 0.0
	var container := get_parent().get_node_or_null("GeneratedParts")
	if container == null: return
	for node: Node in container.find_children("*", "Generic6DOFJoint3D", true, false):
		if not node.has_meta(&"wing_open_relative_a") and not node.has_meta(&"feather_open_relative_a"): continue
		if node.is_queued_for_deletion(): continue
		var joint := node as Generic6DOFJoint3D
		var a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
		var b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
		if not _alive(a) or not _alive(b): continue
		if joint.has_meta(&"feather_open_relative_a"):
			feather_bindings.append({"joint":joint,"a":a,"b":b,"open":joint.get_meta(&"feather_open_relative_a")})
			continue
		bindings.append({"joint": joint, "a": a, "b": b,
			"closed": joint.get_meta(&"generated_rest_b_relative_a"), "open": joint.get_meta(&"wing_open_relative_a")})
	for links: Array in [bindings,feather_bindings]:
		for link: Dictionary in links:
			if not _children_by_body.has(link.a): _children_by_body[link.a] = []
			_children_by_body[link.a].append(link)
	for binding: Dictionary in feather_bindings:
		var body: PhysicalBodyPart3D = binding.a
		var chain: Array[Dictionary] = []
		for index: int in range(bindings.size()+1):
			if PhysicalBodyPart3D.BodyPartTag.Torso in body.tags: break
			var parent_binding: Dictionary = {}
			for wing_binding: Dictionary in bindings:
				if wing_binding.b == body: parent_binding = wing_binding; break
			if parent_binding.is_empty(): break
			chain.append(parent_binding)
			body = parent_binding.a
		binding["torso"] = body if PhysicalBodyPart3D.BodyPartTag.Torso in body.tags else null
		binding["wing_chain"] = chain
	for wing_binding: Dictionary in bindings:
		var root_binding: Dictionary = wing_binding
		var parent_binding: Dictionary = {}
		for other: Dictionary in bindings:
			if other.b == wing_binding.a: parent_binding = other; break
		for depth: int in range(bindings.size()):
			var previous: Dictionary = {}
			for other: Dictionary in bindings:
				if other.b == root_binding.a: previous = other; break
			if previous.is_empty(): break
			root_binding = previous
		var frame: Transform3D = root_binding.joint.get_meta(&"generated_joint_frame_a",Transform3D.IDENTITY)
		var open_direction := Basis(root_binding.open).y
		wing_binding["elevation_sign"] = 1.0 if frame.basis.z.cross(open_direction).dot(Vector3.UP)>=0.0 else -1.0
		wing_binding["section_index"] = _section_index(wing_binding.b)
		wing_binding["parent_section_index"] = _section_index(wing_binding.a) if not parent_binding.is_empty() else -1
		wing_binding["has_wing_parent"] = not parent_binding.is_empty()
		var feathers: Array[Dictionary] = []
		for binding: Dictionary in feather_bindings:
			if binding.a == wing_binding.b: feathers.append(binding)
		wing_binding["feathers"] = feathers

func _section_index(body: PhysicalBodyPart3D) -> int:
	var type := str(body.get_meta(&"generated_part_type",""))
	if type == "WingMiddle" or "_Middle_" in str(body.name): return 1
	if type == "WingTip" or "_Tip_" in str(body.name): return 2
	return 0

func _update_flight_sway(flight: Node, delta: float) -> void:
	_flight_horizontal_speed = 0.0
	_flight_motion_speed = 0.0
	var airborne: bool = flight != null and flight.is_airborne()
	if airborne:
		# Internal pose motion must not keep the idle sway animation alive.
		var velocity: Vector3 = flight.get_flight_velocity()
		_flight_horizontal_speed = velocity.slide(Vector3.UP).length()
		_flight_motion_speed = velocity.length()
	var moving: bool = flight_sway_enabled and airborne and _flight_motion_speed>flight_sway_minimum_speed
	var dive := get_parent().get_node_or_null("BirdDiveAttackController3D")
	if dive != null and dive.is_active(): moving = false
	_sway_blend = move_toward(_sway_blend,1.0 if moving else 0.0,delta/maxf(flight_sway_blend_time,0.05))
	if _sway_blend>0.0: _sway_phase = fposmod(_sway_phase+TAU*maxf(flight_sway_frequency,0.0)*delta,TAU)

func _section_sway_angle(section: int) -> float:
	if section<0: return 0.0
	return deg_to_rad(flight_sway_amplitude_degrees)*sin(_sway_phase-section*deg_to_rad(flight_sway_phase_difference_degrees))*_sway_blend

func _get_expanded_relative_pose(binding: Dictionary) -> Quaternion:
	var frame: Transform3D = binding.joint.get_meta(&"generated_joint_frame_a",Transform3D.IDENTITY)
	var axis := frame.basis.orthonormalized().z
	var elevation := deg_to_rad(segment_elevation_degrees) if binding.has_wing_parent else 0.0
	# Section sway describes absolute angles. Only their difference belongs at each
	# joint, so subdividing Root/Middle/Tip cannot multiply the sway amplitude.
	var sway := _section_sway_angle(binding.section_index)-_section_sway_angle(binding.parent_section_index)
	var offset := float(binding.elevation_sign)*(elevation+sway)
	var opened: Quaternion = Quaternion(axis,offset)*Quaternion(binding.open)
	var limited := false
	if binding.joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT):
		var closed_direction := Basis(binding.closed).y
		var desired_direction := Basis(opened).y
		var motor_angle := -atan2(axis.dot(closed_direction.cross(desired_direction)),closed_direction.dot(desired_direction))
		var allowed := clampf(motor_angle,binding.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),binding.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT))
		limited = absf(allowed-motor_angle)>0.00001
		opened = Quaternion(axis,-allowed)*Quaternion(binding.closed)
	binding["pose_offset_degrees"] = rad_to_deg(offset)
	binding["target_limited"] = limited
	return opened

func _binding_intact(binding: Dictionary) -> bool:
	if not _alive(binding.a) or not _alive(binding.b): return false
	var joint: Generic6DOFJoint3D = binding.joint
	return is_instance_valid(joint) and joint.is_inside_tree() and not joint.is_queued_for_deletion()

func _collect_load_bodies(body: PhysicalBodyPart3D) -> Array[PhysicalBodyPart3D]:
	var result: Array[PhysicalBodyPart3D] = [body]
	var cursor := 0
	while cursor < result.size():
		var parent := result[cursor]
		cursor += 1
		for link: Dictionary in _children_by_body.get(parent,[]):
			if _binding_intact(link) and not result.has(link.b): result.append(link.b)
	return result

func _axis_inertia(body: PhysicalBodyPart3D, axis: Vector3, anchor: Vector3) -> float:
	var inverse := body.get_inverse_inertia_tensor()
	if inverse.determinant() == 0.0: return 0.0
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	var center := body.global_transform*state.center_of_mass_local if state != null else body.global_position
	return axis.dot(inverse.inverse()*axis) + body.mass*(center-anchor).slide(axis).length_squared()

func _effective_hinge_inertia(binding: Dictionary, axis: Vector3, anchor: Vector3) -> float:
	var child_inertia := 0.0
	# Detached descendants must not remain part of the load after a joint breaks.
	for body: PhysicalBodyPart3D in _collect_load_bodies(binding.b):
		if _alive(body): child_inertia += _axis_inertia(body,axis,anchor)
	if child_inertia <= 0.0: return 0.0
	if binding.a.freeze: return child_inertia
	var parent_inertia := _axis_inertia(binding.a,axis,anchor)
	if parent_inertia <= 0.0: return 0.0
	var composite := 1.0/(1.0/child_inertia + 1.0/parent_inertia)
	if joint_motor_pose or binding.joint.has_meta(&"feather_open_relative_a"): return composite
	var inverse: Basis = binding.b.get_inverse_inertia_tensor()
	var parent_inverse: Basis = binding.a.get_inverse_inertia_tensor()
	var local_inertia := 1.0/maxf(axis.dot(inverse*axis)+axis.dot(parent_inverse*axis),0.000000001)
	return minf(composite,local_inertia*maxf(maximum_articulated_load_ratio,1.0))

func _stable_acceleration(error: Vector3, relative_velocity: Vector3, frequency: float, damping: float, delta: float) -> Vector3:
	var omega := TAU*maxf(frequency,0.0)
	var kp := omega*omega
	var kd := 2.0*maxf(damping,0.0)*omega
	return (kp*error-(kd+kp*delta)*relative_velocity)/(1.0+kd*delta+kp*delta*delta)

func claims_input_action(action: StringName) -> bool:
	if not enabled or not _character_enabled or not suppress_jump or action != unfold_action or _planar_active(): return false
	for binding: Dictionary in bindings:
		if _binding_intact(binding): return true
	return false

func _get_gravity_compensation_force(body: PhysicalBodyPart3D) -> Vector3:
	var flight := get_parent().get_node_or_null("BirdFlightController3D")
	if flight != null and flight.is_airborne(): return Vector3.ZERO
	if not gravity_compensation_enabled or not _alive(body) or body.freeze or body.custom_integrator: return Vector3.ZERO
	if not is_finite(gravity_compensation_ratio): return Vector3.ZERO
	# total_gravity already includes Gravity Scale and Area3D gravity overrides.
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	if state == null: return Vector3.ZERO
	var force := -state.total_gravity * body.mass * clampf(gravity_compensation_ratio, 0.0, 1.0)
	return force if force.is_finite() else Vector3.ZERO

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	if not enabled or not _character_enabled or _planar_active():
		_stop_pose_motors()
		return
	if not hinge_only_pose: _stop_pose_motors()
	var pressed := InputMap.has_action(unfold_action) and PLAYER_CONTEXT.action_pressed(self, unfold_action)
	var flight := get_parent().get_node_or_null("BirdFlightController3D")
	if flight != null and flight.is_airborne(): pressed = true
	var dive := get_parent().get_node_or_null("BirdDiveAttackController3D")
	if dive != null and dive.is_active(): pressed = not dive.wants_folded_wings()
	_update_flight_sway(flight,delta)
	var pose_transition_time := transition_time if pressed else fold_transition_time
	if dive != null and dive.is_active() and dive.wants_folded_wings(): pose_transition_time = dive.data.fold_time
	unfold_ratio = move_toward(unfold_ratio, 1.0 if pressed else 0.0, delta / maxf(pose_transition_time, 0.05))
	var compensated: Dictionary = {}
	for binding: Dictionary in bindings:
		if not _binding_intact(binding): continue
		var a: PhysicalBodyPart3D = binding.a
		var b: PhysicalBodyPart3D = binding.b
		if b.freeze: continue
		if not compensated.has(b):
			b.apply_central_force(_get_gravity_compensation_force(b))
			compensated[b] = true
		var closed: Quaternion = binding.closed
		var target := a.global_basis.orthonormalized().get_rotation_quaternion() * closed.slerp(_get_expanded_relative_pose(binding), unfold_ratio)
		var error := target * b.global_basis.orthonormalized().get_rotation_quaternion().inverse()
		if error.w < 0.0: error = -error
		var omega := TAU * maxf(posture_frequency, 0.0)
		var acceleration := _stable_acceleration(error.get_axis()*error.get_angle(), b.angular_velocity-a.angular_velocity, posture_frequency,damping_ratio,delta).limit_length(maxf(maximum_angular_acceleration,0.0))
		var inverse := b.get_inverse_inertia_tensor()
		if not a.freeze:
			var parent_inverse := a.get_inverse_inertia_tensor()
			inverse = Basis(inverse.x + parent_inverse.x, inverse.y + parent_inverse.y, inverse.z + parent_inverse.z)
		if inverse.determinant() == 0.0: continue
		var load_factor := minf(_feather_inertia_factor(binding),torque_load_factor_limit)
		var uncapped_torque := inverse.inverse() * acceleration * load_factor
		var effective_inertia := 0.0
		var torque_limit := maxf(maximum_torque,0.0)
		if hinge_only_pose:
			var local_frame: Transform3D = binding.joint.get_meta(&"generated_joint_frame_a",Transform3D.IDENTITY)
			var axis: Vector3 = (a.global_basis*local_frame.basis).orthonormalized().z
			var hinge_acceleration := acceleration.dot(axis)
			acceleration = axis*hinge_acceleration
			effective_inertia = 1.0/maxf(axis.dot(inverse*axis),0.000000001)
			if automatic_load_inertia:
				effective_inertia = _effective_hinge_inertia(binding,axis,a.global_transform*local_frame.origin)
				load_factor = 1.0
				torque_limit = effective_inertia*maxf(maximum_angular_acceleration,0.0)
				if joint_motor_pose and dive != null and dive.is_aiming(): torque_limit *= dive.data.aiming_wing_motor_force_multiplier
				if absolute_torque_limit_enabled: torque_limit = minf(torque_limit,maxf(maximum_torque,0.0))
			uncapped_torque = axis*hinge_acceleration*effective_inertia*load_factor
			if joint_motor_pose:
				if error.get_angle()>0.01:
					b.sleeping = false
					if not a.freeze: a.sleeping = false
				binding.joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR,true)
				binding.joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY,-((b.angular_velocity-a.angular_velocity).dot(axis)+hinge_acceleration*delta))
				binding.joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT,torque_limit)
			else: binding.joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR,false)
		var torque := uncapped_torque.limit_length(torque_limit)
		if not torque.is_finite(): continue
		if _diagnostic_tracking:
			binding["command"] = {"frame":Engine.get_physics_frames(),"error_degrees":rad_to_deg(error.get_angle()),"error_vector":error.get_axis()*error.get_angle(),"relative_angular_velocity":b.angular_velocity-a.angular_velocity,"acceleration":acceleration,"load_factor":load_factor,"effective_hinge_inertia":effective_inertia,"torque_limit":torque_limit,"automatic_load_inertia":automatic_load_inertia,"step_denominator":1.0+2.0*damping_ratio*omega*delta+omega*omega*delta*delta,"uncapped_torque":uncapped_torque,"torque":torque,"reaction_on_parent":-torque if not a.freeze else Vector3.ZERO,"torque_capped":uncapped_torque.length()>torque_limit,"gravity_compensation":_get_gravity_compensation_force(b)}
			binding.command["joint_motor_pose"] = joint_motor_pose and hinge_only_pose
			binding.command["torque_is_estimate"] = joint_motor_pose and hinge_only_pose
			binding.command["motor_target_velocity"] = binding.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY) if joint_motor_pose and hinge_only_pose else 0.0
			binding.command["section_index"] = binding.section_index
			binding.command["pose_offset_degrees"] = binding.pose_offset_degrees
			binding.command["target_limited"] = binding.target_limited
			binding.command["sway_phase"] = _sway_phase
			binding.command["sway_blend"] = _sway_blend
			binding.command["flight_horizontal_speed"] = _flight_horizontal_speed
			binding.command["flight_motion_speed"] = _flight_motion_speed
		if not joint_motor_pose or not hinge_only_pose:
			b.apply_torque(torque)
			if not a.freeze: a.apply_torque(-torque)
	for binding: Dictionary in feather_bindings:
		if not _binding_intact(binding) or not _alive(binding.torso): continue
		var intact := true
		for wing_binding: Dictionary in binding.wing_chain:
			if not _binding_intact(wing_binding): intact = false; break
		if not intact: continue
		var body: PhysicalBodyPart3D = binding.b
		if body.freeze: continue
		if not compensated.has(body):
			body.apply_central_force(_get_gravity_compensation_force(body))
			compensated[body] = true
		if feather_control_enabled: _apply_feather_pose(binding,delta)
		else: binding.joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR,false)

func _feather_inertia_factor(binding: Dictionary) -> float:
	var wing: PhysicalBodyPart3D = binding.b
	var inverse := wing.get_inverse_inertia_tensor()
	if absf(inverse.determinant())<=0.000000001: return 1.0
	var axis := wing.global_basis.orthonormalized().z
	var base := axis.dot(inverse.inverse()*axis)
	var additional := 0.0
	for feather_binding: Dictionary in binding.get("feathers",[]):
		if not _binding_intact(feather_binding): continue
		var feather: PhysicalBodyPart3D = feather_binding.b
		var feather_inverse := feather.get_inverse_inertia_tensor()
		if absf(feather_inverse.determinant())<=0.000000001: continue
		var lever := (feather.global_position-wing.global_position).slide(axis)
		additional += axis.dot(feather_inverse.inverse()*axis)+feather.mass*lever.length_squared()
	return clampf(1.0+additional/maxf(base,0.000000001),1.0,3.0)

func _apply_feather_pose(binding: Dictionary, delta: float = 1.0/60.0) -> void:
	var wing: PhysicalBodyPart3D = binding.a
	var feather: PhysicalBodyPart3D = binding.b
	var torso: PhysicalBodyPart3D = binding.torso
	var wing_basis := wing.global_basis.orthonormalized()
	var axis := wing_basis.z
	# Fold toward the creature's rear, projected into the wing plane: only the hinge Z axis moves.
	var rear := (torso.global_basis.orthonormalized()*Vector3.LEFT).slide(axis).normalized()
	if rear.is_zero_approx(): return
	var closed_world := Basis(rear.cross(axis),rear,axis).get_rotation_quaternion()
	var closed_relative := wing_basis.get_rotation_quaternion().inverse()*closed_world
	var desired := Basis(wing_basis.get_rotation_quaternion()*closed_relative.slerp(binding.open,unfold_ratio)).y
	var current := feather.global_basis.orthonormalized().y
	var angle := atan2(axis.dot(current.cross(desired)),current.dot(desired))
	var acceleration := clampf(_stable_acceleration(axis*angle,feather.angular_velocity-wing.angular_velocity,feather_posture_frequency,feather_damping_ratio,delta).dot(axis),-maxf(feather_maximum_angular_acceleration,0.0),maxf(feather_maximum_angular_acceleration,0.0))
	var feather_inverse := feather.get_inverse_inertia_tensor()
	if feather_inverse.determinant() == 0.0: return
	var size: Vector3 = feather.get_meta(&"generated_size",Vector3.ONE)
	# Feather bodies are centered halfway along their length, but rotate about their root.
	var lever := feather.global_basis.y.normalized()*size.y*0.5
	var hinge_inertia := axis.dot(feather_inverse.inverse()*axis)+feather.mass*lever.slide(axis).length_squared()
	var inverse_inertia := 1.0/maxf(hinge_inertia,0.000000001)
	if not wing.freeze: inverse_inertia += axis.dot(wing.get_inverse_inertia_tensor()*axis)
	if inverse_inertia <= 0.000000001: return
	var effective_inertia := 1.0/inverse_inertia
	if automatic_load_inertia:
		var local_frame: Transform3D = binding.joint.get_meta(&"generated_joint_frame_a",Transform3D.IDENTITY)
		effective_inertia = _effective_hinge_inertia(binding,axis,wing.global_transform*local_frame.origin)
	var torque_limit := effective_inertia*maxf(feather_maximum_angular_acceleration,0.0) if automatic_load_inertia else maxf(feather_maximum_torque,0.0)
	if automatic_load_inertia and absolute_torque_limit_enabled: torque_limit = minf(torque_limit,maxf(feather_maximum_torque,0.0))
	var magnitude := clampf(acceleration*effective_inertia,-torque_limit,torque_limit)
	if not is_finite(magnitude): return
	if _diagnostic_tracking:
		binding["command"] = {"frame":Engine.get_physics_frames(),"error_degrees":rad_to_deg(angle),"effective_hinge_inertia":effective_inertia,"torque_limit":torque_limit,"torque":magnitude,"torque_capped":absf(acceleration*effective_inertia)>torque_limit}
		binding.command["joint_motor_pose"] = joint_motor_pose
		binding.command["torque_is_estimate"] = joint_motor_pose
	binding.joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR,joint_motor_pose)
	if joint_motor_pose:
		if absf(angle)>0.01:
			feather.sleeping = false
			if not wing.freeze: wing.sleeping = false
		binding.joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_TARGET_VELOCITY,-((feather.angular_velocity-wing.angular_velocity).dot(axis)+acceleration*delta))
		binding.joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_MOTOR_FORCE_LIMIT,torque_limit)
	else:
		feather.apply_torque(axis*magnitude)
		if not wing.freeze: wing.apply_torque(-axis*magnitude)

func set_diagnostic_tracking_enabled(value: bool) -> void:
	_diagnostic_tracking = value
	for binding: Dictionary in bindings: binding.erase("command")
	for binding: Dictionary in feather_bindings: binding.erase("command")

func get_wing_diagnostics() -> Dictionary:
	var rows: Array[Dictionary] = []
	for binding: Dictionary in bindings:
		if not _binding_intact(binding): continue
		var maximum_error := 0.0
		var maximum_feather_torque := 0.0
		var sampled_feathers := 0
		var feather_age := -1
		for feather: Dictionary in binding.get("feathers",[]):
			if not _binding_intact(feather) or not feather.has("command"): continue
			sampled_feathers += 1
			maximum_error = maxf(maximum_error,absf(feather.command.error_degrees))
			maximum_feather_torque = maxf(maximum_feather_torque,absf(feather.command.torque))
			feather_age = maxi(feather_age,Engine.get_physics_frames()-int(feather.command.frame))
		rows.append({"wing":str(binding.b.name),"parent":str(binding.a.name),"joint":str(binding.joint.name),"z_lower":binding.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),"z_upper":binding.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT),"relative_rotation_degrees":(binding.a.global_basis.orthonormalized().inverse()*binding.b.global_basis.orthonormalized()).get_euler()*(180.0/PI),"command":binding.get("command",{}),"command_age_frames":Engine.get_physics_frames()-int(binding.get("command",{}).get("frame",Engine.get_physics_frames())),"sampled_feathers":sampled_feathers,"feather_max_error_degrees":maximum_error,"feather_max_torque":maximum_feather_torque,"feather_command_age_frames":feather_age})
	var flight := get_parent().get_node_or_null("BirdFlightController3D")
	return {"enabled":enabled,"character_enabled":_character_enabled,"planar":_planar_active(),"unfold_ratio":unfold_ratio,"fold_transition_time":fold_transition_time,"hinge_only_pose":hinge_only_pose,"automatic_load_inertia":automatic_load_inertia,"joint_motor_pose":joint_motor_pose,"absolute_torque_limit_enabled":absolute_torque_limit_enabled,"torque_load_factor_limit":torque_load_factor_limit,"raw_space":InputMap.has_action(unfold_action) and Input.is_action_pressed(unfold_action),"gated_space":InputMap.has_action(unfold_action) and PLAYER_CONTEXT.action_pressed(self,unfold_action),"airborne":flight != null and flight.is_airborne(),"gravity_compensation_owner":"flight" if flight != null and flight.is_airborne() else "wing","force_semantics":"motor velocity/force budgets; torque fields are estimates, not solver impulses" if joint_motor_pose else "submitted torques, not solver impulses","wings":rows}
