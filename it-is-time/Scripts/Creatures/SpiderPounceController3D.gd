@tool
extends Node
## Spider-specific attack receiver, driven by the shared movement/action hook.
## Uses the existing component name to retain player, NPC, death and regeneration routing.

const DATA = preload("res://Scripts/Creatures/SpiderPounceData.gd")
const PLAYER = preload("res://Scripts/Player/PlayerControlContext.gd")
const PREDICTION = preload("res://Scripts/Creatures/NPCAttackPrediction3D.gd")
const HITBOX = preload("res://Scripts/Items/TemporaryAttackHitbox3D.gd")
const ACTION: StringName = &"spider_pounce"
enum Phase { IDLE, PAUSING, RISING, LEAPING, RECOVERING }

@export var enabled := true
@export var data: DATA = preload("res://Resources/Actions/SpiderPounce.tres")
@export var movement_path: NodePath = ^"../GeneratedLegStepMovementController3D"
@export var diagnostic_logging := false
var phase := Phase.IDLE
var _movement: Node
var _character_enabled := true
var _npc_attack := false
var _elapsed := 0.0
var _cooldown := 0.0
var _up := Vector3.UP
var _forward := Vector3.RIGHT
var _pitch_axis := Vector3.BACK
var _body_length := 1.0
var _time_scale := 1.0
var _rear_pivot := Vector3.ZERO
var _front_body: RigidBody3D
var _rear_body: RigidBody3D
var _torso_joint: Generic6DOFJoint3D
var _torso_joint_flags: Dictionary = {}
var _target: Node3D
var _plan: Dictionary = {}
var _feet: Array[Dictionary] = []
var _bodies: Array[Dictionary] = []
var _parts: Array[RigidBody3D] = []
var _hitboxes: Array[HITBOX] = []
var _reason: StringName = &"idle"
var _hits := 0
var _launch_origin := Vector3.ZERO
var _maximum_front_rise := 0.0
var _preparation_pose: Dictionary = {}

func _ready() -> void:
	set_physics_process(false) # Updated exactly once by the existing movement/action hook.

func is_active() -> bool: return phase != Phase.IDLE
func blocks_locomotion() -> bool: return is_active()
func owns_height_support() -> bool: return phase in [Phase.PAUSING, Phase.RISING, Phase.LEAPING]
func is_npc_attack_active() -> bool: return _npc_attack and is_active()
func has_input_action(action: StringName) -> bool:
	return enabled and data != null and data.enabled and action == data.input_action

func handle_input(event: InputEvent) -> bool:
	if event.is_echo() or data == null or not has_input_action(data.input_action) or not event.is_action_pressed(data.input_action): return false
	try_start_action()
	return true

func _alive(body: Variant) -> bool:
	return is_instance_valid(body) and body is PhysicalBodyPart3D and body.is_inside_tree() and not body.is_queued_for_deletion() and not body.is_broken and not body.freeze

func _refresh_parts() -> bool:
	_movement = get_node_or_null(movement_path)
	if _movement == null or not _alive(_movement._torso): return false
	if is_active(): return true
	_parts = get_parent()._get_physical_body_parts()
	_up = -_movement._gravity_acceleration().normalized()
	if _up.is_zero_approx(): _up = Vector3.UP
	_forward = _movement._torso.global_basis.x.slide(_up).normalized()
	_pitch_axis = _forward.cross(_up).normalized()
	var minimum := INF
	var maximum := -INF
	for body: RigidBody3D in _movement.get_torso_parts():
		if not _alive(body): continue
		var size: Vector3 = body.get_meta(&"generated_framework_size", body.get_meta(&"generated_size", Vector3.ONE))
		var projection := body.global_position.dot(_forward)
		minimum = minf(minimum, projection - size.x * 0.5)
		maximum = maxf(maximum, projection + size.x * 0.5)
	_body_length = maxf(maximum - minimum, 0.1)
	_time_scale = sqrt(_body_length / data.reference_body_length)
	return true

