extends RefCounted
## Bow-only planar kinematics; the melee pose solver and joint limits remain unchanged.
const POSE = preload("res://Scripts/Combat/WeaponArmPose3D.gd")
const DATA = preload("res://Scripts/Combat/BowAttackData.gd")

static func capture(arm: Dictionary) -> void:
	var parent: RigidBody3D = arm.anchor_body
	var angles: Array[float] = []
	for index: int in arm.pose_chain.size():
		var link: Dictionary = arm.pose_chain[index]
		var joint: Generic6DOFJoint3D = link.joint
		var body: RigidBody3D = link.body
		var parent_key := &"generated_joint_frame_a" if joint.get_node_or_null(joint.node_a)==parent else &"generated_joint_frame_b"
		var child_key := &"generated_joint_frame_a" if joint.get_node_or_null(joint.node_a)==body else &"generated_joint_frame_b"
		link.parent_frame = joint.get_meta(parent_key)
		link.child_frame = joint.get_meta(child_key)
		var activation: Dictionary = joint.get_meta(&"diagnostic_activation_frames",{})
		if activation.get("a_id",0)==joint.get_node(joint.node_a).get_instance_id() and activation.get("b_id",0)==joint.get_node(joint.node_b).get_instance_id():
			link.parent_frame = activation.a if parent_key==&"generated_joint_frame_a" else activation.b
			link.child_frame = activation.a if child_key==&"generated_joint_frame_a" else activation.b
		link.proximal = Transform3D(link.child_frame).origin
		if index==0: arm.pose_anchor_local = Transform3D(link.parent_frame).origin
		else: arm.pose_chain[index-1].distal = Transform3D(link.parent_frame).origin
		link.spring_z = joint.get("angular_spring_z/enabled")
		joint.set("angular_spring_z/enabled",false)
		var relative: Basis = (parent.global_transform*Transform3D(link.parent_frame)).basis.orthonormalized().inverse()*(body.global_transform*Transform3D(link.child_frame)).basis.orthonormalized()
		angles.append(_clamp(link,relative.get_euler().z))
		parent = body
	arm.angles = angles
	arm.command_angles = angles.duplicate()
	var zero: Array[float] = []
	zero.resize(angles.size())
	zero.fill(0.0)
	var rest := poses(arm,zero)
	var lower: Vector3 = rest[1].basis*Vector3(arm.pose_chain[1].distal-arm.pose_chain[1].proximal)
	var hand: Vector3 = rest[2].basis*Vector3(arm.pose_chain[2].distal-arm.pose_chain[2].proximal)
	arm.neutral_wrist_angle = _clamp(arm.pose_chain[2],hand.signed_angle_to(lower,arm.anchor_body.global_basis.z.normalized()))

static func restore(arm: Dictionary) -> void:
	for link: Dictionary in arm.pose_chain:
		if is_instance_valid(link.joint): link.joint.set("angular_spring_z/enabled",link.spring_z)

static func _clamp(link: Dictionary, angle: float) -> float:
	angle = wrapf(angle,-PI,PI)
	if not link.joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT): return angle
	return clampf(angle,-link.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT),-link.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT))

static func poses(arm: Dictionary, angles: Array[float]) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var parent: Transform3D = arm.anchor_body.global_transform
	for index: int in arm.pose_chain.size():
		var link: Dictionary = arm.pose_chain[index]
		parent = parent*Transform3D(link.parent_frame)*Transform3D(Basis(Vector3.BACK,angles[index]),Vector3.ZERO)*Transform3D(link.child_frame).affine_inverse()
		result.append(parent)
	return result

static func endpoint(arm: Dictionary, targets: Array[Transform3D]) -> Vector3:
	return targets[-1]*Vector3(arm.pose_chain[-1].distal)

static func project(arm: Dictionary, point: Vector3) -> Vector3:
	var normal: Vector3 = arm.anchor_body.global_basis.z.normalized()
	var origin: Vector3 = arm.anchor_body.to_global(arm.pose_anchor_local)
	return point-normal*(point-origin).dot(normal)

