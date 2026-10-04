class_name LimbSwingController3D
extends Node3D

const PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")

enum SwingState { IDLE, CHARGING, SWINGING, COOLDOWN, FOLLOW_THROUGH, RECOVERING }

const ARM_TAG: int = 2

## Groups map names to inputs. Arm membership and presets live on BodyParts.
@export var control_groups: Array[SwingControlGroup] = []
@export var diagnostic_logging: bool = false
@export var terrain_cursor: Node3D

var _states: Array[Dictionary] = []
var _body_owner_group: Dictionary = {}
var _rest_geometry_by_binding: Dictionary = {}
var _active_damage_swings: int = 0

func _ready() -> void:
	add_to_group(&"limb_swing_controllers")
	var runtime_console := get_tree().root.get_node_or_null("RuntimeConsole")
	if runtime_console != null and runtime_console.has_method("is_swing_tracking_enabled"):
		diagnostic_logging = bool(runtime_console.call("is_swing_tracking_enabled"))
	refresh_arm_bindings(true)
	var character := get_parent()
	if character != null:
		character.child_entered_tree.connect(_on_character_child_changed)
		character.child_exiting_tree.connect(_on_character_child_changed)

func _physics_process(delta: float) -> void:
	if not PLAYER_CONTEXT.input_allowed(self):
		_cancel_all_members()
		return
	_ensure_runtime_states()
	for group_index: int in range(control_groups.size()):
		var group := control_groups[group_index]
		if group == null or not group.enabled:
			_cancel_group(group_index)
			continue
		var pressed := PLAYER_CONTEXT.action_pressed(self, group.input_action)
		for member_state: Dictionary in _states[group_index].members:
			_process_member(group_index, member_state, pressed, delta)

## Re-scan after changing BodyParts or their bindings at runtime.
func refresh_arm_bindings(reset_rest_pose: bool = false) -> void:
	_cancel_all_members()
	if reset_rest_pose:
		_rest_geometry_by_binding.clear()
	_rebuild_runtime_states()
	var character := get_parent()
	if character == null:
		return
	var group_indices: Dictionary = {}
	for group_index: int in range(control_groups.size()):
		var group := control_groups[group_index]
		if group == null:
			continue
		if group_indices.has(group.group_name):
			push_warning("Duplicate swing group '%s'; the first group is used." % group.group_name)
			continue
		group_indices[group.group_name] = group_index
		if not InputMap.has_action(group.input_action):
			push_warning("Swing group '%s' references missing action '%s'." % [group.group_name, group.input_action])
	for node: Node in character.find_children("*", "PhysicalBodyPart3D", true, false):
		var part := node as PhysicalBodyPart3D
		if part == null or part.is_broken or ARM_TAG not in part.tags:
			continue
		for binding: ArmSwingBinding in part.arm_swing_bindings:
			_register_binding(part, binding, group_indices)

func begin_charge(group_index: int) -> bool:
	_ensure_runtime_states()
	if not _is_valid_group_index(group_index):
		return false
	var started := false
	for member_state: Dictionary in _states[group_index].members:
		if int(member_state.mode) == SwingState.IDLE:
			started = _begin_member(group_index, member_state) or started
	return started

func release_charge(group_index: int) -> bool:
	_ensure_runtime_states()
	if not _is_valid_group_index(group_index):
		return false
	var released := false
	for member_state: Dictionary in _states[group_index].members:
		if int(member_state.mode) == SwingState.CHARGING:
			_release_member(group_index, member_state)
			released = true
	return released

func add_charge_time(group_index: int, duration: float) -> void:
	_ensure_runtime_states()
	if not _is_valid_group_index(group_index):
		return
	for member_state: Dictionary in _states[group_index].members:
		if int(member_state.mode) != SwingState.CHARGING:
			continue
		var preset := member_state.preset as LimbSwingPresetBase
		member_state.charge_time = minf(
			float(member_state.charge_time) + maxf(duration, 0.0),
			maxf(preset.maximum_charge_time, preset.minimum_charge_time)
		)

func get_group_state(group_index: int) -> SwingState:
	if not _has_runtime_group(group_index):
		return SwingState.IDLE
	var found_charging := false
	var found_cooldown := false
	for member_state: Dictionary in _states[group_index].members:
		match int(member_state.mode):
			SwingState.SWINGING, SwingState.FOLLOW_THROUGH:
				return SwingState.SWINGING
			SwingState.RECOVERING:
				found_cooldown = true
			SwingState.CHARGING:
				found_charging = true
			SwingState.COOLDOWN:
				found_cooldown = true
	if found_charging:
		return SwingState.CHARGING
	return SwingState.COOLDOWN if found_cooldown else SwingState.IDLE

func get_group_charge_time(group_index: int) -> float:
	if not _has_runtime_group(group_index):
		return 0.0
	var result := 0.0
	for member_state: Dictionary in _states[group_index].members:
		result = maxf(result, float(member_state.charge_time))
	return result

func get_group_swing_torque(group_index: int) -> float:
	if not _has_runtime_group(group_index):
		return 0.0
	var result := 0.0
	for member_state: Dictionary in _states[group_index].members:
		result = maxf(result, float(member_state.swing_torque))
	return result

func get_group_member_count(group_index: int) -> int:
	return _states[group_index].members.size() if _has_runtime_group(group_index) else 0

func set_diagnostic_logging_enabled(enabled: bool) -> void:
	diagnostic_logging = enabled

func is_diagnostic_logging_enabled() -> bool:
	return diagnostic_logging

func _register_binding(part: PhysicalBodyPart3D, binding: ArmSwingBinding, group_indices: Dictionary) -> void:
	if binding == null or not binding.enabled:
		return
	if binding.swing_preset == null:
		push_warning("Arm '%s' has a swing binding without a preset." % part.name)
		return
	if not group_indices.has(binding.control_group_name):
		push_warning("Arm '%s' references missing swing group '%s'." % [part.name, binding.control_group_name])
		return
	var group_index := int(group_indices[binding.control_group_name])
	for existing: Dictionary in _states[group_index].members:
		if existing.body == part:
			push_warning("Arm '%s' has duplicate bindings for group '%s'." % [part.name, binding.control_group_name])
			return
	var joint := _resolve_binding_joint(part, binding)
	if joint == null:
		push_warning("Arm '%s' cannot resolve a joint for group '%s'." % [part.name, binding.control_group_name])
		return
	_states[group_index].members.append(_new_member_state(part, joint, binding))

