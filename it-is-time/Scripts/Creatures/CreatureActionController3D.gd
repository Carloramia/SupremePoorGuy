extends Node

const DATA = preload("res://Scripts/Creatures/CreatureActionData.gd")
const PLAYER = preload("res://Scripts/Player/PlayerControlContext.gd")
const SHOCKWAVE = preload("res://Scenes/VFX/StompShockwave3D.tscn")
enum Phase { IDLE, RISING, STOMPING, LANDING, RECOVERING }
@export var enabled: bool = true
@export var actions: Array[DATA] = []
@export var movement_path: NodePath = ^"../GeneratedLegStepMovementController3D"
@export var diagnostic_logging: bool = false
var phase: Phase = Phase.IDLE
var _movement: Node
var _data: DATA
var _feet: Array[Dictionary] = []
var _torsos: Array[Dictionary] = []
var _elapsed := 0.0
var _cooldown := 0.0
var _confirmation := 0.0
var _up := Vector3.UP
var _reason: StringName = &""
var _rise_elapsed := 0.0
var _support_lost_time := 0.0
var _support_count := 0
var _npc_attack := false
var _shockwaves_spawned := 0
const HIT_PREDICTION = preload("res://Scripts/Creatures/NPCAttackPrediction3D.gd")

func predict_npc_attack(action_id: StringName, target: Node3D, _charge: float, samples: int = 24, margin: float = 0.1) -> Dictionary:
	samples = clampi(samples,8,48)
	if not has_npc_attack(action_id): return {"hit":false,"reason":&"unavailable_foreleg"}
	var movement := get_node_or_null(movement_path)
	var data: DATA
	for option: DATA in actions:
		if option != null and option.enabled and option.action_id == action_id: data = option; break
	if data == null or data.shockwave == null: return {"hit":false,"reason":&"no_shockwave"}
	if movement.get_action_support_feet().is_empty(): return {"hit":false,"reason":&"no_ground_support"}
	var up: Vector3 = -movement._gravity_acceleration().normalized()
	if up.is_zero_approx(): up = Vector3.UP
	for foot: RigidBody3D in movement.get_leg_parts():
		if not movement._has_body_tag(foot,movement.FORELEG_TAG) or not movement._chain_is_intact(foot): continue
		var chain: Dictionary = movement._chains[foot]
		var root_body := chain.root as RigidBody3D
		var attachment: Vector3 = root_body.to_global(chain.anchor)
		var hit: Dictionary = movement._get_surface_below_leg(foot,movement.surface_adhesion_probe_distance)
		if hit.is_empty(): continue
		var center: Vector3 = hit.position
		var offset := center-attachment
		var forward := root_body.global_basis.x.slide(up).normalized()
		if offset.dot(forward) < -float(chain.length)*data.rearward_tolerance_ratio:
			var side := offset.slide(up)-forward*offset.dot(forward)
			var reach: float = float(chain.length)*movement.chain_reach_ratio*0.95
			var advance := sqrt(maxf(reach*reach-pow(offset.dot(up),2)-side.length_squared(),0.0))*data.forward_extension_ratio
			for attempt: int in range(8,0,-1):
				var candidate := attachment+side+up*offset.dot(up)+forward*advance*float(attempt)/8.0
				var query := PhysicsRayQueryParameters3D.create(candidate+up*2.0,candidate-up*4.0,movement.terrain_collision_mask,movement._get_character_exclusion_rids())
				var surface := foot.get_world_3d().direct_space_state.intersect_ray(query)
				if surface.is_empty() or not movement._surface_is_walkable(surface.normal): continue
				var position: Vector3 = movement._body_position_for_ground_contact(foot,surface.position)
				if position.distance_to(attachment) <= reach and movement._has_leg_clearance(foot,position,surface.rid): center = surface.position; break
		var impact_time := data.rise_time+data.stomp_time
		center += root_body.linear_velocity*impact_time
		for sample: int in range(1,samples+1):
			var fraction := float(sample)/samples
			var time := impact_time+data.shockwave.duration*fraction
			var distance := HIT_PREDICTION.surface_distance(center,target,time)
			if distance <= data.shockwave.radius*fraction+margin:
				return {"hit":true,"reason":&"predicted_shockwave_contact","time":time,"foot":foot.name,"center":center,"confidence":0.8}
	return {"hit":false,"reason":&"shockwave_misses"}

