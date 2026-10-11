@tool
extends "res://Scripts/Creatures/WolfAttackModule3D.gd"
var locked_position := Vector3.ZERO
var launch_velocity := Vector3.ZERO
var combo_checked := false
var flight_duration := 0.7
var body_scale := 1.0
var _target_velocities: Dictionary = {}
var _intercept: Dictionary = {}
var _phase: StringName = &"idle"
var _phase_time := 0.0
var _charge_offset := Vector3.ZERO
var _charge_torsos: Array[Dictionary] = []
var _charge_feet: Array[Dictionary] = []
var _support_count := 0
var _foreleg_flight: Array[Dictionary] = []
var _flight_forward := Vector3.RIGHT
var _gallop_grace_remaining := 0.0

func _launch_support_ready() -> bool:
	var required := maxi(1,ceili(controller.movement.get_leg_parts().size()*0.5))
	return controller.movement.get_action_support_feet().size() >= required

func _preparation_time() -> float:
	return 0.0 if _launch_support_ready() else data.pounce_plant_prediction_time

func _planned_charge_offset() -> Vector3:
	var length: float = controller.pounce_scale()*data.reference_body_length
	var offset: Vector3 = (-controller.forward()*data.pounce_charge_retract_ratio+Vector3.DOWN*data.pounce_charge_crouch_ratio)*length
	if offset.length_squared() < 0.000001: return Vector3.ZERO
	var fraction := 1.0
	for foot: RigidBody3D in controller.movement._chains:
		if not controller.movement._chain_is_intact(foot): continue
		var chain: Dictionary = controller.movement._chains[foot]
		var relative: Vector3 = foot.global_position-chain.root.to_global(chain.anchor)
		var radius := maxf(float(chain.length)*0.98,relative.length()+0.001)
		var along := relative.dot(offset)
		var discriminant := along*along-offset.length_squared()*(relative.length_squared()-radius*radius)
		fraction = minf(fraction,clampf((along+sqrt(maxf(discriminant,0.0)))/offset.length_squared(),0.0,1.0))
	return offset*fraction

func _charge_target(origin: Vector3, time: float) -> Vector3:
	return origin+_charge_offset*smoothstep(0.0,data.pounce_charge_time,time)

func _drive_charge(delta: float) -> void:
	_support_count = 0
	var movement: Node = controller.movement
	for row: Dictionary in _charge_feet:
		var foot: RigidBody3D = row.body
		var surface: Dictionary = movement._support_surface_contact(foot)
		if not surface.is_empty():
			movement.action_ground_foot(foot,surface.normal,_phase_time,delta)
		if movement._support_pins.has(foot) and not surface.is_empty():
			_support_count += 1
		else:
			# Action takeover removes step tracking, so brake its residual airborne momentum.
			var point: Vector3 = row.origin
			var acceleration: Vector3 = ((point-foot.global_position)*data.position_gain-foot.linear_velocity*data.velocity_gain).slide(Vector3.UP)
			if _phase == &"planting":
				var below: Dictionary = movement._get_surface_below_leg(foot,movement.surface_adhesion_probe_distance)
				if not below.is_empty() and movement._surface_is_walkable(below.normal):
					point.y = movement._body_position_for_ground_contact(foot,below.position).y
					acceleration = (point-foot.global_position)*data.position_gain-foot.linear_velocity*data.velocity_gain
			foot.apply_central_force(acceleration.limit_length(data.maximum_acceleration)*foot.mass)
	for row: Dictionary in _charge_torsos:
		var point: Vector3 = row.origin if _phase == &"planting" else _charge_target(row.origin,_phase_time)
		var velocity := Vector3.ZERO if _phase == &"planting" else (_charge_target(row.origin,_phase_time+0.001)-point)/0.001
		var acceleration: Vector3 = (point-row.body.global_position)*data.position_gain+(velocity-row.body.linear_velocity)*data.velocity_gain-movement._gravity_acceleration()
		row.body.apply_central_force(acceleration.limit_length(data.maximum_acceleration)*row.body.mass)