func _new_member_state(body: PhysicalBodyPart3D, joint: Generic6DOFJoint3D, binding: ArmSwingBinding) -> Dictionary:
	var rest_geometry := _get_or_create_rest_geometry(body, joint, binding)
	return {
		&"body": body, &"joint": joint, &"binding": binding, &"preset": binding.swing_preset,
		&"anchor_body": rest_geometry.anchor_body,
		&"anchor_local_position": rest_geometry.anchor_local_position,
		&"axis_local": rest_geometry.axis_local,
		&"joint_basis_local": rest_geometry.joint_basis_local,
		&"rest_basis_local": rest_geometry.rest_basis_local,
		&"rest_lever_local": rest_geometry.rest_lever_local,
		&"mode": SwingState.IDLE, &"charge_time": 0.0, &"time_remaining": 0.0,
		&"lift_angle": 0.0, &"swing_torque": 0.0, &"snapshot": {},
		&"charge_bank_active": false, &"charge_bank_angle": 0.0,
		&"release_axis_world": Vector3.ZERO, &"release_axis_body_local": Vector3.ZERO,
		&"release_joint_snapshot": [], &"attack_tuning": {}, &"recovery_elapsed": 0.0, &"sustained_elapsed": 0.0,
		&"aim_joint_snapshot": {}, &"aim_target": null, &"aim_log_elapsed": 0.0, &"aim_error": 0.0,
	}

func _get_or_create_rest_geometry(
	body: PhysicalBodyPart3D,
	joint: Generic6DOFJoint3D,
	binding: ArmSwingBinding
) -> Dictionary:
	var preset := binding.swing_preset
	var geometry_key := "%d:%d:%d" % [
		body.get_instance_id(),
		joint.get_instance_id(),
		preset.joint_axis,
	]
	if _rest_geometry_by_binding.has(geometry_key):
		var cached := _rest_geometry_by_binding[geometry_key] as Dictionary
		if is_instance_valid(cached.get(&"anchor_body")):
			return cached
	var anchor_body := _get_other_joint_body(joint, body) as PhysicalBodyPart3D
	if anchor_body == null:
		anchor_body = body
	var axis_world := _get_joint_axis_world(joint, preset.joint_axis)
	var rest_geometry := {
		&"anchor_body": anchor_body,
		&"anchor_local_position": anchor_body.to_local(joint.global_position),
		&"axis_local": anchor_body.global_basis.inverse() * axis_world,
		&"joint_basis_local": anchor_body.global_basis.inverse() * joint.global_basis,
		&"rest_basis_local": anchor_body.global_basis.inverse() * body.global_basis,
		&"rest_lever_local": (
			anchor_body.global_basis.inverse()
			* (body.global_position - joint.global_position)
		),
	}
	_rest_geometry_by_binding[geometry_key] = rest_geometry
	return rest_geometry

func _get_other_joint_body(joint: Joint3D, body: PhysicsBody3D) -> PhysicsBody3D:
	var body_a := joint.get_node_or_null(joint.node_a) as PhysicsBody3D
	var body_b := joint.get_node_or_null(joint.node_b) as PhysicsBody3D
	if body_a == body:
		return body_b
	if body_b == body:
		return body_a
	return null

func _resolve_binding_joint(part: PhysicalBodyPart3D, binding: ArmSwingBinding) -> Generic6DOFJoint3D:
	if not binding.joint_path.is_empty():
		return part.get_node_or_null(binding.joint_path) as Generic6DOFJoint3D
	var candidates: Array[Generic6DOFJoint3D] = []
	for node: Node in get_parent().find_children("*", "Generic6DOFJoint3D", true, false):
		var joint := node as Generic6DOFJoint3D
		if joint == null or joint.is_queued_for_deletion():
			continue
		var body_a := joint.get_node_or_null(joint.node_a)
		var body_b := joint.get_node_or_null(joint.node_b)
		if body_a != part and body_b != part:
			continue
		var other := body_b if body_a == part else body_a
		if other is PhysicalBodyPart3D:
			candidates.append(joint)
	if candidates.size() == 1:
		return candidates[0]
	if candidates.size() > 1:
		push_warning("Arm '%s' has multiple BodyPart joints; set Joint Path explicitly." % part.name)
	return null

func _process_member(group_index: int, member_state: Dictionary, pressed: bool, delta: float) -> void:
	var body_value: Variant = member_state.get(&"body")
	var joint_value: Variant = member_state.get(&"joint")
	if not is_instance_valid(body_value) or not is_instance_valid(joint_value):
		_invalidate_member_state(group_index, member_state, body_value)
		return
	var body := body_value as PhysicalBodyPart3D
	var joint := joint_value as Generic6DOFJoint3D
	if body.is_broken:
		_cancel_member(group_index, member_state)
		return
	var preset := member_state.preset as LimbSwingPresetBase
	match int(member_state.mode):
		SwingState.IDLE:
			if pressed:
				_begin_member(group_index, member_state)
		SwingState.CHARGING:
			member_state.charge_time = minf(float(member_state.charge_time) + delta, maxf(preset.maximum_charge_time, preset.minimum_charge_time))
			if not pressed:
				_release_member(group_index, member_state)
			else:
				_apply_charge_target_aim(group_index, member_state, delta)
		SwingState.SWINGING, SwingState.FOLLOW_THROUGH, SwingState.RECOVERING:
			_advance_released_member(group_index, member_state, delta)
		SwingState.COOLDOWN:
			member_state.time_remaining = float(member_state.time_remaining) - delta
			if float(member_state.time_remaining) <= 0.0 and not pressed:
				member_state.mode = SwingState.IDLE
				_release_body_owner(body, group_index)