func has_npc_attack(action_id: StringName) -> bool:
	if not enabled or action_id != &"foreleg_stomp": return false
	var movement := get_node_or_null(movement_path)
	if movement == null: return false
	var configured := false
	for data: DATA in actions:
		if data != null and data.enabled and data.action_id == action_id and data.is_valid(): configured = true; break
	if not configured: return false
	for foot: RigidBody3D in movement.get_leg_parts():
		if movement._has_body_tag(foot, movement.FORELEG_TAG) and movement._chain_is_intact(foot): return true
	return false

func try_start_npc_attack(action_id: StringName, _target: Node3D, _charge: float) -> bool:
	if PLAYER.controlled_character(self) == get_parent(): return false
	if is_active(): return false
	_npc_attack = true
	var started := try_start_action(action_id)
	if not started: _npc_attack = false
	return started

func is_npc_attack_active() -> bool: return _npc_attack and is_active()

func cancel_npc_attack() -> void:
	if _npc_attack: cancel_action(&"npc_cancelled")
	_npc_attack = false

func _action_input_allowed() -> bool:
	return (_npc_attack and PLAYER.controlled_character(self) != get_parent()) or PLAYER.input_allowed(self)

func is_active() -> bool: return phase != Phase.IDLE

func has_input_action(action: StringName) -> bool:
	if not enabled: return false
	for data: DATA in actions:
		if data != null and data.enabled and data.input_action == action: return true
	return false

func handle_input(event: InputEvent) -> bool:
	if not enabled or event.is_echo(): return false
	for data: DATA in actions:
		if data != null and data.enabled and event.is_action_pressed(data.input_action):
			try_start_action(data.action_id)
			return true
	return false

func try_start_action(action_id: StringName = &"foreleg_stomp") -> bool:
	var charge := get_parent().get_node_or_null("ChargeAttackController3D")
	if charge != null and charge.is_active(): return _reject(&"charge_active")
	var dive := get_parent().get_node_or_null("BirdDiveAttackController3D")
	if dive != null and dive.is_active(): return _reject(&"bird_dive_active")
	_movement = get_node_or_null(movement_path)
	if not enabled or is_active() or _cooldown > 0.0 or _movement == null or not _action_input_allowed(): return _reject(&"busy_or_input_blocked")
	if not _movement.is_physics_processing() or _movement.recovery_control_active or _movement.simplified_physics_mode or _movement._planar_mode_active() or _movement._adhesion_release_time_remaining > 0.0: return _reject(&"physics_mode_or_recovery")
	if _movement.is_action_turn_blocked(): return _reject(&"turning")
	_data = null
	for data: DATA in actions:
		if data != null and data.enabled and data.action_id == action_id: _data = data; break
	if _data == null or not _data.is_valid() or action_id != &"foreleg_stomp": return _reject(&"invalid_action")
	_feet.clear()
	_torsos.clear()
	var gravity: Vector3 = _movement._gravity_acceleration()
	_up = -gravity.normalized() if not gravity.is_zero_approx() else Vector3.UP
	var support_count := 0
	var selected_segments: Dictionary = {}
	for foot: RigidBody3D in _movement.get_leg_parts():
		if not _movement._chain_is_intact(foot): continue
		if not _movement._has_body_tag(foot,_movement.FORELEG_TAG):
			if _movement.get_action_support_feet().has(foot): support_count += 1
			continue
		var chain: Dictionary = _movement._chains[foot]
		var root_body: RigidBody3D = chain.root
		var surface := _surface(foot,foot.global_position)
		if surface.is_empty(): return _reject(&"foreleg_without_terrain")
		var ground_body: Vector3 = _movement._body_position_for_ground_contact(foot,surface.position)
		_feet.append({"body": foot,"root": root_body,"length": chain.length,"offset": ground_body-root_body.to_global(chain.anchor),"ground_height": Vector3(surface.position).dot(_up),"lift": float(chain.length)*_data.foot_lift_ratio,"lifted": false,"landed": false,"pin_elapsed": 0.0,"force": Vector3.ZERO})
		selected_segments[int(root_body.get_meta(&"body_segment_id",0))] = true
	if _feet.is_empty() or support_count == 0: return _reject(&"no_forelegs_or_remaining_support")
	var feet: Array[RigidBody3D] = []
	for row: Dictionary in _feet: feet.append(row.body)
	var bodies: Array[RigidBody3D] = []
	var length := INF
	for row: Dictionary in _feet: length = minf(length,float(row.length))
	for id: int in selected_segments:
		for body: RigidBody3D in _movement._segments[id].bodies:
			if body.freeze or _movement._is_body_broken(body): continue
			bodies.append(body)
			# Shared front/rear segments need a smaller lift to preserve rear stance.
			var shared := false
			for foot: RigidBody3D in _movement._segments[id].feet:
				if not feet.has(foot): shared = true
			_torsos.append({"body": body,"segment": id,"height": body.global_position.dot(_up),"lift": length*_data.torso_lift_ratio*(0.5 if shared else 1.0),"force": Vector3.ZERO})
	for row: Dictionary in _feet: _capture_forward_plan(row)
	_movement.begin_action_control(feet,bodies)
	_reason = &"started"
	_shockwaves_spawned = 0
	_confirmation = 0.0
	_rise_elapsed = 0.0
	_support_lost_time = 0.0
	_support_count = support_count
	_set_phase(Phase.RISING)
	return true

