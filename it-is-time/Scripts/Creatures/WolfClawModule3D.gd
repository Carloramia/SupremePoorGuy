@tool
extends "res://Scripts/Creatures/WolfAttackModule3D.gd"
const HITBOX = preload("res://Scripts/Items/WolfAttackHitbox3D.gd")
const COLLISION_GUARD = preload("res://Scripts/Creatures/WolfClawCollisionGuard3D.gd")
var _rows: Array[Dictionary] = []
var _last_hits := 0
var _torsos: Array[Dictionary] = []
var _motion_time := 0.0
var _lift_wait := 0.0
var _lift_confirmed := false
var _torso_recovery_elapsed := 0.0
var _collision_guards: Dictionary = {}

func _suspend_chain_collisions(foot: RigidBody3D) -> void:
	var guards: Array[Node] = []
	for part: RigidBody3D in controller.movement._chains[foot].bodies:
		if part == controller.movement._chains[foot].root: continue
		var guard := part.get_node_or_null("WolfClawCollisionGuard")
		if guard == null:
			guard = COLLISION_GUARD.new()
			guard.name = "WolfClawCollisionGuard"
			part.add_child(guard)
		guard.acquire(part,self,controller.own_rids())
		guards.append(guard)
	_collision_guards[foot] = guards

func _release_chain_collisions(foot: RigidBody3D) -> void:
	for guard: Node in _collision_guards.get(foot,[]):
		if is_instance_valid(guard): guard.release()
	_collision_guards.erase(foot)

func _update_lift_clock(delta: float) -> void:
	for foot: RigidBody3D in controller.movement.get_leg_parts():
		if controller.is_pouncing(): break
		if owned_feet.has(foot) or not controller.movement._chain_is_intact(foot): continue
		var surface: Dictionary = controller.movement._get_surface_below_leg(foot,controller.movement.surface_adhesion_probe_distance)
		if not surface.is_empty() and controller.movement._surface_is_walkable(surface.normal): controller.movement._update_support_foot_lock(foot,surface.normal)
	if _motion_time >= data.windup_time and not _lift_confirmed:
		var ready := _has_rear_support() or data.torso_lift_ratio <= 0.0
		for row: Dictionary in _torsos:
			if row.weight == 1.0 and alive(row.body) and row.body.global_position.y-float(row.height) < float(row.length)*data.torso_lift_ratio*0.5: ready = false
		if not ready and _lift_wait < data.claw_lift_timeout:
			_lift_wait += delta
			return
		_lift_confirmed = true
	_motion_time += delta
	if not _lift_confirmed: _motion_time = minf(_motion_time,data.windup_time)

func _has_rear_support() -> bool:
	for foot: RigidBody3D in controller.movement.get_action_support_feet():
		if not controller.movement._has_body_tag(foot,controller.movement.FORELEG_TAG): return true
	return false

func _lift_amount(time: float, length: float) -> float:
	var rise := smoothstep(0.0,data.windup_time,time)
	if active: rise *= 1.0-smoothstep(0.0,data.windup_time,_torso_recovery_elapsed)
	return length*data.torso_lift_ratio*rise

func _lift_torsos() -> void:
	var supported: bool = not controller.is_pouncing() and _has_rear_support()
	for row: Dictionary in _torsos:
		if not alive(row.body): continue
		controller.movement.set_action_body_weight(row.body,1.0 if supported else 0.0)
		if not supported: continue
		var height: float = row.height+_lift_amount(_motion_time,row.length)*float(row.weight)
		var acceleration: float = (height-row.body.global_position.y)*data.position_gain-row.body.linear_velocity.y*data.velocity_gain-controller.movement._gravity_acceleration().y
		row.body.apply_central_force(Vector3.UP*clampf(acceleration,-data.maximum_acceleration,data.maximum_acceleration)*row.body.mass)

