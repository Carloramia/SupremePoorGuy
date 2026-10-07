extends Node3D
## Temporary flight/wing override; cone weapons use the shared contact damage system.
const DIVE_WEAPON = preload("res://Scenes/Items/BirdDiveWeapon.tscn")
const CONE = preload("res://Scripts/Items/BirdDiveWeapon3D.gd")
var _temporary_weapons: Array[SampleWeapon3D] = []
const DATA = preload("res://Scripts/Creatures/BirdDiveAttackData.gd")
const PLAYER = preload("res://Scripts/Player/PlayerControlContext.gd")
const PREDICTION = preload("res://Scripts/Creatures/NPCAttackPrediction3D.gd")
enum Phase { IDLE, AIMING, DIVING, PULLING_UP }
@export var enabled: bool = true
@export var data: DATA = preload("res://Resources/Actions/BirdDiveAttack.tres")
@export var diagnostic_logging: bool = false
var phase: Phase = Phase.IDLE
var _flight: Node
var _heads: Array[PhysicalBodyPart3D] = []
var _parts: Array[PhysicalBodyPart3D] = []
var _target: Node3D
var _target_character: Node3D
var _aim := Vector3.ZERO
var _elapsed := 0.0
var _cooldown := 0.0
var _npc_attack := false
var _character_enabled := true
var _tracking := false
var _hit_parts: Dictionary = {}
var _ccd_before: Dictionary = {}
var _last_impact := {}
var _last_target_check: Dictionary = {}
var _sequence := 0
var _aiming_ready_elapsed := 0.0
var _aiming_status: Dictionary = {}

func _ready() -> void:
	process_physics_priority = -20
	add_to_group(&"bird_physics_diagnostics")
	add_to_group(&"damage_components")
	var console := get_node_or_null("/root/RuntimeConsole")
	if console != null:
		_tracking = console.is_bird_physics_tracking_enabled()
		diagnostic_logging = console.is_damage_tracking_enabled()
	refresh_physics_query_cache()

func _alive(body: PhysicalBodyPart3D) -> bool:
	return is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion() and not body.is_broken

func refresh_physics_query_cache() -> void:
	cancel_action(&"regenerated")
	_parts.clear(); _heads.clear()
	_character_enabled = true
	_flight = get_parent().get_node_or_null("BirdFlightController3D")
	var container := get_parent().get_node_or_null("GeneratedParts")
	if container == null: return
	for child: Node in container.get_children():
		var part := child as PhysicalBodyPart3D
		if not _alive(part): continue
		_parts.append(part)
		if PhysicalBodyPart3D.BodyPartTag.Head in part.tags: _heads.append(part)

func is_active() -> bool: return phase != Phase.IDLE
func is_aiming() -> bool: return phase == Phase.AIMING
func wants_folded_wings() -> bool: return phase in [Phase.AIMING,Phase.DIVING]
func has_input_action(action: StringName) -> bool:
	return enabled and data != null and data.enabled and action == data.input_action
func handle_input(event: InputEvent) -> bool:
	if event.is_echo() or data == null or not event.is_action_pressed(data.input_action) or not has_input_action(data.input_action): return false
	if PLAYER.input_allowed(self): try_start_action(&"bird_dive")
	return true

func has_npc_attack(action_id: StringName) -> bool:
	if action_id != &"bird_dive" or not enabled or not _character_enabled or data == null or not data.enabled or not data.is_valid(): return false
	for head: PhysicalBodyPart3D in _heads:
		if _alive(head): return true
	return false

func _resolve_target(target: Node3D) -> Node3D:
	var actor := PLAYER.character_of(target) if is_instance_valid(target) else null
	return actor.get_nearest_combat_torso(global_position) if actor != null and not target is PhysicalBodyPart3D else target

