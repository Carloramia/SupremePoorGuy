@tool
extends Node3D
const DATA = preload("res://Scripts/Creatures/ChargeAttackData.gd")
const WEAPON = preload("res://Scenes/Items/ChargeWeapon.tscn")
const PLAYER = preload("res://Scripts/Player/PlayerControlContext.gd")
enum Phase { IDLE, ALIGNING, CHARGING, BRAKING }
@export var enabled: bool = true
@export var data: DATA = preload("res://Resources/Actions/GroundCharge.tres")
@export var diagnostic_logging: bool = false
var phase := Phase.IDLE
var _movement: Node
var _body: PhysicalBodyPart3D
var _target: Node3D
var _weapon: ChargeWeapon3D
var _old_source: Node
var _ccd: Dictionary = {}
var _elapsed := 0.0
var _cooldown := 0.0
var _speed := 0.0
var _direction := 1.0
var _target_x := 0.0
var _lane_z := 0.0
var _stuck := 0.0
var _airborne := 0.0
var _unsupported_elapsed := 0.0
var _previous_x := 0.0
var _reason: StringName = &"idle"
var _npc := false
var _character_enabled := true
var _tracking := false
var _log_elapsed := 0.0
var _charge_time_limit := 0.0
var _target_half_width := 0.0
var _navigation_check: Dictionary = {}
var _force_frame: int = -1
var _force_applied := false
var _force_skip_reason: StringName = &"not_processed"
var _support_count := 0
var _submitted_force := Vector3.ZERO
var _force_rows: Array[Dictionary] = []

func uses_navigation_attack_gate() -> bool:
	return true

func _check_navigation_path(target: Node3D) -> Dictionary:
	var map := get_world_3d().navigation_map
	var layers := 1
	var machine := get_parent().get_node_or_null("NPCStateMachine3D")
	if machine != null and is_instance_valid(machine.navigation_agent):
		map = machine.navigation_agent.get_navigation_map()
		layers = machine.navigation_agent.navigation_layers
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return {"hit":false,"reason":&"navigation_not_ready"}
	var start := NavigationServer3D.map_get_closest_point(map, _body.global_position)
	var end := NavigationServer3D.map_get_closest_point(map, target.global_position)
	if (start-_body.global_position).slide(Vector3.UP).length() > data.navigation_projection_tolerance or (end-target.global_position).slide(Vector3.UP).length() > data.navigation_projection_tolerance:
		return {"hit":false,"reason":&"outside_navigation_mesh","navigation_start":start,"navigation_end":end}
	var points := NavigationServer3D.map_get_path(map,start,end,true,layers)
	var reached := not points.is_empty() and points[-1].distance_to(end) <= data.navigation_endpoint_tolerance
	return {"hit":reached,"reason":&"navigation_path_available" if reached else &"navigation_unreachable","navigation_start":start,"navigation_end":end,"path_points":points.size(),"path_complete":reached}

func get_npc_attack_minimum_range(_action_id: StringName) -> float:
	return data.get_minimum_distance()

func has_unlimited_npc_attack_range(_action_id: StringName) -> bool:
	return true

func get_npc_attack_maximum_duration(_action_id: StringName) -> float:
	return data.alignment_timeout + maxf(_charge_time_limit, data.maximum_charge_time) + data.maximum_braking_time + 1.0
func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	process_physics_priority = -30
	add_to_group(&"charge_attack_controllers")
	add_to_group(&"damage_components")
	var console := get_node_or_null("/root/RuntimeConsole")
	if console != null:
		_tracking = console.is_charge_tracking_enabled()
		diagnostic_logging = console.is_damage_tracking_enabled()
	refresh_physics_query_cache()
func _alive(body: Node) -> bool:
	return is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion() and body.get("is_broken") != true
func refresh_physics_query_cache() -> void:
	if Engine.is_editor_hint(): return
	cancel_action(&"regenerated")
	_movement = get_parent().get_node_or_null("GeneratedLegStepMovementController3D")
	if _movement == null: _movement = get_parent().get_node_or_null("NPCLegStepMovementController3D")
	_body = null
	for part: PhysicalBodyPart3D in get_parent()._get_physical_body_parts():
		if _alive(part) and PhysicalBodyPart3D.BodyPartTag.Head in part.tags:
			_body = part
			break
	if _body == null: _body = get_parent().get_combat_anchor() as PhysicalBodyPart3D