func _joint_rows(chain: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index: int in range(chain.joints.size()-1,-1,-1):
		var joint: Generic6DOFJoint3D = chain.joints[index]
		var child: RigidBody3D = chain.bodies[index]
		var parent: RigidBody3D = chain.bodies[index+1]
		var child_is_a := joint.get_node(joint.node_a) == child
		var child_frame: Transform3D = joint.get_meta(&"generated_joint_frame_a" if child_is_a else &"generated_joint_frame_b")
		var parent_frame: Transform3D = joint.get_meta(&"generated_joint_frame_b" if child_is_a else &"generated_joint_frame_a")
		var lower := -PI
		var upper := PI
		if joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT):
			lower = joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)
			upper = joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)
			# Use the same temporary attack limits as the character, preserving protected elbows.
			if not joint.has_meta(&"wolf_bend_z_limits") and joint.has_meta(&"authored_walk_limits"):
				var preset = controller.get_parent().wolf_physics
				if preset != null and preset.enabled:
					var limits: Vector3 = joint.get_meta(&"authored_walk_limits")
					upper = maxf(limits.z,deg_to_rad(preset.action_z_limit)); lower = -upper
			if not child_is_a:
				var old_lower := lower
				lower = -upper; upper = -old_lower
		var parent_basis := (parent.global_transform*parent_frame).basis.orthonormalized()
		var child_basis := (child.global_transform*child_frame).basis.orthonormalized()
		var angle := (parent_basis.inverse()*child_basis).get_euler().z
		rows.append({"parent_frame":parent_frame,"child_frame":child_frame,"angle":clampf(angle,lower,upper),"lower":lower,"upper":upper})
	return rows

func _forward_pose(root_pose: Transform3D, joints: Array[Dictionary]) -> Dictionary:
	var pose := root_pose
	var pivots: Array[Transform3D] = []
	for row: Dictionary in joints:
		var pivot: Transform3D = pose*row.parent_frame
		pivots.append(pivot)
		pose = pivot*Transform3D(Basis(Vector3.BACK,row.angle),Vector3.ZERO)*Transform3D(row.child_frame).affine_inverse()
	return {"end":pose.origin,"pivots":pivots}

func _extended_endpoint(chain: Dictionary, target_position: Vector3) -> Dictionary:
	var root_body: RigidBody3D = chain.root
	var joints := _joint_rows(chain)
	var origin: Vector3 = root_body.to_global(chain.anchor)
	var goal: Vector3 = origin+controller.forward()*float(chain.length)*1.05
	goal.y = clampf(target_position.y,origin.y-float(chain.length)*0.6,origin.y+float(chain.length)*0.6)
	# Solve in copied joint frames; never move physics bodies or change their constraints.
	for iteration: int in range(10):
		for index: int in range(joints.size()-1,-1,-1):
			var pose := _forward_pose(root_body.global_transform,joints)
			var pivot: Transform3D = pose.pivots[index]
			var axis := pivot.basis.z.normalized()
			var from: Vector3 = (Vector3(pose.end)-pivot.origin).slide(axis)
			var to: Vector3 = (goal-pivot.origin).slide(axis)
			if from.length_squared() < 0.000001 or to.length_squared() < 0.000001: continue
			var row: Dictionary = joints[index]
			row.angle = clampf(float(row.angle)+from.signed_angle_to(to,axis),row.lower,row.upper)
	# Blend slightly toward the authored joint pose to avoid driving into a hard stop.
	for row: Dictionary in joints:
		row.angle = lerpf(clampf(0.0,row.lower,row.upper),row.angle,data.reach_ratio)
	var result := _forward_pose(root_body.global_transform,joints)
	result["joints"] = joints
	return result