func _target_check(target: Node3D, check_path: bool = true) -> Dictionary:
	if not has_npc_attack(&"bird_dive") or not is_instance_valid(_flight) or not _flight.is_airborne(): return {"hit":false,"reason":&"not_airborne_or_no_head"}
	var head: PhysicalBodyPart3D
	for candidate: PhysicalBodyPart3D in _heads:
		if _alive(candidate): head = candidate; break
	if head == null or not is_instance_valid(target) or not target.is_inside_tree(): return {"hit":false,"reason":&"no_target"}
	var actor := PLAYER.character_of(target)
	if actor == null or actor == get_parent() or not actor.is_combat_alive() or actor.get_faction_id() == get_parent().get_faction_id() or target.get("is_broken") == true: return {"hit":false,"reason":&"not_enemy"}
	var geometry: Dictionary = data.evaluate_target_geometry(head.global_position,target.global_position)
	if not geometry.hit: return geometry
	var aim := target.global_position+PREDICTION.velocity(target)*data.target_lead_time
	if check_path:
		var excluded: Array[RID] = []
		for part: PhysicalBodyPart3D in _parts:
			if _alive(part): excluded.append(part.get_rid())
		for part: RigidBody3D in actor._get_physical_body_parts(): excluded.append(part.get_rid())
		var forward := (aim-head.global_position).normalized()
		var up := Vector3.UP.slide(forward).normalized()
		if up.is_zero_approx(): up = Vector3.RIGHT.slide(forward).normalized()
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = CONE.make_cone_shape(head, data.weapon_length_ratio, data.weapon_radius_ratio)
		query.transform = Transform3D(Basis(forward, up, forward.cross(up)), head.global_position)
		query.motion = aim-head.global_position
		query.collision_mask = data.obstacle_mask
		query.exclude = excluded
		var space := get_world_3d().direct_space_state
		var blocked := not space.intersect_shape(query, 1).is_empty()
		var travel := space.cast_motion(query)
		if blocked or (not travel.is_empty() and travel[0] < 0.999):
			geometry.hit = false
			geometry.reason = &"blocked_path"
			return geometry
	geometry.reason = &"predicted_dive_contact"
	geometry["confidence"] = 0.8
	geometry["aim"] = aim
	geometry["collision_prediction"] = &"cone_sweep"
	return geometry

## The NPC coarse range check must use the same 3D geometry, including vertical dives.
func is_npc_target_in_attack_range(action_id: StringName, target: Node3D) -> bool:
	return action_id == &"bird_dive" and _target_check(_resolve_target(target),false).hit

func predict_npc_attack(action_id: StringName, target: Node3D, _charge: float, _samples: int = 24, _margin: float = 0.1) -> Dictionary:
	return _target_check(_resolve_target(target)) if action_id == &"bird_dive" else {"hit":false,"reason":&"unknown_action"}

func _select_target() -> Node3D:
	var controller := PLAYER.controller(self)
	if controller != null and controller.terrain_cursor != null:
		var selected := _resolve_target(controller.terrain_cursor.get_selected_character())
		if is_instance_valid(selected) and _target_check(selected).hit: return selected
	var best: Node3D
	var distance := INF
	for actor: Node3D in get_tree().get_nodes_in_group(&"physical_characters_3d"):
		if actor == get_parent(): continue
		var candidate: Node3D = actor.get_nearest_combat_torso(global_position)
		if not _target_check(candidate).hit: continue
		var next := candidate.global_position.distance_squared_to(_flight._torso.global_position)
		if next<distance: distance = next; best = candidate
	return best

func try_start_action(action_id: StringName = &"bird_dive", target: Node3D = null) -> bool:
	if is_active() or _cooldown>0.0 or not has_npc_attack(action_id): return false
	var module := get_parent().get_node_or_null("CreatureActionController3D")
	if module != null and module.is_active(): return false
	_target = _resolve_target(target) if is_instance_valid(target) else _select_target()
	var prediction := _target_check(_target)
	_last_target_check = prediction.duplicate()
	if not prediction.hit:
		_log(&"rejected",prediction)
		return false
	_target_character = PLAYER.character_of(_target)
	_aim = prediction.aim
	_hit_parts.clear(); _last_impact.clear()
	_sequence += 1
	for head: PhysicalBodyPart3D in _heads:
		if _alive(head):
			_ccd_before[head] = head.continuous_cd
			head.continuous_cd = true
	_set_phase(Phase.AIMING,&"start")
	return true

func try_start_npc_attack(action_id: StringName, target: Node3D, _charge: float) -> bool:
	if PLAYER.controlled_character(self) == get_parent(): return false
	var started := try_start_action(action_id,target)
	_npc_attack = started
	return started
func is_npc_attack_active() -> bool: return _npc_attack and is_active()
func cancel_npc_attack() -> void:
	_npc_attack = false
	if phase in [Phase.AIMING,Phase.DIVING]: _begin_pull_up(&"npc_cancelled")
func cancel_player_actions() -> void:
	if not _npc_attack and phase in [Phase.AIMING,Phase.DIVING]: _begin_pull_up(&"player_cancelled")