func _spawn_shockwave(point: Vector3, normal: Vector3, impulse: float) -> void:
	if _data.shockwave == null or not _data.shockwave.enabled or not _data.shockwave.is_valid(): return
	var wave := SHOCKWAVE.instantiate()
	wave.setup(_data.shockwave,get_parent(),point,normal,impulse)
	var host: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	host.add_child.call_deferred(wave)
	_shockwaves_spawned += 1

func _update_contact_shockwave(row: Dictionary) -> void:
	if not row.has("shockwave_pending") or row.get("shockwave_triggered",false): return
	var pending: Dictionary = row.shockwave_pending
	var frame := Engine.get_physics_frames()
	var sample: Dictionary = row.body.get_foot_contact_impact(pending.collider,int(pending.since_frame))
	# Solver contact data can arrive one tick after the grounding query. Do not
	# substitute commanded downward force or accumulate ordinary stance impulses.
	if sample.is_empty() and frame-int(pending.frame) < 2: return
	var impulse: float = sample.get("impulse",0.0)
	row["stomp_impulse"] = impulse
	row["shockwave_triggered"] = true
	_spawn_shockwave(sample.get("position",pending.point),pending.normal,impulse)

func _reject(reason: StringName) -> bool:
	if not is_active(): _reason = reason
	if diagnostic_logging: print("[creature_action] rejected=",reason," character=",get_parent().name)
	return false