func _plan(next_target: PhysicalBodyPart3D) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var movement: Node = controller.movement
	for foot: RigidBody3D in movement.get_leg_parts():
		if not alive(foot) or not movement._has_body_tag(foot,movement.FORELEG_TAG) or not movement._chain_is_intact(foot): continue
		var chain: Dictionary = movement._chains[foot]
		var root_body: RigidBody3D = chain.root
		var length: float = chain.length
		var forward: Vector3 = controller.forward()
		var raised := foot.global_position-forward*length*0.08+Vector3.UP*length*0.25
		raised = root_body.global_position+(raised-root_body.global_position).limit_length(length*data.reach_ratio)
		var extension := _extended_endpoint(chain,next_target.global_position+next_target.linear_velocity*(data.windup_time+0.5/maxf(data.claw_motion_speed_ratio,0.1)))
		var end: Vector3 = extension.end
		if (end-root_body.global_position).dot(forward) <= 0.0: continue
		var size: Vector3 = foot.get_meta(&"generated_size",Vector3.ONE)
		rows.append({"body":foot,"root":root_body,"start":root_body.to_local(foot.global_position),"raised":root_body.to_local(raised),"end":root_body.to_local(end),"extension":extension,"size":size*data.box_size_ratio,"offset":size*data.box_center_ratio,"delay":rows.size()*data.stagger_time,"completed":false,"phase":&"waiting","phase_elapsed":0.0,"settled":0.0,"progress":0.0,"length":length,"weapon":null})
	return rows

func predict(next_target: PhysicalBodyPart3D, samples: int, margin: float) -> Dictionary:
	if not available(): return {"hit":false,"reason":&"cooldown_or_disabled"}
	var rows := _plan(next_target)
	if rows.is_empty(): return {"hit":false,"reason":&"no_intact_foreleg"}
	for row: Dictionary in rows:
		var shape := BoxShape3D.new()
		shape.size = Vector3(row.size).max(Vector3.ONE*0.02)
		for index: int in range(clampi(samples,8,32)):
			var progress := float(index)/float(clampi(samples,8,32)-1)
			var time: float = row.delay+data.windup_time+_motion_duration(row,row.raised,row.end)*progress
			var position: Vector3 = row.root.to_global(Vector3(row.raised).lerp(row.end,smoothstep(0.0,1.0,progress)))+row.root.linear_velocity*time
			if not controller.is_pouncing() and _has_rear_support(): position.y += _lift_amount(time,controller.movement._chains[row.body].length)
			var pose := Transform3D(row.body.global_basis.orthonormalized(),position+row.body.global_basis*Vector3(row.offset))
			if predicts_enemy_hit(shape,pose,next_target,time,margin):
				return {"hit":true,"reason":&"claw_sweep_hit","confidence":1.0,"part":row.body.name,"time":time}
	return {"hit":false,"reason":&"claw_sweep_misses"}

func start(next_target: PhysicalBodyPart3D) -> bool:
	if not predict(next_target,24,0.1).hit: return false
	_rows = _plan(next_target)
	if not super.start(next_target): return false
	_last_hits = 0
	_motion_time = 0.0
	_lift_wait = 0.0
	_lift_confirmed = false
	_torso_recovery_elapsed = 0.0
	_torsos.clear()
	var roots: Array[RigidBody3D] = []
	var length := INF
	for row: Dictionary in _rows:
		roots.append(row.root)
		length = minf(length,controller.movement._chains[row.body].length)
	for body: RigidBody3D in controller.get_parent()._get_physical_body_parts():
		if not alive(body) or not controller.movement._has_body_tag(body,controller.movement.TORSO_TAG): continue
		owned_bodies.append(body)
		_torsos.append({"body":body,"height":body.global_position.y,"length":length,"weight":1.0 if roots.has(body) else 0.5 if body == controller.torso else 0.0})
	for row: Dictionary in _rows:
		owned_feet.append(row.body)
		_suspend_chain_collisions(row.body)
		var weapon := HITBOX.new()
		weapon.name = "ClawHitbox_"+str(row.body.name)
		weapon.setup(row.body,controller.get_parent(),row.size,row.offset,data.impulse_multiplier,data.hit_ragdoll_duration)
		add_child(weapon)
		row.weapon = weapon
	controller.sync_foot_ownership()
	return true

