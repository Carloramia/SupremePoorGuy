@tool
extends RefCounted

const EXTENSION_MARGIN := deg_to_rad(2.0)
const SOFT_EXTENSION := deg_to_rad(8.0)

static func frame(joint: Generic6DOFJoint3D, body: RigidBody3D) -> Transform3D:
	return joint.get_meta("generated_joint_frame_a" if joint.get_node(joint.node_a) == body else "generated_joint_frame_b")

static func configure(container: Node) -> void:
	var joints := container.get_node("Joints").get_children()
	for hip: Generic6DOFJoint3D in joints:
		if hip.get_meta("generated_connection_kind", "") != "HumanLeg": continue
		var root := hip.get_node(hip.node_a) as PhysicalBodyPart3D
		if PhysicalBodyPart3D.BodyPartTag.Torso not in root.tags: continue
		var upper := hip.get_node(hip.node_b) as RigidBody3D
		for knee: Generic6DOFJoint3D in joints:
			if knee.get_node(knee.node_a) != upper: continue
			var lower := knee.get_node(knee.node_b) as RigidBody3D
			for ankle: Generic6DOFJoint3D in joints:
				if ankle.get_node(ankle.node_a) != lower: continue
				var foot := ankle.get_node(ankle.node_b) as PhysicalBodyPart3D
				if PhysicalBodyPart3D.BodyPartTag.Leg not in foot.tags: continue
				var rest: Array[Quaternion] = [ankle.get_meta("generated_rest_b_relative_a"), knee.get_meta("generated_rest_b_relative_a"), hip.get_meta("generated_rest_b_relative_a")]
				configure_chain({"bodies":[foot,lower,upper,root], "joints":[ankle,knee,hip], "root":root, "anchor":frame(hip,root).origin, "rest_rotations":rest})

static func configure_chain(chain: Dictionary) -> void:
	if chain.bodies.size() != 4: return
	var upper: RigidBody3D = chain.bodies[2]
	var lower: RigidBody3D = chain.bodies[1]
	var knee: Generic6DOFJoint3D = chain.joints[1]
	var upper_vector := frame(knee,upper).origin-frame(chain.joints[2],upper).origin
	var lower_vector := frame(chain.joints[0],lower).origin-frame(knee,lower).origin
	var upper_rest := Basis(chain.rest_rotations[2])
	var lower_rest := upper_rest*Basis(chain.rest_rotations[1])
	var axis := (upper_rest*frame(knee,upper).basis.z).normalized()
	var bend := (upper_rest*upper_vector).signed_angle_to(lower_rest*lower_vector,axis)
	var side := signf(Vector3(chain.anchor).x)
	if is_zero_approx(side): side = 1.0
	var frame_sign := 1.0 if knee.get_node(knee.node_a) == upper else -1.0
	var allowed_sign := -side*signf(axis.z)*frame_sign
	var straight := -frame_sign*bend
	var original_limit: float = Vector3(knee.get_meta("authored_walk_limits",Vector3(0,0,PI/3.0))).z
	# The authored limit is relative to the generated pose, not to a straight leg.
	var maximum := clampf(original_limit-allowed_sign*straight,deg_to_rad(10.0),PI-deg_to_rad(1.0))
	var extended := straight-allowed_sign*EXTENSION_MARGIN
	var folded := straight+allowed_sign*maximum
	var limits := Vector2(minf(extended,folded),maxf(extended,folded))
	var geometry := {"side":side,"upper_vector":upper_vector,"lower_vector":lower_vector,"upper_length":upper_vector.length(),"lower_length":lower_vector.length(),"maximum_bend":maximum,"straight":straight,"allowed_sign":allowed_sign,"measured_limits":limits}
	chain["human_knee"] = geometry
	knee.set_meta("human_knee",geometry)
	# Generic6DOF limits measure A relative to B; the pose solver measures B relative to A.
	knee.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,-limits.y)
	knee.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,-limits.x)

static func solve(chain: Dictionary, ankle: Vector3, prediction: Vector3 = Vector3.ZERO) -> Dictionary:
	var result: Array[Quaternion] = chain.rest_rotations.duplicate()
	if not chain.has("human_knee"): return {"rotations":result,"reachable":true}
	var geometry: Dictionary = chain.human_knee
	var root: RigidBody3D = chain.root
	var hip := root.to_global(chain.anchor)+prediction
	var span := ankle-hip
	var a: float = geometry.upper_length
	var b: float = geometry.lower_length
	if minf(a,b)<0.001 or span.length()<0.001: return {"rotations":result,"reachable":false}
	var minimum := sqrt(a*a+b*b+2.0*a*b*cos(geometry.maximum_bend))
	var maximum := sqrt(a*a+b*b+2.0*a*b*cos(deg_to_rad(1.0)))
	var distance := clampf(span.length(),minimum,maximum)
	var outward := root.global_basis.x*float(geometry.side)
	var bend := outward.slide(span.normalized()).normalized()
	if bend.is_zero_approx(): return {"rotations":result,"reachable":false}
	var along := (a*a+distance*distance-b*b)/(2.0*distance)
	var knee := hip+span.normalized()*along+bend*sqrt(maxf(a*a-along*along,0.0))
	var fitted_ankle := hip+span.normalized()*distance
	var upper_rest := root.global_basis*Basis(result[2])
	var lower_rest := upper_rest*Basis(result[1])
	var upper_target := Basis(Quaternion((upper_rest*Vector3(geometry.upper_vector)).normalized(),(knee-hip).normalized()))*upper_rest
	var lower_target := Basis(Quaternion((lower_rest*Vector3(geometry.lower_vector)).normalized(),(fitted_ankle-knee).normalized()))*lower_rest
	result[2] = (root.global_basis.inverse()*upper_target).get_rotation_quaternion()
	result[1] = (upper_target.inverse()*lower_target).get_rotation_quaternion()
	var reachable := absf(span.length()-distance)<0.02
	for index: int in [1,2]:
		var joint: Generic6DOFJoint3D = chain.joints[index]
		var child: RigidBody3D = chain.bodies[index]
		var parent: RigidBody3D = chain.bodies[index+1]
		var angles := (frame(joint,parent).basis.inverse()*Basis(result[index])*frame(joint,child).basis).get_euler()
		# Existing hip X/Y rules already govern lateral motion; constrain the new bend range here.
		var low := -joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)
		var high := -joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)
		if angles.z<low-deg_to_rad(2.0) or angles.z>high+deg_to_rad(2.0): reachable = false
	return {"rotations":result,"reachable":reachable}

static func diagnostics(chain: Dictionary) -> Dictionary:
	if not chain.has("human_knee"): return {}
	var geometry: Dictionary = chain.human_knee
	var root: RigidBody3D = chain.root
	var upper: RigidBody3D = chain.bodies[2]
	var lower: RigidBody3D = chain.bodies[1]
	var upper_direction := (upper.global_basis*Vector3(geometry.upper_vector)).slide(root.global_basis.z.normalized())
	var lower_direction := (lower.global_basis*Vector3(geometry.lower_vector)).slide(root.global_basis.z.normalized())
	var flex := -float(geometry.side)*upper_direction.signed_angle_to(lower_direction,root.global_basis.z)
	return {"outward_bend_degrees":rad_to_deg(flex),"inward":flex < 0.0,"extension_limit_exceeded":flex < -EXTENSION_MARGIN,"measured_z_limits_degrees":Vector2(geometry.measured_limits)*180.0/PI}