## Carry time across phases so long physics frames do not lengthen the attack.
func _advance_released_member(group_index: int, state: Dictionary, delta: float) -> void:
	var remaining := maxf(delta, 0.0)
	while remaining > 0.0:
		var mode := int(state.mode)
		if mode == SwingState.SWINGING:
			_apply_member_torque(state)
			_apply_release_direction_hold(state)
		elif mode == SwingState.FOLLOW_THROUGH:
			_apply_release_direction_hold(state)
		elif mode == SwingState.RECOVERING:
			_apply_recovery_torque(state)
		else:
			return
		var used := minf(remaining, maxf(float(state.time_remaining), 0.0))
		if mode in [SwingState.SWINGING, SwingState.FOLLOW_THROUGH]:
			# Weight the final partial interval, and avoid applying the same torque twice across a phase boundary.
			var active_time := minf(used, maxf(float(state.attack_tuning.sustained_time) - float(state.sustained_elapsed), 0.0))
			_apply_sustained_swing_torque(state, active_time / maxf(delta, 0.000001))
			state.sustained_elapsed = float(state.sustained_elapsed) + used
		state.time_remaining = float(state.time_remaining) - used
		remaining -= used
		if mode == SwingState.RECOVERING:
			state.recovery_elapsed = float(state.recovery_elapsed) + used
		if float(state.time_remaining) > 0.000001:
			return
		if mode == SwingState.SWINGING:
			state.mode = SwingState.FOLLOW_THROUGH
			state.time_remaining = state.attack_tuning.follow_time
			_log_member(group_index, state, "follow_through_started")
		elif mode == SwingState.FOLLOW_THROUGH:
			_end_damage_swing()
			state.mode = SwingState.RECOVERING
			state.recovery_elapsed = 0.0
			state.time_remaining = state.attack_tuning.recovery_time
			_log_member(group_index, state, "recovery_started")
		else:
			var extension := float(state.attack_tuning.recovery_extension)
			if not _is_recovery_ready(state) and float(state.recovery_elapsed) < float(state.attack_tuning.recovery_time) + extension:
				state.time_remaining = minf(0.05, float(state.attack_tuning.recovery_time) + extension - float(state.recovery_elapsed))
			else:
				_log_member(group_index, state, "recovery_complete" if _is_recovery_ready(state) else "recovery_timeout")
				_finish_member(group_index, state)
				return

func _apply_release_direction_hold(state: Dictionary) -> void:
	var body := state.body as PhysicalBodyPart3D
	var axis: Vector3 = state.release_axis_world
	var current := (body.global_basis * (state.release_axis_body_local as Vector3)).normalized()
	# Stabilize the swing plane, leaving rotation around its normal free to swing.
	var tuning: Dictionary = state.attack_tuning
	var torque := current.cross(axis) * float(tuning.hold_stiffness)
	torque -= body.angular_velocity.slide(axis) * float(tuning.hold_damping)
	body.sleeping = false
	body.apply_torque(torque.limit_length(float(tuning.hold_max_torque)))

func _recovery_error(state: Dictionary) -> Vector3:
	var anchor := state.anchor_body as PhysicalBodyPart3D
	if not is_instance_valid(anchor):
		return Vector3.ZERO
	var body := state.body as PhysicalBodyPart3D
	var target := anchor.global_basis * (state.rest_basis_local as Basis)
	var rotation := (target.orthonormalized().get_rotation_quaternion() * body.global_basis.orthonormalized().get_rotation_quaternion().inverse()).normalized()
	if rotation.w < 0.0:
		rotation = -rotation
	return rotation.get_axis() * rotation.get_angle()

func _apply_recovery_torque(state: Dictionary) -> void:
	var body := state.body as PhysicalBodyPart3D
	var anchor := state.anchor_body as PhysicalBodyPart3D
	var relative_speed := body.angular_velocity
	if is_instance_valid(anchor):
		relative_speed -= anchor.angular_velocity
	var tuning: Dictionary = state.attack_tuning
	var torque := _recovery_error(state) * float(tuning.recovery_stiffness) - relative_speed * float(tuning.recovery_damping)
	body.apply_torque(torque.limit_length(float(tuning.recovery_max_torque)))

func _is_recovery_ready(state: Dictionary) -> bool:
	return _recovery_error(state).length() <= deg_to_rad(10.0)

## Returns true only if at least one charging Arm accepts the cursor drag.
func adjust_charge_swing_angle(cursor: Node3D, target: Node3D, motion: Vector2) -> bool:
	_ensure_runtime_states()
	if _get_selected_aim_target() != target or terrain_cursor != cursor:
		return false
	# A cursor belongs to its controlled character, never to another character's controller.
	if cursor is TerrainCursor3D:
		var owner_cursor := cursor as TerrainCursor3D
		if is_instance_valid(owner_cursor.controlled_character) and owner_cursor.controlled_character != get_parent():
			return false
		if is_instance_valid(owner_cursor.movement_anchor) and not get_parent().is_ancestor_of(owner_cursor.movement_anchor):
			return false
	var accepted := false
	for group_index: int in range(control_groups.size()):
		var group := control_groups[group_index]
		if group == null or not group.enabled or group.input_action not in [&"MouseLeft", &"LeftMouse"]:
			continue
		for state: Dictionary in _states[group_index].members:
			var preset := state.preset as LimbSwingPresetBase
			var body_value: Variant = state.body
			if int(state.mode) != SwingState.CHARGING or not preset.charge_angle_drag_enabled or not preset.target_aim_enabled:
				continue
			if not is_instance_valid(body_value) or (body_value as PhysicalBodyPart3D).is_broken:
				continue
			accepted = true
			if is_zero_approx(motion.x):
				continue
			var up := -_get_gravity_direction(body_value as RigidBody3D)
			_enable_target_aim_joint(state, up)
			_prepare_release_joint(state)
			state.charge_bank_active = true
			state.charge_bank_angle = clampf(float(state.charge_bank_angle) + deg_to_rad(motion.x * preset.charge_angle_drag_sensitivity),
				-deg_to_rad(preset.maximum_charge_bank_degrees), deg_to_rad(preset.maximum_charge_bank_degrees))
			if diagnostic_logging:
				print("[swing_angle_drag] arm=%s target=%s angle_deg=%.2f mouse=%s" % [
					(body_value as Node).name, target.name, rad_to_deg(float(state.charge_bank_angle)), motion])
	return accepted

func _get_charge_bank_target_basis(state: Dictionary, target_position: Vector3) -> Basis:
	var body := state.body as PhysicalBodyPart3D
	var anchor := state.anchor_body as PhysicalBodyPart3D
	var up := -_get_gravity_direction(body)
	var pivot := anchor.to_global(state.anchor_local_position)
	var direction := (target_position - pivot).slide(up).normalized()
	if direction.is_zero_approx():
		return body.global_basis.orthonormalized()
	var banked_up := up.rotated(direction, float(state.charge_bank_angle))
	var normal := direction.cross(banked_up).normalized()
	var lift := absf(float(state.lift_angle))
	var raised_direction := direction * cos(lift) + banked_up * sin(lift)
	var raised_up := -direction * sin(lift) + banked_up * cos(lift)
	var local_direction := ((state.rest_basis_local as Basis).inverse() * (state.rest_lever_local as Vector3)).normalized()
	var local_normal := (state.snapshot.aim_swing_axis_local as Vector3) * float(state.snapshot.world_lift_sign)
	var local_up := local_normal.cross(local_direction).normalized()
	var local_frame := Basis(local_direction, local_up, local_direction.cross(local_up)).orthonormalized()
	return Basis(raised_direction, raised_up, normal) * local_frame.inverse()

