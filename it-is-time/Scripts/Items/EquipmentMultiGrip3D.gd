extends RefCounted
## Soft auxiliary grips leave the item mass and collision geometry on its primary holder.

const POSE = preload("res://Scripts/Combat/WeaponArmPose3D.gd")
const OWNER := &"equipment_grip_driver"
const IDLE_OWNER := &"equipment_idle_pose_driver"
var rows: Array[Dictionary] = []
var idle_pose_diagnostics: Dictionary = {"state": "disabled"}
var _bindings: Array[Dictionary] = []
var _idle_pair: Array[Dictionary] = []
var _idle_mass: float = 1.0
var _idle_anchor: RigidBody3D
var _idle_bodies: Array = []
var _idle_joints: Array = []
var _idle_springs: Array[Dictionary] = []
var _inventory: Node
var _item: SampleItem3D
var _primary: RigidBody3D

func configure(inventory: Node, item: SampleItem3D, primary: RigidBody3D) -> void:
	release()
	_inventory = inventory
	_item = item
	_primary = primary
	var used := {primary: true}
	var joints := inventory.get_parent().find_children("*", "Generic6DOFJoint3D", true, false)
	for index: int in item.grip_point_count:
		var row := {"point": index+1, "role": "primary" if index == item.active_grip_point else "auxiliary",
			"requested_arm": str(item.get_grip_arm_path(index)), "enabled": item.is_grip_enabled(index), "state": "unassigned"}
		rows.append(row)
		if index == item.active_grip_point:
			row.state = "rigid_bound"
			row.holder = str(primary.get_path())
			continue
		if not row.enabled: row.state = "disabled"; continue
		if index >= item.grip_point_poses.size() or not item.grip_point_poses[index].origin.is_finite() or not item.grip_point_poses[index].basis.is_finite() or absf(item.grip_point_poses[index].basis.determinant()) < 0.000001: row.state = "invalid_pose"; continue
		if item.get_grip_arm_path(index).is_empty(): continue
		var hand: PhysicalBodyPart3D = inventory._resolve_grip_arm(item.get_grip_arm_path(index))
		if hand == null: row.state = "arm_unavailable"; continue
		if used.has(hand): row.state = "duplicate_arm"; continue
		var socket: Marker3D = inventory._resolve_item_socket(hand)
		var chain := _capture_chain(hand, socket, joints)
		var conflict := false
		for body: RigidBody3D in chain.bodies:
			if body.has_meta(OWNER) and is_instance_valid(body.get_meta(OWNER)): conflict = true
		if conflict: row.state = "arm_busy"; continue
		var swing := inventory.get_parent().get_node_or_null("LimbSwingController3D")
		if swing != null: swing.cancel_attacks_for_holder(hand)
		var settings := item.get_grip_settings(index)
		if settings == null: settings = ItemGripSettings.new()
		var record := {"index": index, "hand": hand, "socket": socket, "settings": settings,
			"chain": chain, "row": row, "springs": [], "visual": hand.get_visual_state(), "visual_owned": false}
		for body: RigidBody3D in chain.bodies: body.set_meta(OWNER, inventory)
		for joint: Generic6DOFJoint3D in chain.joints:
			for axis: String in ["x", "y", "z"]:
				var property := "angular_spring_%s/enabled" % axis
				record.springs.append({"joint": joint, "property": property, "value": joint.get(property)})
				joint.set(property, false)
		if &"grip" in hand.get_available_visual_states(): record.visual_owned = hand.set_visual_state(&"grip")
		row.holder = str(hand.get_path())
		row.state = "tracking"
		_bindings.append(record)
		used[hand] = true
	_capture_idle_pair(joints)