func _front_feet() -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	for foot: RigidBody3D in _movement.get_leg_parts():
		if _movement._chain_is_intact(foot) and _alive(foot): result.append(foot)
	# Authored root offsets cannot swap order as feet swing or the body turns.
	result.sort_custom(func(a: RigidBody3D, b: RigidBody3D) -> bool:
		var x_a: float = _movement._chains[a].anchor.x
		var x_b: float = _movement._chains[b].anchor.x
		return x_a > x_b if not is_equal_approx(x_a, x_b) else str(a.name) < str(b.name))
	if result.size() < 8: return []
	result.resize(4)
	return result

func _target_valid(target: Node3D) -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion(): return false
	var actor := PLAYER.character_of(target)
	return actor != null and actor != get_parent() and actor.is_combat_alive() and actor.get_faction_id() != get_parent().get_faction_id() and target.get_world_3d() == get_parent().get_world_3d() and target.get("is_broken") != true

func _select_target() -> Node3D:
	var source := PLAYER.controller(self)
	if source != null and source.terrain_cursor != null:
		var selected: Node3D = source.terrain_cursor.get_selected_character()
		if is_instance_valid(selected):
			var torso: Node3D = selected.get_nearest_combat_torso(_movement._torso.global_position)
			if _target_valid(torso): return torso
	var best: Node3D
	var distance := INF
	for actor: Node in get_tree().get_nodes_in_group(&"physical_characters_3d"):
		if actor == get_parent() or actor.get_world_3d() != get_parent().get_world_3d() or not actor.is_combat_alive(): continue
		var candidate: Node3D = actor.get_nearest_combat_torso(_movement._torso.global_position)
		if not _target_valid(candidate): continue
		var d := candidate.global_position.distance_squared_to(_movement._torso.global_position)
		if d < distance: best = candidate; distance = d
	return best

func _trajectory(target: Node3D, delay: float, check_start_range: bool = true) -> Dictionary:
	if not _target_valid(target): return {"hit": false, "reason": &"no_enemy"}
	var origin: Vector3 = _movement._torso.global_position
	var current_distance := (target.global_position - origin).slide(_up).length()
	var maximum_distance := get_npc_attack_maximum_range(ACTION, target)
	if check_start_range and (current_distance < _body_length * data.minimum_distance_body_ratio or current_distance > maximum_distance):
		return {"hit": false, "reason": &"distance", "current_distance": current_distance, "maximum_distance": maximum_distance}
	var duration := data.flight_time * _time_scale
	var endpoint := target.global_position + PREDICTION.velocity(target) * (delay + duration)
	var offset := (endpoint - origin).slide(_up)
	var distance := offset.length()
	var direction := offset.normalized()
	if direction.dot(_forward) < 0.5 or absf((endpoint-origin).dot(_up)) > _body_length: return {"hit": false, "reason": &"facing_or_height"}
	var travel := offset - direction * _body_length * data.landing_standoff_body_ratio
	var gravity: Vector3 = _movement._gravity_acceleration()
	var velocity := travel / duration - gravity * duration * 0.5
	# Admission uses the current distance; the moving interception point is limited by launch speed.
	if velocity.length() > data.maximum_launch_speed * _time_scale:
		return {"hit": false, "reason": &"launch_speed", "current_distance": current_distance, "distance": distance, "required_launch_speed": velocity.length(), "maximum_launch_speed": data.maximum_launch_speed * _time_scale}
	var excluded: Array[RID] = _movement._get_character_exclusion_rids()
	var previous := origin
	# shortcut: tests the ballistic center line; use a swept hull for narrow passages.
	for index: int in range(1, 9):
		var t := duration * float(index) / 8.0
		var point := origin + velocity * t + gravity * t * t * 0.5
		var query := PhysicsRayQueryParameters3D.create(previous, point, _movement.terrain_collision_mask, excluded)
		var hit: Dictionary = get_parent().get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider is StaticBody3D: return {"hit": false, "reason": &"trajectory_blocked"}
		previous = point
	return {"hit": true, "reason": &"predicted_leap", "confidence": 0.8, "velocity": velocity, "duration": duration, "endpoint": origin + travel, "distance": distance, "current_distance": current_distance, "maximum_distance": maximum_distance, "direction": direction}

