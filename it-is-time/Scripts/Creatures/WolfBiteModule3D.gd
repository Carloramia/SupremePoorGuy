@tool
extends "res://Scripts/Creatures/WolfAttackModule3D.gd"
const HITBOX = preload("res://Scripts/Items/TemporaryAttackHitbox3D.gd")
class BiteHitbox extends HITBOX:
	var contacted := false
	func apply_contact_damage(other: PhysicalBodyPart3D, impulse: float) -> float:
		contacted = true
		return super.apply_contact_damage(other,impulse)
var jaw: PhysicalBodyPart3D
var head: PhysicalBodyPart3D
var joint: Generic6DOFJoint3D
var _rest := Quaternion.IDENTITY
var _jaw_rest_pose := Transform3D.IDENTITY
var _head_anchor := Vector3.ZERO
var _reason: StringName = &"none"
var _contacted := false
var _joint_state: Dictionary = {}
var _weapon: BiteHitbox
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
var _head_aim_point := Vector3.ZERO
var _head_joint: Generic6DOFJoint3D
var _head_joint_state: Dictionary = {}

func _head_aim_goal(point: Vector3) -> Dictionary:
	if data == null or not data.bite_head_aim_enabled or not alive(head) or not alive(jaw): return {}
	var support := controller.get_parent().get_node_or_null("HeadPositionSupport3D")
	if support == null or not support.enabled or not support.is_physics_processing(): return {}
	for binding: Dictionary in support.bindings:
		if binding.head != head or binding.has_neck or not support._chain_intact(binding): continue
		var neck: Generic6DOFJoint3D = binding.joints[0] as Generic6DOFJoint3D
		if neck == null: return {}
		var parent: PhysicalBodyPart3D = binding.torso
		var parent_basis := parent.global_basis.orthonormalized()
		var rest_basis := parent_basis*Basis(Quaternion(binding.rest_rotation))
		var rest_position: Vector3 = parent.global_position+parent.global_basis*Vector3(binding.rest_offset)
		var pivot: Vector3 = binding.head_pivot
		var pivot_world: Vector3 = rest_position+rest_basis*pivot
		var mouth_local: Vector3 = _jaw_rest_pose*(Vector3(jaw.get_meta(&"generated_size",Vector3.ONE))*data.box_center_ratio)
		var axis := parent_basis.z
		var from: Vector3 = (rest_basis*(mouth_local-pivot)).slide(axis)
		var toward := (point-pivot_world).slide(axis)
		if from.length_squared()<0.000001 or toward.length_squared()<0.000001: return {}
		var limit := deg_to_rad(data.bite_head_aim_limit_degrees)
		var angle := clampf(from.signed_angle_to(toward,axis),-limit,limit)
		if neck.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT):
			# Keep the servo inside the real joint limits; never force against its stop.
			var head_sign := -1.0 if neck.get_node_or_null(neck.node_a) == head else 1.0
			var lower := neck.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)
			var upper := neck.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)
			var frame_a: Transform3D = neck.get_meta(&"generated_joint_frame_a",Transform3D.IDENTITY)
			var frame_b: Transform3D = neck.get_meta(&"generated_joint_frame_b",Transform3D.IDENTITY)
			var basis_a := (rest_basis if head_sign<0.0 else parent_basis)*frame_a.basis
			var basis_b := (parent_basis if head_sign<0.0 else rest_basis)*frame_b.basis
			var rest_angle := (basis_a.inverse()*basis_b).get_euler(EULER_ORDER_ZYX).z
			var margin := maxf(upper-lower,0.0)*0.05
			if lower <= upper: angle = (clampf(rest_angle+angle*head_sign,lower+margin,upper-margin)-rest_angle)*head_sign
		var desired_basis := parent_basis*Basis(Vector3.BACK,angle)*Basis(Quaternion(binding.rest_rotation))
		var pose := Transform3D(desired_basis,rest_position+rest_basis*pivot-desired_basis*pivot)
		return {"head":head,"joint":neck,"angle":angle,"pose":pose,"error_degrees":rad_to_deg((head.global_basis*(mouth_local-pivot)).slide(axis).signed_angle_to(toward,axis)),"servo_error_degrees":rad_to_deg((head.global_basis*(mouth_local-pivot)).slide(axis).signed_angle_to((desired_basis*(mouth_local-pivot)).slide(axis),axis))}
	return {}

