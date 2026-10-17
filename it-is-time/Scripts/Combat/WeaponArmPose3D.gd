extends RefCounted
## Shared physical pose targets and NPC prediction. Joint positions remain solver-owned.

static func capture(state: Dictionary) -> Array[Dictionary]:
	var bodies: Array[RigidBody3D] = [state.body]
	var joints: Array[Generic6DOFJoint3D] = [state.joint]
	for follower: Dictionary in state.followers:
		bodies.append(follower.body)
		joints.append(follower.joint)
	var anchor: RigidBody3D = state.anchor_body
	var result: Array[Dictionary] = []
	for index: int in bodies.size():
		var body := bodies[index]
		var joint := joints[index]
		var proximal := local_anchor(joint,body)
		var distal := local_anchor(joints[index+1],body) if index+1 < joints.size() else proximal
		# A single Arm has no elbow; it reaches by rotating its existing rigid lever.
		if bodies.size() == 1: distal = Vector3.ZERO
		result.append({"body":body,"joint":joint,"proximal":proximal,"distal":distal,
			"rest_basis":anchor.global_basis.inverse()*body.global_basis})
	return result

static func local_anchor(joint: Generic6DOFJoint3D, body: RigidBody3D) -> Vector3:
	var key := &"generated_joint_frame_a" if joint.get_node_or_null(joint.node_a) == body else &"generated_joint_frame_b"
	if joint.has_meta(key): return (joint.get_meta(key) as Transform3D).origin
	return body.to_local(joint.global_position)

static func reach(chain: Array[Dictionary]) -> float:
	var result := 0.0
	for link: Dictionary in chain: result += (link.body.global_basis*Vector3(link.distal-link.proximal)).length()
	return result

static func poses(state: Dictionary, preset: WeaponArmAttackPreset, direction: Vector3, up: Vector3, progress: float) -> Array[Transform3D]:
	var chain: Array[Dictionary] = state.pose_chain
	var anchor: RigidBody3D = state.anchor_body
	var pivot := anchor.to_global(state.pose_anchor_local)
	var length := reach(chain)
	var blend := smoothstep(0.0,1.0,progress)
	if chain.size() == 1:
		# With no elbow, keep the shoulder attached and use a short aimed jab arc.
		var link: Dictionary = chain[0]
		var basis: Basis = anchor.global_basis*Basis(link.rest_basis)
		var forward: Vector3 = basis*Vector3(state.get("weapon_aim_local",state.weapon_forward_local))
		if not forward.is_zero_approx(): basis = Basis(Quaternion(forward.normalized(),direction))*basis
		var axis := direction.cross(up).normalized()
		var lever := basis*-Vector3(link.proximal)
		var side := signf(direction.dot(axis.cross(lever)))
		if is_zero_approx(side): side = 1.0
		var span := asin(clampf((preset.strike_reach-preset.preparation_reach)*0.5,0.05,0.45))
		basis = Basis(axis,lerpf(-span,span,blend)*side)*basis
		return [Transform3D(basis,pivot-basis*Vector3(link.proximal))]
	var extension := lerpf(preset.preparation_reach,preset.strike_reach,blend)
	var height := lerpf(preset.preparation_height,preset.strike_height,blend)
	var end := pivot+(direction*extension+up*height).limit_length(0.99)*length
	return targets(state,end,direction,up)

