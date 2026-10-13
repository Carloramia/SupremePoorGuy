@tool
extends "res://Scripts/Creatures/WolfAttackModule3D.gd"
const HITBOX = preload("res://Scripts/Items/TemporaryAttackHitbox3D.gd")
var jaw: PhysicalBodyPart3D
var head: PhysicalBodyPart3D
var joint: Generic6DOFJoint3D
var _rest := Quaternion.IDENTITY
var _joint_state: Dictionary = {}
var _weapon: HITBOX
var _phase: StringName = &"idle"
var _last_hits := 0
var _angle_error := 0.0
var _phase_time := 0.0
var _forward := Vector3.RIGHT
var _origin := Vector3.ZERO
var _retract := 0.0
var _advance := 0.0
var _crouch := 0.0
var _torsos: Array[Dictionary] = []
var _support_count := 0
var _close_reason: StringName = &""
var _foot_plans: Array[Dictionary] = []
var _repositioned_feet := 0
var _spacing_distance := 0.0
var _spacing_origin := Vector3.ZERO

func _set_phase(value: StringName) -> void:
	if value == &"recovering":
		for row: Dictionary in _torsos:
			if alive(row.body): row["recovery_start"] = row.body.global_position
	_phase = value
	_phase_time = 0.0
	controller.log_event(name,value,{"retract":_retract,"advance":_advance,"crouch":_crouch,"charge_time":maxf(data.bite_retract_time,data.jaw_open_time),"torso_position":controller.torso.global_position,"torso_velocity":controller.torso.linear_velocity,"torso_advance":(controller.torso.global_position-_origin).dot(_forward)})

func _spacing_for(next_target: PhysicalBodyPart3D) -> float:
	var length: float = controller.pounce_scale()*controller.get_node("Pounce").data.reference_body_length
	var distance := (next_target.global_position-head.global_position).slide(Vector3.UP).length()
	return length*data.bite_spacing_retreat_ratio if distance < length*data.bite_close_distance_ratio else 0.0

func _begin_planting() -> bool:
	# Backing away changes both roots and feet; discard all pre-retreat world points.
	_origin = controller.torso.global_position
	for row: Dictionary in _torsos:
		row.origin = row.body.global_position
		row.height = row.body.global_position.y
	if not _plan_natural_feet():
		finish(&"natural_landing_unavailable")
		return false
	_set_phase(&"planting")
	return true

func _retreat_for_spacing() -> void:
	var traveled: float = (_spacing_origin-controller.torso.global_position).dot(_forward)
	var remaining := maxf(_spacing_distance-traveled,0.0)
	var speed := minf(_spacing_distance/data.bite_spacing_retreat_time,remaining*data.velocity_gain)
	for body: RigidBody3D in controller.get_parent()._get_physical_body_parts():
		if not alive(body): continue
		var acceleration: Vector3 = (-_forward*speed-body.linear_velocity.slide(Vector3.UP))*data.velocity_gain
		body.apply_central_force(acceleration.limit_length(data.maximum_acceleration)*body.mass)
	if remaining <= maxf(_spacing_distance*0.1,0.05) or _phase_time >= data.bite_spacing_retreat_time*2.0:
		controller.log_event(name,&"spacing_retreat_finished",{"requested":_spacing_distance,"traveled":traveled,"elapsed":_phase_time})
		_begin_planting()

