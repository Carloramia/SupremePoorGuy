@tool
extends Node
## Keep the existing component path/action ID so saved Rats and battle loadouts retain their bindings.
signal module_event(module: StringName, event: StringName, details: Dictionary)
const DATA = preload("res://Scripts/Creatures/RatBiteAttackData.gd")
const HITBOX = preload("res://Scripts/Items/TemporaryAttackHitbox3D.gd")
const PLAYER = preload("res://Scripts/Player/PlayerControlContext.gd")
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const ACTION: StringName = &"wolf_bite"
enum Phase { IDLE, PREPARING, STRIKING }
@export var enabled := true
@export var diagnostic_logging := false
@export var data: DATA
var movement: Node
var torso: PhysicalBodyPart3D
var head: PhysicalBodyPart3D
var jaw: PhysicalBodyPart3D
var phase := Phase.IDLE
var _character_enabled := true
var _joint: Generic6DOFJoint3D
var _joint_state: Dictionary = {}
var _head_state: Dictionary = {}
var _rest := Quaternion.IDENTITY
var _forefeet: Array[RigidBody3D] = []
var _bodies: Array[Dictionary] = []
var _locked_point := Vector3.ZERO
var _locked_head_point := Vector3.ZERO
var _head_start := Vector3.ZERO
var _mouth_offset := Vector3.ZERO
var _elapsed := 0.0
var _phase_elapsed := 0.0
var _closing_elapsed := -1.0
var _cooldown := 0.0
var _log_elapsed := 0.0
var _lock_count := 0
var _arrived := false
var _reason: StringName = &"idle"
var _weapon: HITBOX
var _last_hits := 0
var _marker: Marker3D
var _angle_error := 0.0
var _support_scale := 1.0

func _alive(part: Variant) -> bool:
	return is_instance_valid(part) and part is PhysicalBodyPart3D and part.is_inside_tree() and not part.is_queued_for_deletion() and not part.is_broken and not part.freeze

func _ready() -> void:
	if Engine.is_editor_hint(): set_physics_process(false); return
	process_physics_priority = -40
	add_to_group(&"wolf_attack_controllers")
	var console := get_node_or_null("/root/RuntimeConsole")
	if console != null: diagnostic_logging = console.is_wolf_attack_tracking_enabled(get_parent())
	refresh_physics_query_cache()

func refresh_physics_query_cache() -> void:
	if Engine.is_editor_hint(): return
	cancel_action(&"regenerated")
	movement = get_parent().get_node_or_null("GeneratedLegStepMovementController3D")
	torso = movement._torso if movement != null else null
	head = null; jaw = null; _joint = null
	var parts := get_parent().get_node_or_null("GeneratedParts")
	if data == null or parts == null: return
	for part: Node in parts.get_children():
		if not part is PhysicalBodyPart3D: continue
		var key: StringName = part.get_meta(&"generated_part_key",part.name)
		if key == data.head_key: head = part
		if key == data.jaw_key: jaw = part
	if not _alive(head) or not _alive(jaw): return
	_rest = (head.global_basis.orthonormalized().inverse()*jaw.global_basis.orthonormalized()).get_rotation_quaternion()
	_mouth_offset = head.to_local(jaw.to_global(Vector3(jaw.get_meta(&"generated_size",Vector3.ONE))*data.box_center_ratio))
	for candidate: Node in parts.get_node("Joints").get_children():
		if candidate is Generic6DOFJoint3D:
			var a := candidate.get_node_or_null(candidate.node_a)
			var b := candidate.get_node_or_null(candidate.node_b)
			if (a == head and b == jaw) or (a == jaw and b == head): _joint = candidate; break

func _body_length() -> float:
	return maxf(float(Vector3(torso.get_meta(&"generated_size",Vector3.ONE)).x),0.1) if _alive(torso) else 1.0

func _allowed() -> bool:
	if not enabled or not _character_enabled or data == null or not data.enabled or movement == null or not _alive(torso) or not _alive(head) or not _alive(jaw) or not is_instance_valid(_joint): return false
	return not get_parent().is_temporarily_ragdolled() and not movement.recovery_control_active and not movement._planar_mode_active() and not movement.simplified_physics_mode