func get_head_posture_request() -> Dictionary:
	if not active: return {}
	var request := _head_aim_goal(_head_aim_point)
	if request.is_empty(): return {}
	if _phase == &"recovering": request.angle = 0.0
	request["angular_speed"] = deg_to_rad(data.bite_head_aim_speed_degrees)
	request["z_strength"] = data.bite_head_aim_strength
	request["z_damping"] = data.bite_head_aim_damping
	request["z_acceleration_limit"] = data.maximum_angular_acceleration
	request["z_torque_limit"] = data.maximum_torque*pow(controller.scale_factor(),5.0)
	return request

func _claim_head_aim() -> void:
	var request := get_head_posture_request()
	if request.is_empty(): return
	_head_joint = request.joint
	_head_joint_state = {"spring":_head_joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING),"motor":_head_joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR)}
	# The standing zero-angle spring must not oppose the attack servo.
	_head_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING,false)
	_head_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR,false)

func _set_phase(value: StringName) -> void:
	if value == &"recovering":
		for row: Dictionary in _torsos:
			if alive(row.body): row["recovery_start"] = row.body.global_position
	_phase = value
	_phase_time = 0.0
	if value == &"lunging": CombatAudio3D.play_at(head, &"attack")
	elif value == &"closing": CombatAudio3D.play_at(jaw, &"bite")
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
		var error := foot.global_position.distance_to(point)
		var settled: bool = error <= maxf(float(chain.length)*0.025,0.08) and foot.linear_velocity.length() <= 0.8 and not controller.movement._support_surface_contact(foot).is_empty()
		_foot_plans.append({"foot":foot,"start":foot.global_position,"target":point,"normal":surface.normal,"best_error":error,"stalled_time":0.0,"skipped":false,"elapsed":0.0,"done":settled})
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
		elif _phase == &"closing" and (_contacted or _phase_time >= data.jaw_close_time): acceleration -= row.body.linear_velocity.slide(Vector3.UP)*data.velocity_gain
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
	_jaw_rest_pose = head.global_transform.affine_inverse()*jaw.global_transform
	for candidate: Node in parts.get_node("Joints").get_children():
		if not candidate is Generic6DOFJoint3D: continue
		var a: Node = candidate.get_node_or_null(candidate.node_a)
		var b: Node = candidate.get_node_or_null(candidate.node_b)
		if (a == head and b == jaw) or (a == jaw and b == head): joint = candidate; break
	if is_instance_valid(joint):
		var key: StringName = &"generated_joint_frame_a" if joint.get_node_or_null(joint.node_a) == head else &"generated_joint_frame_b"
		_head_anchor = Transform3D(joint.get_meta(key,head.global_transform.affine_inverse()*joint.global_transform)).origin

func _shape() -> BoxShape3D:
	var box := BoxShape3D.new()
	box.size = (Vector3(jaw.get_meta(&"generated_size",Vector3.ONE))*data.box_size_ratio).max(Vector3.ONE*0.02)
	return box

func maximum_reach() -> float:
	var box := _shape()
	var offset := Vector3(jaw.get_meta(&"generated_size",Vector3.ONE))*data.box_center_ratio
	var reach := 0.0
	for index: int in 9:
		var pose := _closure_pose(float(index)/8.0,true)
		for corner: int in 8:
			var point := offset+box.size*Vector3(1.0 if corner&1 else -1.0,1.0 if corner&2 else -1.0,1.0 if corner&4 else -1.0)*0.5
			reach = maxf(reach,controller.torso.global_position.distance_to(pose*point))
	var length: float = controller.pounce_scale()*controller.get_node("Pounce").data.reference_body_length
	return reach+minf(length*data.bite_advance_ratio,_travel_limit(controller.forward()))

func admission_range(next_target: Node3D) -> float:
	var reach := maximum_reach()
	if not is_instance_valid(next_target): return reach
	var direction: Vector3 = (next_target.global_position-controller.torso.global_position).slide(Vector3.UP).normalized()
	var closing_speed := maxf(-PREDICTION.velocity(next_target).dot(direction),0.0)
	return reach+closing_speed*(data.bite_plant_prediction_time+maxf(data.bite_retract_time,data.jaw_open_time))