func _begin_charge() -> void:
	# Planting can move the body; charge from the settled pose rather than a stale start point.
	_origin = controller.torso.global_position
	var length: float = controller.pounce_scale()*controller.get_node("Pounce").data.reference_body_length
	_retract = minf(length*data.bite_retract_ratio,_travel_limit(-_forward))
	_advance = minf(length*data.bite_advance_ratio,_travel_limit(_forward))
	_crouch = length*data.bite_crouch_ratio
	var offset := -_forward*_retract+Vector3.DOWN*_crouch
	var fraction := 1.0
	# Bound the combined descent/retraction, not just its horizontal component.
	if offset.length_squared() > 0.000001:
		for foot: RigidBody3D in owned_feet:
			var chain: Dictionary = controller.movement._chains[foot]
			var relative: Vector3 = foot.global_position-chain.root.to_global(chain.anchor)
			var radius := maxf(float(chain.length)*0.98,relative.length()+0.001)
			var along := relative.dot(offset)
			var discriminant := along*along-offset.length_squared()*(relative.length_squared()-radius*radius)
			fraction = minf(fraction,clampf((along+sqrt(maxf(discriminant,0.0)))/offset.length_squared(),0.0,1.0))
	_retract *= fraction
	_crouch *= fraction
	for row: Dictionary in _torsos:
		row.origin = row.body.global_position
		row.height = row.body.global_position.y
	_set_phase(&"charging")

func _body_target(row: Dictionary, time: float) -> Vector3:
	var origin: Vector3 = row.origin
	if _phase == &"charging":
		return origin+(-_forward*_retract+Vector3.DOWN*_crouch)*smoothstep(0.0,maxf(data.bite_retract_time,data.jaw_open_time),time)
	if _phase == &"lunging":
		return origin+Vector3.DOWN*_crouch*(1.0-smoothstep(0.0,data.jaw_open_time,time))
	if _phase == &"recovering":
		return Vector3(row.recovery_start).lerp(origin,smoothstep(0.0,data.recovery_time,time))
	return origin

func _travel_limit(direction: Vector3) -> float:
	var limit := INF
	for foot: RigidBody3D in controller.movement.get_leg_parts():
		if not controller.movement._chain_is_intact(foot): continue
		var chain: Dictionary = controller.movement._chains[foot]
		var relative: Vector3 = foot.global_position-chain.root.to_global(chain.anchor)
		var along := relative.dot(direction)
		var transverse := relative-direction*along
		var radius := float(chain.length)*0.98
		limit = minf(limit,maxf(along+sqrt(maxf(radius*radius-transverse.length_squared(),0.0)),0.0))
	return 0.0 if is_inf(limit) else limit

func _plan_natural_feet() -> bool:
	_foot_plans.clear()
	_repositioned_feet = 0
	var exclusions: Array[RID] = []
	for actor: Node in get_tree().get_nodes_in_group(&"physical_characters_3d"):
		for body: RigidBody3D in actor._get_physical_body_parts(): exclusions.append(body.get_rid())
	for foot: RigidBody3D in owned_feet:
		var chain: Dictionary = controller.movement._chains[foot]
		var rest: Vector3 = controller.movement._get_leg_rest_world_position(foot)
		var anchor: Vector3 = chain.root.to_global(chain.anchor)
		# Use the authored lateral lane, but avoid treating a stretched gait offset as rest.
		var longitudinal := clampf((rest-anchor).dot(_forward),-float(chain.length)*0.15,float(chain.length)*0.15)
		rest += _forward*(longitudinal-(rest-anchor).dot(_forward))
		var query := PhysicsRayQueryParameters3D.create(Vector3(rest.x,anchor.y+1.0,rest.z),Vector3(rest.x,anchor.y-float(chain.length)*2.0,rest.z))
		query.exclude = exclusions
		query.collision_mask = controller.movement.terrain_collision_mask
		var surface: Dictionary = controller.movement._intersect_ray(query)
		if surface.is_empty() or not controller.movement._surface_is_walkable(surface.normal): return false
		var point: Vector3 = controller.movement._body_position_for_ground_contact(foot,surface.position)
		if point.distance_to(anchor) > maxf(float(chain.length)*0.98,foot.global_position.distance_to(anchor))+0.05: return false
		_foot_plans.append({"foot":foot,"start":foot.global_position,"target":point,"normal":surface.normal,"best_error":foot.global_position.distance_to(point),"stalled_time":0.0,"skipped":false,"elapsed":0.0,"done":false})
	controller.log_event(name,&"feet_replanned",{"feet":_foot_plans})
	return not _foot_plans.is_empty()