func set_character_control_enabled(value: bool) -> void:
	_character_enabled = value
	if not value: cancel_action(&"character_disabled")
func cancel_action(reason: StringName = &"cancelled") -> void:
	for head: Variant in _ccd_before:
		if is_instance_valid(head): head.continuous_cd = _ccd_before[head]
	_ccd_before.clear()
	if is_active(): _cooldown = data.cooldown if data != null else 0.0
	_npc_attack = false
	_target = null; _target_character = null
	_set_phase(Phase.IDLE,reason)

func _set_phase(next: Phase, reason: StringName) -> void:
	if phase == next: return
	if next != Phase.DIVING: _remove_dive_weapons()
	phase = next; _elapsed = 0.0
	if next == Phase.DIVING:
		for head: PhysicalBodyPart3D in _heads:
			if not _alive(head): continue
			var weapon := DIVE_WEAPON.instantiate() as SampleWeapon3D
			add_child(weapon)
			weapon.attach_to_head(head, data.weapon_length_ratio, data.weapon_radius_ratio)
			_temporary_weapons.append(weapon)
		_log(&"weapon_created", {"count": _temporary_weapons.size()})
	_aiming_ready_elapsed = 0.0
	_aiming_status.clear()
	_log(&"phase",{"phase":Phase.keys()[phase],"reason":reason,"sequence":_sequence})

func _remove_dive_weapons() -> void:
	for weapon: SampleWeapon3D in _temporary_weapons:
		if not is_instance_valid(weapon): continue
		weapon.detach()
		weapon.queue_free()
	_temporary_weapons.clear()

func _exit_tree() -> void:
	for head: Variant in _ccd_before:
		if is_instance_valid(head): head.continuous_cd = _ccd_before[head]

func _begin_pull_up(reason: StringName) -> void:
	if phase == Phase.PULLING_UP or phase == Phase.IDLE: return
	var total_mass := 0.0
	var torso_mass := 0.0
	var velocity_y := 0.0
	for part: PhysicalBodyPart3D in _parts:
		if not _alive(part) or part.freeze: continue
		total_mass += part.mass
		velocity_y += part.linear_velocity.y*part.mass
		if PhysicalBodyPart3D.BodyPartTag.Torso in part.tags: torso_mass += part.mass
	velocity_y /= maxf(total_mass,0.000001)
	var change := clampf(data.pull_up_speed-velocity_y,0.0,data.maximum_pull_up_velocity_change)
	for part: PhysicalBodyPart3D in _parts:
		if _alive(part) and not part.freeze and PhysicalBodyPart3D.BodyPartTag.Torso in part.tags:
			part.apply_central_impulse(Vector3.UP*change*total_mass*part.mass/maxf(torso_mass,0.000001))
	_set_phase(Phase.PULLING_UP,reason)
	_log(&"pull_up",{"incoming_velocity_y":velocity_y,"velocity_change":change,"impulse":change*total_mass})

func _register_head_contact(head: PhysicalBodyPart3D, collider: Object, impulse: float, weapon: SampleWeapon3D) -> void:
	if phase != Phase.DIVING or not _alive(head) or impulse<=0.0: return
	if collider is PhysicalBodyPart3D:
		var target := collider as PhysicalBodyPart3D
		var actor := PLAYER.character_of(target)
		if not _alive(target) or actor == null or actor == get_parent() or actor.get_faction_id() == get_parent().get_faction_id(): return
		if _hit_parts.has(target.get_instance_id()): return
		_hit_parts[target.get_instance_id()] = true
		var damage := weapon.apply_contact_damage(target, impulse)
		_last_impact = {"head":str(head.name),"target":str(target.name),"impulse":impulse,"damage":damage,"armor":target.armor,"source":"cone_weapon"}
		_log(&"impact",_last_impact)
		_begin_pull_up(&"enemy_hit")
	elif collider is PhysicsBody3D: _begin_pull_up(&"terrain_or_obstacle_hit")