func _valid_target(target: Node3D) -> bool:
	if not is_instance_valid(target) or not target is PhysicalBodyPart3D or not target.is_inside_tree() or target.is_queued_for_deletion() or target.is_broken: return false
	var actor := PLAYER.character_of(target)
	return actor != null and actor != get_parent() and actor.get_faction_id()!=get_parent().get_faction_id() and actor.get_world_3d()==get_parent().get_world_3d()

func has_npc_attack(action: StringName) -> bool:
	var ai := get_parent().get_node_or_null("NPCStateMachine3D")
	return action==ACTION and _allowed() and ai!=null and ai.attack_execution_enabled and PLAYER.controlled_character(self)!=get_parent()

func _target_point(target: PhysicalBodyPart3D) -> Vector3:
	# Aim inside the nearest shell at mouth height, clamped to this Part's actual vertical extent.
	var box := GEOMETRY.bounds(target)
	var mouth := jaw.to_global(Vector3(jaw.get_meta(&"generated_size",Vector3.ONE))*data.box_center_ratio)
	var point := target.to_local(mouth).clamp(box.position,box.end)
	return target.to_global(point.lerp(box.get_center(),0.05))

func uses_dynamic_npc_attack_range(_action: StringName) -> bool: return true
func get_npc_attack_minimum_range(_action: StringName) -> float: return 0.0
func get_npc_attack_maximum_range(_action: StringName, _target: Node3D = null) -> float:
	return torso.global_position.distance_to(head.global_position)+_body_length()*data.maximum_extension_ratio if _alive(torso) and _alive(head) and data!=null else 0.0
func get_npc_attack_preferred_distance(action: StringName, target: Node3D = null) -> float:
	return get_npc_attack_maximum_range(action,target)*data.preferred_range_ratio
func get_npc_attack_distance_tolerance(_action: StringName) -> float: return _body_length()*data.distance_tolerance_body_ratio
func get_npc_attack_maximum_duration(_action: StringName) -> float: return data.preparation_time+data.preparation_extra_wait+data.strike_timeout+data.jaw_close_time+data.jaw_close_extra_wait+0.5
func is_npc_target_in_attack_range(_action: StringName, target: Node3D) -> bool:
	return _valid_target(target) and head.global_position.distance_to(_target_point(target)-head.global_basis*_mouth_offset)<=_body_length()*data.maximum_extension_ratio

func predict_npc_attack(action: StringName, target: Node3D, _charge: float = 0.0, _samples: int = 24, _margin: float = 0.1) -> Dictionary:
	if not has_npc_attack(action) or not _valid_target(target): return {"hit":false,"reason":&"unavailable_or_invalid_target"}
	if is_npc_attack_active() or _cooldown>0.0 or movement.is_action_turn_blocked(): return {"hit":false,"reason":&"busy_cooldown_or_turning"}
	var point := _target_point(target)
	var within := is_npc_target_in_attack_range(action,target)
	return {"hit":within,"reason":&"static_point_reachable" if within else &"outside_static_point_reach","point":point,"confidence":1.0}

func try_start_npc_attack(action: StringName, target: Node3D, charge: float = 0.0) -> bool:
	var prediction := predict_npc_attack(action,target,charge)
	if not prediction.hit: return false
	_locked_point = prediction.point
	_locked_head_point = _locked_point-head.global_basis*_mouth_offset
	_head_start = head.global_position
	_lock_count = 1
	_forefeet.clear(); _bodies.clear()
	var claims: Array[RigidBody3D] = []
	var torso_mass := 0.0
	var supported_mass := 0.0
	for part: RigidBody3D in get_parent()._get_physical_body_parts():
		if not _alive(part): continue
		supported_mass += part.mass
		if PhysicalBodyPart3D.BodyPartTag.Torso in part.tags:
			_bodies.append({"part":part,"start":part.global_position})
			claims.append(part)
			torso_mass += part.mass
	for foot: RigidBody3D in movement.get_leg_parts():
		if _alive(foot) and PhysicalBodyPart3D.BodyPartTag.ForeLeg in foot.tags: _forefeet.append(foot)
	claims.append(head)
	_support_scale = maxf((supported_mass-head.mass-jaw.mass)/maxf(torso_mass,0.001),1.0)
	movement.begin_action_control(_forefeet,claims,self)
	_head_state = {"position":head.head_position_support_enabled,"posture":head.head_posture_damping_enabled}
	head.head_position_support_enabled = false
	head.head_posture_damping_enabled = false
	_joint_state = {"limit":_joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT),"spring":_joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING),"motor":_joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR)}
	_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,false)
	_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING,false)
	_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR,false)
	_marker = Marker3D.new()
	_marker.name = "LockedBiteTarget"
	add_child(_marker)
	_marker.top_level = true
	_marker.global_position = _locked_point
	_elapsed = 0.0; _phase_elapsed = 0.0; _closing_elapsed = -1.0
	_arrived = false; _last_hits = 0; _reason = &"started"
	phase = Phase.PREPARING
	log_event(&"Bite",&"started",get_diagnostics())
	log_event(&"Bite",&"target_locked",{"point":_locked_point,"head_point":_locked_head_point,"target_height":_locked_point.y,"locks":_lock_count})
	return true

