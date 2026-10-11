extends Node3D
## Mass-scaled Head position servo relative to the Torso reached through its Neck.
@export var enabled: bool = true
var bindings: Array[Dictionary] = []
var diagnostics: Array[Dictionary] = []
var _character_enabled: bool = true

func set_character_control_enabled(value: bool) -> void:
	_character_enabled = value
	if not value: diagnostics.clear()

func _ready() -> void:
	refresh_physics_query_cache()

func _planar_active() -> bool:
	var actor := get_parent()
	return actor.has_method("is_planar_mode_active") and actor.is_planar_mode_active()

func _alive(body: Variant) -> bool:
	return is_instance_valid(body) and not body.is_queued_for_deletion() and body.get("is_broken") != true

func refresh_physics_query_cache() -> void:
	var previous: Dictionary = {}
	for binding: Dictionary in bindings:
		if _alive(binding.head): previous[binding.head] = binding
	bindings.clear()
	var actor := get_parent()
	var container := actor.get_node_or_null("GeneratedParts")
	if container == null: container = actor
	var graph: Dictionary = {}
	for node: Node in container.find_children("*","Joint3D",true,false):
		var joint := node as Joint3D
		if joint.has_meta(&"planar_depth_guide") or joint.is_queued_for_deletion(): continue
		var a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
		var b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
		if not _alive(a) or not _alive(b): continue
		if not graph.has(a): graph[a] = []
		if not graph.has(b): graph[b] = []
		graph[a].append({"body": b,"joint": joint})
		graph[b].append({"body": a,"joint": joint})
	for node: Node in container.get_children():
		if not node is PhysicalBodyPart3D or not _alive(node): continue
		var head := node as PhysicalBodyPart3D
		if PhysicalBodyPart3D.BodyPartTag.Head not in head.tags: continue
		var queue: Array[Dictionary] = [{"body": head,"bodies": [head],"joints": []}]
		var visited: Array = [head]
		while not queue.is_empty():
			var state: Dictionary = queue.pop_front()
			var body: PhysicalBodyPart3D = state.body
			if body != head and PhysicalBodyPart3D.BodyPartTag.Torso in body.tags:
				var offset := body.global_basis.inverse()*(head.global_position-body.global_position)
				if previous.has(head) and previous[head].torso == body: offset = previous[head].rest_offset
				var rest_rotation := (body.global_basis.orthonormalized().inverse()*head.global_basis.orthonormalized()).get_rotation_quaternion()
				if previous.has(head) and previous[head].torso == body: rest_rotation = previous[head].rest_rotation
				bindings.append({"head": head,"torso": body,"rest_offset": offset,"rest_rotation": rest_rotation,"has_neck": state.bodies.size()>2,"bodies": state.bodies,"joints": state.joints,"slack": Vector3(-1,-1,-1)})
				var binding: Dictionary = bindings[-1]
				binding["head_pivot"] = head.to_local(state.joints[0].global_position) if not state.joints.is_empty() else Vector3.ZERO
				binding["charge_pitch"] = 0.0
				if previous.has(head) and previous[head].torso == body:
					binding.head_pivot = previous[head].get("head_pivot",binding.head_pivot)
					binding.charge_pitch = previous[head].get("charge_pitch",0.0)
				break
			for edge: Dictionary in graph.get(body,[]):
				var next: PhysicalBodyPart3D = edge.body
				if next in visited: continue
				var role: String = str(next.get_meta(&"generated_role",""))
				if role != "Neck" and PhysicalBodyPart3D.BodyPartTag.Torso not in next.tags: continue
				visited.append(next)
				queue.append({"body": next,"bodies": state.bodies+[next],"joints": state.joints+[edge.joint]})
	# Configure even if planar is enabled: newly generated joints still exist here.
	# Never write parameters onto an already-cleared planar Joint RID.
	for binding: Dictionary in bindings: _sync_direct_head_slack(binding)

func _sync_direct_head_slack(binding: Dictionary) -> void:
	if binding.has_neck or not _alive(binding.head) or binding.joints.is_empty(): return
	var joint: Generic6DOFJoint3D = binding.joints[0] as Generic6DOFJoint3D
	if not is_instance_valid(joint) or joint.is_queued_for_deletion(): return
	if PhysicsServer3D.joint_get_type(joint.get_rid()) == PhysicsServer3D.JOINT_TYPE_MAX: return
	var slack: Vector3 = binding.head.head_no_neck_linear_slack
	if not slack.is_finite(): return
	slack = slack.max(Vector3.ZERO)
	if slack == Vector3(binding.slack): return
	for index: int in range(3):
		var axis: String = ["x","y","z"][index]
		joint.call("set_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT,true)
		joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,-slack[index])
		joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,slack[index])
	binding.slack = slack

func _chain_intact(binding: Dictionary) -> bool:
	for body: Variant in binding.bodies:
		if not _alive(body): return false
	for joint: Variant in binding.joints:
		if not is_instance_valid(joint) or joint.is_queued_for_deletion(): return false
	return true