func _foreleg_offset(row: Dictionary, progress: float) -> Vector3:
	var start: Vector3 = row.start
	var folded: Vector3 = row.folded
	var extended: Vector3 = row.extended
	return start.lerp(folded,smoothstep(0.0,0.5,progress)) if progress <= 0.5 else folded.lerp(extended,smoothstep(0.5,1.0,progress))

func _drive_airborne_forelegs() -> void:
	var progress := clampf(_phase_time/flight_duration,0.0,1.0)
	for row: Dictionary in _foreleg_flight:
		var foot: RigidBody3D = row.foot
		if not alive(foot) or not controller.movement._chain_is_intact(foot): continue
		var chain: Dictionary = controller.movement._chains[foot]
		var anchor: Vector3 = chain.root.to_global(chain.anchor)
		var offset := _foreleg_offset(row,progress)
		var velocity: Vector3 = chain.root.linear_velocity+(_foreleg_offset(row,minf(progress+0.001/flight_duration,1.0))-offset)/0.001
		var acceleration: Vector3 = (anchor+offset-foot.global_position)*data.position_gain+(velocity-foot.linear_velocity)*data.velocity_gain
		# The foot must move the connected limb chain, not only its own mass.
		var moving_mass := 0.0
		for body: RigidBody3D in chain.bodies:
			if body != chain.root: moving_mass += body.mass
		var force := acceleration.limit_length(data.maximum_acceleration)*moving_mass
		foot.apply_central_force(force)
		chain.root.apply_central_force(-force)

func _target_velocity(part: PhysicalBodyPart3D) -> Vector3:
	var id := part.get_instance_id()
	if not _target_velocities.has(id):
		_target_velocities[id] = {"part":weakref(part),"velocity":PREDICTION.velocity(part),"age":0.0}
	_target_velocities[id].age = 0.0
	return _target_velocities[id].velocity

func _flight_duration(scale: float) -> float:
	return maxf(data.flight_time*sqrt(scale),sqrt(8.0*data.minimum_lift_height*scale/maxf(controller.movement._gravity_acceleration().length(),0.001)))

func maximum_target_distance(part: Node3D = null) -> float:
	var scale: float = controller.pounce_scale()
	var reach: float = data.maximum_range*scale*(1.0-data.pounce_range_margin_ratio)+landing_standoff()+_planned_charge_offset().dot(controller.forward())
	if part is PhysicalBodyPart3D:
		var direction: Vector3 = (part.global_position-controller.torso.global_position).slide(Vector3.UP).normalized()
		reach += maxf(-_target_velocity(part).dot(direction),0.0)*(_flight_duration(scale)+data.pounce_charge_time+_preparation_time())
	return reach

func intercept_plan(next_target: PhysicalBodyPart3D, remaining_charge_time: float = -1.0, actual_launch_origin: Vector3 = Vector3.INF) -> Dictionary:
	var current_origin: Vector3 = controller.torso.global_position
	var offset := _planned_charge_offset() if not actual_launch_origin.is_finite() else Vector3.ZERO
	var origin: Vector3 = current_origin+offset if not actual_launch_origin.is_finite() else actual_launch_origin
	var forward: Vector3 = controller.forward()
	var scale: float = controller.pounce_scale()
	var delta := next_target.global_position-current_origin
	if delta.slide(Vector3.UP).length() < controller.get_npc_attack_minimum_range(&"wolf_pounce") or delta.dot(forward) <= 0.0:
		return {"hit":false,"reason":&"pounce_range_or_behind"}
	var duration := _flight_duration(scale)
	var charge_time := data.pounce_charge_time+_preparation_time() if remaining_charge_time < 0.0 else remaining_charge_time
	var target_velocity := _target_velocity(next_target)
	var target_position := next_target.global_position+target_velocity*(charge_time+duration)
	var endpoint := target_position-forward*landing_standoff()
	endpoint.y = maxf(endpoint.y,origin.y)
	var distance := (endpoint-origin).slide(Vector3.UP).length()
	var maximum := data.maximum_range*scale*(1.0-data.pounce_range_margin_ratio)
	if (endpoint-origin).dot(forward) < scale*0.5:
		return {"hit":false,"reason":&"no_forward_launch_space"}
	if distance > maximum:
		return {"hit":false,"reason":&"intercept_out_of_range","planned_distance":distance,"maximum_distance":maximum,"predicted_target_position":target_position}
	var gravity: Vector3 = controller.movement._gravity_acceleration()
	var brake_time := minf(data.combo_window*sqrt(scale),duration*0.4)
	var velocity := (endpoint-origin)/(duration-brake_time*0.5)
	velocity.y = (endpoint.y-origin.y)/duration-gravity.y*(0.5*duration)
	if velocity.length() > data.maximum_launch_speed*sqrt(scale): return {"hit":false,"reason":&"launch_speed_limit"}
	return {"hit":true,"reason":&"ballistic_intercept","confidence":0.9,"endpoint":endpoint,"velocity":velocity,"duration":duration,"charge_duration":charge_time,"prediction_horizon":charge_time+duration,"launch_origin":origin,"charge_offset":offset,"body_scale":scale,"predicted_target_position":target_position,"target_velocity":target_velocity,"current_distance":delta.slide(Vector3.UP).length(),"planned_distance":distance,"maximum_distance":maximum}