func has_npc_attack(action_id: StringName) -> bool:
	return not Engine.is_editor_hint() and enabled and _character_enabled and data != null and data.enabled and data.is_valid() and action_id == ACTION and _refresh_parts() and _front_feet().size() == 4

func predict_npc_attack(action_id: StringName, target: Node3D, _charge: float, _samples: int = 24, _margin: float = 0.1) -> Dictionary:
	if not has_npc_attack(action_id): return {"hit": false, "reason": &"unavailable"}
	if is_active() or _cooldown > 0.0 or _movement.recovery_control_active or _movement._planar_mode_active() or _movement.simplified_physics_mode or _movement.is_action_turn_blocked(): return {"hit": false, "reason": &"busy_turning_or_recovery"}
	if _movement.get_action_support_feet().is_empty(): return {"hit": false, "reason": &"no_ground_support"}
	return _trajectory(target, data.pause_time + data.rise_time + data.preparation_pose_max_wait)

func try_start_npc_attack(action_id: StringName, target: Node3D, charge: float) -> bool:
	if PLAYER.controlled_character(self) == get_parent(): return false
	if not predict_npc_attack(action_id, target, charge).get("hit", false): return false
	_npc_attack = true
	var started := try_start_action(action_id, target)
	if not started: _npc_attack = false
	return started

func uses_dynamic_npc_attack_range(_action_id: StringName) -> bool: return true
func get_npc_attack_minimum_range(_action_id: StringName) -> float:
	_refresh_parts()
	return _body_length * data.minimum_distance_body_ratio
func get_npc_attack_maximum_range(_action_id: StringName, _target_part: Node3D = null) -> float:
	_refresh_parts()
	return minf(_body_length * data.maximum_distance_body_ratio, data.maximum_launch_speed * _time_scale * data.flight_time * _time_scale)
func get_npc_attack_preferred_distance(_action_id: StringName, _target_part: Node3D = null) -> float:
	_refresh_parts()
	return _body_length * data.preferred_distance_body_ratio
func get_npc_attack_distance_tolerance(_action_id: StringName) -> float: return _body_length * 0.08
func get_npc_attack_maximum_duration(_action_id: StringName) -> float:
	return data.pause_time + data.rise_time + data.preparation_pose_max_wait + data.flight_time * _time_scale + data.landing_timeout + data.recovery_time + 0.5