func _track(part: RigidBody3D, point: Vector3, velocity: Vector3, gravity_scale: float, delta: float) -> void:
	var gain := data.position_gain
	var damping := data.velocity_gain
	var acceleration := ((point-part.global_position)*gain+(velocity-part.linear_velocity)*(damping+gain*delta))/(1.0+damping*delta+gain*delta*delta)
	acceleration -= movement._gravity_acceleration()*gravity_scale
	part.apply_central_force(acceleration.limit_length(data.maximum_acceleration)*part.mass)

func _drive_pose(delta: float) -> void:
	var displacement := _locked_head_point-_head_start
	var duration := maxf(displacement.length()/(_body_length()*data.strike_speed_body_lengths),0.08)
	var progress := clampf(_phase_elapsed/duration,0.0,1.0) if phase==Phase.STRIKING else 0.0
	var blend := smoothstep(0.0,1.0,progress)
	var velocity := displacement*(6.0*progress*(1.0-progress)/duration)
	if phase==Phase.PREPARING: velocity = Vector3.ZERO
	for row: Dictionary in _bodies:
		_track(row.part,Vector3(row.start)+displacement*blend,velocity,_support_scale,delta)
	_track(head,_head_start+displacement*blend,velocity,1.0,delta)
	for foot: RigidBody3D in _forefeet:
		var point: Vector3 = movement._get_leg_rest_world_position(foot)
		point.y += _body_length()*data.foreleg_lift_ratio
		_track(foot,point,Vector3.ZERO,1.0,delta)

func _drive_jaw(opening: float) -> void:
	if not _alive(head) or not _alive(jaw): return
	var desired := Quaternion(Vector3.BACK,-deg_to_rad(opening))*_rest
	var axis := head.global_basis.z.normalized()
	var error: float = movement._stance_rotation_error(jaw,head,desired).dot(axis)
	_angle_error = rad_to_deg(error)
	var rate := (jaw.angular_velocity-head.angular_velocity).dot(axis)
	var acceleration := clampf(error*data.angular_strength-rate*data.angular_damping,-data.maximum_angular_acceleration,data.maximum_angular_acceleration)
	var inverse: float = axis.dot(movement._stance_inverse_inertia(jaw)*axis)+axis.dot(movement._stance_inverse_inertia(head)*axis)
	var torque := axis*clampf(acceleration/maxf(inverse,0.000001),-data.maximum_torque,data.maximum_torque)
	jaw.apply_torque(torque)
	head.apply_torque(-torque)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): return
	_cooldown = maxf(_cooldown-delta,0.0)
	if not _allowed(): cancel_action(&"control_or_part_unavailable"); return
	if not is_npc_attack_active(): _drive_jaw(0.0); return
	for foot: RigidBody3D in _forefeet:
		if not _alive(foot) or not movement._chain_is_intact(foot): cancel_action(&"foreleg_broken"); return
	for row: Dictionary in _bodies:
		if not _alive(row.part): cancel_action(&"torso_broken"); return
	_elapsed += delta; _phase_elapsed += delta
	var opening := data.jaw_open_degrees
	if phase==Phase.PREPARING:
		opening *= smoothstep(0.0,data.preparation_time,_phase_elapsed)
		if _phase_elapsed>=data.preparation_time and (absf(_angle_error)<5.0 or _phase_elapsed>=data.preparation_time+data.preparation_extra_wait):
			_weapon = HITBOX.new()
			_weapon.damage_multiplier = data.damage_multiplier
			_weapon.name = "RatBiteHitbox"
			_weapon.damage_label = &"rat_bite_hit"
			var size: Vector3 = jaw.get_meta(&"generated_size",Vector3.ONE)
			_weapon.setup(jaw,get_parent(),size*data.box_size_ratio,size*data.box_center_ratio,data.impulse_multiplier,data.hit_ragdoll_duration)
			add_child(_weapon)
			phase = Phase.STRIKING
			CombatAudio3D.play_at(head, &"attack")
			_phase_elapsed = 0.0
			log_event(&"Bite",&"striking",get_diagnostics())
	else:
		_weapon.update_hitbox(delta,true)
		if _closing_elapsed<0.0 and head.global_position.distance_to(_locked_head_point)<=_body_length()*data.arrival_tolerance_ratio:
			_arrived = true
			_closing_elapsed = 0.0
			CombatAudio3D.play_at(jaw, &"bite")
			log_event(&"Bite",&"point_reached",get_diagnostics())
		if _closing_elapsed>=0.0:
			_closing_elapsed += delta
			opening *= 1.0-smoothstep(0.0,data.jaw_close_time,_closing_elapsed)
			if _closing_elapsed>=data.jaw_close_time+data.jaw_close_extra_wait:
				cancel_action(&"completed"); return
		elif _phase_elapsed>=data.strike_timeout:
			cancel_action(&"point_unreachable"); return
	_drive_pose(delta)
	_drive_jaw(opening)
	_log_elapsed += delta
	if diagnostic_logging and _log_elapsed>=0.1:
		_log_elapsed = 0.0
		print("[rat_attack] character=",get_parent().get_path()," state=",get_diagnostics())