func _capture_idle_pair(joints: Array[Node]) -> void:
	if _item.idle_grip_pose == null: return
	for path: NodePath in [_item.idle_grip_pose.higher_arm_path, _item.idle_grip_pose.lower_arm_path]:
		var hand: RigidBody3D = _inventory._resolve_grip_arm(path)
		var point := -1
		var socket: Marker3D
		if hand != null and hand == _primary:
			point = _item.active_grip_point
			socket = hand.get_node_or_null("ItemSocket3D")
		else:
			for binding: Dictionary in _bindings:
				if binding.hand == hand:
					point = binding.index
					socket = binding.socket
		if point < 0 or socket == null:
			_idle_pair.clear()
			return
		_idle_pair.append({"hand": hand, "point": point, "socket": socket})
	if _idle_pair[0].hand == _idle_pair[1].hand:
		_idle_pair.clear()
		return
	if _primary != _idle_pair[0].hand and _primary != _idle_pair[1].hand:
		_idle_pair.clear()
		return
	var primary_chain := _capture_chain(_primary, _primary.get_node("ItemSocket3D"), joints)
	_idle_anchor = primary_chain.anchor
	_idle_bodies = primary_chain.bodies
	_idle_joints = primary_chain.joints
	var primary_mass := 0.0
	var auxiliary_mass := 0.0
	for body: RigidBody3D in primary_chain.bodies: primary_mass += body.mass
	for binding: Dictionary in _bindings:
		if binding.hand == _idle_pair[0].hand or binding.hand == _idle_pair[1].hand:
			for body: RigidBody3D in binding.chain.bodies: auxiliary_mass += body.mass
	_idle_mass = 1.0/(1.0/maxf(primary_mass, 0.001)+1.0/maxf(auxiliary_mass, 0.001))

func suspend_idle_pose() -> void:
	for body: Variant in _idle_bodies:
		if is_instance_valid(body) and body.has_meta(IDLE_OWNER) and body.get_meta(IDLE_OWNER) == _inventory: body.remove_meta(IDLE_OWNER)
	for saved: Dictionary in _idle_springs:
		if is_instance_valid(saved.joint): saved.joint.set(saved.property,saved.value)
	_idle_springs.clear()
	idle_pose_diagnostics = {"state": "suspended"}

func _update_idle_pose(delta: float) -> void:
	var config := _item.idle_grip_pose
	if config == null:
		suspend_idle_pose()
		idle_pose_diagnostics = {"state": "disabled"}
		return
	var blocked := ""
	var swing := _inventory.get_parent().get_node_or_null("LimbSwingController3D")
	if not config.enabled: blocked = "disabled"
	elif _idle_pair.size() != 2: blocked = "missing_pair"
	elif _primary.freeze: blocked = "frozen_primary"
	elif swing != null and swing.is_body_attacking(_primary): blocked = "attacking"
	if blocked.is_empty():
		for grip: Dictionary in _idle_pair:
			if not is_instance_valid(grip.hand) or not is_instance_valid(grip.socket) or grip.hand.is_broken or not _item.is_grip_enabled(grip.point) or grip.point >= _item.grip_point_poses.size():
				blocked = "unbound_pair"
				break
			if grip.hand != _primary and (not grip.hand.has_meta(OWNER) or grip.hand.get_meta(OWNER) != _inventory):
				blocked = "unbound_pair"
	if not blocked.is_empty():
		suspend_idle_pose()
		idle_pose_diagnostics.state = blocked
		return
	var higher: RigidBody3D = _idle_pair[0].hand
	var lower: RigidBody3D = _idle_pair[1].hand
	if config.use_line_angle and not _primary.has_meta(IDLE_OWNER):
		for body: RigidBody3D in _idle_bodies: body.set_meta(IDLE_OWNER, _inventory)
		for joint: Generic6DOFJoint3D in _idle_joints:
			for axis: String in ["x","y","z"]:
				var property := "angular_spring_%s/enabled" % axis
				_idle_springs.append({"joint":joint,"property":property,"value":joint.get(property)})
				joint.set(property, false)
	elif not config.use_line_angle and _primary.has_meta(IDLE_OWNER): suspend_idle_pose()
	var separation := higher.global_position-lower.global_position
	var horizontal := separation.slide(Vector3.UP)
	var relative_velocity := _point_velocity(higher,higher.global_position)-_point_velocity(lower,lower.global_position)
	var actual := separation.y
	var slope := tan(deg_to_rad(clampf(config.line_angle_degrees, 0.0, 75.0)))
	var target := horizontal.length()*slope if config.use_line_angle else config.height_difference
	var target_speed := horizontal.normalized().dot(relative_velocity)*slope if config.use_line_angle else 0.0
	var acceleration := _spring(Vector3.UP*(target-actual), Vector3.UP*(relative_velocity.y-target_speed), config.frequency, config.damping_ratio, delta).limit_length(config.maximum_acceleration)
	var force := (acceleration*_idle_mass).limit_length(config.maximum_force)
	# Adjust the primary arm against its shoulder; leave auxiliary grip tracking in control.
	if higher != _primary: force = -force
	var reach_force := Vector3.ZERO
	if config.use_line_angle:
		for binding: Dictionary in _bindings:
			if binding.hand != higher and binding.hand != lower: continue
			if not is_instance_valid(binding.chain.anchor): continue
			var pivot: Vector3 = binding.chain.anchor.to_global(binding.chain.anchor_local)
			var target_point := _item.to_global(_item.grip_point_poses[binding.index].origin)
			var radial := target_point-pivot
			var reach: float = binding.chain.reach*0.97
			if radial.length() <= reach: continue
			var velocity := _point_velocity(_primary,target_point)-_point_velocity(binding.chain.anchor,pivot)
			reach_force += _spring(radial.limit_length(reach)-radial,velocity.project(radial),config.frequency,config.damping_ratio,delta).limit_length(config.maximum_acceleration)*_idle_mass
	force = (force+reach_force).limit_length(config.maximum_force)
	if not force.is_zero_approx(): _primary.sleeping = false
	_primary.apply_force(force, Vector3.ZERO)
	if is_instance_valid(_idle_anchor) and not _idle_anchor.freeze: _idle_anchor.apply_force(-force, Vector3.ZERO)
	idle_pose_diagnostics = {"state": "tracking", "higher_arm": str(higher.name), "lower_arm": str(lower.name),
		"target_height_difference": target, "actual_height_difference": actual, "height_error": target-actual, "force": force,
		"angle_mode": config.use_line_angle, "target_angle_degrees": config.line_angle_degrees,
		"actual_angle_degrees": rad_to_deg(atan2(actual, horizontal.length())), "reach_force": reach_force}