func try_start_action(action_id: StringName = ACTION, target: Node3D = null) -> bool:
	if not has_npc_attack(action_id) or is_active() or _cooldown > 0.0: return false
	if not _npc_attack and not PLAYER.input_allowed(self): return false
	if get_parent().is_temporarily_ragdolled() or _movement.recovery_control_active or _movement._planar_mode_active() or _movement.simplified_physics_mode or _movement.is_action_turn_blocked(): return false
	_target = target if is_instance_valid(target) else _select_target()
	_plan = _trajectory(_target, data.pause_time + data.rise_time + data.preparation_pose_max_wait)
	if not _plan.hit or _movement.get_action_support_feet().is_empty(): return false
	var fronts := _front_feet()
	_feet.clear()
	_bodies.clear()
	_hits = 0
	_maximum_front_rise = 0.0
	_preparation_pose.clear()
	var feet: Array[RigidBody3D] = []
	var bodies: Array[RigidBody3D] = []
	var rear_x := INF
	var front_x := -INF
	_front_body = null
	_rear_body = null
	for part: RigidBody3D in _parts:
		if not _alive(part): continue
		if _movement._has_body_tag(part, _movement.TORSO_TAG) or PhysicalBodyPart3D.BodyPartTag.Head in part.tags:
			_bodies.append({"body": part, "origin": part.global_position, "basis": part.global_basis.orthonormalized()})
			bodies.append(part)
			if not _movement._has_body_tag(part, _movement.TORSO_TAG): continue
			if part.global_position.dot(_forward) > front_x:
				front_x = part.global_position.dot(_forward)
				_front_body = part
			if part.global_position.dot(_forward) < rear_x:
				rear_x = part.global_position.dot(_forward)
				_rear_body = part
	if not _release_torso_pitch(): return false
	for row: Dictionary in _bodies: row["front"] = row.body != _rear_body
	for foot: RigidBody3D in _movement.get_leg_parts():
		if not _movement._chain_is_intact(foot) or not _alive(foot): continue
		feet.append(foot)
		var chain: Dictionary = _movement._chains[foot]
		var offset: Vector3 = foot.global_position - chain.root.to_global(chain.anchor)
		_feet.append({"body": foot, "front": fronts.has(foot), "origin": foot.global_position, "basis": foot.global_basis.orthonormalized(), "offset": offset, "length": float(chain.length), "root": chain.root, "anchor": chain.anchor, "landed": false})
	_movement.cancel_step(&"spider_pounce")
	_movement.begin_action_control(feet, bodies, self)
	for row: Dictionary in _feet:
		if row.front: _prepare_knee_lift(row)
	for body: RigidBody3D in bodies: _movement.set_action_body_weight(body, 1.0)
	_reason = &"started"
	_set_phase(Phase.PAUSING)
	return true

func _prepare_knee_lift(row: Dictionary) -> void:
	var chain: Dictionary = _movement._chains[row.body]
	var upper: RigidBody3D = chain.bodies[1]
	var knee: Generic6DOFJoint3D = chain.joints[0]
	var relative: Basis = upper.global_basis.orthonormalized().inverse() * row.body.global_basis.orthonormalized()
	var frame_a: Transform3D = knee.get_meta(&"generated_joint_frame_a")
	var frame_b: Transform3D = knee.get_meta(&"generated_joint_frame_b")
	var root_frame: Transform3D = chain.joints[1].get_meta(&"generated_joint_frame_a")
	var root_direction := (root_frame.origin - frame_a.origin).slide(Vector3.BACK).normalized()
	var toe_direction: Vector3 = (row.body.to_local(_movement._get_foot_world_position(row.body)) - frame_b.origin).slide(Vector3.BACK).normalized()
	var current_toe := relative * toe_direction
	var initial_angle := atan2(Vector3.BACK.dot(root_direction.cross(current_toe)), root_direction.dot(current_toe))
	var delta := TAU
	# Connector directions define the interior bend; node Y axes can face opposite ways.
	for sign_angle: float in [-1.0, 1.0]:
		var candidate := wrapf(sign_angle * deg_to_rad(data.front_leg_relative_angle_degrees) - initial_angle, -PI, PI)
		if absf(candidate) < absf(delta): delta = candidate
	row["knee"] = knee
	row["upper"] = upper
	row["relative_basis"] = relative
	row["knee_rotation"] = delta
	row["upper_anchor"] = frame_a.origin
	row["foot_anchor"] = frame_b.origin
	row["root_direction"] = root_direction
	row["toe_direction"] = toe_direction
	row["knee_flags"] = {}
	for flag: int in [Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR]:
		row.knee_flags[flag] = knee.get_flag_z(flag)
		knee.set_flag_z(flag, false)
	# Only the active front knees bypass the ordinary world-pitch bounds.
	knee.set_meta(&"spider_attack_knee", true)

func _restore_knee_lifts() -> void:
	for row: Dictionary in _feet:
		if not row.has("knee") or not is_instance_valid(row.knee) or row.knee.is_queued_for_deletion(): continue
		row.knee.remove_meta(&"spider_attack_knee")
		for flag: int in row.knee_flags: row.knee.set_flag_z(flag, row.knee_flags[flag])