func _reposition_feet(delta: float) -> bool:
	_repositioned_feet = 0
	for row: Dictionary in _foot_plans:
		var foot: RigidBody3D = row.foot
		var contact: Dictionary = controller.movement._support_surface_contact(foot)
		var error: float = foot.global_position.distance_to(row.target)
		if not row.done:
			row.elapsed += delta
			var tolerance := maxf(float(controller.movement._chains[foot].length)*0.025,0.08)
			var settled := error <= tolerance and foot.linear_velocity.length() <= 0.8 and not contact.is_empty()
			if row.elapsed >= 0.45:
				if error < float(row.best_error)-0.02:
					row.best_error = error
					row.stalled_time = 0.0
				else: row.stalled_time += delta
			var blocked := float(row.stalled_time) >= 0.4 or float(row.elapsed) >= 1.5
			if settled or blocked:
				row.done = true
				row.skipped = blocked and not settled
				controller.log_event(name,&"foot_reposition_skipped" if row.skipped else &"foot_reposition_completed",{"foot":foot.name,"error":error,"time":row.elapsed,"grounded":not contact.is_empty(),"reason":(&"no_progress" if float(row.stalled_time)>=0.4 else &"foot_timeout") if row.skipped else &"settled"})
		if row.done:
			_repositioned_feet += 1
			if not contact.is_empty(): controller.movement.action_ground_foot(foot,contact.normal,_phase_time,delta)
			else:
				var brake: Vector3 = -foot.linear_velocity.slide(Vector3.UP)*data.velocity_gain
				foot.apply_central_force(brake.limit_length(data.maximum_acceleration)*foot.mass)
			continue
		var point: Vector3 = row.start.lerp(row.target,smoothstep(0.0,0.45,row.elapsed))
		point.y += sin(PI*clampf(float(row.elapsed)/0.45,0.0,1.0))*minf(float(controller.movement._chains[foot].length)*0.08,0.6)
		var acceleration: Vector3 = (point-foot.global_position)*data.position_gain-foot.linear_velocity*data.velocity_gain-controller.movement._gravity_acceleration()
		foot.apply_central_force(acceleration.limit_length(data.maximum_acceleration)*foot.mass)
	_support_count = 0
	for row: Dictionary in _foot_plans:
		if controller.movement._support_pins.has(row.foot) and not controller.movement._support_surface_contact(row.foot).is_empty(): _support_count += 1
	return _repositioned_feet == _foot_plans.size() and _support_count > 0

func _plant_feet(delta: float) -> int:
	var count := 0
	for foot: RigidBody3D in owned_feet:
		if not alive(foot) or not controller.movement._chain_is_intact(foot): continue
		var surface: Dictionary = controller.movement._get_surface_below_leg(foot,controller.movement.surface_adhesion_probe_distance)
		if surface.is_empty() or not controller.movement._surface_is_walkable(surface.normal): continue
		controller.movement.action_ground_foot(foot,surface.normal,elapsed,delta)
		if controller.movement._support_pins.has(foot): count += 1
	return count

func _drive_torsos() -> void:
	for row: Dictionary in _torsos:
		if not alive(row.body): continue
		var point := _body_target(row,_phase_time)
		var velocity := (_body_target(row,_phase_time+0.001)-point)/0.001
		var acceleration: Vector3 = Vector3.UP*((point.y-row.body.global_position.y)*data.position_gain+(velocity.y-row.body.linear_velocity.y)*data.velocity_gain-controller.movement._gravity_acceleration().y)
		if _phase in [&"planting",&"charging",&"recovering"]:
			var error: Vector3 = (point-row.body.global_position).slide(Vector3.UP)
			acceleration += error*data.position_gain+(velocity-row.body.linear_velocity).slide(Vector3.UP)*data.velocity_gain
		elif _phase == &"lunging" and _phase_time < data.bite_lunge_acceleration_time:
			acceleration += _forward*data.bite_lunge_acceleration*sqrt(controller.pounce_scale())
		elif _phase == &"closing": acceleration -= row.body.linear_velocity.slide(Vector3.UP)*data.velocity_gain
		row.body.apply_central_force(acceleration.limit_length(data.maximum_acceleration)*row.body.mass)