## Called by the movement controller before its ordinary force update.
func update_action(delta: float) -> void:
	_cooldown = maxf(_cooldown-delta,0.0)
	if not is_active(): return
	if not enabled or not is_instance_valid(_movement) or not _movement.is_physics_processing() or not _action_input_allowed() or _movement.recovery_control_active or _movement._planar_mode_active() or _movement.simplified_physics_mode or _movement._adhesion_release_time_remaining > 0.0:
		cancel_player_actions(); return
	if _movement._turn_planning_active or _movement._layout_turn_owned:
		cancel_action(&"turn_interrupted"); return
	if _movement.input_enabled and _movement.is_burst_requested():
		cancel_action(&"jump_requested"); return
	for row: Dictionary in _feet:
		if not is_instance_valid(row.body) or not is_instance_valid(row.root) or not _movement._chain_is_intact(row.body) or row.body.freeze or _movement._is_body_broken(row.body): cancel_action(&"part_invalid"); return
	for row: Dictionary in _torsos:
		if not is_instance_valid(row.body) or row.body.freeze or _movement._is_body_broken(row.body): cancel_action(&"torso_invalid"); return
	_elapsed += delta
	_support_count = _movement.get_action_support_feet().size()
	var lift_paused := phase == Phase.RISING and _support_count == 0
	if phase == Phase.RISING:
		if lift_paused:
			_support_lost_time += delta
			if _support_lost_time >= _data.support_loss_timeout:
				_reason = &"support_lost"
				_set_phase(Phase.RECOVERING)
				lift_paused = false
		else:
			_support_lost_time = 0.0
			_rise_elapsed += delta
	var weight := smoothstep(0.0,0.1,_elapsed) if phase == Phase.RISING else 1.0
	if phase == Phase.RECOVERING: weight = 1.0-smoothstep(0.0,_data.recovery_time,_elapsed)
	for row: Dictionary in _torsos:
		_movement.set_action_body_weight(row.body,weight)
		var height := float(row.height)
		if phase == Phase.RISING: height += float(row.lift)*smoothstep(0.0,_data.rise_time,_rise_elapsed)
		elif phase == Phase.STOMPING: height += float(row.lift)*(1.0-smoothstep(0.0,_data.stomp_time,_elapsed))
		var target: Vector3 = row.body.global_position+_up*(height-row.body.global_position.dot(_up))
		row.force = Vector3.ZERO if lift_paused else _servo(row.body,target,Vector3.ZERO,true,weight,0.0)
	var ready := true
	var all_landed := true
	for row: Dictionary in _feet:
		var foot: RigidBody3D = row.body
		var chain: Dictionary = _movement._chains[foot]
		var attachment: Vector3 = row.root.to_global(chain.anchor)
		var progress := smoothstep(0.0,_data.rise_time,_rise_elapsed)
		if phase == Phase.STOMPING or phase == Phase.LANDING: progress = 1.0
		var planned: Vector3 = row.landing_offset
		var desired := attachment+Vector3(row.offset).lerp(planned,progress)
		row["extension_progress"] = progress
		var hit := _surface(foot,desired)
		if hit.is_empty(): cancel_action(&"terrain_lost"); return
		var floor_body: Vector3 = _movement._body_position_for_ground_contact(foot,hit.position)
		var actual := _surface(foot,foot.global_position)
		var gap: float = INF if actual.is_empty() else (_movement._get_foot_world_position(foot)-Vector3(actual.position)).dot(Vector3(actual.normal))
		if gap >= maxf(0.05,float(row.lift)*0.2): row.lifted = true
		if phase == Phase.RISING:
			_movement._release_support_pin(foot)
			desired = floor_body+_up*float(row.lift)*smoothstep(0.0,_data.rise_time,_rise_elapsed)
			ready = ready and bool(row.lifted) and gap >= float(row.lift)*_data.height_confirmation_ratio
		else:
			if (row.lifted or phase == Phase.RECOVERING) and not actual.is_empty() and absf(gap) <= 0.07 and _movement.is_leg_grounded(foot):
				if row.lifted and phase in [Phase.STOMPING,Phase.LANDING] and not row.get("shockwave_triggered",false) and not row.has("shockwave_pending"):
					var frame := Engine.get_physics_frames()
					row["shockwave_pending"] = {"point":actual.position,"normal":actual.normal,"collider":actual.collider,"frame":frame,"since_frame":maxi(frame-2,int(row.get("stomp_start_frame",frame)))}
				row.landed = true
				_movement.action_ground_foot(foot,actual.normal,float(row.pin_elapsed),delta)
				row.landed = _movement._support_pins.has(foot)
				row.pin_elapsed += delta
			else:
				row.landed = false
				row.pin_elapsed = 0.0
				_movement.set_action_foot_grounded(foot,false)
				_movement._release_support_pin(foot)
			if phase == Phase.STOMPING: desired = floor_body+_up*float(row.lift)*(1.0-smoothstep(0.0,_data.stomp_time,_elapsed))
			else: desired = floor_body
		_update_contact_shockwave(row)
		desired = _limit_airborne_extension(row,attachment,desired)
		row.force = Vector3.ZERO
		if not row.landed:
			var velocity: Vector3 = row.root.linear_velocity.slide(_up)
			if phase == Phase.RISING and not lift_paused:
				var t := clampf(_rise_elapsed/_data.rise_time,0.0,1.0)
				velocity += (planned-Vector3(row.offset)).slide(_up)*(6.0*t*(1.0-t)/_data.rise_time)
			var down := _data.downward_acceleration if phase == Phase.STOMPING and _elapsed >= _data.stomp_time*0.35 else 0.0
			row.force = _servo(foot,desired,velocity,false,weight,down,lift_paused)
		all_landed = all_landed and bool(row.landed)
		row["ground_gap"] = gap
		row["target"] = desired
	if phase == Phase.RISING:
		# A rigid segment's center is the lift target. Small solver differences
		# between individual torso blocks must not prevent the whole segment from stomping.
		var segment_rise: Dictionary = {}
		for row: Dictionary in _torsos:
			if not segment_rise.has(row.segment): segment_rise[row.segment] = Vector2.ZERO
			var rise: float = row.body.global_position.dot(_up)-float(row.height)
			segment_rise[row.segment] += Vector2(rise,float(row.lift))*row.body.mass
		for value: Vector2 in segment_rise.values(): ready = ready and value.x >= value.y*_data.height_confirmation_ratio
		if ready and not lift_paused and _rise_elapsed >= _data.rise_time:
			for row: Dictionary in _feet: _plan_stomp_landing(row)
			_set_phase(Phase.STOMPING)
		elif _elapsed >= _data.rise_timeout: _reason = &"rise_timeout"; _set_phase(Phase.RECOVERING)
	elif phase == Phase.STOMPING:
		if all_landed: _set_phase(Phase.LANDING)
		elif _elapsed >= _data.landing_timeout: _reason = &"landing_timeout"; _set_phase(Phase.RECOVERING)
	elif phase == Phase.LANDING:
		_confirmation = _confirmation+delta if all_landed else 0.0
		if _confirmation >= _data.contact_confirmation_time: _set_phase(Phase.RECOVERING)
		elif _elapsed >= _data.landing_timeout: _reason = &"contact_lost"; _set_phase(Phase.RECOVERING)
	elif phase == Phase.RECOVERING and _elapsed >= _data.recovery_time: cancel_action(&"completed")