func _apply_charge_bank_pose(state: Dictionary, target_position: Vector3) -> void:
	var body := state.body as PhysicalBodyPart3D
	var target := _get_charge_bank_target_basis(state, target_position)
	var rotation := (target.get_rotation_quaternion() * body.global_basis.orthonormalized().get_rotation_quaternion().inverse()).normalized()
	if rotation.w < 0.0:
		rotation = -rotation
	var preset := state.preset as LimbSwingPresetBase
	var torque := rotation.get_axis() * rotation.get_angle() * preset.charge_bank_stiffness
	torque -= body.angular_velocity * preset.charge_bank_damping
	body.apply_torque(torque.limit_length(preset.maximum_charge_bank_torque))

func _get_selected_aim_target() -> Node3D:
	if not is_instance_valid(terrain_cursor):
		terrain_cursor = get_tree().get_first_node_in_group(&"terrain_cursor_3d") as Node3D
	if not is_instance_valid(terrain_cursor) or not terrain_cursor.has_method("get_selected_character"):
		return null
	if terrain_cursor.has_method("is_gameplay_cursor_active") and not bool(terrain_cursor.call("is_gameplay_cursor_active")):
		return null
	var target := terrain_cursor.call("get_selected_character") as Node3D
	if not is_instance_valid(target) or target.is_queued_for_deletion() or target == get_parent():
		return null
	return target

func _calculate_target_aim(member_state: Dictionary, target_position: Vector3) -> Dictionary:
	var body := member_state.body as PhysicalBodyPart3D
	var anchor := member_state.anchor_body as PhysicalBodyPart3D
	var up := -_get_gravity_direction(body)
	var pivot := anchor.to_global(member_state.anchor_local_position)
	var current := (body.global_position - pivot).slide(up)
	var desired := (target_position - pivot).slide(up)
	# A vertical Arm has no reliable horizontal heading; wait instead of choosing a random yaw.
	if current.length_squared() < 0.0025 or desired.length_squared() < 0.0025:
		return {"axis": up, "error": 0.0, "torque": Vector3.ZERO}
	current = current.normalized()
	desired = desired.normalized()
	var angle := atan2(up.dot(current.cross(desired)), clampf(current.dot(desired), -1.0, 1.0))
	if absf(angle) > PI - 0.02:
		angle = absf(angle) * (signf(float(member_state.aim_error)) if absf(float(member_state.aim_error)) > 0.01 else 1.0)
	var preset := member_state.preset as LimbSwingPresetBase
	var relative_speed := (body.angular_velocity - anchor.angular_velocity).dot(up)
	var magnitude := clampf(angle * preset.target_aim_stiffness - relative_speed * preset.target_aim_damping,
		-preset.maximum_target_aim_torque, preset.maximum_target_aim_torque)
	return {"axis": up, "error": angle, "torque": up * magnitude}

func _apply_charge_target_aim(group_index: int, member_state: Dictionary, delta: float) -> void:
	var preset := member_state.preset as LimbSwingPresetBase
	var action := control_groups[group_index].input_action
	var target := _get_selected_aim_target() if preset.target_aim_enabled and action in [&"MouseLeft", &"LeftMouse"] else null
	var body := member_state.body as PhysicalBodyPart3D
	var anchor := member_state.anchor_body as PhysicalBodyPart3D
	if target == null or not is_instance_valid(anchor) or anchor.is_broken or body.is_broken:
		if is_instance_valid(member_state.aim_target):
			_log_member(group_index, member_state, "target_aim_lost")
		if bool(member_state.charge_bank_active):
			_restore_release_joint(member_state)
			member_state.charge_bank_active = false
			member_state.charge_bank_angle = 0.0
		_restore_target_aim_joint(member_state)
		return
	var target_position: Vector3 = terrain_cursor.call("get_target_ground_position")
	var aim := _calculate_target_aim(member_state, target_position)
	_enable_target_aim_joint(member_state, aim.axis)
	var changed: bool = member_state.aim_target != target
	member_state.aim_target = target
	member_state.aim_error = aim.error
	member_state.aim_log_elapsed = float(member_state.aim_log_elapsed) + delta
	body.sleeping = false
	if bool(member_state.charge_bank_active):
		_apply_charge_bank_pose(member_state, target_position)
	else:
		body.apply_torque(aim.torque)
	if diagnostic_logging and (changed or float(member_state.aim_log_elapsed) >= 0.1):
		member_state.aim_log_elapsed = 0.0
		print("[swing_target_aim] character=%s arm=%s target=%s charge=%.3f error_deg=%.2f axis=%s torque=%s target_position=%s" % [
			get_parent().name, body.name, target.name, member_state.charge_time,
			rad_to_deg(float(aim.error)), aim.axis, aim.torque, target_position])

func _enable_target_aim_joint(member_state: Dictionary, up: Vector3) -> void:
	if not (member_state.aim_joint_snapshot as Dictionary).is_empty():
		return
	var joint := member_state.joint as Generic6DOFJoint3D
	var body := member_state.body as PhysicalBodyPart3D
	var anchor := member_state.anchor_body as PhysicalBodyPart3D
	var local_up: Vector3 = (anchor.global_basis * (member_state.joint_basis_local as Basis)).inverse() * up
	var axis := local_up.abs().max_axis_index()
	var world_axis := up.abs().max_axis_index()
	var lock_property := StringName("axis_lock_angular_" + ["x", "y", "z"][world_axis])
	var lift_axis := _get_member_axis_world(member_state)
	member_state.snapshot[&"aim_swing_axis_local"] = body.global_basis.inverse() * lift_axis
	member_state.aim_joint_snapshot = {
		"axis": axis, "limit_enabled": joint.get(_axis_property(axis, "angular_limit", "enabled")),
		"spring_enabled": joint.get(_axis_property(axis, "angular_spring", "enabled")),
		"body_lock": lock_property, "body_lock_enabled": body.get(lock_property),
	}
	joint.set(_axis_property(axis, "angular_limit", "enabled"), false)
	# Keep the lift spring if an unusual model uses this same axis for lifting.
	if axis != (member_state.preset as LimbSwingPresetBase).joint_axis:
		joint.set(_axis_property(axis, "angular_spring", "enabled"), false)
	body.set(lock_property, false)