func _physics_process(delta: float) -> void:
	diagnostics.clear()
	if not enabled or not _character_enabled or _planar_active(): return
	var dive := get_parent().get_node_or_null("BirdDiveAttackController3D")
	if dive != null and dive.is_active(): return
	for binding: Dictionary in bindings:
		if not _chain_intact(binding): continue
		_sync_direct_head_slack(binding)
		var head: PhysicalBodyPart3D = binding.head
		var torso: PhysicalBodyPart3D = binding.torso
		if head.freeze: continue
		var charge := get_parent().get_node_or_null("ChargeAttackController3D")
		var request: Dictionary = charge.get_head_posture_request() if charge != null and charge.has_method("get_head_posture_request") else {"angle":0.0,"transition_time":0.3}
		var old_pitch: float = binding.get("charge_pitch",0.0)
		var target_pitch: float = request.angle
		var pitch := move_toward(old_pitch,target_pitch,float(request.get("angular_speed",deg_to_rad(50.0)))*delta)
		if absf(pitch-target_pitch)<0.0001: pitch = target_pitch
		binding["charge_pitch"] = pitch
		var rest_basis := torso.global_basis.orthonormalized()*Basis(Quaternion(binding.rest_rotation))
		var desired_basis := torso.global_basis.orthonormalized()*Basis(Vector3.BACK,pitch)*Basis(Quaternion(binding.rest_rotation))
		var offset: Vector3 = torso.global_basis*Vector3(binding.rest_offset)
		# Preserve the connection pivot while rotating the body; the position
		# servo must not fight the joint by holding the old centre fixed.
		var pivot: Vector3 = binding.get("head_pivot",Vector3.ZERO)
		offset += rest_basis*pivot-desired_basis*pivot
		var target_position := torso.global_position+offset
		var target_velocity := torso.linear_velocity+torso.angular_velocity.cross(offset)
		var position_error := target_position-head.global_position
		var velocity_error := target_velocity-head.linear_velocity
		var gain: float = head.head_position_gain if binding.has_neck else head.head_no_neck_position_gain
		var damping: float = head.head_position_damping if binding.has_neck else head.head_no_neck_position_damping
		var acceleration := position_error*maxf(gain,0.0)+velocity_error*maxf(damping,0.0)
		var flight := get_parent().get_node_or_null("BirdFlightController3D")
		var flight_owns_gravity: bool = flight != null and flight.is_airborne()
		if flight_owns_gravity:
			acceleration = (position_error*maxf(gain,0.0)+velocity_error*(maxf(damping,0.0)+maxf(gain,0.0)*delta))/(1.0+maxf(damping,0.0)*delta+maxf(gain,0.0)*delta*delta)
		if head.head_gravity_compensation and not flight_owns_gravity: acceleration -= head.get_gravity()
		var force := acceleration.limit_length(maxf(head.head_maximum_support_acceleration,0.0))*head.mass
		if not head.head_position_support_enabled: force = Vector3.ZERO
		head.apply_central_force(force)
		var desired_rotation: Quaternion = desired_basis.get_rotation_quaternion()
		var rotation_error := desired_rotation*head.global_basis.orthonormalized().get_rotation_quaternion().inverse()
		if rotation_error.w < 0.0: rotation_error = -rotation_error
		var error_vector := rotation_error.get_axis()*rotation_error.get_angle()
		var angular_velocity_error := torso.angular_velocity-head.angular_velocity
		var torque := Vector3.ZERO
		if head.head_posture_damping_enabled:
			var angular_acceleration := (error_vector*maxf(head.head_posture_gain,0.0)+angular_velocity_error*maxf(head.head_posture_damping,0.0)).limit_length(maxf(head.head_maximum_angular_acceleration,0.0))
			if flight_owns_gravity:
				var stiffness := maxf(head.head_posture_gain,0.0)
				var angular_damping := maxf(head.head_posture_damping,0.0)
				angular_acceleration = ((error_vector*stiffness+angular_velocity_error*(angular_damping+stiffness*delta))/(1.0+angular_damping*delta+stiffness*delta*delta)).limit_length(maxf(head.head_maximum_angular_acceleration,0.0))
			var inverse := head.get_inverse_inertia_tensor()
			if absf(inverse.determinant())>0.000000001:
				torque = (inverse.inverse()*angular_acceleration).limit_length(maxf(head.head_maximum_posture_torque,0.0))
			head.apply_torque(torque)
		diagnostics.append({"head": head.name,"torso": torso.name,"has_neck": binding.has_neck,"position_error": position_error,"velocity_error": velocity_error,"force": force,"gravity_compensation_owner": "flight" if flight_owns_gravity else "head","rotation_error_degrees": error_vector*(180.0/PI),"angular_velocity_error": angular_velocity_error,"posture_torque": torque,"linear_slack": binding.slack if not binding.has_neck else Vector3.ZERO,"charge_pitch_degrees":rad_to_deg(pitch),"charge_target_pitch_degrees":rad_to_deg(target_pitch)})

func get_head_support_diagnostics() -> Array[Dictionary]:
	return diagnostics