func predict(next_target: PhysicalBodyPart3D, samples: int, margin: float) -> Dictionary:
	if not alive(head) or not alive(jaw) or not is_instance_valid(joint) or joint.is_queued_for_deletion(): return {"hit":false,"reason":&"jaw_unavailable"}
	if not available(): return {"hit":false,"reason":&"busy_or_cooldown"}
	return _closing_prediction(next_target,samples,margin,true)

func _closure_pose(progress: float, include_lunge: bool, aimed_pose: Variant = null) -> Transform3D:
	var head_pose: Transform3D = aimed_pose if aimed_pose is Transform3D else Transform3D(head.global_basis.orthonormalized(),head.global_position)
	var start := _jaw_rest_pose if include_lunge else head_pose.affine_inverse()*jaw.global_transform
	if include_lunge:
		var opening := Basis(Vector3.BACK,-deg_to_rad(data.jaw_open_degrees))
		start = Transform3D(opening*start.basis,_head_anchor+opening*(start.origin-_head_anchor))
	var relative := start.basis.get_rotation_quaternion().slerp(_rest,progress)
	var rotation := Basis(relative)*start.basis.inverse()
	return head_pose*Transform3D(Basis(relative),_head_anchor+rotation*(start.origin-_head_anchor))

func _closing_prediction(next_target: PhysicalBodyPart3D, samples: int, margin: float, include_lunge: bool = false, preparation_delay: float = -1.0, forecast_motion: bool = true) -> Dictionary:
	var box := _shape()
	var offset := Vector3(jaw.get_meta(&"generated_size",Vector3.ONE))*data.box_center_ratio
	var aim := _head_aim_goal(next_target.global_position) if include_lunge else {}
	for index: int in range(clampi(samples,8,32)):
		var progress := float(index)/float(clampi(samples,8,32)-1)
		var time := (data.jaw_close_time+data.jaw_close_extra_wait)*progress
		var pose := _closure_pose(smoothstep(0.0,data.jaw_close_time,time),include_lunge,aim.get("pose"))
		pose.origin = pose*offset
		if include_lunge:
			var spacing := _spacing_for(next_target) if preparation_delay < 0.0 else 0.0
			time += (data.bite_plant_prediction_time+maxf(data.bite_retract_time,data.jaw_open_time) if preparation_delay < 0.0 else preparation_delay)+data.bite_lunge_timeout*progress
			if spacing > 0.0:
				time += data.bite_spacing_retreat_time
				pose.origin -= controller.forward()*spacing
			var length: float = controller.pounce_scale()*controller.get_node("Pounce").data.reference_body_length
			var travel := minf(length*data.bite_advance_ratio,_travel_limit(controller.forward()))
			if is_zero_approx(preparation_delay) and _phase == &"charging":
				travel = minf(maxf(_advance-(controller.torso.global_position-_origin).dot(_forward),0.0),_travel_limit(_forward))
				pose.origin.y += _crouch*smoothstep(0.0,data.jaw_open_time,data.bite_lunge_timeout*progress)
			pose.origin += controller.forward()*travel*progress
		else: pose.origin += head.linear_velocity*time
		if predicts_enemy_hit(box,pose,next_target,time if forecast_motion else 0.0,margin):
			return {"hit":true,"reason":&"bite_sweep_hit" if forecast_motion else &"current_reach_hit","confidence":1.0 if forecast_motion else 0.5,"time":time}
	return {"hit":false,"reason":&"bite_sweep_misses"}