func _motion_duration(row: Dictionary, from: Vector3, to: Vector3) -> float:
	return maxf(from.distance_to(to)/maxf(float(row.length)*data.claw_motion_speed_ratio,0.001),0.05)

func _motion_complete(row: Dictionary, point: Vector3) -> bool:
	var root_velocity: Vector3 = row.root.linear_velocity+row.root.angular_velocity.cross(point-row.root.global_position)
	row["tracking_error"] = point.distance_to(row.body.global_position)
	row["relative_speed"] = (row.body.linear_velocity-root_velocity).length()
	return row.tracking_error <= float(row.length)*data.claw_position_tolerance_ratio and row.relative_speed <= float(row.length)*data.claw_relative_speed_tolerance_ratio

func _set_part_phase(row: Dictionary, phase: StringName) -> void:
	if phase == &"recovering" and is_instance_valid(row.weapon): row.weapon.end_damage_swing()
	row.phase = phase
	row.phase_elapsed = 0.0
	row.settled = 0.0
	row.progress = 0.0
	row["blocked_time"] = 0.0
	row["best_error"] = INF
	controller.log_event(name,phase,{"part":row.body.name,"time":elapsed,"position":row.body.global_position,"tracking_error":row.get("tracking_error",0.0),"relative_speed":row.get("relative_speed",0.0)})

func tick(delta: float) -> void:
	super.tick(delta)
	if not active: return
	_update_lift_clock(delta)
	var lowering := _rows.all(func(row): return row.completed or row.phase == &"recovering")
	if lowering: _torso_recovery_elapsed += delta
	_lift_torsos()
	for row: Dictionary in _rows:
		if not alive(row.body) or not alive(row.root) or not controller.movement._chain_is_intact(row.body):
			_release_chain_collisions(row.body)
			row.completed = true
			if is_instance_valid(row.weapon): _last_hits += row.weapon.hit_count; row.weapon.dispose(); row.weapon = null
			owned_feet.erase(row.body)
			controller.sync_foot_ownership()
			continue
		if row.phase == &"waiting":
			if elapsed < row.delay: continue
			_set_part_phase(row,&"raising")
		row.phase_elapsed += delta
		if not row.completed and row.phase_elapsed > data.claw_phase_timeout:
			controller.log_event(name,&"motion_blocked",{"part":row.body.name,"phase":row.phase,"tracking_error":row.get("tracking_error",0.0),"relative_speed":row.get("relative_speed",0.0)})
			finish(&"motion_timeout")
			return
		var from: Vector3 = row.start
		var to: Vector3 = row.raised
		var duration: float = data.windup_time
		if row.phase == &"striking":
			from = row.raised; to = row.end
			duration = _motion_duration(row,from,to)
		elif row.phase in [&"recovering",&"completed"]:
			from = row.end; to = row.start
			duration = _motion_duration(row,from,to)
		var progress := 1.0 if row.completed else clampf(float(row.phase_elapsed)/duration,0.0,1.0)
		row.progress = progress
		var point: Vector3 = row.root.to_global(from.lerp(to,smoothstep(0.0,1.0,progress)))
		var velocity: Vector3 = row.root.linear_velocity+row.root.angular_velocity.cross(point-row.root.global_position)+row.root.global_basis*(to-from)*(6.0*progress*(1.0-progress)/duration)
		var acceleration: Vector3 = ((point-row.body.global_position)*data.position_gain+(velocity-row.body.linear_velocity)*data.velocity_gain-controller.movement._gravity_acceleration()).limit_length(data.maximum_acceleration*controller.scale_factor())
		row.body.apply_central_force(acceleration*row.body.mass)
		row["target_position"] = point
		var arrived := _motion_complete(row,point)
		# Stop pushing a stationary chain against an unreachable extension endpoint.
		if row.phase == &"striking" and progress >= 1.0 and not arrived:
			var improved: bool = row.tracking_error < float(row.get("best_error",INF))-float(row.length)*0.005
			if improved: row.best_error = row.tracking_error
			row.blocked_time = 0.0 if improved or row.relative_speed > float(row.length)*0.15 else float(row.get("blocked_time",0.0))+delta
			if row.blocked_time >= 0.4:
				controller.log_event(name,&"extension_blocked",{"part":row.body.name,"tracking_error":row.tracking_error,"relative_speed":row.relative_speed})
				if is_instance_valid(row.weapon): row.weapon.update_hitbox(delta,false)
				row.end = row.root.to_local(row.body.global_position)
				_set_part_phase(row,&"recovering")
				continue
		if is_instance_valid(row.weapon): row.weapon.update_hitbox(delta,row.phase == &"striking")
		# Hold the endpoint until both position and relative velocity settle.
		var can_finish: bool = progress >= 1.0 and arrived and (row.phase != &"raising" or _lift_confirmed)
		row.settled = float(row.settled)+delta if can_finish else 0.0
		if not row.completed and can_finish and row.settled >= data.claw_settle_time:
			if row.phase == &"raising": _set_part_phase(row,&"striking")
			elif row.phase == &"striking": _set_part_phase(row,&"recovering")
			elif row.phase == &"recovering":
				_set_part_phase(row,&"completed")
				row.completed = true
				if is_instance_valid(row.weapon): _last_hits += row.weapon.hit_count; row.weapon.dispose(); row.weapon = null
	var completed := _rows.all(func(row): return row.completed)
	if not completed: return
	if owned_feet.is_empty(): finish(); return
	var torso_ready := _torso_recovery_elapsed >= data.windup_time
	for row: Dictionary in _rows:
		if alive(row.body) and alive(row.root) and not _motion_complete(row,row.root.to_global(row.start)): torso_ready = false
	for row: Dictionary in _torsos:
		if not alive(row.body): continue
		if absf(row.body.global_position.y-float(row.height)) > float(row.length)*data.claw_position_tolerance_ratio or absf(row.body.linear_velocity.y) > float(row.length)*data.claw_relative_speed_tolerance_ratio: torso_ready = false
	if torso_ready: finish()
	elif _torso_recovery_elapsed > data.claw_phase_timeout: finish(&"torso_recovery_timeout")