func _restore_target_aim_joint(member_state: Dictionary) -> void:
	var saved := member_state.aim_joint_snapshot as Dictionary
	if not saved.is_empty():
		var joint_value: Variant = member_state.get("joint")
		if is_instance_valid(joint_value):
			var joint := joint_value as Generic6DOFJoint3D
			joint.set(_axis_property(int(saved.axis), "angular_limit", "enabled"), saved.limit_enabled)
			joint.set(_axis_property(int(saved.axis), "angular_spring", "enabled"), saved.spring_enabled)
		var body_value: Variant = member_state.get("body")
		if is_instance_valid(body_value):
			(body_value as RigidBody3D).set(saved.body_lock, saved.body_lock_enabled)
	member_state.aim_joint_snapshot = {}
	member_state.aim_target = null
	member_state.aim_error = 0.0
	member_state.aim_log_elapsed = 0.0

func _begin_member(group_index: int, member_state: Dictionary) -> bool:
	var body := member_state.body as PhysicalBodyPart3D
	var joint := member_state.joint as Generic6DOFJoint3D
	if not is_instance_valid(body) or not is_instance_valid(joint) or body.is_broken:
		return false
	if _body_owner_group.has(body) and int(_body_owner_group[body]) != group_index:
		return false
	_body_owner_group[body] = group_index
	var preset := member_state.preset as LimbSwingPresetBase
	member_state.mode = SwingState.CHARGING
	member_state.charge_time = 0.0
	member_state.swing_torque = 0.0
	member_state.charge_bank_active = false
	member_state.charge_bank_angle = 0.0
	var anchor_body := member_state.anchor_body as PhysicalBodyPart3D
	if not is_instance_valid(anchor_body):
		member_state.mode = SwingState.IDLE
		_release_body_owner(body, group_index)
		return false
	var anchor_position := anchor_body.to_global(member_state.anchor_local_position)
	var axis_local: Vector3 = member_state.axis_local
	var rest_lever_local: Vector3 = member_state.rest_lever_local
	var axis_world := (anchor_body.global_basis * axis_local).normalized()
	var rest_lever_world := anchor_body.global_basis * rest_lever_local
	var gravity_direction := _get_gravity_direction(body)
	var direction := _get_point_direction_diagnostics(
		anchor_position + rest_lever_world,
		anchor_position,
		axis_world,
		gravity_direction
	)
	var current_direction := _get_point_direction_diagnostics(
		body.global_position,
		anchor_position,
		axis_world,
		gravity_direction
	)
	var load := _get_attached_load_diagnostics(
		body,
		joint,
		anchor_position,
		axis_world,
		gravity_direction
	)
	var lift_sign := float(direction.lift_sign)
	var lift_angle := deg_to_rad(preset.lift_angle_degrees * lift_sign)
	var snapshot := _capture_joint(joint, preset.joint_axis)
	snapshot.gravity_direction = gravity_direction
	snapshot.world_lift_sign = lift_sign
	snapshot.axis_world = axis_world
	snapshot.rest_lever_projected = direction.lever_projected
	snapshot.current_lever_projected = current_direction.lever_projected
	snapshot.anti_gravity_projected = direction.anti_gravity_projected
	snapshot.signed_sine = direction.signed_sine
	snapshot.current_signed_sine = current_direction.signed_sine
	snapshot.arm_position = body.global_position
	snapshot.anchor_position = anchor_position
	snapshot.joint_node_position = joint.global_position
	snapshot.arm_mass = body.mass
	snapshot.attached_mass = load.attached_mass
	snapshot.attached_bodies = load.attached_bodies
	snapshot.combined_center = load.combined_center
	snapshot.combined_signed_sine = load.combined_signed_sine
	snapshot.body_rotation_degrees = Vector3(
		rad_to_deg(body.global_rotation.x),
		rad_to_deg(body.global_rotation.y),
		rad_to_deg(body.global_rotation.z)
	)
	snapshot.linear_velocity = body.linear_velocity
	snapshot.angular_velocity = body.angular_velocity
	snapshot.joint_target_degrees = rad_to_deg(-lift_angle)
	member_state.snapshot = snapshot
	member_state.lift_angle = lift_angle
	_configure_lift_joint(joint, preset, -lift_angle)
	_log_direction_diagnostics(group_index, member_state)
	_log_member(group_index, member_state, "charge_started")
	return true

func _release_member(group_index: int, member_state: Dictionary) -> void:
	var preset := member_state.preset as LimbSwingPresetBase
	if float(member_state.charge_time) < preset.minimum_charge_time:
		_restore_member_joint(member_state)
		member_state.mode = SwingState.IDLE
		member_state.charge_time = 0.0
		_release_body_owner(member_state.body as PhysicalBodyPart3D, group_index)
		_log_member(group_index, member_state, "charge_cancelled_too_short")
		return
	var ratio := clampf((float(member_state.charge_time) - preset.minimum_charge_time) / maxf(preset.maximum_charge_time - preset.minimum_charge_time, 0.001), 0.0, 1.0)
	member_state.swing_torque = lerpf(preset.minimum_swing_torque, preset.maximum_swing_torque, ratio)
	var body := member_state.body as PhysicalBodyPart3D
	member_state.release_axis_world = _get_member_axis_world(member_state)
	member_state.release_axis_body_local = body.global_basis.inverse() * (member_state.release_axis_world as Vector3)
	var sustained_time := maxf(preset.sustained_swing_duration, 0.0) if preset.sustained_swing_enabled and preset.sustained_swing_torque > 0.0 else 0.0
	member_state.sustained_elapsed = 0.0
	member_state.attack_tuning = {
		"sustained_torque": maxf(preset.sustained_swing_torque, 0.0) if preset.sustained_swing_enabled else 0.0,
		"sustained_time": sustained_time,
		"swing_time": maxf(preset.swing_duration, 0.001),
		"follow_time": maxf(maxf(preset.swing_duration * preset.follow_through_ratio, preset.minimum_follow_through_time), sustained_time - maxf(preset.swing_duration, 0.001)),
		"recovery_time": maxf(preset.recovery_duration, 0.001), "recovery_extension": preset.maximum_recovery_extension,
		"hold_stiffness": preset.direction_hold_stiffness, "hold_damping": preset.direction_hold_damping,
		"hold_max_torque": preset.maximum_direction_hold_torque,
		"recovery_stiffness": preset.recovery_stiffness, "recovery_damping": preset.recovery_damping,
		"recovery_max_torque": preset.maximum_recovery_torque, "cooldown_time": preset.cooldown_duration,
	}
	_prepare_release_joint(member_state)
	member_state.mode = SwingState.SWINGING
	member_state.time_remaining = member_state.attack_tuning.swing_time
	var joint := member_state.joint as Generic6DOFJoint3D
	if is_instance_valid(joint):
		joint.set(_axis_property(preset.joint_axis, "angular_spring", "enabled"), false)
	_begin_damage_swing()
	_apply_member_torque(member_state)
	_log_member(group_index, member_state, "swing_started")
	if diagnostic_logging:
		print("[swing_timing] arm=%s force_time=%.3f follow_time=%.3f direction_hold_time=%.3f recovery_time=%.3f sustained_torque=%.3f sustained_time=%.3f axis=%s" % [
			body.name, member_state.attack_tuning.swing_time, member_state.attack_tuning.follow_time,
			float(member_state.attack_tuning.swing_time) + float(member_state.attack_tuning.follow_time),
			member_state.attack_tuning.recovery_time, member_state.attack_tuning.sustained_torque,
			member_state.attack_tuning.sustained_time, member_state.release_axis_world])