static func targets(state: Dictionary, end: Vector3, direction: Vector3, up: Vector3) -> Array[Transform3D]:
	var chain: Array[Dictionary] = state.pose_chain
	var anchor: RigidBody3D = state.anchor_body
	var pivot := anchor.to_global(state.pose_anchor_local)
	var length := reach(chain)
	end = pivot+(end-pivot).limit_length(length*0.99)
	var points: Array[Vector3] = [pivot]
	var lengths: Array[float] = []
	# Deterministic bend plane prevents the IK solution flipping across a straight elbow.
	for index: int in chain.size():
		var link: Dictionary = chain[index]
		lengths.append((link.body.global_basis*Vector3(link.distal-link.proximal)).length())
		var fraction := float(index+1)/chain.size()
		points.append(pivot.lerp(end,fraction)-up*sin(fraction*PI)*length*0.35)
	for iteration: int in 12:
		points[-1] = end
		for index: int in range(lengths.size()-1,-1,-1):
			var axis := (points[index]-points[index+1]).normalized()
			points[index] = points[index+1]+axis*lengths[index]
		points[0] = pivot
		for index: int in lengths.size():
			var axis := (points[index+1]-points[index]).normalized()
			if axis.is_zero_approx(): axis = direction
			points[index+1] = points[index]+axis*lengths[index]
	var result: Array[Transform3D] = []
	for index: int in chain.size():
		var link: Dictionary = chain[index]
		var basis: Basis = anchor.global_basis*Basis(link.rest_basis)
		var rest_vector: Vector3 = basis*Vector3(link.distal-link.proximal)
		var desired := points[index+1]-points[index]
		if not rest_vector.is_zero_approx() and not desired.is_zero_approx():
			basis = Basis(Quaternion(rest_vector.normalized(),desired.normalized()))*basis
		if index == chain.size()-1 and chain.size() > 1:
			var forward: Vector3 = basis*Vector3(state.get("weapon_aim_local",state.weapon_forward_local))
			if not forward.is_zero_approx(): basis = Basis(Quaternion(forward.normalized(),direction))*basis
		result.append(Transform3D(basis,points[index]-basis*Vector3(link.proximal)))
	return result

static func apply(state: Dictionary, preset: WeaponArmAttackPreset, targets: Array[Transform3D], delta: float, power: float) -> void:
	var omega := TAU*preset.pose_frequency
	var stiffness := omega*omega
	var damping := 2.0*preset.pose_damping_ratio*omega
	var anchor: RigidBody3D = state.anchor_body
	var drives: Array[Vector3] = []
	for index: int in state.pose_chain.size():
		var body: RigidBody3D = state.pose_chain[index].body
		var error := (targets[index].basis.get_rotation_quaternion()*body.global_basis.get_rotation_quaternion().inverse()).normalized()
		if error.w < 0.0: error = -error
		var rate := body.angular_velocity-anchor.angular_velocity
		var acceleration := ((error.get_axis()*error.get_angle()*stiffness-rate*(damping+stiffness*delta))/(1.0+damping*delta+stiffness*delta*delta)).limit_length(preset.maximum_pose_acceleration*power)
		var inverse := body.get_inverse_inertia_tensor()
		var lever: Vector3 = body.global_basis*(body.center_of_mass-Vector3(state.pose_chain[index].proximal))
		var torque := Vector3.ZERO
		for axis: Vector3 in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]:
			var inverse_moment := axis.dot(inverse*axis)
			if inverse_moment > 0.000001: torque += axis*acceleration.dot(axis)*(1.0/inverse_moment+body.mass*lever.cross(axis).length_squared())
		drives.append(torque)
	# Carry distal motor reactions into the proximal motor, rather than fighting
	# the elbow with the wrist servo. The final reaction still reaches the Torso.
	var motor := Vector3.ZERO
	for index: int in range(state.pose_chain.size()-1,-1,-1):
		var body: RigidBody3D = state.pose_chain[index].body
		var parent_body: RigidBody3D = anchor if index == 0 else state.pose_chain[index-1].body
		motor = (drives[index]+motor).limit_length(preset.maximum_pose_torque)
		body.sleeping = false
		body.apply_torque(motor)
		if not parent_body.freeze: parent_body.apply_torque(-motor)

static func unlock(state: Dictionary) -> void:
	var saved: Array[Dictionary] = []
	for link: Dictionary in state.pose_chain:
		var joint: Generic6DOFJoint3D = link.joint
		var body: RigidBody3D = link.body
		for axis: String in ["x","y","z"]:
			var limit := "angular_limit_%s/enabled" % axis
			var spring := "angular_spring_%s/enabled" % axis
			var lock := "axis_lock_angular_%s" % axis
			saved.append({"joint":joint,"body":body,"limit":limit,"spring":spring,"lock":lock,
				"limit_value":joint.get(limit),"spring_value":joint.get(spring),"lock_value":body.get(lock)})
			joint.set(limit,false)
			joint.set(spring,false)
			body.set(lock,false)
	state.pose_snapshot = saved

static func restore(state: Dictionary) -> void:
	for saved: Dictionary in state.get("pose_snapshot",[]):
		if is_instance_valid(saved.joint):
			saved.joint.set(saved.limit,saved.limit_value)
			saved.joint.set(saved.spring,saved.spring_value)
		if is_instance_valid(saved.body): saved.body.set(saved.lock,saved.lock_value)
	state.pose_snapshot = []