func finish(reason: StringName = &"completed") -> void:
	for foot: RigidBody3D in _collision_guards.keys(): _release_chain_collisions(foot)
	for row: Dictionary in _rows:
		if is_instance_valid(row.weapon):
			_last_hits += row.weapon.hit_count
			row.weapon.dispose()
	_rows.clear()
	_torsos.clear()
	super.finish(reason)

func diagnostics() -> Dictionary:
	var result := super.diagnostics()
	var parts: Array[Dictionary] = []
	for row: Dictionary in _rows:
		parts.append({"part":row.body.name if is_instance_valid(row.body) else &"freed","phase":row.phase,"delay":row.delay,"hits":row.weapon.hit_count if is_instance_valid(row.weapon) else 0,"position":row.body.global_position if is_instance_valid(row.body) else Vector3.ZERO,"target_position":row.get("target_position",Vector3.ZERO),"extension_local":row.end,"tracking_error":row.get("tracking_error",0.0),"relative_speed":row.get("relative_speed",0.0),"phase_elapsed":row.phase_elapsed,"settled":row.settled,"progress":row.progress})
	result["parts"] = parts
	result["last_hits"] = _last_hits
	result["motion_time"] = _motion_time
	result["lift_wait"] = _lift_wait
	result["collision_suspended_chains"] = _collision_guards.size()
	var torsos: Array[Dictionary] = []
	for row: Dictionary in _torsos:
		if alive(row.body): torsos.append({"part":row.body.name,"actual_rise":row.body.global_position.y-float(row.height),"target_rise":_lift_amount(_motion_time,row.length)*float(row.weight)})
	result["torso_lift"] = torsos
	return result