func _apply_member_torque(member_state: Dictionary) -> void:
	var body := member_state.body as PhysicalBodyPart3D
	var joint := member_state.joint as Generic6DOFJoint3D
	var snapshot := member_state.snapshot as Dictionary
	if not is_instance_valid(body) or not is_instance_valid(joint) or body.is_broken or snapshot.is_empty():
		return
	var axis_world := _get_member_axis_world(member_state)
	body.apply_torque(axis_world * -float(snapshot.world_lift_sign) * float(member_state.swing_torque))

func _get_sustained_swing_torque(state: Dictionary) -> Vector3:
	if int(state.mode) not in [SwingState.SWINGING, SwingState.FOLLOW_THROUGH] or state.snapshot.is_empty():
		return Vector3.ZERO
	if float(state.sustained_elapsed) >= float(state.attack_tuning.sustained_time):
		return Vector3.ZERO
	return (state.release_axis_world as Vector3) * -float(state.snapshot.world_lift_sign) * float(state.attack_tuning.sustained_torque)

func _apply_sustained_swing_torque(state: Dictionary, weight: float = 1.0) -> void:
	var body_value: Variant = state.body
	var joint_value: Variant = state.joint
	if not is_instance_valid(body_value) or not is_instance_valid(joint_value) or (body_value as PhysicalBodyPart3D).is_broken:
		return
	var torque := _get_sustained_swing_torque(state) * clampf(weight, 0.0, 1.0)
	if not torque.is_zero_approx():
		(body_value as RigidBody3D).sleeping = false
		(body_value as RigidBody3D).apply_torque(torque)

func _finish_member(group_index: int, member_state: Dictionary) -> void:
	var preset := member_state.preset as LimbSwingPresetBase
	_restore_member_joint(member_state)
	var cooldown: float = member_state.attack_tuning.get("cooldown_time", preset.cooldown_duration)
	member_state.mode = SwingState.COOLDOWN if cooldown > 0.0 else SwingState.IDLE
	member_state.time_remaining = cooldown
	member_state.charge_time = 0.0
	if int(member_state.mode) == SwingState.IDLE:
		_release_body_owner(member_state.body as PhysicalBodyPart3D, group_index)
	_log_member(group_index, member_state, "swing_finished")

func _cancel_member(group_index: int, member_state: Dictionary) -> void:
	if int(member_state.mode) in [SwingState.SWINGING, SwingState.FOLLOW_THROUGH]:
		_end_damage_swing()
	_restore_member_joint(member_state)
	member_state.mode = SwingState.IDLE
	member_state.charge_time = 0.0
	member_state.time_remaining = 0.0
	var body_value: Variant = member_state.get(&"body")
	if is_instance_valid(body_value):
		_release_body_owner(body_value as PhysicalBodyPart3D, group_index)

func _invalidate_member_state(group_index: int, member_state: Dictionary, body_value: Variant) -> void:
	if int(member_state.mode) in [SwingState.SWINGING, SwingState.FOLLOW_THROUGH]:
		_end_damage_swing()
	_restore_member_joint(member_state)
	member_state.mode = SwingState.IDLE
	member_state.charge_time = 0.0
	member_state.time_remaining = 0.0
	if is_instance_valid(body_value):
		_release_body_owner(body_value as PhysicalBodyPart3D, group_index)

func _cancel_group(group_index: int) -> void:
	if not _has_runtime_group(group_index):
		return
	for member_state: Dictionary in _states[group_index].members:
		if int(member_state.mode) != SwingState.IDLE:
			_cancel_member(group_index, member_state)

func _cancel_all_members() -> void:
	for group_index: int in range(_states.size()):
		_cancel_group(group_index)
	_body_owner_group.clear()

func _release_body_owner(body: PhysicalBodyPart3D, group_index: int) -> void:
	if is_instance_valid(body) and _body_owner_group.get(body, -1) == group_index:
		_body_owner_group.erase(body)

func _begin_damage_swing() -> void:
	_active_damage_swings += 1
	if _active_damage_swings == 1:
		var inventory := get_parent().get_node_or_null("InventoryController3D")
		if inventory != null and inventory.has_method("notify_weapon_swing_started"):
			inventory.call("notify_weapon_swing_started")

func _end_damage_swing() -> void:
	_active_damage_swings = maxi(_active_damage_swings - 1, 0)
	if _active_damage_swings == 0:
		var inventory := get_parent().get_node_or_null("InventoryController3D")
		if inventory != null and inventory.has_method("notify_weapon_swing_finished"):
			inventory.call("notify_weapon_swing_finished")

func _prepare_release_joint(state: Dictionary) -> void:
	if not (state.release_joint_snapshot as Array).is_empty():
		return
	var joint := state.joint as Generic6DOFJoint3D
	var body := state.body as PhysicalBodyPart3D
	var saved: Array = []
	for axis: int in 3:
		var lock_property := StringName("axis_lock_angular_" + ["x", "y", "z"][axis])
		saved.append({"limit": joint.get(_axis_property(axis, "angular_limit", "enabled")),
			"spring": joint.get(_axis_property(axis, "angular_spring", "enabled")), "lock": body.get(lock_property)})
		joint.set(_axis_property(axis, "angular_limit", "enabled"), false)
		joint.set(_axis_property(axis, "angular_spring", "enabled"), false)
		body.set(lock_property, false)
	state.release_joint_snapshot = saved