func _trajectory_point(origin: Vector3, velocity: Vector3, gravity: Vector3, time: float, duration: float, brake_time: float) -> Vector3:
	var horizontal_time := time
	if brake_time > 0.0 and time > duration-brake_time:
		var progress := clampf((time-duration+brake_time)/brake_time,0.0,1.0)
		horizontal_time -= brake_time*(pow(progress,3.0)-0.5*pow(progress,4.0))
	var point := origin+velocity.slide(Vector3.UP)*horizontal_time
	point.y = origin.y+velocity.y*time+gravity.y*0.5*time*time
	return point

func landing_standoff() -> float:
	var reach := 0.0
	for foot: RigidBody3D in controller.movement._chains:
		if not controller.movement._has_body_tag(foot,controller.movement.FORELEG_TAG) or not controller.movement._chain_is_intact(foot): continue
		var chain: Dictionary = controller.movement._chains[foot]
		var offset: Vector3 = chain.root.global_position-controller.torso.global_position
		reach = maxf(reach,offset.dot(controller.forward())+float(chain.length)*0.5)
	return reach*data.landing_reach_ratio

func has_launch_gait() -> bool:
	return controller.movement._gallop_active() or _gallop_grace_remaining > 0.0

func predict(next_target: PhysicalBodyPart3D, _samples: int, _margin: float) -> Dictionary:
	if not available(): return {"hit":false,"reason":&"cooldown_or_disabled"}
	if controller.is_target_in_bite_distance(next_target): return {"hit":false,"reason":&"within_bite_range"}
	var movement: Node = controller.movement
	if not has_launch_gait(): return {"hit":false,"reason":&"not_galloping"}
	if movement.get_action_support_feet().is_empty():
		var can_plant := false
		for foot: RigidBody3D in movement.get_leg_parts():
			if not movement._chain_is_intact(foot): continue
			var below: Dictionary = movement._get_surface_below_leg(foot,movement.surface_adhesion_probe_distance)
			if not below.is_empty() and movement._surface_is_walkable(below.normal): can_plant = true; break
		if not can_plant: return {"hit":false,"reason":&"no_launch_surface"}
	var plan := intercept_plan(next_target)
	if not plan.hit: return plan
	if not _trajectory_clear(plan): return {"hit":false,"reason":&"trajectory_blocked"}
	return plan

func _trajectory_clear(plan: Dictionary) -> bool:
	var gravity: Vector3 = controller.movement._gravity_acceleration()
	var duration: float = plan.duration
	var brake_time := minf(data.combo_window*sqrt(float(plan.body_scale)),duration*0.4)
	var previous: Vector3 = controller.torso.global_position
	for index: int in range(0,9):
		var time := duration*float(index)/8.0
		var point := _trajectory_point(plan.launch_origin,plan.velocity,gravity,time,duration,brake_time)
		if point.distance_squared_to(previous) < 0.000001: continue
		var query := PhysicsRayQueryParameters3D.create(previous,point,0xFFFFFFFF,controller.own_rids())
		var hit: Dictionary = controller.get_parent().get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider is StaticBody3D: return false
		previous = point
	return true