func _release_torso_pitch() -> bool:
	if _front_body == _rear_body or not _alive(_front_body) or not _alive(_rear_body): return false
	for node: Node in get_parent().get_node("GeneratedParts").find_children("*", "Generic6DOFJoint3D", true, false):
		var joint := node as Generic6DOFJoint3D
		var a := joint.get_node_or_null(joint.node_a)
		var b := joint.get_node_or_null(joint.node_b)
		if not ((a == _front_body and b == _rear_body) or (b == _front_body and a == _rear_body)): continue
		_torso_joint = joint
		var rear_frame: Transform3D = joint.get_meta(&"generated_joint_frame_a" if a == _rear_body else &"generated_joint_frame_b")
		_rear_pivot = _rear_body.to_global(rear_frame.origin)
		for flag: int in [Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, Generic6DOFJoint3D.FLAG_ENABLE_MOTOR]:
			_torso_joint_flags[flag] = joint.get_flag_z(flag)
			joint.set_flag_z(flag, false)
		return true
	return false

func _restore_torso_pitch() -> void:
	if is_instance_valid(_torso_joint) and not _torso_joint.is_queued_for_deletion():
		for flag: int in _torso_joint_flags: _torso_joint.set_flag_z(flag, _torso_joint_flags[flag])
	_torso_joint_flags.clear()
	_torso_joint = null

func _set_phase(next: Phase) -> void:
	phase = next
	_elapsed = 0.0
	if diagnostic_logging: print("[spider_attack] character=", get_parent().get_path(), " phase=", Phase.keys()[phase], " reason=", _reason, " preparation=", _preparation_pose, " plan=", _plan)

func _position_servo(body: RigidBody3D, point: Vector3, velocity: Vector3, compensate_gravity: bool) -> void:
	var acceleration := (point-body.global_position)*data.position_gain + (velocity-body.linear_velocity)*2.0*sqrt(data.position_gain)
	if compensate_gravity: acceleration -= _movement._gravity_acceleration()*body.gravity_scale
	body.apply_central_force(acceleration.limit_length(data.maximum_acceleration)*body.mass)

func _attitude_servo(body: RigidBody3D, basis: Basis, angular_velocity: Vector3 = Vector3.ZERO, gain_scale: float = 1.0) -> void:
	var rotation := (basis.get_rotation_quaternion()*body.global_basis.orthonormalized().get_rotation_quaternion().inverse()).normalized()
	if rotation.w < 0.0: rotation = -rotation
	var vector := Vector3(rotation.x, rotation.y, rotation.z)
	var error := vector.normalized()*2.0*atan2(vector.length(), rotation.w)
	var gain := data.attitude_gain * gain_scale
	var acceleration := (error*gain+(angular_velocity-body.angular_velocity)*2.0*sqrt(gain)).limit_length(data.maximum_acceleration)
	var inverse := body.get_inverse_inertia_tensor()
	if inverse.determinant() > 0.0: body.apply_torque(inverse.inverse()*acceleration)