static func apply(arm: Dictionary, motor: WeaponArmAttackPreset, delta: float, speed: float) -> void:
	var parent: RigidBody3D = arm.anchor_body
	var omega := TAU*motor.pose_frequency
	var stiffness := omega*omega
	var damping := 2.0*motor.pose_damping_ratio*omega
	var loads: Array[Dictionary] = []
	var drives: Array[Dictionary] = []
	for link: Dictionary in arm.pose_chain:
		var body: RigidBody3D = link.body
		var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
		var gravity: Vector3 = state.total_gravity if state!=null else Vector3(ProjectSettings.get_setting("physics/3d/default_gravity_vector"))*float(ProjectSettings.get_setting("physics/3d/default_gravity"))*body.gravity_scale
		loads.append({"point":body.to_global(state.center_of_mass_local if state!=null else body.center_of_mass),"force":gravity*body.mass})
	if arm.get("primary",false) and is_instance_valid(arm.get("weapon")):
		var compensation: Dictionary = arm.weapon.get_held_gravity_compensation()
		if not compensation.is_empty() and compensation.body==arm.hand:
			loads.append({"point":compensation.point,"force":compensation.force})
	for index: int in arm.pose_chain.size():
		var link: Dictionary = arm.pose_chain[index]
		var body: RigidBody3D = link.body
		var frame: Basis = (parent.global_transform*Transform3D(link.parent_frame)).basis.orthonormalized()
		var relative: Basis = frame.inverse()*(body.global_transform*Transform3D(link.child_frame)).basis.orthonormalized()
		arm.command_angles[index] = move_toward(arm.command_angles[index],arm.angles[index],speed*delta)
		var change := (Basis(Vector3.BACK,arm.command_angles[index])*relative.inverse()).get_rotation_quaternion().normalized()
		if change.w<0.0: change = -change
		var error := change.get_axis()*change.get_angle()
		# A bounded hinge must take the legal route, rather than the shortest quaternion route across its stop.
		error.z = float(arm.command_angles[index])-relative.get_euler().z
		var rate := body.angular_velocity-parent.angular_velocity
		var requested_acceleration := (frame*error*stiffness-rate*(damping+stiffness*delta))/(1.0+damping*delta+stiffness*delta*delta)
		var acceleration := requested_acceleration.limit_length(motor.maximum_pose_acceleration)
		var a := body.get_inverse_inertia_tensor()
		var b := parent.get_inverse_inertia_tensor() if not parent.freeze else Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO)
		var torque := Vector3.ZERO
		for axis: Vector3 in [frame.x,frame.y,frame.z]:
			var inverse := axis.dot(a*axis+b*axis)
			if inverse>0.000001: torque += axis*acceleration.dot(axis)/inverse
		# Each proximal joint also carries the gravity load of its distal links and held bow.
		var pivot: Vector3 = parent.to_global(Transform3D(link.parent_frame).origin)
		var gravity_torque := Vector3.ZERO
		for load_index: int in range(index,loads.size()):
			gravity_torque += (Vector3(loads[load_index].point)-pivot).cross(-Vector3(loads[load_index].force))
		link.gravity_torque = gravity_torque
		link.actual_angle = relative.get_euler().z
		link.motor_frame = Engine.get_physics_frames()
		link.angle_error = error
		link.relative_angular_velocity = rate
		link.requested_acceleration = requested_acceleration
		link.servo_acceleration = acceleration
		link.servo_torque = torque
		drives.append({"body":body,"parent":parent,"motor":torque,"gravity":gravity_torque})
		parent = body
	# Carry distal servo reactions through the chain, as in WeaponArmPose3D.
	# Gravity already includes distal loads and must not be accumulated a second time.
	var carried := Vector3.ZERO
	for index: int in range(drives.size()-1,-1,-1):
		var drive: Dictionary = drives[index]
		carried += Vector3(drive.motor)
		var torque := (carried+Vector3(drive.gravity)).limit_length(motor.maximum_pose_torque)
		arm.pose_chain[index].carried_servo_torque = carried
		arm.pose_chain[index].requested_torque = carried+Vector3(drive.gravity)
		arm.pose_chain[index].last_torque = torque
		drive.body.apply_torque(torque)
		if not drive.parent.freeze: drive.parent.apply_torque(-torque)