func start(next_target: PhysicalBodyPart3D) -> bool:
	var prediction := predict(next_target,16,0.1)
	if not prediction.hit or not super.start(next_target): return false
	locked_position = prediction.endpoint
	launch_velocity = prediction.velocity
	flight_duration = prediction.duration
	body_scale = prediction.body_scale
	_intercept = prediction.duplicate()
	combo_checked = false
	_phase = &"charging" if _launch_support_ready() else &"planting"
	_phase_time = 0.0
	_charge_offset = prediction.charge_offset
	_charge_torsos.clear()
	_charge_feet.clear()
	for foot: RigidBody3D in controller.movement.get_leg_parts():
		if controller.movement._chain_is_intact(foot):
			owned_feet.append(foot)
			_charge_feet.append({"body":foot,"origin":foot.global_position})
	for part: RigidBody3D in controller.get_parent()._get_physical_body_parts():
		if alive(part) and controller.movement._has_body_tag(part,controller.movement.TORSO_TAG):
			owned_bodies.append(part)
			_charge_torsos.append({"body":part,"origin":part.global_position})
	controller.sync_foot_ownership()
	controller.log_event(name,_phase,{"intercept":_intercept,"recent_gallop_remaining":_gallop_grace_remaining})
	return true

func _launch() -> void:
	# Recheck from the actual settled body pose; only the airborne trajectory is locked.
	var plan := intercept_plan(target,0.0,controller.torso.global_position)
	if not plan.hit or not _trajectory_clear(plan):
		controller.log_event(name,&"launch_prediction_failed",plan)
		finish(&"launch_intercept_invalid")
		return
	locked_position = plan.endpoint
	launch_velocity = plan.velocity
	flight_duration = plan.duration
	body_scale = plan.body_scale
	_intercept = plan.duplicate()
	_phase = &"flying"
	_phase_time = 0.0
	_foreleg_flight.clear()
	_flight_forward = controller.forward()
	for foot: RigidBody3D in owned_feet:
		if controller.movement._has_body_tag(foot,controller.movement.FORELEG_TAG):
			var chain: Dictionary = controller.movement._chains[foot]
			var offset: Vector3 = foot.global_position-chain.root.to_global(chain.anchor)
			var lateral := offset.slide(Vector3.UP)-_flight_forward*offset.dot(_flight_forward)
			var folded := lateral-_flight_forward*float(chain.length)*data.pounce_foreleg_retract_ratio+Vector3.DOWN*float(chain.length)*data.pounce_foreleg_fold_drop_ratio
			var extended := lateral+_flight_forward*float(chain.length)*data.pounce_foreleg_extend_ratio+Vector3.UP*offset.y
			var reach := float(chain.length)*0.95
			_foreleg_flight.append({"foot":foot,"start":offset,"folded":folded.limit_length(reach),"extended":extended.limit_length(reach)})
		controller.movement._release_support_pin(foot)
		controller.movement.set_action_foot_grounded(foot,false)
	for part: RigidBody3D in controller.get_parent()._get_physical_body_parts():
		if alive(part): part.apply_central_impulse((launch_velocity-part.linear_velocity)*part.mass)
	controller.log_event(name,&"intercept_locked",_intercept)