func _preparation() -> void:
	var fraction := smoothstep(0.0, data.rise_time, _elapsed) if phase == Phase.RISING else 0.0
	# Finish folding slightly before launch so the physical hinge can settle.
	var knee_time := data.rise_time * 0.8
	var knee_fraction := smoothstep(0.0, knee_time, _elapsed) if phase == Phase.RISING else 0.0
	var knee_progress := clampf(_elapsed / knee_time, 0.0, 1.0) if phase == Phase.RISING else 0.0
	var rotation := Basis(_pitch_axis, deg_to_rad(data.front_pitch_degrees)*fraction)
	var progress := clampf(_elapsed / data.rise_time, 0.0, 1.0) if phase == Phase.RISING else 0.0
	var angular_velocity := _pitch_axis * deg_to_rad(data.front_pitch_degrees) * 6.0 * progress * (1.0-progress) / data.rise_time
	for row: Dictionary in _bodies:
		var offset := rotation*(Vector3(row.origin)-_rear_pivot)
		row["target_position"] = _rear_pivot+offset if row.front else row.origin
		row["target_basis"] = rotation*Basis(row.basis) if row.front else row.basis
		_position_servo(row.body, row.target_position, angular_velocity.cross(offset) if row.front else Vector3.ZERO, true)
		_attitude_servo(row.body, row.target_basis, angular_velocity if row.front else Vector3.ZERO)
		if row.body == _front_body: _maximum_front_rise = maxf(_maximum_front_rise, (row.body.global_position-Vector3(row.origin)).dot(_up))
	for row: Dictionary in _feet:
		var foot: RigidBody3D = row.body
		if row.front:
			var upper: RigidBody3D = row.upper
			var basis := upper.global_basis.orthonormalized() * Basis(Vector3.BACK, float(row.knee_rotation)*knee_fraction) * Basis(row.relative_basis)
			var spin := upper.angular_velocity + upper.global_basis.z.normalized() * float(row.knee_rotation) * 6.0 * knee_progress * (1.0-knee_progress) / knee_time
			var anchor: Vector3 = upper.to_global(row.upper_anchor)
			var offset: Vector3 = basis * Vector3(row.foot_anchor)
			var velocity := upper.linear_velocity + upper.angular_velocity.cross(anchor-upper.global_position) - spin.cross(offset)
			row["target_position"] = anchor-offset
			row["target_basis"] = basis
			_position_servo(foot, row.target_position, velocity, true)
			_attitude_servo(foot, basis, spin, 2.0)
		else:
			row["target_position"] = row.origin
			_position_servo(foot, row.origin, Vector3.ZERO, true)
			if _movement.is_leg_grounded(foot): _movement.action_ground_foot(foot, _up, _elapsed, get_physics_process_delta_time())

func _preparation_pose_status() -> Dictionary:
	var pending: Array[StringName] = []
	var parts: Array[Dictionary] = []
	var position_error := 0.0
	var angle_error := 0.0
	for row: Dictionary in _feet + _bodies:
		# Rear feet hold ground support; only the moving front assembly has a lift goal.
		if not row.front: continue
		var distance: float = row.body.global_position.distance_to(row.target_position)
		var angle := 0.0
		if row.has("target_basis"):
			angle = rad_to_deg(row.body.global_basis.orthonormalized().get_rotation_quaternion().angle_to(Basis(row.target_basis).get_rotation_quaternion()))
		var tolerance: float = float(row.get("length", _body_length)) * data.preparation_position_tolerance_ratio
		if distance > tolerance or angle > data.preparation_angle_tolerance_degrees: pending.append(row.body.name)
		var part := {"part": row.body.name, "position_error": distance, "angle_error_degrees": angle}
		if row.has("root_direction"):
			part["relative_angle_degrees"] = rad_to_deg((row.upper.global_basis * Vector3(row.root_direction)).angle_to(row.body.global_basis * Vector3(row.toe_direction)))
		parts.append(part)
		position_error = maxf(position_error, distance)
		angle_error = maxf(angle_error, angle)
	return {"ready": pending.is_empty(), "pending": pending, "parts": parts, "maximum_position_error": position_error, "maximum_angle_error_degrees": angle_error, "extra_wait": clampf(_elapsed-data.rise_time, 0.0, data.preparation_pose_max_wait), "wait_expired": _elapsed >= data.rise_time+data.preparation_pose_max_wait}