func refresh() -> void:
	finish(&"regenerated")
	jaw = null; head = null; joint = null
	if data == null: return
	var parts := controller.get_parent().get_node_or_null("GeneratedParts")
	if parts == null: return
	for body: Node in parts.get_children():
		if not body is PhysicalBodyPart3D: continue
		if body.get_meta(&"generated_part_key",body.name) == data.jaw_key: jaw = body
		if body.get_meta(&"generated_part_key",body.name) == data.head_key: head = body
	if not is_instance_valid(jaw) or not is_instance_valid(head): return
	_rest = (head.global_basis.orthonormalized().inverse()*jaw.global_basis.orthonormalized()).get_rotation_quaternion()
	for candidate: Node in parts.get_node("Joints").get_children():
		if not candidate is Generic6DOFJoint3D: continue
		var a: Node = candidate.get_node_or_null(candidate.node_a)
		var b: Node = candidate.get_node_or_null(candidate.node_b)
		if (a == head and b == jaw) or (a == jaw and b == head): joint = candidate; break

func _shape() -> BoxShape3D:
	var box := BoxShape3D.new()
	box.size = (Vector3(jaw.get_meta(&"generated_size",Vector3.ONE))*data.box_size_ratio).max(Vector3.ONE*0.02)
	return box

func predict(next_target: PhysicalBodyPart3D, samples: int, margin: float) -> Dictionary:
	if not available() or not alive(head) or not alive(jaw) or not is_instance_valid(joint): return {"hit":false,"reason":&"jaw_unavailable"}
	return _closing_prediction(next_target,samples,margin,true)

func _closing_prediction(next_target: PhysicalBodyPart3D, samples: int, margin: float, include_lunge: bool = false) -> Dictionary:
	var box := _shape()
	var offset := Vector3(jaw.get_meta(&"generated_size",Vector3.ONE))*data.box_center_ratio
	var axis := head.global_basis.z.normalized()
	var pivot := joint.global_position
	for index: int in range(clampi(samples,8,32)):
		var progress := float(index)/float(clampi(samples,8,32)-1)
		var angle := -deg_to_rad(data.jaw_open_degrees)*(1.0-progress)
		var rotation := Basis(axis,angle)
		var time := data.jaw_close_time*progress
		var center := pivot+rotation*(jaw.to_global(offset)-pivot)+head.linear_velocity*time
		if include_lunge:
			var spacing := _spacing_for(next_target)
			time += maxf(data.bite_retract_time,data.jaw_open_time)+data.bite_lunge_timeout*progress
			if spacing > 0.0:
				time += data.bite_spacing_retreat_time
				center -= controller.forward()*spacing
			var length: float = controller.pounce_scale()*controller.get_node("Pounce").data.reference_body_length
			center += controller.forward()*minf(length*data.bite_advance_ratio,_travel_limit(controller.forward()))*progress
		if predicts_enemy_hit(box,Transform3D(rotation*jaw.global_basis.orthonormalized(),center),next_target,time,margin):
			return {"hit":true,"reason":&"bite_sweep_hit","confidence":1.0,"time":time}
	return {"hit":false,"reason":&"bite_sweep_misses"}