func is_active() -> bool: return phase != Phase.IDLE
func owns_velocity() -> bool: return phase in [Phase.CHARGING, Phase.BRAKING]
func get_expected_speed() -> float: return _speed
func get_head_posture_request() -> Dictionary:
	if data == null: return {"angle":0.0,"transition_time":0.3,"angular_speed":deg_to_rad(50.0)}
	var lowering := enabled and _character_enabled and data.enabled and data.lower_head_enabled and phase == Phase.CHARGING
	return {"angle":-deg_to_rad(data.head_lower_angle_degrees) if lowering else 0.0,"transition_time":data.head_lower_transition_time,"angular_speed":deg_to_rad(maxf(data.head_lower_angle_degrees,1.0))/maxf(data.head_lower_transition_time,0.05)}
func get_movement_direction() -> Vector3:
	if phase == Phase.ALIGNING and _alive(_target) and _alive(_body):
		var dz := _target.global_position.z - _body.global_position.z
		return Vector3(0, 0, signf(dz)) if absf(dz) > data.z_tolerance else Vector3.ZERO
	return Vector3(_direction, 0, 0) if phase == Phase.CHARGING else Vector3.ZERO
func get_generated_facing_direction(_delta: float) -> Vector3:
	if phase == Phase.ALIGNING and _alive(_target) and _alive(_body):
		return Vector3(signf(_target.global_position.x-_body.global_position.x),0,0)
	return Vector3(_direction,0,0) if owns_velocity() else Vector3.ZERO
func is_jump_requested() -> bool: return false
func is_fast_requested() -> bool: return false
func _resolve_target(target: Node3D) -> Node3D:
	var actor := PLAYER.character_of(target) if is_instance_valid(target) else null
	return actor.get_nearest_combat_torso(_body.global_position) if actor != null and not target is PhysicalBodyPart3D and _alive(_body) else target
func has_npc_attack(action_id: StringName) -> bool:
	if _cooldown > 0.0: return false
	return action_id == &"ground_charge" and enabled and _character_enabled and data != null and data.enabled and data.is_valid() and _alive(_body) and is_instance_valid(_movement)
func _target_check(target: Node3D, path: bool = true) -> Dictionary:
	if not has_npc_attack(&"ground_charge") or not _alive(target): return {"hit":false,"reason":&"unavailable"}
	var actor := PLAYER.character_of(target)
	if actor == null or actor.get_world_3d() != get_world_3d() or actor == get_parent() or not actor.is_combat_alive() or actor.get_faction_id() == get_parent().get_faction_id(): return {"hit":false,"reason":&"not_enemy"}
	var offset := target.global_position - _body.global_position
	if absf(offset.x) < data.get_minimum_distance(): return {"hit":false,"reason":&"below_acceleration_distance","minimum_distance":data.get_minimum_distance(),"x_distance":absf(offset.x)}
	if path:
		_navigation_check = _check_navigation_path(target)
		if not _navigation_check.hit: return _navigation_check.duplicate()
	return {"hit":true,"reason":&"charge_lane_available","confidence":0.9}
func is_npc_target_in_attack_range(action_id: StringName, target: Node3D) -> bool:
	return action_id == &"ground_charge" and _target_check(_resolve_target(target),false).hit
func get_npc_attack_range_diagnostics(action_id: StringName, target: Node3D) -> Dictionary:
	var resolved := _resolve_target(target)
	var result: Dictionary = _target_check(resolved, false).duplicate() if action_id == &"ground_charge" else {"hit":false,"reason":&"unknown_action"}
	result.merge({"controller_enabled":enabled,"character_enabled":_character_enabled,
		"data_enabled":data != null and data.enabled,"data_valid":data != null and data.is_valid(),
		"body_alive":_alive(_body),"movement_available":is_instance_valid(_movement),
		"receiver_available":has_npc_attack(action_id),"receiver_cooldown":_cooldown,
		"phase":Phase.keys()[phase],"minimum_distance":data.get_minimum_distance() if data != null else -1.0,
		"maximum_unlimited":true,"height_check_enabled":false,"navigation_check":_navigation_check}, true)
	if _alive(_body) and _alive(resolved):
		var offset := resolved.global_position - _body.global_position
		result.merge({"source_part":str(_body.get_path()),"target_part":str(resolved.get_path()),
			"source_position":_body.global_position,"target_position":resolved.global_position,
			"x_distance":absf(offset.x),"z_distance":absf(offset.z),"height_difference":absf(offset.y)}, true)
	return result
func predict_npc_attack(action_id: StringName, target: Node3D, _charge: float, _samples: int = 24, _margin: float = 0.1) -> Dictionary:
	return _target_check(_resolve_target(target)) if action_id == &"ground_charge" else {"hit":false,"reason":&"unknown_action"}