func _launch() -> void:
	# Use the admitted endpoint even when the target has since escaped the leap.
	var origin: Vector3 = _movement._torso.global_position
	var endpoint: Vector3 = _plan.get("endpoint",Vector3.INF)
	var duration: float = _plan.get("duration",0.0)
	var maximum_speed: float = data.maximum_launch_speed*_time_scale
	var gravity: Vector3 = _movement._gravity_acceleration()
	if not origin.is_finite() or not endpoint.is_finite() or not gravity.is_finite() or not is_finite(duration) or duration <= 0.0 or not is_finite(maximum_speed) or maximum_speed <= 0.0:
		cancel_action(&"invalid_committed_plan"); return
	var velocity := (endpoint-origin)/duration-gravity*duration*0.5
	if not velocity.is_finite(): cancel_action(&"invalid_committed_plan"); return
	velocity = velocity.limit_length(maximum_speed)
	_plan.merge({"velocity":velocity,"launch_origin":origin,"committed":true},true)
	_movement.release_all_support_pins()
	for row: Dictionary in _feet:
		_movement.set_action_foot_grounded(row.body, false)
		row["swing_start"] = row.body.global_position-row.root.to_global(row.anchor)
		# The fold servo owns preparation; passive damping resumes for the sweep.
		if row.front: row.knee.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING, row.knee_flags[Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING])
	for part: RigidBody3D in _parts:
		if _alive(part): part.apply_central_impulse((Vector3(_plan.velocity)-part.linear_velocity)*part.mass)
	for row: Dictionary in _feet:
		if not row.front: continue
		var collision := row.body.get_node("CollisionShape3D") as CollisionShape3D
		var hitbox := HITBOX.new()
		hitbox.name = "SpiderForelegDamage_" + str(row.body.name)
		hitbox.setup(row.body, get_parent(), collision.shape.size*collision.scale.abs()*data.hitbox_padding, collision.position, data.impulse_multiplier, 0.0)
		get_parent().add_child(hitbox)
		_hitboxes.append(hitbox)
		row["hitbox"] = hitbox
	_launch_origin = _movement._torso.global_position
	_set_phase(Phase.LEAPING)

func _flight_pose() -> void:
	var progress := smoothstep(0.0, float(_plan.duration)*0.7, _elapsed)
	for row: Dictionary in _feet:
		# Do not keep pushing a connected limb through a struck body.
		if row.front and row.hitbox.hit_count > 0: continue
		var offset: Vector3 = row.swing_start
		if row.front:
			offset = offset.lerp(Vector3(row.offset)+_forward*float(row.length)*data.forward_sweep_ratio-_up*float(row.length)*0.05, progress)
		var target: Vector3 = row.root.to_global(row.anchor)+offset.limit_length(float(row.length)*0.96)
		_position_servo(row.body, target, row.root.linear_velocity, false)
	var rotation := Basis(_pitch_axis, deg_to_rad(data.front_pitch_degrees)*(1.0-progress))
	for row: Dictionary in _bodies: _attitude_servo(row.body, rotation*Basis(row.basis) if row.front else row.basis)

func update_action(delta: float) -> void:
	if Engine.is_editor_hint(): return
	_cooldown = maxf(0.0, _cooldown-delta)
	if not is_active(): return
	if not enabled or not _character_enabled or data == null or not data.enabled or not data.is_valid() or get_parent().is_temporarily_ragdolled() or _movement.recovery_control_active or _movement._planar_mode_active() or (not _npc_attack and not PLAYER.input_allowed(self)):
		cancel_action(&"control_disabled"); return
	for row: Dictionary in _feet:
		if not _alive(row.body) or not _movement._chain_is_intact(row.body): cancel_action(&"leg_broken"); return
	for row: Dictionary in _bodies:
		if not _alive(row.body): cancel_action(&"body_broken"); return
	_elapsed += delta
	match phase:
		Phase.PAUSING, Phase.RISING:
			if not _target_valid(_target): cancel_action(&"target_lost"); return
			_preparation()
			if phase == Phase.PAUSING and _elapsed >= data.pause_time: _set_phase(Phase.RISING)
			elif phase == Phase.RISING and _elapsed >= data.rise_time:
				_preparation_pose = _preparation_pose_status()
				var supports := 0
				for row: Dictionary in _feet:
					if not row.front and _movement.is_leg_grounded(row.body): supports += 1
				if supports >= 2 and (_preparation_pose.ready or _preparation_pose.wait_expired):
					_reason = &"preparation_pose_timeout" if not _preparation_pose.ready else &"preparation_ready"
					_launch()
				elif _preparation_pose.wait_expired: cancel_action(&"rear_support_lost")
		Phase.LEAPING:
			_flight_pose()
			for hitbox: HITBOX in _hitboxes: hitbox.update_hitbox(delta, true)
			var grounded := 0
			for row: Dictionary in _feet:
				if _movement.is_leg_grounded(row.body): grounded += 1
			if _elapsed >= float(_plan.duration)*0.65 and grounded >= 2:
				_begin_recovery(&"landed")
			elif _elapsed >= float(_plan.duration)+data.landing_timeout: _begin_recovery(&"landing_timeout")
		Phase.RECOVERING:
			for row: Dictionary in _bodies: _attitude_servo(row.body, row.basis)
			if _elapsed >= data.recovery_time: cancel_action(&"completed")