func start(next_target: PhysicalBodyPart3D) -> bool:
	if not predict(next_target,24,0.1).hit or not super.start(next_target): return false
	_last_hits = 0
	_close_reason = &""
	_support_count = 0
	_crouch = 0.0
	_forward = controller.forward()
	_origin = controller.torso.global_position
	var length: float = controller.pounce_scale()*controller.get_node("Pounce").data.reference_body_length
	_retract = minf(length*data.bite_retract_ratio,_travel_limit(-_forward))
	_advance = minf(length*data.bite_advance_ratio,_travel_limit(_forward))
	for foot: RigidBody3D in controller.movement.get_leg_parts():
		if controller.movement._chain_is_intact(foot): owned_feet.append(foot)
	_torsos.clear()
	for body: RigidBody3D in controller.get_parent()._get_physical_body_parts():
		if alive(body) and controller.movement._has_body_tag(body,controller.movement.TORSO_TAG):
			owned_bodies.append(body)
			_torsos.append({"body":body,"origin":body.global_position,"height":body.global_position.y})
	controller.sync_foot_ownership()
	_spacing_origin = _origin
	_spacing_distance = _spacing_for(next_target)
	_joint_state = {"limit":joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT),"spring":joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING),"motor":joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR),"lower":joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),"upper":joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)}
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,false)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING,false)
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR,false)
	_weapon = HITBOX.new()
	_weapon.name = "BiteHitbox"
	_weapon.setup(jaw,controller.get_parent(),_shape().size,Vector3(jaw.get_meta(&"generated_size",Vector3.ONE))*data.box_center_ratio,data.impulse_multiplier,data.hit_ragdoll_duration)
	add_child(_weapon)
	if _spacing_distance > 0.0: _set_phase(&"spacing_retreat")
	elif not _begin_planting(): return false
	return true

func tick(delta: float) -> void:
	super.tick(delta)
	if not active: return
	if not alive(head) or not alive(jaw) or not is_instance_valid(joint): finish(&"part_broken"); return
	_phase_time += delta
	for body: RigidBody3D in owned_bodies:
		if not alive(body): finish(&"torso_broken"); return
	for foot: RigidBody3D in owned_feet:
		if not alive(foot) or not controller.movement._chain_is_intact(foot): finish(&"leg_chain_broken"); return
	if _phase not in [&"planting",&"spacing_retreat"]: _support_count = _plant_feet(delta)
	if _phase == &"spacing_retreat":
		_retreat_for_spacing()
		if not active: return
	elif _phase == &"planting":
		if _reposition_feet(delta): _begin_charge()
		elif _phase_time >= data.bite_plant_timeout: finish(&"cannot_plant_feet"); return
	elif _phase == &"charging" and _phase_time >= maxf(data.bite_retract_time,data.jaw_open_time):
		_set_phase(&"lunging")
		var speed: float = data.bite_lunge_speed*sqrt(controller.pounce_scale())
		for body: RigidBody3D in owned_bodies: body.apply_central_impulse(_forward*(speed-body.linear_velocity.dot(_forward))*body.mass)
	elif _phase == &"lunging":
		var can_hit: bool = _closing_prediction(target,12,0.05).hit
		var at_limit: bool = (controller.torso.global_position-_origin).dot(_forward) >= _advance
		if (can_hit and _phase_time >= data.bite_lunge_acceleration_time) or at_limit or _phase_time >= data.bite_lunge_timeout:
			_close_reason = &"predicted_hit" if can_hit else &"advance_limit" if at_limit else &"lunge_timeout"
			_set_phase(&"closing")
	elif _phase == &"closing" and _phase_time >= data.jaw_close_time:
		_set_phase(&"recovering")
	elif _phase == &"recovering" and _phase_time >= data.recovery_time: finish(); return
	_drive_torsos()
	var angle := deg_to_rad(data.jaw_open_degrees)
	if _phase in [&"planting",&"spacing_retreat"]: angle = 0.0
	elif _phase == &"charging": angle *= smoothstep(0.0,maxf(data.bite_retract_time,data.jaw_open_time),_phase_time)
	elif _phase == &"closing": angle *= 1.0-smoothstep(0.0,data.jaw_close_time,_phase_time)
	elif _phase == &"recovering": angle = 0.0
	var desired := Quaternion(Vector3.BACK,-angle)*_rest
	var axis := head.global_basis.z.normalized()
	var error: float = controller.movement._stance_rotation_error(jaw,head,desired).dot(axis)
	_angle_error = rad_to_deg(error)
	var rate := (jaw.angular_velocity-head.angular_velocity).dot(axis)
	var acceleration := clampf(error*data.angular_strength-rate*data.angular_damping,-data.maximum_angular_acceleration,data.maximum_angular_acceleration)
	var inverse: float = axis.dot(controller.movement._stance_inverse_inertia(jaw)*axis)+axis.dot(controller.movement._stance_inverse_inertia(head)*axis)
	var cap := data.maximum_torque*pow(controller.scale_factor(),5.0)
	var torque := axis*clampf(acceleration/maxf(inverse,0.000001),-cap,cap)
	jaw.apply_torque(torque)
	head.apply_torque(-torque)
	_weapon.update_hitbox(delta,_phase == &"closing")