## Decide from the real foot/root posture before any lift. The landing reference
## uses that root height even at the top of the action, when the root cannot
## yet reach the floor. Actual airborne extension is bounded separately.
func _capture_forward_plan(row: Dictionary) -> void:
	var chain: Dictionary = _movement._chains[row.body]
	var attachment: Vector3 = row.root.to_global(chain.anchor)
	var forward: Vector3 = row.root.global_basis.x.slide(_up).normalized()
	row["forward"] = forward
	row["root_reference_height"] = attachment.dot(_up)
	row["initial_forward_offset"] = (row.body.global_position-attachment).dot(forward)
	row["needs_forward_extension"] = not forward.is_zero_approx() and float(row.initial_forward_offset) < -float(chain.length)*_data.rearward_tolerance_ratio
	row["landing_offset"] = row.offset
	_plan_stomp_landing(row)

func _landing_is_valid(row: Dictionary, hit: Dictionary, original: Dictionary, attachment: Vector3) -> bool:
	if hit.is_empty(): return false
	var target: Vector3 = _movement._body_position_for_ground_contact(row.body,hit.position)
	var radius: float = _movement._chains[row.body].length*_movement.chain_reach_ratio*0.95
	if target.distance_to(attachment) > radius: return false
	var height_difference: float = (Vector3(hit.position)-Vector3(original.position)).dot(_up)
	if height_difference > _movement.maximum_step_up or height_difference < -_movement.maximum_step_down: return false
	return _movement._has_leg_clearance(row.body,target,hit.get(&"rid",RID()))