func _restore_release_joint(state: Dictionary) -> void:
	var joint_value: Variant = state.joint
	var body_value: Variant = state.body
	var saved: Array = state.release_joint_snapshot
	for axis: int in saved.size():
		if is_instance_valid(joint_value):
			var joint := joint_value as Generic6DOFJoint3D
			joint.set(_axis_property(axis, "angular_limit", "enabled"), saved[axis].limit)
			joint.set(_axis_property(axis, "angular_spring", "enabled"), saved[axis].spring)
		if is_instance_valid(body_value):
			(body_value as RigidBody3D).set(StringName("axis_lock_angular_" + ["x", "y", "z"][axis]), saved[axis].lock)
	state.release_joint_snapshot = []

func _capture_joint(joint: Generic6DOFJoint3D, axis: int) -> Dictionary:
	return {
		&"axis": axis,
		&"lower": joint.get(_axis_property(axis, "angular_limit", "lower_angle")),
		&"upper": joint.get(_axis_property(axis, "angular_limit", "upper_angle")),
		&"spring_enabled": joint.get(_axis_property(axis, "angular_spring", "enabled")),
		&"spring_stiffness": joint.get(_axis_property(axis, "angular_spring", "stiffness")),
		&"spring_damping": joint.get(_axis_property(axis, "angular_spring", "damping")),
		&"spring_equilibrium": joint.get(_axis_property(axis, "angular_spring", "equilibrium_point")),
	}

func _configure_lift_joint(joint: Generic6DOFJoint3D, preset: LimbSwingPresetBase, target_angle: float) -> void:
	var margin := deg_to_rad(5.0)
	var lower_path := _axis_property(preset.joint_axis, "angular_limit", "lower_angle")
	var upper_path := _axis_property(preset.joint_axis, "angular_limit", "upper_angle")
	joint.set(lower_path, minf(float(joint.get(lower_path)), target_angle - margin))
	joint.set(upper_path, maxf(float(joint.get(upper_path)), target_angle + margin))
	joint.set(_axis_property(preset.joint_axis, "angular_spring", "enabled"), true)
	joint.set(_axis_property(preset.joint_axis, "angular_spring", "stiffness"), preset.lift_spring_stiffness)
	joint.set(_axis_property(preset.joint_axis, "angular_spring", "damping"), preset.lift_spring_damping)
	joint.set(_axis_property(preset.joint_axis, "angular_spring", "equilibrium_point"), target_angle)

func _restore_member_joint(member_state: Dictionary) -> void:
	_restore_release_joint(member_state)
	_restore_target_aim_joint(member_state)
	var snapshot := member_state.snapshot as Dictionary
	if snapshot.is_empty():
		return
	var joint_value: Variant = member_state.get(&"joint")
	if is_instance_valid(joint_value):
		var joint := joint_value as Generic6DOFJoint3D
		var axis := int(snapshot.axis)
		joint.set(_axis_property(axis, "angular_limit", "lower_angle"), snapshot.lower)
		joint.set(_axis_property(axis, "angular_limit", "upper_angle"), snapshot.upper)
		joint.set(_axis_property(axis, "angular_spring", "enabled"), snapshot.spring_enabled)
		joint.set(_axis_property(axis, "angular_spring", "stiffness"), snapshot.spring_stiffness)
		joint.set(_axis_property(axis, "angular_spring", "damping"), snapshot.spring_damping)
		joint.set(_axis_property(axis, "angular_spring", "equilibrium_point"), snapshot.spring_equilibrium)
	member_state.snapshot = {}

func _axis_property(axis: int, section: String, property_name: String) -> StringName:
	var axis_name: String = ["x", "y", "z"][clampi(axis, 0, 2)]
	return StringName("%s_%s/%s" % [section, axis_name, property_name])

func _get_joint_axis_world(joint: Generic6DOFJoint3D, axis: int) -> Vector3:
	match clampi(axis, 0, 2):
		0: return joint.global_basis.x.normalized()
		1: return joint.global_basis.y.normalized()
		_: return joint.global_basis.z.normalized()

func _get_gravity_direction(body: RigidBody3D) -> Vector3:
	var direct_state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	if direct_state != null and not direct_state.total_gravity.is_zero_approx():
		return direct_state.total_gravity.normalized()
	var configured_gravity: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
	return configured_gravity.normalized() if not configured_gravity.is_zero_approx() else Vector3.DOWN

func _get_anti_gravity_rotation_sign(body: RigidBody3D, joint: Generic6DOFJoint3D, axis_world: Vector3, gravity_direction: Vector3) -> float:
	return float(_get_lift_direction_diagnostics(body, joint, axis_world, gravity_direction).lift_sign)

func _get_lift_direction_diagnostics(
	body: RigidBody3D,
	joint: Generic6DOFJoint3D,
	axis_world: Vector3,
	gravity_direction: Vector3
) -> Dictionary:
	return _get_point_direction_diagnostics(
		body.global_position,
		joint.global_position,
		axis_world,
		gravity_direction
	)

func _get_point_direction_diagnostics(
	point: Vector3,
	joint_position: Vector3,
	axis_world: Vector3,
	gravity_direction: Vector3
) -> Dictionary:
	var lever := point - joint_position
	lever -= axis_world * lever.dot(axis_world)
	var anti_gravity := -gravity_direction
	anti_gravity -= axis_world * anti_gravity.dot(axis_world)
	if lever.is_zero_approx() or anti_gravity.is_zero_approx():
		return {
			&"lever_projected": lever,
			&"anti_gravity_projected": anti_gravity,
			&"signed_sine": 0.0,
			&"lift_sign": 1.0,
		}
	var signed_sine := axis_world.dot(lever.normalized().cross(anti_gravity.normalized()))
	return {
		&"lever_projected": lever,
		&"anti_gravity_projected": anti_gravity,
		&"signed_sine": signed_sine,
		&"lift_sign": 1.0 if is_zero_approx(signed_sine) else signf(signed_sine),
	}

