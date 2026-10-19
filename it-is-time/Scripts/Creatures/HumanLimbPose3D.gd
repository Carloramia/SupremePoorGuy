extends RefCounted

const KNEE = preload("res://Scripts/Creatures/HumanKneeGeometry3D.gd")

var _arms: Array[Dictionary] = []
var _blends: Dictionary = {}
var rows: Array[Dictionary] = []
var frame: int = -1

func capture(movement: Node) -> void:
	_arms.clear()
	_blends.clear()
	rows.clear()
	for chain: Dictionary in movement._chains.values(): KNEE.configure_chain(chain)
	var parts := movement.get_node_or_null(movement.parts_root_path)
	if parts == null: return
	for joint: Generic6DOFJoint3D in parts.find_children("*", "Generic6DOFJoint3D", true, false):
		if joint.get_meta("generated_connection_kind", "") != "HumanArm": continue
		var parent_body := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
		var child := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
		if child == null or parent_body == null: continue
		var springs: Array[bool] = []
		for axis: String in ["x", "y", "z"]: springs.append(joint.call("get_flag_"+axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING))
		var actual_springs := springs.duplicate()
		if not joint.has_meta("human_original_arm_springs"): joint.set_meta("human_original_arm_springs",springs)
		springs = joint.get_meta("human_original_arm_springs")
		_arms.append({"child":child, "parent":parent_body, "joint":joint, "springs":springs, "claimed":actual_springs != springs,
			"rest":joint.get_meta("generated_rest_b_relative_a", parent_body.quaternion.inverse()*child.quaternion)})

func apply(movement: Node, delta: float) -> void:
	rows.clear()
	frame = Engine.get_physics_frames()
	var swing := movement.get_parent().get_node_or_null("LimbSwingController3D")
	var blocked: bool = not movement.human_limb_pose_enabled or movement.recovery_control_active or movement._planar_mode_active()
	for link: Dictionary in _arms:
		if not _available(link.child, link.parent, link.joint): continue
		var attacking: bool = swing != null and (swing.is_body_driven(link.child) or swing.is_body_driven(link.parent))
		if blocked or attacking:
			_blends.erase(link.joint)
			# Attack code owns its spring snapshots until recovery is finished.
			if blocked and not attacking and link.claimed: _set_arm_springs(link, true)
			var owner := "disabled"
			if attacking:
				owner = "attack" if swing.is_body_attacking(link.child) or swing.is_body_attacking(link.parent) else ("equipment_idle_pose" if link.child.has_meta(&"equipment_idle_pose_driver") or link.parent.has_meta(&"equipment_idle_pose_driver") else "equipment_grip")
			rows.append({"joint":link.joint.name, "body":link.child.name, "owner":owner, "torque":Vector3.ZERO})
			continue
		if not link.claimed: _set_arm_springs(link, false)
		_apply_joint(movement, link.child, link.parent, link.joint, link.rest, 1.0, "rest", delta)
	if blocked:
		_blends.clear()
		return
	for foot: Variant in movement._chains:
		if not movement._chain_is_intact(foot): continue
		var chain: Dictionary = movement._chains[foot]
		var stepping: bool = movement.is_leg_stepping(foot) or movement._turn_command_pending
		var moving: bool = not movement.get_input_movement_direction().is_zero_approx() or chain.root.linear_velocity.slide(Vector3.UP).length() > 0.15
		var targets: Array[Quaternion] = _leg_targets(chain)
		if stepping and foot == movement._active_leg:
			var progress: float = clampf(movement._step_elapsed/maxf(movement._active_step_duration,0.001),0.0,1.0)
			var planned: Vector3 = movement._quadratic_step_position(progress) if movement._step_state == movement.StepState.MOVING else movement._step_target
			targets = KNEE.solve(chain,planned+foot.global_basis*_frame(chain.joints[0],foot).origin).rotations
		for index: int in range(1, chain.joints.size()):
			var child: RigidBody3D = chain.bodies[index]
			var parent_body: RigidBody3D = chain.bodies[index+1]
			var joint: Generic6DOFJoint3D = chain.joints[index]
			if not _available(child, parent_body, joint): continue
			if stepping and index != 1:
				_blends.erase(joint)
				rows.append({"joint":joint.name, "body":child.name, "owner":"step", "torque":Vector3.ZERO})
				continue
			var weight: float = 0.0 if movement._turn_command_pending else movement.human_swing_knee_weight if stepping else movement.human_moving_pose_weight if moving else 1.0
			_apply_joint(movement, child, parent_body, joint, targets[index], weight, "swing_knee" if stepping else "stance_ik" if moving else "rest", delta, not movement._turn_command_pending)
			if index == 1: rows[-1].merge(KNEE.diagnostics(chain))