## Initial planning and one pre-stomp validation use the same expected landing
## posture; a temporary rise must never consume all available horizontal reach.
func _plan_stomp_landing(row: Dictionary) -> void:
	var foot: RigidBody3D = row.body
	var chain: Dictionary = _movement._chains[foot]
	var attachment: Vector3 = row.root.to_global(chain.anchor)
	attachment += _up*(float(row.root_reference_height)-attachment.dot(_up))
	var forward: Vector3 = row.forward
	var original := _surface(foot,attachment+Vector3(row.offset))
	row["landing_replan"] = &"terrain_unavailable"
	if original.is_empty(): return
	var original_target: Vector3 = _movement._body_position_for_ground_contact(foot,original.position)
	var offset := original_target-attachment
	row["landing_forward_before"] = float(row.initial_forward_offset)
	row["landing_forward_after"] = offset.dot(forward)
	if not row.needs_forward_extension:
		row.landing_offset = offset
		row.landing_replan = &"already_forward_or_within_tolerance"
		return
	# Preserve a valid previously selected target rather than changing reach
	# on every phase transition. Translation is still followed while walking.
	if row.get("forward_plan_valid",false):
		var previous := _surface(foot,attachment+Vector3(row.landing_offset))
		if _landing_is_valid(row,previous,original,attachment):
			var previous_target: Vector3 = _movement._body_position_for_ground_contact(foot,previous.position)
			if (previous_target-attachment).dot(forward) > 0.0:
				row.landing_offset = previous_target-attachment
				row.landing_forward_after = Vector3(row.landing_offset).dot(forward)
				row.landing_replan = &"extended_forward"
				return
	row["forward_plan_valid"] = false
	row.landing_offset = offset
	row.landing_replan = &"no_valid_forward_point"
	var side := offset.slide(_up)-forward*offset.dot(forward)
	var radius: float = float(chain.length)*_movement.chain_reach_ratio*0.95
	var reach := sqrt(maxf(radius*radius-offset.dot(_up)*offset.dot(_up)-side.length_squared(),0.0))
	var front_distance := maxf(reach-maxf(float(chain.length)*0.05,0.05),0.0)*_data.forward_extension_ratio
	if front_distance <= 0.0: return
	for sample: int in range(8,0,-1):
		var candidate := attachment+side+_up*offset.dot(_up)+forward*front_distance*float(sample)/8.0
		var hit := _surface(foot,candidate)
		if not _landing_is_valid(row,hit,original,attachment): continue
		var target: Vector3 = _movement._body_position_for_ground_contact(foot,hit.position)
		if (target-attachment).dot(forward) <= 0.0: continue
		row.landing_offset = target-attachment
		row.landing_forward_after = Vector3(row.landing_offset).dot(forward)
		row.landing_replan = &"extended_forward"
		row.forward_plan_valid = true
		return

func _limit_airborne_extension(row: Dictionary, attachment: Vector3, target: Vector3) -> Vector3:
	if not row.needs_forward_extension or not row.get("forward_plan_valid",false): return target
	var offset := target-attachment
	var forward: Vector3 = row.forward
	var side := offset.slide(_up)-forward*offset.dot(forward)
	var vertical := offset.dot(_up)
	var radius: float = float(row.length)*_movement.chain_reach_ratio
	var available := sqrt(maxf(radius*radius-vertical*vertical-side.length_squared(),0.0))
	var along := offset.dot(forward)
	return target+forward*(clampf(along,-available,available)-along)

func _surface(foot: RigidBody3D, position: Vector3) -> Dictionary:
	var sole_offset: Vector3 = foot.global_position-_movement._get_foot_world_position(foot)
	var sole := position-sole_offset
	var start_height: float = sole.dot(_up)+_movement.ray_start_height
	# During descent the root-relative target can pass below the floor. Keep
	# the ray origin above the known floor rather than tracing from inside it.
	for row: Dictionary in _feet:
		if row.body == foot: start_height = maxf(start_height,float(row.ground_height)+_movement.ray_start_height)
	var start := sole+_up*(start_height-sole.dot(_up))
	var query := PhysicsRayQueryParameters3D.create(start,sole-_up*_ground_probe_length(foot),_movement.terrain_collision_mask,_movement._get_character_exclusion_rids())
	query.collide_with_areas = false
	var hit: Dictionary = _movement._intersect_ray(query)
	return hit if not hit.is_empty() and _movement._surface_is_walkable(hit.normal) else {}