func _clear_hitboxes() -> void:
	for hitbox: HITBOX in _hitboxes:
		if is_instance_valid(hitbox): _hits += hitbox.hit_count; hitbox.dispose()
	_hitboxes.clear()

func _begin_recovery(reason: StringName) -> void:
	_reason = reason
	_clear_hitboxes()
	_movement.release_all_support_pins()
	_movement.end_action_control(self)
	_set_phase(Phase.RECOVERING)

func cancel_npc_attack() -> void: cancel_action(&"npc_cancelled")
func cancel_player_actions() -> void: cancel_action(&"input_suspended")
func set_character_control_enabled(value: bool) -> void:
	_character_enabled = value
	if not value: cancel_action(&"character_disabled")

func cancel_action(reason: StringName = &"cancelled") -> void:
	if Engine.is_editor_hint() or not is_active(): return
	_reason = reason if reason != &"completed" else _reason
	_clear_hitboxes()
	_restore_knee_lifts()
	_restore_torso_pitch()
	if is_instance_valid(_movement):
		_movement.release_all_support_pins()
		_movement.end_action_control(self)
	_cooldown = data.cooldown if data != null else 0.0
	_npc_attack = false
	_set_phase(Phase.IDLE)
	_feet.clear()
	_bodies.clear()
	_target = null

func _exit_tree() -> void: cancel_action(&"removed")

func get_action_diagnostics() -> Dictionary:
	var feet: Array = []
	for row: Dictionary in _feet:
		var info := {"part": row.body.name if is_instance_valid(row.body) else &"freed", "front": row.front}
		if row.front and _alive(row.body) and _alive(row.upper):
			info["relative_angle_degrees"] = rad_to_deg((row.upper.global_basis * Vector3(row.root_direction)).angle_to(row.body.global_basis * Vector3(row.toe_direction)))
			info["target_relative_angle_degrees"] = data.front_leg_relative_angle_degrees
		feet.append(info)
	var hits := _hits
	for hitbox: HITBOX in _hitboxes:
		if is_instance_valid(hitbox): hits += hitbox.hit_count
	var relative_pitch := rad_to_deg(atan2(_rear_body.global_basis.y.dot(_front_body.global_basis.x), _rear_body.global_basis.x.dot(_front_body.global_basis.x))) if _alive(_front_body) and _alive(_rear_body) else 0.0
	return {"action": ACTION, "enabled": enabled, "active": is_active(), "phase": Phase.keys()[phase], "elapsed": _elapsed, "reason": _reason, "cooldown": _cooldown, "feet": feet, "body_length": _body_length, "plan": _plan, "hits": hits, "front_rise": _maximum_front_rise, "front_relative_pitch_degrees": relative_pitch, "torso_pitch_released": not _torso_joint_flags.is_empty(), "preparation_pose": _preparation_pose, "launch_origin": _launch_origin}