func _capture_chain(hand: RigidBody3D, socket: Marker3D, joints: Array[Node]) -> Dictionary:
	var chain := {"bodies": [], "joints": [], "anchor": null, "anchor_local": Vector3.ZERO, "reach": 0.0}
	var current := hand
	var distal := socket.position
	var visited := {}
	while current != null and not visited.has(current):
		visited[current] = true
		chain.bodies.append(current)
		var found := false
		for joint: Generic6DOFJoint3D in joints:
			var a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
			var b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
			var other := b if a == current else (a if b == current else null)
			if other == null or visited.has(other) or other.is_broken: continue
			if other.is_ancestor_of(_item) or other == _primary: continue
			var proximal := POSE.local_anchor(joint, current)
			chain.reach += (current.global_basis*(proximal-distal)).length()
			chain.joints.append(joint)
			if PhysicalBodyPart3D.BodyPartTag.Torso not in other.tags and (PhysicalBodyPart3D.BodyPartTag.ArmLimb in other.tags or PhysicalBodyPart3D.BodyPartTag.Arm in other.tags):
				distal = POSE.local_anchor(joint, other)
				current = other
			else:
				chain.anchor = other
				chain.anchor_local = POSE.local_anchor(joint, other)
				current = null
			found = true
			break
		if not found: break
	return chain