func _read_head_contacts() -> void:
	for head: PhysicalBodyPart3D in _heads:
		if not _alive(head): continue
		var state := PhysicsServer3D.body_get_direct_state(head.get_rid())
		if state == null: continue
		var contacts: Dictionary = {}
		for index: int in range(state.get_contact_count()):
			var weapon := SampleWeapon3D.from_contact(head, state.get_contact_local_shape(index))
			if weapon == null or weapon not in _temporary_weapons: continue
			var collider := state.get_contact_collider_object(index)
			if not is_instance_valid(collider): continue
			if not contacts.has(collider): contacts[collider] = {"impulse":0.0,"weapon":weapon}
			contacts[collider].impulse = maxf(contacts[collider].impulse,state.get_contact_impulse(index).length())
		for collider: Object in contacts: _register_head_contact(head,collider,contacts[collider].impulse,contacts[collider].weapon)

func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown-delta,0.0)
	if not is_active(): return
	if not enabled or not _character_enabled or data == null or not data.enabled or not data.is_valid() or not is_instance_valid(_flight) or not _flight.is_airborne(): cancel_action(&"unavailable"); return
	var head: PhysicalBodyPart3D
	for candidate: PhysicalBodyPart3D in _heads:
		if _alive(candidate): head = candidate; break
	if head == null: cancel_action(&"no_head"); return
	_elapsed += delta
	if phase in [Phase.AIMING,Phase.DIVING] and (not is_instance_valid(_target) or _target.get("is_broken") == true or not is_instance_valid(_target_character) or not _target_character.is_combat_alive()): _begin_pull_up(&"target_lost")
	var wing := get_parent().get_node_or_null("WingPoseController3D")
	if phase == Phase.AIMING:
		_aim = _target.global_position+PREDICTION.velocity(_target)*data.target_lead_time
		_aiming_status = _get_aiming_readiness(wing)
		var ready: bool = _elapsed>=maxf(data.minimum_aiming_time,data.fold_time) and _aiming_status.head_ready and _aiming_status.wings_ready
		_aiming_ready_elapsed = _aiming_ready_elapsed+delta if ready else 0.0
		if ready and _aiming_ready_elapsed>=data.aiming_confirmation_time:
			var check := _target_check(_target)
			_last_target_check = check.duplicate()
			if not check.hit: _begin_pull_up(&"target_no_longer_valid")
			else:
				_aim = check.aim
				_log(&"aim_ready",_aiming_status)
				_set_phase(Phase.DIVING,&"aim_and_wings_ready")
		elif _elapsed>=data.maximum_aiming_time:
			_log(&"aim_timeout",_aiming_status)
			cancel_action(&"aim_timeout")
			return
	if phase == Phase.DIVING:
		_read_head_contacts()
		if phase == Phase.DIVING and (_elapsed>=data.maximum_dive_time or head.global_position.y<_aim.y-1.0): _begin_pull_up(&"miss_or_timeout")
	if phase == Phase.PULLING_UP and _elapsed>=data.pull_up_time: cancel_action(&"finished"); return
	var direction := (_aim-head.global_position).normalized()
	var target_velocity := Vector3.ZERO
	if phase == Phase.AIMING: target_velocity = Vector3.UP*data.aiming_ascent_speed
	elif phase == Phase.DIVING: target_velocity = direction*data.dive_speed
	elif phase == Phase.PULLING_UP: target_velocity = Vector3.UP*data.pull_up_speed
	var compensation := data.dive_gravity_compensation if phase == Phase.DIVING else 1.0
	var forward := direction if phase in [Phase.AIMING,Phase.DIVING] else Vector3.RIGHT*signf(_flight._torso.global_basis.x.x)
	if forward.is_zero_approx(): forward = Vector3.RIGHT
	for part: PhysicalBodyPart3D in _parts:
		if not _alive(part) or part.freeze or part.custom_integrator: continue
		var state := PhysicsServer3D.body_get_direct_state(part.get_rid())
		if state == null: continue
		var acceleration := ((target_velocity-part.linear_velocity)*data.velocity_response).limit_length(data.maximum_acceleration)
		part.apply_central_force((acceleration-state.total_gravity*compensation)*part.mass)
	_apply_attack_pose(forward,delta)