static func posture_metrics(arm: Dictionary, targets: Array[Transform3D], angles: Array[float], direction: Vector3, preferences: DATA) -> Dictionary:
	var shoulder: Vector3 = arm.anchor_body.to_global(arm.pose_anchor_local)
	var elbow: Vector3 = targets[0]*Vector3(arm.pose_chain[0].distal)
	var wrist: Vector3 = targets[1]*Vector3(arm.pose_chain[1].distal)
	var grip := endpoint(arm,targets)
	var upper := (elbow-shoulder).normalized()
	var elevation := rad_to_deg(asin(clampf(upper.dot(arm.anchor_body.global_basis.y.normalized()),-1.0,1.0)))
	var interior := rad_to_deg((shoulder-elbow).angle_to(wrist-elbow))
	var wrist_bend := 180.0-rad_to_deg((elbow-wrist).angle_to(grip-wrist))
	var desired := preferences.bow_arm_elbow_degrees if arm.get("primary",false) else preferences.string_arm_elbow_degrees
	var minimum_margin := 180.0
	var margin_cost := 0.0
	for index: int in angles.size():
		var joint: Generic6DOFJoint3D = arm.pose_chain[index].joint
		if not joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT): continue
		var lower := -joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)
		var limit := -joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)
		var margin := rad_to_deg(minf(angles[index]-lower,limit-angles[index]))
		minimum_margin = minf(minimum_margin,margin)
		margin_cost += pow(maxf(preferences.preferred_joint_margin_degrees-margin,0.0)/maxf(preferences.preferred_joint_margin_degrees,1.0),2.0)
	var score := 4.0*pow(maxf(elevation-preferences.maximum_elbow_elevation_degrees,0.0)/45.0,2.0)
	score += pow((interior-desired)/60.0,2.0)+2.0*pow(wrist_bend/preferences.maximum_wrist_bend_degrees,2.0)+margin_cost
	if arm.get("primary",false): score += 3.0*pow(maxf(-upper.dot(direction)-0.1,0.0),2.0)
	var comfortable: bool = elevation<=preferences.maximum_elbow_elevation_degrees+2.0 and wrist_bend<=preferences.maximum_wrist_bend_degrees+2.0 and absf(interior-desired)<=35.0 and minimum_margin>=preferences.preferred_joint_margin_degrees*0.5
	return {"score":score,"comfortable":comfortable,"elbow_elevation_degrees":elevation,"elbow_interior_degrees":interior,"wrist_bend_degrees":wrist_bend,"minimum_joint_margin_degrees":minimum_margin}