func update(delta: float) -> void:
	if not is_instance_valid(_item) or not is_instance_valid(_primary): return
	for record: Dictionary in _bindings:
		if record.row.state in ["released", "broken", "disabled"]: continue
		var intact: bool = is_instance_valid(record.socket) and not record.socket.is_queued_for_deletion()
		for body: Variant in record.chain.bodies:
			if not is_instance_valid(body) or body.is_queued_for_deletion() or body.is_broken: intact = false
		for joint: Variant in record.chain.joints:
			if not is_instance_valid(joint) or joint.is_queued_for_deletion(): intact = false
		var anchor: Variant = record.chain.anchor
		if anchor != null and (not is_instance_valid(anchor) or anchor.is_broken): intact = false
		if not intact:
			_release_binding(record)
			record.row.state = "broken"
			continue
		var settings: ItemGripSettings = record.settings
		if not settings.enabled or record.index >= _item.grip_point_count or record.index >= _item.grip_point_poses.size():
			_release_binding(record)
			record.row.state = "disabled"
			continue
		var hand: RigidBody3D = record.hand
		var pose: Transform3D = _item.grip_point_poses[record.index]
		var target := _item.to_global(pose.origin)
		var socket_world: Vector3 = record.socket.global_position
		var desired := target
		var reachable := true
		if is_instance_valid(record.chain.anchor):
			var pivot: Vector3 = record.chain.anchor.to_global(record.chain.anchor_local)
			var reach: float = record.chain.reach
			reachable = pivot.distance_to(target) <= reach+0.02
			desired = pivot+(target-pivot).limit_length(reach*0.995)
		var relative_velocity := _point_velocity(hand, socket_world)-_point_velocity(_primary, target)
		var acceleration := _spring(desired-socket_world, relative_velocity, settings.position_frequency, settings.damping_ratio, delta).limit_length(settings.maximum_acceleration)
		var inverse_mass := 1.0/hand.mass+1.0/_primary.mass
		var force := (acceleration/inverse_mass).limit_length(settings.maximum_force)
		if not hand.freeze:
			hand.sleeping = false
			hand.apply_force(force, socket_world-hand.global_position)
		if not _primary.freeze: _primary.apply_force(-force, target-_primary.global_position)
		if settings.follow_rotation:
			var desired_basis := _item.global_basis*pose.basis.inverse()
			var error: Quaternion = (desired_basis.orthonormalized().get_rotation_quaternion()*record.socket.global_basis.orthonormalized().get_rotation_quaternion().inverse()).normalized()
			if error.w < 0: error = -error
			var alpha := _spring(error.get_axis()*error.get_angle(), hand.angular_velocity-_primary.angular_velocity, settings.rotation_frequency, settings.damping_ratio, delta).limit_length(settings.maximum_acceleration)
			var a := hand.get_inverse_inertia_tensor()
			var b := _primary.get_inverse_inertia_tensor()
			var inverse_inertia := Basis(a.x+b.x, a.y+b.y, a.z+b.z)
			var torque := Vector3.ZERO
			if absf(inverse_inertia.determinant()) > 1e-18: torque = (inverse_inertia.inverse()*alpha).limit_length(settings.maximum_torque)
			if not hand.freeze: hand.apply_torque(torque)
			if not _primary.freeze: _primary.apply_torque(-torque)
		record.row.merge({"state": "tracking" if reachable else "unreachable", "target_world": target,
			"socket_world": socket_world, "error_length": socket_world.distance_to(target), "reachable": reachable,
			"relative_speed": relative_velocity.length(), "force": force, "force_length": force.length(), "reach": record.chain.reach}, true)
	_update_idle_pose(delta)

func _spring(error: Vector3, velocity: Vector3, frequency: float, damping_ratio: float, delta: float) -> Vector3:
	var stiffness := pow(TAU*maxf(frequency, 0.1), 2.0)
	var damping := 2.0*maxf(damping_ratio, 0.1)*sqrt(stiffness)
	return (error*stiffness-velocity*(damping+stiffness*delta))/(1.0+damping*delta+stiffness*delta*delta)

func _point_velocity(body: RigidBody3D, point: Vector3) -> Vector3:
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	var center := body.to_global(state.center_of_mass_local if state != null else body.center_of_mass)
	return body.linear_velocity+body.angular_velocity.cross(point-center)

func release_part(part: RigidBody3D) -> void:
	if part in _idle_bodies or part == _idle_anchor:
		_idle_pair.clear()
		suspend_idle_pose()
	for record: Dictionary in _bindings:
		if part in record.chain.bodies:
			_release_binding(record)
			record.row.state = "broken"

func _release_binding(record: Dictionary) -> void:
	for body: Variant in record.chain.bodies:
		if is_instance_valid(body) and body.has_meta(OWNER) and body.get_meta(OWNER) == _inventory: body.remove_meta(OWNER)
	for saved: Dictionary in record.springs:
		if is_instance_valid(saved.joint): saved.joint.set(saved.property, saved.value)
	record.springs.clear()
	if is_instance_valid(record.hand) and record.visual_owned and record.hand.get_visual_state() == &"grip":
		record.hand.set_visual_state(record.visual)
	record.visual_owned = false
	record.row.state = "released"

func release() -> void:
	suspend_idle_pose()
	_idle_pair.clear()
	_idle_bodies.clear()
	_idle_anchor = null
	_idle_joints.clear()
	for record: Dictionary in _bindings: _release_binding(record)
	_bindings.clear()
	rows.clear()
	_item = null
	_primary = null
	_inventory = null