func _ground_probe_length(foot: RigidBody3D) -> float:
	var length: float = _movement._get_leg_reference_length(foot)
	var lift_ratio := _data.foot_lift_ratio+_data.torso_lift_ratio if _data != null else 0.0
	return maxf(maxf(_movement.ray_length,5.0),length*(1.0+lift_ratio)+_movement.ray_start_height)

func _servo(body: RigidBody3D, target: Vector3, velocity: Vector3, vertical_only: bool, weight: float, down: float, horizontal_only: bool = false) -> Vector3:
	var acceleration := (target-body.global_position)*_data.position_gain+(velocity-body.linear_velocity)*(2.0*_data.damping_ratio*sqrt(_data.position_gain))
	if vertical_only: acceleration = _up*acceleration.dot(_up)
	acceleration -= _up*down
	acceleration -= _movement._gravity_acceleration()*body.gravity_scale
	# No vertical servo or gravity compensation may keep an unsupported lift aloft.
	if horizontal_only: acceleration = acceleration.slide(_up)
	var force := (acceleration.limit_length(_data.maximum_acceleration)*body.mass*weight).limit_length(_data.maximum_force)
	body.sleeping = false
	body.apply_central_force(force)
	return force

func _set_phase(value: Phase) -> void:
	phase = value
	if phase == Phase.STOMPING:
		for row: Dictionary in _feet: row["stomp_start_frame"] = Engine.get_physics_frames()
	_elapsed = 0.0
	if diagnostic_logging: print("[creature_action] character=",get_parent().name," phase=",Phase.keys()[phase]," reason=",_reason)

func cancel_player_actions() -> void: cancel_action(&"input_suspended")

func cancel_action(reason: StringName = &"cancelled") -> void:
	_npc_attack = false
	if not is_active(): return
	if reason != &"completed" or _reason == &"started": _reason = reason
	_cooldown = _data.cooldown
	if is_instance_valid(_movement): _movement.end_action_control()
	_set_phase(Phase.IDLE)
	_feet.clear()
	_torsos.clear()

func _exit_tree() -> void: cancel_action(&"removed")

func get_action_diagnostics() -> Dictionary:
	var feet: Array[Dictionary] = []
	for row: Dictionary in _feet:
		feet.append({"part": row.body.name if is_instance_valid(row.body) else &"freed","lifted": row.lifted,"landed": row.landed,"lift": row.lift,"gap": row.get("ground_gap",0.0),"force": row.force,"target": row.get("target",Vector3.ZERO),"pin_elapsed": row.pin_elapsed,"landing_replan": row.get("landing_replan",&"pending"),"landing_forward_before": row.get("landing_forward_before",0.0),"landing_forward_after": row.get("landing_forward_after",0.0),"landing_offset": row.get("landing_offset",Vector3.ZERO),"needs_forward_extension": row.get("needs_forward_extension",false),"root_reference_height": row.get("root_reference_height",0.0),"extension_progress": row.get("extension_progress",0.0)})
	var torsos: Array[Dictionary] = []
	for row: Dictionary in _torsos:
		if is_instance_valid(row.body): torsos.append({"part": row.body.name,"rise": row.body.global_position.dot(_up)-float(row.height),"lift": row.lift,"force": row.force})
	return {"enabled": enabled,"active": is_active(),"action": _data.action_id if _data != null else &"","phase": Phase.keys()[phase],"elapsed": _elapsed,"reason": _reason,"cooldown": _cooldown,"shockwaves_spawned": _shockwaves_spawned,"rear_support_count": _support_count,"lift_paused": phase == Phase.RISING and _support_count == 0,"rise_progress_time": _rise_elapsed,"support_lost_time": _support_lost_time,"feet": feet,"torsos": torsos}