func tick(delta: float) -> void:
	super.tick(delta)
	if active:
		_gallop_grace_remaining = 0.0
	elif controller.movement._gallop_active():
		_gallop_grace_remaining = data.pounce_gallop_grace_time
	else:
		_gallop_grace_remaining = maxf(0.0,_gallop_grace_remaining-delta)
	for id: int in _target_velocities.keys():
		var row: Dictionary = _target_velocities[id]
		var part = row.part.get_ref()
		row.age += delta
		if not is_instance_valid(part) or row.age > 1.0:
			_target_velocities.erase(id)
			continue
		var weight := 1.0 if data.pounce_velocity_smoothing_time <= 0.0 else 1.0-exp(-delta/data.pounce_velocity_smoothing_time)
		row.velocity = Vector3(row.velocity).lerp(PREDICTION.velocity(part),weight)
	if not active: return
	_phase_time += delta
	if _phase == &"charging" or _phase == &"planting":
		for foot: RigidBody3D in owned_feet:
			if not alive(foot) or not controller.movement._chain_is_intact(foot): finish(&"charge_leg_broken"); return
		for body: RigidBody3D in owned_bodies:
			if not alive(body): finish(&"charge_torso_broken"); return
		_drive_charge(delta)
		if _phase == &"planting":
			if _support_count >= maxi(1,ceili(owned_feet.size()*0.5)):
				var plan := intercept_plan(target,data.pounce_charge_time)
				if not plan.hit or not _trajectory_clear(plan): finish(&"plant_intercept_invalid"); return
				controller.log_event(name,&"launch_support_ready",{"plant_elapsed":_phase_time,"grounded_feet":_support_count,"planned_distance":plan.planned_distance,"maximum_distance":plan.maximum_distance})
				_intercept = plan
				_charge_offset = plan.charge_offset
				for row: Dictionary in _charge_torsos: row.origin = row.body.global_position
				_phase = &"charging"
				_phase_time = 0.0
				controller.log_event(name,&"charging",_intercept)
			elif _phase_time >= data.pounce_plant_timeout:
				controller.log_event(name,&"launch_support_timeout",{"plant_elapsed":_phase_time,"grounded_feet":_support_count,"required_feet":maxi(1,ceili(owned_feet.size()*0.5))})
				finish(&"plant_support_unavailable")
			return
		if _phase_time >= data.pounce_charge_time:
			if _support_count < maxi(1,ceili(owned_feet.size()*0.5)): finish(&"charge_support_lost"); return
			_launch()
		return
	_drive_airborne_forelegs()
	var brake_time := minf(data.combo_window*sqrt(body_scale),flight_duration*0.4)
	if brake_time > 0.0 and _phase_time > flight_duration-brake_time:
		var progress := clampf((_phase_time-flight_duration+brake_time)/brake_time,0.0,1.0)
		var desired := launch_velocity.slide(Vector3.UP)*(1.0-smoothstep(0.0,1.0,progress))
		for part: RigidBody3D in controller.get_parent()._get_physical_body_parts():
			if alive(part): part.apply_central_force(((desired-part.linear_velocity.slide(Vector3.UP))*data.landing_braking_gain/sqrt(body_scale)).limit_length(data.maximum_acceleration)*part.mass)
	if _phase_time >= maxf(flight_duration-data.combo_window,0.0) and not combo_checked:
		combo_checked = true
		controller.try_end_combo(target)
	if _phase_time >= flight_duration:
		var landed := false
		for foot: RigidBody3D in owned_feet:
			if alive(foot) and controller.movement.is_leg_grounded(foot): landed = true; break
		if landed or _phase_time >= flight_duration+data.landing_timeout: finish(&"landed" if landed else &"flight_timeout")

func finish(reason: StringName = &"completed") -> void:
	if controller != null and controller.movement != null:
		for foot: RigidBody3D in owned_feet:
			if is_instance_valid(foot): controller.movement._release_support_pin(foot)
	_charge_torsos.clear()
	_charge_feet.clear()
	_foreleg_flight.clear()
	_phase = &"idle"
	_gallop_grace_remaining = 0.0
	super.finish(reason)

func diagnostics() -> Dictionary:
	var result := super.diagnostics()
	result.merge({"locked_position":locked_position,"launch_velocity":launch_velocity,"flight_duration":flight_duration,"body_scale":body_scale,"combo_checked":combo_checked})
	result["intercept"] = _intercept
	var forelegs: Array[Dictionary] = []
	for row: Dictionary in _foreleg_flight:
		if alive(row.foot): forelegs.append({"foot":row.foot.name,"offset_target":_foreleg_offset(row,clampf(_phase_time/flight_duration,0.0,1.0)),"position":row.foot.global_position})
	result["foreleg_flight"] = forelegs
	result.merge({"phase":_phase,"phase_elapsed":_phase_time,"charge_offset":_charge_offset,"pinned_feet":_support_count,"recent_gallop_remaining":_gallop_grace_remaining})
	return result