func _available(child: Variant, parent_body: Variant, joint: Variant) -> bool:
	return is_instance_valid(child) and is_instance_valid(parent_body) and is_instance_valid(joint) and not joint.is_queued_for_deletion() and not child.is_broken and not parent_body.is_broken and not child.freeze

func _set_arm_springs(link: Dictionary, restore: bool) -> void:
	for index: int in 3:
		link.joint.call("set_flag_"+["x","y","z"][index], Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, link.springs[index] if restore else false)
	link.claimed = not restore

func _frame(joint: Generic6DOFJoint3D, body: RigidBody3D) -> Transform3D:
	return joint.get_meta("generated_joint_frame_a" if joint.get_node_or_null(joint.node_a) == body else "generated_joint_frame_b")

func _leg_targets(chain: Dictionary) -> Array[Quaternion]:
	if chain.bodies.size() != 4: return chain.rest_rotations
	var foot: RigidBody3D = chain.bodies[0]
	var ankle := foot.to_global(_frame(chain.joints[0], foot).origin)
	return KNEE.solve(chain,ankle).rotations

func _apply_joint(movement: Node, child: RigidBody3D, parent_body: RigidBody3D, joint: Generic6DOFJoint3D, target: Quaternion, weight: float, owner: String, delta: float, extension_guard: bool = true) -> void:
	var child_frame := _frame(joint, child)
	var parent_frame := _frame(joint, parent_body)
	var local_target := parent_frame.basis.inverse()*Basis(target)*child_frame.basis
	var angles := local_target.get_euler()
	if extension_guard and joint.has_meta("human_knee"):
		var geometry: Dictionary = joint.get_meta("human_knee")
		var current := (parent_frame.basis.inverse()*parent_body.global_basis.inverse()*child.global_basis*child_frame.basis).get_euler().z
		var bend: float = (current-float(geometry.straight))*float(geometry.allowed_sign)
		var extension_weight := 1.0-smoothstep(0.0,KNEE.SOFT_EXTENSION,bend)
		weight = maxf(weight,extension_weight*0.6)
		if (angles.z-float(geometry.straight))*float(geometry.allowed_sign)<KNEE.SOFT_EXTENSION:
			angles.z = float(geometry.straight)+float(geometry.allowed_sign)*KNEE.SOFT_EXTENSION
	for index: int in 3:
		var axis: String = ["x","y","z"][index]
		if joint.call("get_flag_"+axis, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT):
			angles[index] = clampf(angles[index], -joint.call("get_param_"+axis, Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), -joint.call("get_param_"+axis, Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT))
	target = (parent_frame.basis*Basis.from_euler(angles)*child_frame.basis.inverse()).get_rotation_quaternion()
	var error: Vector3 = movement._stance_rotation_error(child, parent_body, target)
	var rate := child.angular_velocity-parent_body.angular_velocity
	var omega: float = TAU*movement.human_pose_frequency
	var stiffness := omega*omega
	var damping: float = 2.0*movement.human_pose_damping_ratio*omega
	# Same implicit damping used by the bird pose servo, after relative-inertia scaling.
	var acceleration := ((error*stiffness-rate*(damping+stiffness*delta))/(1.0+damping*delta+stiffness*delta*delta)).limit_length(movement.human_pose_acceleration_limit)
	var child_inverse: Basis = movement._stance_inverse_inertia(child)
	var parent_inverse: Basis = movement._stance_inverse_inertia(parent_body)
	var basis := parent_body.global_basis*parent_frame.basis
	if owner == "swing_knee": acceleration = acceleration.project(basis.z.normalized())
	var raw := Vector3.ZERO
	for index: int in 3:
		# Like Wolf's plane servo, assist solver drift toward the authored locked frame.
		var axis: Vector3 = basis[index].normalized()
		raw += axis*acceleration.dot(axis)/maxf(axis.dot(child_inverse*axis+parent_inverse*axis),0.000001)
	var blend := move_toward(float(_blends.get(joint,0.0)), weight, delta/0.2)
	_blends[joint] = blend
	var torque := raw.limit_length(movement.human_pose_torque_limit)*blend
	child.apply_torque(torque)
	if not parent_body.freeze: parent_body.apply_torque(-torque)
	rows.append({"joint":joint.name, "body":child.name, "owner":owner, "error_degrees":rad_to_deg(error.length()), "relative_speed":rate.length(), "blend":blend, "torque":torque, "limited":raw.length()>movement.human_pose_torque_limit})