func _get_attached_load_diagnostics(
	body: PhysicalBodyPart3D,
	shoulder_joint: Generic6DOFJoint3D,
	anchor_position: Vector3,
	axis_world: Vector3,
	gravity_direction: Vector3
) -> Dictionary:
	var body_center := body.global_position
	if body.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
		body_center = body.to_global(body.center_of_mass)
	var weighted_position := body_center * body.mass
	var total_mass := body.mass
	var attached_mass := 0.0
	var attached_bodies: Array[StringName] = []
	# Merged items are already included in the body's mass and center of mass.
	for child: Node in body.get_children():
		if child is SampleItem3D and (child as SampleItem3D).rigid_attachment_holder == body:
			attached_mass += (child as SampleItem3D).mass
			attached_bodies.append(child.name)
	for node: Node in get_parent().find_children("*", "Generic6DOFJoint3D", true, false):
		var joint := node as Generic6DOFJoint3D
		if joint == null or joint == shoulder_joint or joint.is_queued_for_deletion():
			continue
		var body_a := joint.get_node_or_null(joint.node_a)
		var body_b := joint.get_node_or_null(joint.node_b)
		if body_a != body and body_b != body:
			continue
		var other := body_b if body_a == body else body_a
		if other is not RigidBody3D or other is PhysicalBodyPart3D:
			continue
		var load_body := other as RigidBody3D
		attached_mass += load_body.mass
		total_mass += load_body.mass
		weighted_position += load_body.global_position * load_body.mass
		attached_bodies.append(load_body.name)
	var combined_center := weighted_position / maxf(total_mass, 0.001)
	var combined_direction := _get_point_direction_diagnostics(
		combined_center,
		anchor_position,
		axis_world,
		gravity_direction
	)
	return {
		&"attached_mass": attached_mass,
		&"attached_bodies": attached_bodies,
		&"combined_center": combined_center,
		&"combined_signed_sine": combined_direction.signed_sine,
	}

func _get_member_axis_world(member_state: Dictionary) -> Vector3:
	if int(member_state.mode) in [SwingState.SWINGING, SwingState.FOLLOW_THROUGH]:
		return member_state.release_axis_world
	var snapshot := member_state.snapshot as Dictionary
	if not (member_state.aim_joint_snapshot as Dictionary).is_empty() and snapshot.has(&"aim_swing_axis_local"):
		var body := member_state.body as PhysicalBodyPart3D
		if is_instance_valid(body):
			return (body.global_basis * (snapshot.aim_swing_axis_local as Vector3)).normalized()
	var anchor_body := member_state.anchor_body as PhysicalBodyPart3D
	if not is_instance_valid(anchor_body):
		return Vector3.ZERO
	var axis_local: Vector3 = member_state.axis_local
	return (anchor_body.global_basis * axis_local).normalized()

func _rebuild_runtime_states() -> void:
	_states.clear()
	for _group: SwingControlGroup in control_groups:
		_states.append({&"members": []})

func _ensure_runtime_states() -> void:
	if _states.size() != control_groups.size():
		refresh_arm_bindings()

func _is_valid_group_index(group_index: int) -> bool:
	return group_index >= 0 and group_index < control_groups.size()

func _has_runtime_group(group_index: int) -> bool:
	return _is_valid_group_index(group_index) and group_index < _states.size()

func _on_character_child_changed(_node: Node) -> void:
	if is_inside_tree() and _node is PhysicalBodyPart3D:
		call_deferred("refresh_arm_bindings")

func _log_member(group_index: int, member_state: Dictionary, event_name: String) -> void:
	if not diagnostic_logging:
		return
	var snapshot := member_state.snapshot as Dictionary
	print(
		("[limb_swing] character=%s group=%s arm=%s event=%s state=%d charge=%.3f "
		+ "lift_angle_deg=%.3f torque=%.3f gravity=%s")
		% [get_parent().name, control_groups[group_index].group_name, (member_state.body as Node).name,
		event_name, int(member_state.mode), float(member_state.charge_time),
		rad_to_deg(float(member_state.lift_angle)), float(member_state.swing_torque),
		snapshot.get(&"gravity_direction", Vector3.ZERO)]
	)

func _log_direction_diagnostics(group_index: int, member_state: Dictionary) -> void:
	if not diagnostic_logging:
		return
	var snapshot := member_state.snapshot as Dictionary
	var body := member_state.body as PhysicalBodyPart3D
	var joint := member_state.joint as Generic6DOFJoint3D
	var preset := member_state.preset as LimbSwingPresetBase
	print(
		("[swing_direction] character=%s group=%s arm=%s joint=%s preset=%s "
		+ "arm_mass=%.3f attached_mass=%.3f attached=%s arm_pos=%s anchor_pos=%s "
		+ "joint_node_pos=%s rest_lever=%s current_lever=%s combined_com=%s "
		+ "axis=%s gravity=%s anti_gravity=%s signed_sine=%.6f "
		+ "current_signed_sine=%.6f combined_signed_sine=%.6f lift_sign=%.1f "
		+ "lift_angle_deg=%.3f joint_target_deg=%.3f "
		+ "body_rotation_deg=%s linear_velocity=%s angular_velocity=%s")
		% [
			get_parent().name,
			control_groups[group_index].group_name,
			body.name,
			joint.name,
			preset.resource_path,
			float(snapshot.arm_mass),
			float(snapshot.attached_mass),
			snapshot.attached_bodies,
			snapshot.arm_position,
			snapshot.anchor_position,
			snapshot.joint_node_position,
			snapshot.rest_lever_projected,
			snapshot.current_lever_projected,
			snapshot.combined_center,
			snapshot.axis_world,
			snapshot.gravity_direction,
			snapshot.anti_gravity_projected,
			float(snapshot.signed_sine),
			float(snapshot.current_signed_sine),
			float(snapshot.combined_signed_sine),
			float(snapshot.world_lift_sign),
			rad_to_deg(float(member_state.lift_angle)),
			float(snapshot.joint_target_degrees),
			snapshot.body_rotation_degrees,
			snapshot.linear_velocity,
			snapshot.angular_velocity,
		]
	)
	if absf(float(snapshot.signed_sine)) < 0.15:
		print(
			"[swing_direction_warning] character=%s arm=%s reason=near_sign_boundary signed_sine=%.6f"
			% [get_parent().name, body.name, float(snapshot.signed_sine)]
		)
	var combined_sign := signf(float(snapshot.combined_signed_sine))
	if not is_zero_approx(combined_sign) and combined_sign != float(snapshot.world_lift_sign):
		print(
			("[swing_direction_warning] character=%s arm=%s reason=load_com_disagrees "
			+ "arm_sign=%.1f combined_sign=%.1f attached_mass=%.3f")
			% [get_parent().name, body.name, float(snapshot.world_lift_sign), combined_sign, float(snapshot.attached_mass)]
		)

func cancel_player_actions() -> void:
	_cancel_all_members()