func try_start_npc_attack(action_id: StringName, target: Node3D, _charge: float) -> bool:
	if PLAYER.controlled_character(self) == get_parent(): return false
	var started := try_start_action(action_id,target)
	_npc = started
	return started
func try_start_action(action_id: StringName, target: Node3D) -> bool:
	if is_active() or _cooldown > 0.0 or not has_npc_attack(action_id): return false
	if _movement.get("recovery_control_active") == true: return false
	if get_parent().get("planar_constraints_enabled") == true: return false
	for name: String in ["CreatureActionController3D", "BirdDiveAttackController3D"]:
		var other := get_parent().get_node_or_null(name)
		if other != null and other.is_active(): return false
	_target = _resolve_target(target)
	if not _target_check(_target).hit: return false
	_old_source = _movement.command_source
	_movement.command_source = self
	_set_phase(Phase.ALIGNING, &"start")
	return true
func is_npc_attack_active() -> bool: return _npc and is_active()
func cancel_npc_attack() -> void: cancel_action(&"npc_cancelled")
func cancel_player_actions() -> void:
	if not _npc: cancel_action(&"player_cancelled")
func set_character_control_enabled(value: bool) -> void:
	_character_enabled = value
	if not value: cancel_action(&"character_disabled")
func _remove_weapon() -> void:
	if is_instance_valid(_weapon):
		_weapon.detach()
		_weapon.queue_free()
	_weapon = null
func cancel_action(reason: StringName = &"cancelled") -> void:
	_remove_weapon()
	for part: Variant in _ccd:
		if is_instance_valid(part): part.continuous_cd = _ccd[part]
	_ccd.clear()
	if is_instance_valid(_movement) and _movement.command_source == self:
		_movement.command_source = _old_source if is_instance_valid(_old_source) else null
	_old_source = null
	if is_active():
		_cooldown = data.cooldown if data != null else 0.0
		_set_phase(Phase.IDLE,reason)
	_target = null
	_npc = false
	_speed = 0.0
func _set_phase(next: Phase, reason: StringName) -> void:
	phase = next
	_elapsed = 0.0
	_reason = reason
	_log(&"phase")
func _charge_center() -> Vector3:
	var center := Vector3.ZERO
	var mass := 0.0
	for torso: RigidBody3D in _movement.get_torso_parts():
		if _alive(torso):
			center += torso.global_position * torso.mass
			mass += torso.mass
	return center / mass if mass > 0.0 else _body.global_position
var _load_parts: Array[RigidBody3D] = []
var _load_metrics: Dictionary = {}

func _start_charge() -> void:
	_load_parts.clear()
	if get_parent().has_method("_get_physical_body_parts"):
		for part: RigidBody3D in get_parent()._get_physical_body_parts():
			if not _load_parts.has(part): _load_parts.append(part)
	_direction = signf(_target.global_position.x - _body.global_position.x)
	_target_x = _target.global_position.x
	_target_half_width = float(_target.get_meta(&"generated_size", Vector3.ONE).x) * 0.5
	_lane_z = _body.global_position.z
	_previous_x = _charge_center().x
	var pass_distance := absf(_target_x - _previous_x) + data.pass_margin + float(_target.get_meta(&"generated_size", Vector3.ONE).x) * 0.5
	# Long charges get their travel time plus the configured timeout as slack.
	_charge_time_limit = data.get_travel_time(pass_distance) + data.maximum_charge_time
	_stuck = 0.0
	_airborne = 0.0
	_unsupported_elapsed = 0.0
	_speed = data.starting_speed
	_weapon = WEAPON.instantiate()
	add_child(_weapon)
	_weapon.attach_to_body(_body,data.weapon_length_ratio,data.weapon_radius_ratio)
	_weapon.update_ground_box(_direction,data.obstacle_mask,false)
	for part: PhysicalBodyPart3D in get_parent()._get_physical_body_parts():
		_ccd[part] = part.continuous_cd
		part.continuous_cd = true
	_movement.cancel_step(&"charge_started")
	_set_phase(Phase.CHARGING, &"aligned")
func _begin_braking(reason: StringName) -> void:
	_remove_weapon()
	_set_phase(Phase.BRAKING,reason)
