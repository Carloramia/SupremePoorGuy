@tool
extends Node3D
## Relative joint posture servo: applies equal/opposite physical torques, never teleports blocks.
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
var unfold_ratio: float = 0.0
var _character_enabled: bool = true

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
	if not value: unfold_ratio = 0.0

func _alive(body: PhysicalBodyPart3D) -> bool:
	return is_instance_valid(body) and not body.is_queued_for_deletion() and not body.is_broken

func _planar_active() -> bool:
	var actor := get_parent()
	return actor != null and actor.has_method("is_planar_mode_active") and actor.is_planar_mode_active()

func refresh_physics_query_cache() -> void:
	bindings.clear()
	feather_bindings.clear()
	unfold_ratio = 0.0
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
		var feathers: Array[Dictionary] = []
		for binding: Dictionary in feather_bindings:
			if binding.a == wing_binding.b: feathers.append(binding)
		wing_binding["feathers"] = feathers

func _binding_intact(binding: Dictionary) -> bool:
	if not _alive(binding.a) or not _alive(binding.b): return false
	var joint: Generic6DOFJoint3D = binding.joint
	return is_instance_valid(joint) and joint.is_inside_tree() and not joint.is_queued_for_deletion()

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
	if Engine.is_editor_hint() or not enabled or not _character_enabled or _planar_active(): return
	var pressed := InputMap.has_action(unfold_action) and PLAYER_CONTEXT.action_pressed(self, unfold_action)
	var flight := get_parent().get_node_or_null("BirdFlightController3D")
	if flight != null and flight.is_airborne(): pressed = true
	unfold_ratio = move_toward(unfold_ratio, 1.0 if pressed else 0.0, delta / maxf(transition_time if pressed else fold_transition_time, 0.05))
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
		var target := a.global_basis.orthonormalized().get_rotation_quaternion() * closed.slerp(binding.open, unfold_ratio)
		var error := target * b.global_basis.orthonormalized().get_rotation_quaternion().inverse()
		if error.w < 0.0: error = -error
		var omega := TAU * maxf(posture_frequency, 0.0)
		var acceleration := (error.get_axis() * error.get_angle() * omega * omega
			+ (a.angular_velocity - b.angular_velocity) * 2.0 * maxf(damping_ratio, 0.0) * omega).limit_length(maxf(maximum_angular_acceleration, 0.0))
		var inverse := b.get_inverse_inertia_tensor()
		if not a.freeze:
			var parent_inverse := a.get_inverse_inertia_tensor()
			inverse = Basis(inverse.x + parent_inverse.x, inverse.y + parent_inverse.y, inverse.z + parent_inverse.z)
		if absf(inverse.determinant()) < 0.000000001: continue
		var load_factor := minf(_feather_inertia_factor(binding),torque_load_factor_limit)
		var uncapped_torque := inverse.inverse() * acceleration * load_factor
		if hinge_only_pose:
			var local_frame: Transform3D = binding.joint.get_meta(&"generated_joint_frame_a",Transform3D.IDENTITY)
			var axis: Vector3 = (a.global_basis*local_frame.basis).orthonormalized().z
			var hinge_acceleration := clampf(error.get_axis().dot(axis)*error.get_angle()*omega*omega+(a.angular_velocity-b.angular_velocity).dot(axis)*2.0*maxf(damping_ratio,0.0)*omega,-maximum_angular_acceleration,maximum_angular_acceleration)
			acceleration = axis*hinge_acceleration
			uncapped_torque = axis*hinge_acceleration/maxf(axis.dot(inverse*axis),0.000000001)*load_factor
		var torque := uncapped_torque.limit_length(maxf(maximum_torque, 0.0))
		if not torque.is_finite(): continue
		if _diagnostic_tracking:
			binding["command"] = {"frame":Engine.get_physics_frames(),"error_degrees":rad_to_deg(error.get_angle()),"error_vector":error.get_axis()*error.get_angle(),"relative_angular_velocity":b.angular_velocity-a.angular_velocity,"acceleration":acceleration,"load_factor":load_factor,"uncapped_torque":uncapped_torque,"torque":torque,"reaction_on_parent":-torque if not a.freeze else Vector3.ZERO,"torque_capped":uncapped_torque.length()>maximum_torque,"gravity_compensation":_get_gravity_compensation_force(b)}
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
		if feather_control_enabled: _apply_feather_pose(binding)

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

func _apply_feather_pose(binding: Dictionary) -> void:
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
	var omega := TAU*maxf(feather_posture_frequency,0.0)
	var acceleration := clampf(angle*omega*omega+(wing.angular_velocity-feather.angular_velocity).dot(axis)*2.0*maxf(feather_damping_ratio,0.0)*omega,-maxf(feather_maximum_angular_acceleration,0.0),maxf(feather_maximum_angular_acceleration,0.0))
	var feather_inverse := feather.get_inverse_inertia_tensor()
	if absf(feather_inverse.determinant())<=0.000000001: return
	var size: Vector3 = feather.get_meta(&"generated_size",Vector3.ONE)
	# Feather bodies are centered halfway along their length, but rotate about their root.
	var lever := feather.global_basis.y.normalized()*size.y*0.5
	var hinge_inertia := axis.dot(feather_inverse.inverse()*axis)+feather.mass*lever.slide(axis).length_squared()
	var inverse_inertia := 1.0/maxf(hinge_inertia,0.000000001)
	if not wing.freeze: inverse_inertia += axis.dot(wing.get_inverse_inertia_tensor()*axis)
	if inverse_inertia <= 0.000000001: return
	var magnitude := clampf(acceleration/inverse_inertia,-maxf(feather_maximum_torque,0.0),maxf(feather_maximum_torque,0.0))
	if not is_finite(magnitude): return
	if _diagnostic_tracking:
		binding["command"] = {"frame":Engine.get_physics_frames(),"error_degrees":rad_to_deg(angle),"torque":magnitude,"torque_capped":absf(acceleration/inverse_inertia)>feather_maximum_torque}
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
	return {"enabled":enabled,"character_enabled":_character_enabled,"planar":_planar_active(),"unfold_ratio":unfold_ratio,"fold_transition_time":fold_transition_time,"hinge_only_pose":hinge_only_pose,"torque_load_factor_limit":torque_load_factor_limit,"raw_space":InputMap.has_action(unfold_action) and Input.is_action_pressed(unfold_action),"gated_space":InputMap.has_action(unfold_action) and PLAYER_CONTEXT.action_pressed(self,unfold_action),"airborne":flight != null and flight.is_airborne(),"gravity_compensation_owner":"flight" if flight != null and flight.is_airborne() else "wing","force_semantics":"submitted torques, not solver impulses","wings":rows}