func is_npc_attack_active() -> bool: return phase!=Phase.IDLE
func blocks_locomotion() -> bool: return is_npc_attack_active()
func is_pouncing() -> bool: return false
func cancel_npc_attack() -> void: cancel_action(&"npc_cancelled")
func cancel_player_actions() -> void: cancel_action(&"player_control_changed")
func set_character_control_enabled(value: bool) -> void:
	_character_enabled = value
	if not value: cancel_action(&"character_disabled")

func cancel_action(reason: StringName = &"cancelled") -> void:
	if not is_npc_attack_active(): return
	_reason = reason
	if is_instance_valid(_weapon):
		_last_hits = _weapon.hit_count
		_weapon.dispose()
	_weapon = null
	if is_instance_valid(_marker): _marker.queue_free()
	_marker = null
	if is_instance_valid(movement): movement.end_action_control(self)
	if is_instance_valid(head) and not _head_state.is_empty():
		head.head_position_support_enabled = _head_state.position
		head.head_posture_damping_enabled = _head_state.posture
	_head_state.clear()
	if is_instance_valid(_joint) and not _joint.is_queued_for_deletion() and not _joint_state.is_empty():
		_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,_joint_state.limit)
		_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING,_joint_state.spring)
		_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR,_joint_state.motor)
	_joint_state.clear()
	phase = Phase.IDLE
	_forefeet.clear(); _bodies.clear()
	_cooldown = data.cooldown if data!=null else 0.0
	log_event(&"Bite",reason,get_diagnostics())

func get_diagnostics() -> Dictionary:
	return {"phase":Phase.keys()[phase],"elapsed":_elapsed,"phase_elapsed":_phase_elapsed,"cooldown":_cooldown,"locked_point":_locked_point,"locked_head_point":_locked_head_point,"locks":_lock_count,"prediction_cancel_enabled":false,"head_error":head.global_position.distance_to(_locked_head_point) if _alive(head) else -1.0,"head_position":head.global_position if _alive(head) else Vector3.ZERO,"angle_error_degrees":_angle_error,"arrived":_arrived,"closing":_closing_elapsed>=0.0,"hits":_weapon.hit_count if is_instance_valid(_weapon) else _last_hits,"result":_reason,"released_forefeet":_forefeet.map(func(foot): return foot.name)}
func get_attack_diagnostics() -> Array[Dictionary]: return [get_diagnostics()]
func log_event(module: StringName, event: StringName, details: Dictionary = {}) -> void:
	module_event.emit(module,event,details)
	if diagnostic_logging: print("[rat_attack] character=",get_parent().get_path()," module=",module," event=",event," details=",details)
func _exit_tree() -> void:
	if not Engine.is_editor_hint(): cancel_action(&"removed")