func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown-delta,0.0)
	if not is_active(): return
	_force_frame = Engine.get_physics_frames()
	_airborne_support = {"weight":0.0,"remaining":0.0,"feet":0}
	_force_applied = false
	_force_skip_reason = &"phase_has_no_velocity_control"
	_support_count = 0
	_submitted_force = Vector3.ZERO
	_force_rows.clear()
	if not enabled or not _character_enabled or data == null or not data.enabled or not data.is_valid() or not _alive(_body): cancel_action(&"disabled_or_broken"); return
	if _movement.get("recovery_control_active") == true: cancel_action(&"recovery"); return
	_elapsed += delta
	if phase == Phase.ALIGNING:
		if not _alive(_target): cancel_action(&"target_lost"); return
		if _elapsed > data.alignment_timeout: cancel_action(&"alignment_timeout"); return
		var facing := get_parent().get_node_or_null("PhysicalFacingController3D")
		var direction := Vector3(signf(_target.global_position.x-_body.global_position.x),0,0)
		var ready: bool = facing == null or facing.is_npc_facing_ready(direction)
		if facing == null and _movement.has_method("set_segment_facing_direction"):
			_movement.set_segment_facing_direction(direction)
			for torso: RigidBody3D in _movement.get_torso_parts():
				if _alive(torso) and torso.global_basis.x.slide(Vector3.UP).normalized().dot(direction) < cos(deg_to_rad(15.0)): ready = false
		if absf(_target.global_position.z-_body.global_position.z) <= data.z_tolerance and ready:
			if _target_check(_target).hit: _start_charge()
	elif phase == Phase.CHARGING:
		_speed = move_toward(_speed,data.maximum_speed,data.acceleration*delta)
		if _alive(_target): _target_x = _target.global_position.x
		if not _alive(_target): _begin_braking(&"target_lost")
		elif _direction*(_charge_center().x-_target_x) >= data.pass_margin + _target_half_width: _begin_braking(&"passed_target")
		elif _elapsed > _charge_time_limit: _begin_braking(&"charge_timeout")
		else:
			_stuck = _stuck+delta if _direction*(_charge_center().x-_previous_x) < 0.05*delta else 0.0
			if _stuck >= data.stuck_timeout: _begin_braking(&"blocked")
		_previous_x = _charge_center().x
	elif phase == Phase.BRAKING:
		_speed = move_toward(_speed,0.0,data.deceleration*delta)
		if (_speed <= 0.01 and absf(_body.linear_velocity.x) < 0.3) or _elapsed >= data.maximum_braking_time: cancel_action(&"completed"); return
	if owns_velocity():
		if is_instance_valid(_weapon): _weapon.update_ground_box(_direction,data.obstacle_mask)
		_support_count = _movement.get_torso_movement_force_legs(false).size()
		var supported := _support_count > 0
		var lease := {"weight":0.0,"remaining":0.0,"feet":0}
		if phase == Phase.CHARGING and data.allow_all_feet_airborne and _movement.has_method("get_charge_airborne_support"):
			lease = _movement.get_charge_airborne_support()
		_airborne = 0.0 if supported else _airborne+delta
		_airborne_support = lease
		var flight_supported: bool = float(lease.weight) > 0.0 and float(lease.remaining) > 0.0
		# Count the safety grace only after both real and remembered support end.
		_unsupported_elapsed = 0.0 if supported or flight_supported else _unsupported_elapsed+delta
		if _unsupported_elapsed > data.airborne_timeout: cancel_action(&"airborne"); return
		if supported: _apply_velocity(delta)
		elif flight_supported: _apply_velocity(delta,float(lease.weight))
		else: _force_skip_reason = &"no_contact_or_flight_support"
	_log_elapsed += delta
	if _tracking and _log_elapsed >= 0.1:
		_log_elapsed = 0.0
		_log(&"sample")
var _airborne_support: Dictionary = {"weight":0.0,"remaining":0.0,"feet":0}

func _get_load_metrics() -> Dictionary:
	var torso_mass := 0.0
	for body: RigidBody3D in _movement.get_torso_parts():
		if _alive(body) and not body.freeze: torso_mass += body.mass
	var load_mass := 0.0
	var damping_mass := 0.0
	var default_damping := float(ProjectSettings.get_setting("physics/3d/default_linear_damp",0.1))
	for body: RigidBody3D in _load_parts:
		if not _alive(body) or body.freeze: continue
		load_mass += body.mass
		var damping := body.linear_damp
		if body.linear_damp_mode == RigidBody3D.DAMP_MODE_COMBINE: damping += default_damping
		damping_mass += body.mass*damping
	load_mass = maxf(load_mass,torso_mass)
	return {"torso_mass":torso_mass,"load_mass":load_mass,"budget_mass":load_mass if data.use_total_load_mass else torso_mass,"damping_rate":damping_mass/maxf(load_mass,0.001)}