func start(next_target: PhysicalBodyPart3D) -> bool:
	if not predict(next_target,24,0.1).hit or not super.start(next_target): return false
	_last_hits = 0
	_reason = &"started"
	_contacted = false
	_close_reason = &""
	_support_count = 0
	_crouch = 0.0
	_head_aim_point = next_target.global_position
	_claim_head_aim()
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
	_weapon = BiteHitbox.new()
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
	# Query the arriving mouth before closing/braking can erase its impact velocity.
	_weapon.update_hitbox(delta,_phase in [&"lunging",&"closing"])
	if not active: return
	_contacted = _contacted or _weapon.contacted
	if _weapon.hit_count > 0: _reason = &"hit"
	if _phase not in [&"planting",&"spacing_retreat"]: _support_count = _plant_feet(delta)
	if _phase == &"spacing_retreat":
		_retreat_for_spacing()
		if not active: return
	elif _phase == &"planting":
		if _reposition_feet(delta):
			_begin_charge()
		elif _phase_time >= data.bite_plant_timeout: finish(&"cannot_plant_feet"); return
	elif _phase == &"charging" and _phase_time >= maxf(data.bite_retract_time,data.jaw_open_time):
		_set_phase(&"lunging")
		var speed: float = data.bite_lunge_speed*sqrt(controller.pounce_scale())
		for body: RigidBody3D in owned_bodies: body.apply_central_impulse(_forward*(speed-body.linear_velocity.dot(_forward))*body.mass)
	elif _phase == &"lunging":
		var can_hit: bool = _closing_prediction(target,12,0.05).hit
		var at_limit: bool = (controller.torso.global_position-_origin).dot(_forward) >= _advance
		if (can_hit and _phase_time >= data.bite_lunge_acceleration_time) or _contacted:
			_close_reason = &"mouth_contact" if _contacted else &"predicted_hit"
			_set_phase(&"closing")
		elif at_limit or _phase_time >= data.bite_lunge_timeout:
			_close_reason = &"reach_limit_no_contact" if at_limit else &"lunge_timeout"
			_reason = _close_reason
			_set_phase(&"recovering")
	elif _phase == &"closing" and _phase_time >= data.jaw_close_time:
		var relative := (head.global_basis.orthonormalized().inverse()*jaw.global_basis.orthonormalized()).get_rotation_quaternion()
		if rad_to_deg(relative.angle_to(_rest)) <= data.jaw_close_tolerance_degrees or _phase_time >= data.jaw_close_time+data.jaw_close_extra_wait:
			_set_phase(&"recovering")
	elif _phase == &"recovering" and (_phase_time >= data.recovery_time or (_phase_time >= 0.05 and _recovery_settled())): finish(); return
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

func _recovery_settled() -> bool:
	if absf(_angle_error) > 5.0: return false
	for row: Dictionary in _torsos:
		if row.body.global_position.distance_to(row.origin) > maxf(controller.pounce_scale()*0.1,0.02) or row.body.linear_velocity.length() > 0.5: return false
	return true

func finish(reason: StringName = &"completed") -> void:
	if active and _reason != &"hit" and (reason != &"completed" or _reason == &"started"): _reason = reason
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
	if is_instance_valid(_head_joint) and not _head_joint.is_queued_for_deletion() and not _head_joint_state.is_empty() and PhysicsServer3D.joint_get_type(_head_joint.get_rid()) == PhysicsServer3D.JOINT_TYPE_6DOF:
		_head_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING,_head_joint_state.spring)
		_head_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR,_head_joint_state.motor)
	_head_joint_state.clear()
	_head_joint = null
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
	result["torso_advance"] = (controller.torso.global_position-_origin).dot(_forward) if controller != null and is_instance_valid(controller.torso) and controller.torso.is_inside_tree() else 0.0
	result["pinned_feet"] = _support_count
	var foot_status: Array[Dictionary] = []
	for row: Dictionary in _foot_plans:
		if alive(row.foot): foot_status.append({"foot":row.foot.name,"position":row.foot.global_position,"target":row.target,"error":row.foot.global_position.distance_to(row.target),"velocity":row.foot.linear_velocity,"skipped":row.skipped,"stalled_time":row.stalled_time,"elapsed":row.elapsed,"done":row.done})
	result["foot_plans"] = foot_status
	result["repositioned_feet"] = _repositioned_feet
	result["burst_acceleration"] = data.bite_lunge_acceleration if data != null else 0.0
	result["burst_duration"] = data.bite_lunge_acceleration_time if data != null else 0.0
	result["close_reason"] = _close_reason
	result["result"] = _reason
	result["head_anchor_world"] = head.to_global(_head_anchor) if alive(head) else Vector3.ZERO
	var aim := get_head_posture_request()
	result["head_aim"] = {"active":not aim.is_empty() and _phase != &"recovering","locked_point":_head_aim_point,"pitch_degrees":rad_to_deg(float(aim.get("angle",0.0))),"error_degrees":aim.get("error_degrees",0.0),"servo_error_degrees":aim.get("servo_error_degrees",0.0)}
	result["spacing_retreat_distance"] = _spacing_distance
	result["spacing_retreat_traveled"] = (_spacing_origin-controller.torso.global_position).dot(_forward) if controller != null and is_instance_valid(controller.torso) and controller.torso.is_inside_tree() else 0.0
	return result