func finish(reason: StringName = &"completed") -> void:
	if controller != null and controller.movement != null:
		for foot: RigidBody3D in owned_feet: controller.movement._release_support_pin(foot)
	_torsos.clear()
	_foot_plans.clear()
	if is_instance_valid(_weapon):
		_last_hits = _weapon.hit_count
		_weapon.dispose()
	_weapon = null
	if is_instance_valid(joint) and not _joint_state.is_empty():
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,_joint_state.limit)
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING,_joint_state.spring)
		joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR,_joint_state.motor)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,_joint_state.lower)
		joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,_joint_state.upper)
	_joint_state.clear()
	_phase = &"idle"
	super.finish(reason)

func diagnostics() -> Dictionary:
	var result := super.diagnostics()
	result["phase"] = _phase
	result["hits"] = _weapon.hit_count if is_instance_valid(_weapon) else _last_hits
	result["angle_error_degrees"] = _angle_error
	result["phase_elapsed"] = _phase_time
	result["retract_distance"] = _retract
	result["crouch_distance"] = _crouch
	result["charge_duration"] = maxf(data.bite_retract_time,data.jaw_open_time) if data != null else 0.0
	var torso_targets: Array[Dictionary] = []
	for row: Dictionary in _torsos:
		if alive(row.body): torso_targets.append({"part":row.body.name,"position":row.body.global_position,"target":_body_target(row,_phase_time)})
	result["torso_targets"] = torso_targets
	result["advance_limit"] = _advance
	result["torso_advance"] = (controller.torso.global_position-_origin).dot(_forward) if controller != null and is_instance_valid(controller.torso) else 0.0
	result["pinned_feet"] = _support_count
	var foot_status: Array[Dictionary] = []
	for row: Dictionary in _foot_plans:
		if alive(row.foot): foot_status.append({"foot":row.foot.name,"position":row.foot.global_position,"target":row.target,"error":row.foot.global_position.distance_to(row.target),"velocity":row.foot.linear_velocity,"skipped":row.skipped,"stalled_time":row.stalled_time,"elapsed":row.elapsed,"done":row.done})
	result["foot_plans"] = foot_status
	result["repositioned_feet"] = _repositioned_feet
	result["burst_acceleration"] = data.bite_lunge_acceleration if data != null else 0.0
	result["burst_duration"] = data.bite_lunge_acceleration_time if data != null else 0.0
	result["close_reason"] = _close_reason
	result["spacing_retreat_distance"] = _spacing_distance
	result["spacing_retreat_traveled"] = (_spacing_origin-controller.torso.global_position).dot(_forward) if controller != null and is_instance_valid(controller.torso) else 0.0
	return result