func _apply_velocity(_delta: float, support_weight: float = 1.0) -> void:
	_force_skip_reason = &"no_eligible_torso"
	_load_metrics = _get_load_metrics()
	var torso_mass: float = _load_metrics.torso_mass
	if torso_mass <= 0.0:
		if _tracking or diagnostic_logging:
			for body: RigidBody3D in _movement.get_torso_parts():
				if is_instance_valid(body): _force_rows.append({"torso":body.name,"applied":false,"reason":&"frozen" if body.freeze else &"broken_or_removed"})
		return
	var mass_ratio: float = _load_metrics.budget_mass/torso_mass
	var ramp_acceleration := data.acceleration if phase == Phase.CHARGING and _speed < data.maximum_speed else 0.0
	for body: RigidBody3D in _movement.get_torso_parts():
		if not _alive(body) or body.freeze: continue
		var desired := Vector3(_direction*_speed,0,clampf((_lane_z-body.global_position.z)*data.velocity_gain,-2.0,2.0))
		var damping_acceleration := desired*float(_load_metrics.damping_rate) if data.compensate_linear_damping else Vector3.ZERO
		var feedforward := Vector3(_direction*ramp_acceleration,0,0)+damping_acceleration
		var acceleration := (desired-Vector3(body.linear_velocity.x,0,body.linear_velocity.z))*data.velocity_gain+feedforward
		var limited := acceleration.limit_length(data.maximum_acceleration)
		var budget_mass := body.mass*mass_ratio
		var force := limited*budget_mass*clampf(support_weight,0.0,1.0)
		body.apply_central_force(force)
		_force_applied = true
		_force_skip_reason = &"none"
		_submitted_force += force
		if _tracking or diagnostic_logging:
			_force_rows.append({"torso":body.name,"applied":true,"mass":body.mass,"budget_mass":budget_mass,"velocity":body.linear_velocity,"desired_velocity":desired,"feedforward_acceleration":feedforward,"requested_acceleration":acceleration,"limited_acceleration":limited,"acceleration_limited":acceleration.length()>data.maximum_acceleration,"submitted_force":force})
func set_damage_logging_enabled(value: bool) -> void: diagnostic_logging = value
func set_diagnostic_tracking_enabled(value: bool) -> void: _tracking = value
func get_charge_diagnostics() -> Dictionary:
	var velocity := Vector3.ZERO
	var mass := 0.0
	var feet: Array[Dictionary] = []
	if is_instance_valid(_movement):
		for torso: RigidBody3D in _movement.get_torso_parts():
			if not _alive(torso): continue
			velocity += torso.linear_velocity*torso.mass
			mass += torso.mass
		for foot: RigidBody3D in _movement.get_leg_parts():
			if not _alive(foot): continue
			var row: Dictionary = _movement.get_support_foot_diagnostics(foot).duplicate()
			row.merge({"foot":foot.name,"position":foot.global_position,"velocity":foot.linear_velocity,"stepping":_movement.is_leg_stepping(foot),"grounded":_movement.is_leg_grounded(foot)},true)
			feet.append(row)
	return {"character":get_parent().name,"phase":Phase.keys()[phase],"reason":_reason,"elapsed":_elapsed,"speed":_speed,"direction":_direction,"target_x":_target_x,"lane_z":_lane_z,"actual_velocity":_body.linear_velocity if _alive(_body) else Vector3.ZERO,"cooldown":_cooldown,"weapon":is_instance_valid(_weapon),"minimum_distance":data.get_minimum_distance(),"maximum_distance_unlimited":true,"charge_time_limit":_charge_time_limit,
		"torso_center":_charge_center() if _alive(_body) and is_instance_valid(_movement) else Vector3.ZERO,"torso_velocity":velocity/mass if mass>0.0 else Vector3.ZERO,"torso_mass":mass,
		"force_frame":_force_frame,"force_applied":_force_applied,"force_skip_reason":_force_skip_reason,"support_count":_support_count,"submitted_force":_submitted_force,"torso_force_rows":_force_rows,"feet":feet,"head_posture_request":get_head_posture_request(),"head_posture":get_parent().get_node("HeadPositionSupport3D").get_head_support_diagnostics() if get_parent().has_node("HeadPositionSupport3D") else [],
		"stuck_elapsed":_stuck,"stuck_timeout":data.stuck_timeout,"airborne_elapsed":_airborne,"unsupported_elapsed":_unsupported_elapsed,"allow_all_feet_airborne":data.allow_all_feet_airborne,"airborne_support":_airborne_support,"load_budget":_load_metrics}
func _log(event: StringName) -> void:
	if diagnostic_logging or _tracking: print("[ground_charge] event=",event," ",get_charge_diagnostics())
func _exit_tree() -> void:
	if not Engine.is_editor_hint(): cancel_action(&"removed")