static func solve(arm: Dictionary, end: Vector3, direction: Vector3, orient_hand: bool, preferences: DATA = null) -> Dictionary:
	end = project(arm,end)
	var normal: Vector3 = arm.anchor_body.global_basis.z.normalized()
	var angles: Array[float] = arm.angles.duplicate()
	var targets := poses(arm,angles)
	var anatomical: bool = preferences!=null and preferences.anatomical_pose_enabled and preferences.anatomical_pose_weight>0.0
	if not orient_hand:
		# The string hand has no required roll; keep its wrist free within its authored limits.
		if anatomical and not arm.get("continuous_pose",false): angles[-1] = arm.neutral_wrist_angle
		targets = poses(arm,angles)
		for iteration: int in 16:
			for index: int in range(angles.size()-1,-1,-1):
				var pivot: Vector3 = targets[index]*Vector3(arm.pose_chain[index].proximal)
				var current := (endpoint(arm,targets)-pivot).slide(normal)
				var desired := (end-pivot).slide(normal)
				if current.is_zero_approx() or desired.is_zero_approx(): continue
				angles[index] = _clamp(arm.pose_chain[index],angles[index]+current.signed_angle_to(desired,normal))
				if anatomical and index==angles.size()-1:
					var span := deg_to_rad(preferences.maximum_wrist_bend_degrees)
					angles[index] = _clamp(arm.pose_chain[index],clampf(angles[index],arm.neutral_wrist_angle-span,arm.neutral_wrist_angle+span))
				targets = poses(arm,angles)
			if endpoint(arm,targets).distance_to(end)<0.002: break
		return {"poses":targets,"angles":angles,"end":endpoint(arm,targets),"error":endpoint(arm,targets).distance_to(end),"aim_error":0.0}
	# Fix the hand orientation first, subtract its wrist-to-grip lever, then solve the elbow.
	var zero: Array[float] = []
	zero.resize(angles.size())
	zero.fill(0.0)
	var rest := poses(arm,zero)
	var hand_basis := rest[-1].basis
	var forward: Vector3 = (hand_basis*Vector3(arm.weapon_forward_local)).slide(normal)
	var desired_forward := direction.slide(normal).normalized()
	hand_basis = Basis(normal,forward.signed_angle_to(desired_forward,normal))*hand_basis
	var hand: Dictionary = arm.pose_chain[-1]
	var wrist := end-hand_basis*Vector3(hand.distal-hand.proximal)
	var pivot: Vector3 = arm.anchor_body.to_global(arm.pose_anchor_local)
	var offset := (wrist-pivot).slide(normal)
	var upper: Vector3 = rest[0].basis*Vector3(arm.pose_chain[0].distal-arm.pose_chain[0].proximal)
	var lower: Vector3 = rest[1].basis*Vector3(arm.pose_chain[1].distal-arm.pose_chain[1].proximal)
	var distance := clampf(offset.length(),absf(upper.length()-lower.length())+0.001,upper.length()+lower.length()-0.001)
	var axis := offset.normalized() if not offset.is_zero_approx() else desired_forward
	var along := (upper.length_squared()+distance*distance-lower.length_squared())/(2.0*distance)
	var height := sqrt(maxf(upper.length_squared()-along*along,0.0))
	var best: Dictionary = {}
	for sign_value: float in [-1.0,1.0]:
		var elbow := pivot+axis*along+normal.cross(axis)*height*sign_value
		var bases: Array[Basis] = [Basis(normal,upper.signed_angle_to(elbow-pivot,normal))*rest[0].basis,
			Basis(normal,lower.signed_angle_to(pivot+axis*distance-elbow,normal))*rest[1].basis,hand_basis]
		var parent: Transform3D = arm.anchor_body.global_transform
		var candidate: Array[float] = []
		for index: int in angles.size():
			var link: Dictionary = arm.pose_chain[index]
			var relative: Basis = (parent*Transform3D(link.parent_frame)).basis.orthonormalized().inverse()*(bases[index]*Transform3D(link.child_frame).basis).orthonormalized()
			candidate.append(_clamp(link,relative.get_euler().z))
			parent = parent*Transform3D(link.parent_frame)*Transform3D(Basis(Vector3.BACK,candidate[-1]),Vector3.ZERO)*Transform3D(link.child_frame).affine_inverse()
		targets = poses(arm,candidate)
		var aim := (targets[-1].basis*Vector3(arm.weapon_forward_local)).normalized().angle_to(desired_forward)
		var error := endpoint(arm,targets).distance_to(end)
		var feasible := error<POSE.reach(arm.pose_chain)*0.05 and aim<deg_to_rad(3.0)
		var score := error*error+aim*aim*POSE.reach(arm.pose_chain)*POSE.reach(arm.pose_chain)
		if anatomical: score += preferences.anatomical_pose_weight*float(posture_metrics(arm,targets,candidate,direction,preferences).score)
		var continuity := 0.0
		for index: int in angles.size(): continuity += pow(candidate[index]-angles[index],2.0)
		var better: bool = best.is_empty() or score<float(best.score)
		if anatomical and not best.is_empty() and feasible!=bool(best.feasible): better = feasible
		elif arm.get("continuous_pose",false) and not best.is_empty() and feasible and best.feasible: better = continuity<float(best.continuity)
		if better:
			best = {"poses":targets,"angles":candidate,"end":endpoint(arm,targets),"error":error,"aim_error":aim,"score":score,"feasible":feasible,"continuity":continuity}
	return best