func _get_aiming_readiness(wing: Node) -> Dictionary:
	var head_error := 0.0
	var head_speed := 0.0
	for head: PhysicalBodyPart3D in _heads:
		if not _alive(head): continue
		var direction := (_aim-head.global_position).normalized()
		head_error = maxf(head_error,rad_to_deg(acos(clampf(head.global_basis.x.normalized().dot(direction),-1.0,1.0))))
		head_speed = maxf(head_speed,head.angular_velocity.slide(direction).length())
	var wing_error := 0.0
	var wing_errors: Array[Dictionary] = []
	var wings_ready := true
	if wing != null and not wing.bindings.is_empty():
		wings_ready = wing.enabled and wing.unfold_ratio<=0.05
		for binding: Dictionary in wing.bindings:
			if not wing._binding_intact(binding): continue
			var relative: Quaternion = (binding.a.global_basis.orthonormalized().inverse()*binding.b.global_basis.orthonormalized()).get_rotation_quaternion()
			var error_degrees := rad_to_deg(relative.angle_to(Quaternion(binding.closed)))
			wing_error = maxf(wing_error,error_degrees)
			wing_errors.append({"wing":str(binding.b.name),"error":error_degrees,"actual":rad_to_deg(relative.get_euler().z),"closed":rad_to_deg(Quaternion(binding.closed).get_euler().z)})
		wings_ready = wings_ready and wing_error<=data.wing_fold_tolerance_degrees
	return {"head_error_degrees":head_error,"head_angular_speed":head_speed,"wing_error_degrees":wing_error,"head_ready":head_error<=data.head_alignment_tolerance_degrees and head_speed<=data.aiming_maximum_angular_speed,"wings_ready":wings_ready,"wing_errors":wing_errors}

func _pose_acceleration(current: Basis, forward: Vector3, velocity: Vector3, delta: float) -> Vector3:
	# Aim the local +X forward axis while keeping the back upright. This also handles
	# targets behind the bird without pitching the entire body upside down.
	var up := Vector3.UP.slide(forward).normalized()
	if up.is_zero_approx(): up = current.y.slide(forward).normalized()
	if up.is_zero_approx(): up = Vector3.RIGHT.slide(forward).normalized()
	var desired := Basis(forward,up,forward.cross(up)).orthonormalized().get_rotation_quaternion()
	var error := desired*current.orthonormalized().get_rotation_quaternion().inverse()
	if error.w<0.0: error = -error
	var rotation := error.get_axis()*error.get_angle()
	return ((rotation*data.pose_strength-velocity*(data.pose_damping+data.pose_strength*delta))/(1.0+data.pose_damping*delta+data.pose_strength*delta*delta)).limit_length(data.maximum_acceleration)

func _apply_attack_pose(forward: Vector3, delta: float) -> void:
	var structure: Dictionary = _flight._flight_structure()
	var current := Vector3.ZERO
	for part: PhysicalBodyPart3D in _parts:
		if _alive(part) and not part.freeze and PhysicalBodyPart3D.BodyPartTag.Torso in part.tags: current += part.global_basis.x.normalized()*part.mass
	var current_forward := current.normalized()
	var current_up: Vector3 = structure.up
	var current_basis := Basis(current_forward,current_up,current_forward.cross(current_up)).orthonormalized()
	var acceleration := _pose_acceleration(current_basis,forward,structure.angular_velocity,delta)
	var torque: Vector3 = Basis(structure.inertia)*acceleration
	for part: PhysicalBodyPart3D in _parts:
		if not _alive(part) or part.freeze or part.custom_integrator: continue
		if PhysicalBodyPart3D.BodyPartTag.Torso in part.tags and float(structure.torso_mass)>0.0:
			part.apply_torque(torque*part.mass/float(structure.torso_mass))
		elif PhysicalBodyPart3D.BodyPartTag.Head in part.tags:
			var head_forward := (_aim-part.global_position).normalized() if phase in [Phase.AIMING,Phase.DIVING] else forward
			var inverse := part.get_inverse_inertia_tensor()
			if inverse.determinant()!=0.0: part.apply_torque(inverse.inverse()*_pose_acceleration(part.global_basis.orthonormalized(),head_forward,part.angular_velocity,delta))

func get_dive_diagnostics() -> Dictionary:
	return {"phase":Phase.keys()[phase],"sequence":_sequence,"elapsed":_elapsed,"cooldown":_cooldown,"aim":_aim,"head_count":_heads.size(),"impact":_last_impact,"target_check":_last_target_check,"aiming":_aiming_status,"aiming_confirmation_elapsed":_aiming_ready_elapsed}
func set_diagnostic_tracking_enabled(value: bool) -> void: _tracking = value
func set_damage_logging_enabled(value: bool) -> void: diagnostic_logging = value
func _log(event: StringName, details: Dictionary) -> void:
	if _tracking or diagnostic_logging: print("[bird_dive] character=",get_parent().name," event=",event," ",details)
