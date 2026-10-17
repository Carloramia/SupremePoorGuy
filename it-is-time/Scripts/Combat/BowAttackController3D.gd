extends Node3D
## NPC receiver and physical holding pose. Player firing/ammunition inventory are intentionally separate.
const DATA = preload("res://Scripts/Combat/BowAttackData.gd")
const BOW = preload("res://Scripts/Items/BowWeapon3D.gd")
const ARROW = preload("res://Scripts/Items/ArrowWeapon3D.gd")
const POSE = preload("res://Scripts/Combat/WeaponArmPose3D.gd")
const PLANAR = preload("res://Scripts/Combat/BowArmPose3D.gd")
const CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")
const PREDICTION = preload("res://Scripts/Creatures/NPCAttackPrediction3D.gd")
const OWNER := &"equipment_bow_pose_driver"
enum Phase { IDLE, PREPARING, DRAWING, RECOVERING }
@export var enabled := true
@export var preset: DATA = preload("res://Resources/Combat/Weapons/BowAttack.tres")
signal shot_fired(arrow: RigidBody3D)
var phase := Phase.IDLE
var shots_fired := 0
var attacks_started := 0
var cancelled_attacks := 0
var hits := 0
var damaging_hits := 0
var last_reason := &"idle"
var locked_point := Vector3.ZERO
var _attack_target: Node3D
var _bow: BOW
var _arms: Array[Dictionary] = []
var _motor := WeaponArmAttackPreset.new()
var _nocked: ARROW
var _elapsed := 0.0
var _phase_elapsed := 0.0
var _cooldown := 0.0
var _reach := 4.5
var _direction := Vector3.RIGHT
var _right_target := Vector3.ZERO
var _position_error := INF
var _aim_error := PI
var _draw_ratio := 0.0
var last_shot: Dictionary = {}
var last_impact: Dictionary = {}
var _controls_enabled := true
var _pre_draw := 0.0
var _full_draw := 0.0
var _original_draw_limit := 0.0
var _solve_remaining := 0.0
var _posture_search_remaining := 0.0
var _pose_feasible := false
var _solver_error := INF
var _left_target := Vector3.ZERO
var _charge_draw_ratio := 0.0
var _plan_shift := Vector2.ZERO
var _plan_sequence := 0
var _last_plan_frame := -1
var _posture_locked := false
var _desired_direction := Vector3.RIGHT
var _pose_pull := 0.0
var _draw_start_pull := 0.0
var _recovery_start_pull := 0.0
var _recovery_start_direction := Vector3.RIGHT
var _recovery_string_origin := -1.0
var _stable_elapsed := 0.0
var _relative_bow_speed := 0.0
var _maximum_joint_speed := 0.0
var _observed_prepare_time := 0.6
var _last_prepare_duration := 0.0
var _locked_prediction: Dictionary = {}

func _ready() -> void:
	add_to_group(&"bow_attack_controllers")
	process_physics_priority = -15

func _exit_tree() -> void: _release()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED and is_inside_tree(): _release()

func _inventory() -> Node:
	return get_parent().get_node_or_null("InventoryController3D")

func _valid() -> bool:
	if not is_instance_valid(_bow) or not _bow.is_inside_tree() or _bow.is_queued_for_deletion() or _bow.wielder_character != get_parent() or _bow.ammunition_scene==null: return false
	if _arms.size()!=2: return false
	for arm: Dictionary in _arms:
		if not is_instance_valid(arm.anchor_body) or not arm.anchor_body.is_inside_tree() or arm.anchor_body.is_broken: return false
		for link: Dictionary in arm.pose_chain:
			if not is_instance_valid(link.body) or not link.body.is_inside_tree() or link.body.is_queued_for_deletion() or link.body.is_broken or not is_instance_valid(link.joint) or not link.joint.is_inside_tree() or link.joint.is_queued_for_deletion(): return false
	return true

func _capture(bow: BOW) -> bool:
	var inventory := _inventory()
	if inventory == null or bow.ammunition_scene==null: return false
	_bow = bow
	var joints := get_parent().find_children("*","Generic6DOFJoint3D",true,false)
	var swing := get_parent().get_node_or_null("LimbSwingController3D")
	for index: int in 2:
		var hand: PhysicalBodyPart3D = inventory._resolve_grip_arm(bow.get_grip_arm_path(index))
		if hand == null or not hand.is_inside_tree() or hand.is_broken: _release(); return false
		if swing != null: swing.cancel_attacks_for_holder(hand)
		var socket: Marker3D = inventory._resolve_item_socket(hand)
		var chain: Dictionary = inventory._multi_grips._capture_chain(hand,socket,joints)
		if chain.anchor == null or chain.bodies.size()!=3: _release(); return false
		if not chain.anchor.is_inside_tree(): _release(); return false
		for body: RigidBody3D in chain.bodies:
			if not body.is_inside_tree() or not PhysicsServer3D.body_get_space(body.get_rid()).is_valid(): _release(); return false
		var links: Array[Dictionary] = []
		for position: int in range(chain.bodies.size()-1,-1,-1):
			var body: RigidBody3D = chain.bodies[position]
			links.append({"body":body,"joint":chain.joints[position],"proximal":POSE.local_anchor(chain.joints[position],body),
				"distal":POSE.local_anchor(chain.joints[position-1],body) if position>0 else socket.position,
				"rest_basis":chain.anchor.global_basis.inverse()*body.global_basis})
		var arm := {"pose_chain":links,"anchor_body":chain.anchor,"pose_anchor_local":chain.anchor_local,
			"hand":hand,"socket":socket,"weapon_forward_local":hand.global_basis.inverse()*bow.global_basis.x,"pose_snapshot":[],"primary":index==0,"weapon":bow}
		_arms.append(arm)
		PLANAR.capture(arm)
		for link: Dictionary in links: link.body.set_meta(OWNER,self)
	_reach = minf(POSE.reach(_arms[0].pose_chain),POSE.reach(_arms[1].pose_chain))
	if _reach<0.01: _release(); return false
	_original_draw_limit = bow.maximum_draw_distance
	_full_draw = preset.draw_reach_ratio*_reach
	bow.maximum_draw_distance = _full_draw
	_solve_remaining = 0.0
	_plan_shift = Vector2.ZERO
	_posture_search_remaining = 0.0
	_posture_locked = false
	_pose_pull = 0.0
	_direction = _arms[0].anchor_body.global_basis.x.slide(_plane_normal()).normalized()
	_desired_direction = _direction
	return true

func _release() -> void:
	cancel_npc_attack(&"pose_released")
	for arm: Dictionary in _arms:
		PLANAR.restore(arm)
		for link: Dictionary in arm.pose_chain:
			if is_instance_valid(link.body) and link.body.has_meta(OWNER) and link.body.get_meta(OWNER)==self: link.body.remove_meta(OWNER)
	_arms.clear()
	if is_instance_valid(_bow) and _original_draw_limit>0.0: _bow.maximum_draw_distance = _original_draw_limit
	_bow = null
	_original_draw_limit = 0.0
	_pose_feasible = false
	_pre_draw = 0.0
	_full_draw = 0.0
	_posture_search_remaining = 0.0
	_posture_locked = false
	_pose_pull = 0.0

func cancel_action(reason: StringName = &"cancelled") -> void: cancel_npc_attack(reason)
func release_weapon_pose() -> void: _release()

func set_character_control_enabled(value: bool) -> void:
	_controls_enabled = value
	if not value: _release()

func cancel_npc_attack(diagnostic_reason: StringName = &"cancelled") -> void:
	var was_active := is_npc_attack_active()
	var previous_phase := phase
	var previous_age := _phase_elapsed
	if phase in [Phase.PREPARING,Phase.DRAWING]: cancelled_attacks += 1
	if is_instance_valid(_nocked): _nocked.queue_free()
	_nocked = null
	_attack_target = null
	if is_instance_valid(_bow): _bow.draw_target_distance = -1.0
	phase = Phase.IDLE
	_elapsed = 0.0
	_phase_elapsed = 0.0
	_stable_elapsed = 0.0
	_solve_remaining = 0.0
	if was_active: last_reason = &"cancelled"
	if was_active: _log_bow_event(&"attack_cancelled",{"previous_phase":Phase.keys()[previous_phase],"previous_phase_elapsed":previous_age,"cause":diagnostic_reason})

func _log_bow_event(event: StringName, detail: Dictionary = {}) -> void:
	if not is_inside_tree(): return
	var console := get_node_or_null("/root/RuntimeConsole")
	if console!=null: console.log_bow_event(self,event,detail)

func is_npc_attack_active() -> bool: return phase!=Phase.IDLE
func has_npc_attack(action: StringName) -> bool: return action==&"bow_shoot" and enabled and _controls_enabled and preset!=null and _valid()
func uses_dynamic_npc_attack_range(_action: StringName) -> bool: return true
func has_unlimited_npc_attack_range(_action: StringName) -> bool: return true
func uses_weapon_attack_spacing(_action: StringName) -> bool: return true
func get_npc_attack_minimum_range(_action: StringName) -> float: return preset.minimum_range*_reach/4.5
func get_npc_attack_maximum_range(_action: StringName, _target: Node3D) -> float: return INF
func get_npc_attack_preferred_distance(_action: StringName, _target: Node3D) -> float: return preset.preferred_range*_reach/4.5
func get_npc_attack_distance_tolerance(_action: StringName) -> float: return preset.distance_tolerance*_reach/4.5
func get_npc_attack_maximum_duration(_action: StringName) -> float: return preset.maximum_prepare_time+maxf(preset.maximum_recovery_time,preset.recovery_time+0.5)+0.5

func is_npc_target_in_attack_range(action: StringName, target: Node3D) -> bool:
	if not is_instance_valid(target) or preset==null: return false
	var anchor: Node3D = get_parent().get_combat_anchor()
	if not is_instance_valid(anchor): return false
	var distance := (target.global_position-anchor.global_position).slide(Vector3.UP).length()
	return distance>=get_npc_attack_minimum_range(action)

func _holding_point(direction: Vector3) -> Vector3:
	var a: Vector3 = _arms[0].anchor_body.to_global(_arms[0].pose_anchor_local)
	return a+direction*preset.holding_reach_ratio*POSE.reach(_arms[0].pose_chain)+_arms[0].anchor_body.global_basis.y.normalized()*preset.holding_height_ratio*_reach

func _plane_normal() -> Vector3:
	return _arms[0].anchor_body.global_basis.z.normalized()

func _plan_pose(direction: Vector3, pull: float, allow_pre_draw: bool) -> void:
	var nominal := _holding_point(direction)
	var up: Vector3 = _arms[0].anchor_body.global_basis.y.normalized()
	var best: Dictionary = {}
	var anatomical := preset.anatomical_pose_enabled and preset.anatomical_pose_weight>0.0
	var reuse_posture := _posture_locked
	if allow_pre_draw: _pre_draw = clampf(_pre_draw,0.0,_full_draw*preset.posture_draw_ratio)
	var shifts: Array[Vector2] = [_plan_shift]
	if not reuse_posture:
		for forward_shift: float in [0.0,-0.1,0.1,-0.3,-0.5]:
			for height_shift: float in [0.0,-0.1,0.1,0.3]:
				var shift := Vector2(forward_shift,height_shift)
				if shift not in shifts: shifts.append(shift)
	for shift: Vector2 in shifts:
		var end := nominal+(direction*shift.x+up*shift.y)*_reach
		var right := PLANAR.solve(_arms[0],end,direction,true,preset)
		var pulls: Array[float] = [pull]
		if allow_pre_draw and not reuse_posture: pulls = [_pre_draw,0.0,_full_draw*preset.posture_draw_ratio*0.5,_full_draw*preset.posture_draw_ratio]
		for amount: float in pulls:
			var left_end: Vector3 = right.end-direction*(_bow.get_rest_grip_distance()+amount)
			var left := PLANAR.solve(_arms[1],left_end,direction,false,preset)
			var error: float = maxf(right.error,left.error)
			var feasible: bool = error<_reach*0.05 and float(right.aim_error)<deg_to_rad(3.0)
			var score: float = right.error*right.error+left.error*left.error+pow(right.aim_error*_reach,2.0)
			var comfortable := true
			if anatomical:
				var right_posture := PLANAR.posture_metrics(_arms[0],right.poses,right.angles,direction,preset)
				var left_posture := PLANAR.posture_metrics(_arms[1],left.poses,left.angles,direction,preset)
				score += preset.anatomical_pose_weight*(right_posture.score+left_posture.score*0.5)
				score += shift.length_squared()*0.1
				comfortable = right_posture.comfortable and left_posture.comfortable
			if best.is_empty() or (feasible and not best.feasible) or (feasible==bool(best.feasible) and score<float(best.score)):
				best = {"right":right,"left":left,"score":score,"pull":amount,"feasible":feasible,"error":error,"shift":shift,"comfortable":comfortable}
			if best.feasible and reuse_posture: break
		if best.feasible and (not anatomical or reuse_posture or best.comfortable): break
	# Keep the same posture branch through a shot; search again only when it stops being reachable.
	if reuse_posture and not best.feasible and phase in [Phase.IDLE,Phase.PREPARING] and _posture_search_remaining<=0.0:
		_posture_locked = false
		_posture_search_remaining = 0.5
		_plan_pose(direction,pull,allow_pre_draw)
		return
	var console := get_node_or_null("/root/RuntimeConsole")
	var trace_plan: bool = console!=null and console.is_bow_tracking_enabled(self)
	var plan_change := {}
	if trace_plan:
		var angle_change := 0.0
		for index: int in 2:
			var next: Dictionary = best.right if index==0 else best.left
			for joint_index: int in _arms[index].angles.size():
				angle_change = maxf(angle_change,absf(float(next.angles[joint_index])-float(_arms[index].angles[joint_index])))
		if angle_change>deg_to_rad(5.0) or absf(float(best.pull)-_pre_draw)>_reach*0.01 or _plan_shift.distance_to(best.shift)>0.001:
			plan_change = {"maximum_target_change_degrees":rad_to_deg(angle_change),"previous_pre_draw":_pre_draw,"previous_plan_shift":_plan_shift}
	_arms[0].angles = best.right.angles
	_arms[1].angles = best.left.angles
	_pose_feasible = best.feasible
	_solver_error = best.error
	_plan_shift = best.shift
	if allow_pre_draw and not reuse_posture:
		_pre_draw = best.pull
		_pose_pull = best.pull
	if best.feasible:
		_posture_locked = true
		for arm: Dictionary in _arms: arm.continuous_pose = true
	_plan_sequence += 1
	_last_plan_frame = Engine.get_physics_frames()
	if not plan_change.is_empty(): _log_bow_event(&"pose_replanned",plan_change)

func _excluded_rids() -> Array[RID]:
	var result: Array[RID] = []
	if get_parent().has_method("get_physical_body_rids"): result.append_array(get_parent().get_physical_body_rids())
	if is_instance_valid(_bow): result.append(_bow.get_string_center().get_rid())
	return result

func _shot_solution(origin: Vector3, point: Vector3, requested_speed: float) -> Dictionary:
	var gravity := ARROW.gravity_vector()
	var offset := point-origin
	# Keep some speed above the minimum ballistic solution to avoid a limiting 45-degree arc.
	var required_speed := sqrt(maxf(gravity.length()*offset.length()-gravity.dot(offset),0.0))*1.25
	return ARROW.solve_velocity(origin,point,maxf(requested_speed,required_speed),gravity)

func _prediction(target: Node3D, samples: int) -> Dictionary:
	if not is_instance_valid(target): return {"hit":false,"reason":&"invalid_target"}
	var direction := (target.global_position-_bow.global_position).slide(_plane_normal()).normalized()
	var origin := _holding_point(direction)+direction*(ARROW.HALF_LENGTH*2.0-_bow.get_rest_grip_distance()-preset.draw_reach_ratio*_reach)
	var point := target.global_position
	var solution: Dictionary = {}
	var prepare_time := _estimated_prepare_time()
	var velocity := PREDICTION.velocity(target)
	var actor := CONTEXT.character_of(target)
	if actor!=null:
		for component: Node in actor.get_children():
			if component.has_method("get_leg_parts") and component.has_method("_contact_drive_supports") and not component._contact_drive_supports(component.get_leg_parts()).is_empty():
				velocity = velocity.slide(Vector3.UP)
				break
	for iteration: int in 4:
		solution = _shot_solution(origin,point,preset.maximum_arrow_speed)
		if solution.is_empty(): return {"hit":false,"reason":&"ballistic_range"}
		point = target.global_position+velocity*(preset.draw_time+prepare_time+float(solution.time))
	if Vector3(solution.velocity).normalized().angle_to(Vector3(solution.velocity).slide(_plane_normal()).normalized())>deg_to_rad(preset.target_plane_tolerance_degrees):
		return {"hit":false,"reason":&"target_out_of_bow_plane"}
	var excluded := _excluded_rids()
	var previous := origin
	var target_actor := CONTEXT.character_of(target)
	for index: int in range(1,maxi(samples,8)+1):
		var time: float = solution.time*float(index)/maxi(samples,8)
		var position: Vector3 = origin+Vector3(solution.velocity)*time+ARROW.gravity_vector()*time*time*0.5
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(previous,position,0xFFFFFFFF,excluded))
		if not hit.is_empty() and hit.collider!=target and (target_actor==null or CONTEXT.character_of(hit.collider)!=target_actor): return {"hit":false,"reason":&"ballistic_path_blocked"}
		previous = position
	return {"hit":true,"reason":&"predicted_arrow_path","point":point,"velocity":solution.velocity,"time":solution.time,"prepare_time":prepare_time,"target_velocity":velocity,"confidence":0.8}

func _estimated_prepare_time() -> float:
	var travel := _position_error/maxf(_reach*2.0,0.1)
	if not is_finite(travel): travel = _observed_prepare_time
	var turning := _aim_error/deg_to_rad(preset.aim_transition_speed_degrees)
	return clampf(maxf(_observed_prepare_time,maxf(travel,turning))+preset.settle_time,preset.settle_time,maxf(preset.maximum_prepare_time-preset.draw_time,preset.settle_time))

func predict_npc_attack(action: StringName, target: Node3D, _charge: float, samples: int = 24, _margin: float = 0.1) -> Dictionary:
	if not has_npc_attack(action): return {"hit":false,"reason":&"bow_unavailable"}
	if not is_npc_target_in_attack_range(action,target): return {"hit":false,"reason":&"out_of_range"}
	return _prediction(target,samples)

func try_start_npc_attack(action: StringName, target: Node3D, _charge: float) -> bool:
	if not has_npc_attack(action) or is_npc_attack_active() or _cooldown>0.0: return false
	if not is_npc_target_in_attack_range(action,target): return false
	var prediction := _prediction(target,24)
	if not prediction.hit: last_reason = prediction.reason; return false
	locked_point = prediction.point
	_locked_prediction = prediction.duplicate()
	_attack_target = target
	attacks_started += 1
	phase = Phase.PREPARING
	_elapsed = 0.0
	_phase_elapsed = 0.0
	_stable_elapsed = 0.0
	last_reason = &"preparing"
	_solve_remaining = 0.0
	_log_bow_event(&"attack_started",{"previous_phase":"IDLE"})
	return true

func _update_pose(delta: float) -> void:
	var heading := Vector3.RIGHT
	var movement := get_parent().get_node_or_null("GeneratedLegStepMovementController3D")
	if movement != null: heading = Vector3.RIGHT.rotated(Vector3.UP,movement._get_physical_heading_yaw())
	var normal := _plane_normal()
	_desired_direction = heading.slide(normal).normalized()
	if phase in [Phase.PREPARING,Phase.DRAWING]:
		# Aim from the planned holding frame so hand wobble cannot feed back into its own target.
		var origin := _holding_point(_desired_direction)+_desired_direction*(ARROW.HALF_LENGTH*2.0-_bow.get_rest_grip_distance()-_full_draw)
		var solution := _shot_solution(origin,locked_point,preset.maximum_arrow_speed)
		if not solution.is_empty(): _desired_direction = Vector3(solution.velocity).slide(normal).normalized()
	var progress := smoothstep(0.0,1.0,clampf(_phase_elapsed/maxf(preset.recovery_time,0.01),0.0,1.0))
	if phase==Phase.RECOVERING:
		var start: Vector3 = (_arms[0].anchor_body.global_basis*_recovery_start_direction).slide(normal).normalized()
		_direction = start.slerp(_desired_direction,progress).normalized()
	else:
		_direction = _direction.slide(normal).normalized()
		_direction = _direction.rotated(normal,clampf(_direction.signed_angle_to(_desired_direction,normal),-deg_to_rad(preset.aim_transition_speed_degrees)*delta,deg_to_rad(preset.aim_transition_speed_degrees)*delta))
	_motor.pose_frequency = preset.pose_frequency
	_motor.pose_damping_ratio = preset.pose_damping_ratio
	_motor.maximum_pose_acceleration = preset.maximum_pose_acceleration
	_motor.maximum_pose_torque = preset.maximum_pose_torque
	var draw := smoothstep(0.0,1.0,clampf(_phase_elapsed/preset.draw_time,0.0,1.0)) if phase==Phase.DRAWING else 0.0
	_pre_draw = clampf(_pre_draw,0.0,_full_draw*preset.posture_draw_ratio)
	if phase==Phase.DRAWING: _pose_pull = lerpf(_draw_start_pull,_full_draw,draw)
	elif phase==Phase.RECOVERING: _pose_pull = lerpf(_recovery_start_pull,_pre_draw,progress)
	else: _pose_pull = move_toward(_pose_pull,_pre_draw,_full_draw/maxf(preset.draw_time,0.1)*delta)
	_solve_remaining -= delta
	_posture_search_remaining -= delta
	if _solve_remaining<=0.0:
		_plan_pose(_direction,_pose_pull,phase==Phase.IDLE or phase==Phase.PREPARING)
		_solve_remaining = 0.08+float(get_instance_id()%7)*0.004
	_bow.draw_target_distance = _pose_pull
	if phase==Phase.RECOVERING:
		if _phase_elapsed<preset.string_release_time: _bow.draw_target_distance = -1.0
		else:
			if _recovery_string_origin<0.0: _recovery_string_origin = clampf(_draw_ratio,0.0,1.0)*_full_draw
			var rejoin := smoothstep(0.0,1.0,clampf((_phase_elapsed-preset.string_release_time)/maxf(preset.recovery_time-preset.string_release_time,0.1),0.0,1.0))
			_bow.draw_target_distance = lerpf(_recovery_string_origin,_pre_draw,rejoin)
	for index: int in 2:
		var targets := PLANAR.poses(_arms[index],_arms[index].angles)
		var end := PLANAR.endpoint(_arms[index],targets)
		if index==0: _right_target = end
		else: _left_target = end
		PLANAR.apply(_arms[index],_motor,delta,deg_to_rad(preset.joint_target_speed_degrees))
	_position_error = maxf(_arms[0].socket.global_position.distance_to(_right_target),_arms[1].socket.global_position.distance_to(PLANAR.project(_arms[1],_bow.get_string_center().global_position)))
	_aim_error = acos(clampf(_bow.global_basis.x.normalized().dot(_desired_direction),-1.0,1.0))
	_relative_bow_speed = (_arms[0].hand.angular_velocity-_arms[0].anchor_body.angular_velocity).length()
	_maximum_joint_speed = 0.0
	for arm: Dictionary in _arms:
		for link: Dictionary in arm.pose_chain: _maximum_joint_speed = maxf(_maximum_joint_speed,Vector3(link.get("relative_angular_velocity",Vector3.ZERO)).length())
	_draw_ratio = clampf((_bow.get_draw_target(0.0)-_bow.get_string_center().global_position).dot(_bow.global_basis.x.normalized())/maxf(preset.draw_reach_ratio*_reach,0.001),0.0,1.0)
	_charge_draw_ratio = clampf((_draw_ratio*_full_draw-_pre_draw)/maxf(_full_draw-_pre_draw,0.001),0.0,1.0)
	if is_instance_valid(_nocked): _nocked.global_transform = Transform3D(_bow.global_basis.orthonormalized(),_bow.get_string_center().global_position+_bow.global_basis.x.normalized()*ARROW.HALF_LENGTH)

func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0,_cooldown-delta)
	var inventory := _inventory()
	var item: Variant = inventory.get_equipped_item() if inventory!=null else null
	if not enabled or not _controls_enabled or preset==null or not item is BOW or (get_parent().has_method("is_temporarily_ragdolled") and get_parent().is_temporarily_ragdolled()):
		if not _arms.is_empty(): _release()
		return
	if item!=_bow or not _valid():
		_release()
		if not _capture(item): return
	if _arms[0].hand.freeze or _arms[1].hand.freeze: return
	if phase in [Phase.PREPARING,Phase.DRAWING] and is_instance_valid(_attack_target) and not is_npc_target_in_attack_range(&"bow_shoot",_attack_target):
		cancel_npc_attack(&"target_too_close")
		last_reason = &"target_too_close"
	_update_pose(delta)
	if phase==Phase.IDLE: return
	_elapsed += delta
	_phase_elapsed += delta
	if phase in [Phase.PREPARING,Phase.DRAWING] and _elapsed>preset.maximum_prepare_time:
		cancel_npc_attack(&"pose_timeout")
		last_reason = &"pose_timeout"
		_cooldown = preset.cooldown
		return
	var ready := _pose_feasible and _position_error<=preset.pose_tolerance_ratio*_reach and _aim_error<=deg_to_rad(preset.aim_tolerance_degrees)
	var settled := ready and _relative_bow_speed<=deg_to_rad(preset.settled_angular_speed_degrees) and _maximum_joint_speed<=deg_to_rad(preset.settled_angular_speed_degrees)*2.0
	_stable_elapsed = _stable_elapsed+delta if settled else 0.0
	if phase==Phase.PREPARING and _stable_elapsed>=preset.settle_time and settled:
		_last_prepare_duration = _phase_elapsed
		_observed_prepare_time = lerpf(_observed_prepare_time,_phase_elapsed,0.5)
		_draw_start_pull = _pose_pull
		phase = Phase.DRAWING
		_phase_elapsed = 0.0
		_stable_elapsed = 0.0
		last_reason = &"drawing"
		_log_bow_event(&"drawing_started",{"previous_phase":"PREPARING"})
		var ammunition := _bow.ammunition_scene.instantiate()
		_nocked = ammunition as ARROW
		if _nocked==null:
			ammunition.free()
			cancel_npc_attack(&"invalid_ammunition")
			last_reason = &"invalid_ammunition"
			return
		_nocked.freeze = true
		_nocked.collision_layer = 0
		_nocked.collision_mask = 0
		_nocked.can_be_picked_up = false
		add_child(_nocked)
	elif phase==Phase.DRAWING and _phase_elapsed>=preset.draw_time and settled and _stable_elapsed>=preset.settle_time and _charge_draw_ratio>=0.8:
		_fire()
	elif phase==Phase.RECOVERING and _phase_elapsed>=preset.recovery_time and settled and _stable_elapsed>=preset.settle_time:
		phase = Phase.IDLE
		last_reason = &"recovered"
		_log_bow_event(&"recovery_finished",{"previous_phase":"RECOVERING"})
	elif phase==Phase.RECOVERING and _phase_elapsed>=maxf(preset.maximum_recovery_time,preset.recovery_time+0.5):
		cancel_npc_attack(&"recovery_timeout")
		last_reason = &"recovery_timeout"
		_cooldown = preset.cooldown

func _fire() -> void:
	var origin := _bow.get_string_center().global_position+_bow.global_basis.x.normalized()*ARROW.HALF_LENGTH*2.0
	var solution := _shot_solution(origin,locked_point,preset.arrow_speed(_draw_ratio))
	if solution.is_empty(): cancel_npc_attack(&"ballistic_range"); last_reason = &"ballistic_range"; return
	var arrow := _nocked
	_nocked = null
	arrow.reparent(CONTEXT.level(self),true)
	arrow.global_basis = Basis(Quaternion(Vector3.RIGHT,Vector3(solution.velocity).normalized()))
	arrow.global_position = origin-arrow.global_basis.x*ARROW.HALF_LENGTH
	var flight_lifetime := maxf(preset.arrow_lifetime,float(solution.time)*1.25+0.5)
	arrow.launch(get_parent(),solution.velocity,flight_lifetime)
	arrow.impacted.connect(_on_impact)
	last_shot = {"origin":origin,"velocity":solution.velocity,"speed":Vector3(solution.velocity).length(),"draw_ratio":_draw_ratio,"locked_point":locked_point,"prepare_and_draw_time":_elapsed,"prepare_time":_last_prepare_duration,"predicted_prepare_time":_locked_prediction.get("prepare_time",0.0),"flight_time":solution.time,"lifetime":flight_lifetime,"aim_error_degrees":rad_to_deg(_aim_error),"relative_angular_speed_degrees":rad_to_deg(_relative_bow_speed)}
	shots_fired += 1
	shot_fired.emit(arrow)
	_recovery_start_direction = _arms[0].anchor_body.global_basis.inverse()*_direction
	_recovery_start_pull = _pose_pull
	_recovery_string_origin = -1.0
	_stable_elapsed = 0.0
	phase = Phase.RECOVERING
	_phase_elapsed = 0.0
	_cooldown = preset.cooldown
	_bow.draw_target_distance = -1.0
	last_reason = &"fired"
	_log_bow_event(&"shot_fired",{"previous_phase":"DRAWING"})

func _on_impact(target: Object, damage: float, impulse: float) -> void:
	hits += 1
	if damage>0.0: damaging_hits += 1
	last_impact = {"target":str(target.get_path()) if target is Node and target.is_inside_tree() else "removed","damage":damage,"impulse":impulse}

func get_attack_diagnostics() -> Dictionary:
	var joints: Array[Dictionary] = []
	for arm: Dictionary in _arms:
		if not is_instance_valid(arm.anchor_body) or not arm.anchor_body.is_inside_tree(): continue
		var parent: RigidBody3D = arm.anchor_body
		for index: int in arm.pose_chain.size():
			var link: Dictionary = arm.pose_chain[index]
			if not is_instance_valid(link.body): continue
			var requested: Vector3 = link.get("requested_torque",Vector3.ZERO)
			var applied: Vector3 = link.get("last_torque",Vector3.ZERO)
			joints.append({"body":str(link.body.name),"parent":str(parent.name),"target_degrees":rad_to_deg(arm.angles[index]),"command_degrees":rad_to_deg(arm.command_angles[index]),"actual_degrees":rad_to_deg(float(link.get("actual_angle",0.0))),
				"motor_physics_frame":link.get("motor_frame",-1),"angle_error_degrees":Vector3(link.get("angle_error",Vector3.ZERO))*(180.0/PI),"relative_angular_velocity":link.get("relative_angular_velocity",Vector3.ZERO),
				"requested_acceleration":link.get("requested_acceleration",Vector3.ZERO),"servo_acceleration":link.get("servo_acceleration",Vector3.ZERO),"servo_torque":link.get("servo_torque",Vector3.ZERO),"carried_servo_torque":link.get("carried_servo_torque",Vector3.ZERO),
				"requested_torque":requested,"torque":applied,"torque_limited":requested.distance_to(applied)>0.0001,"gravity_torque":link.get("gravity_torque",Vector3.ZERO),
				"anchor_gap":(parent.global_transform*Transform3D(link.parent_frame)).origin.distance_to((link.body.global_transform*Transform3D(link.child_frame)).origin)})
			parent = link.body
	var pose := {}
	if _valid():
		var torso: RigidBody3D = _arms[0].anchor_body
		var holder: RigidBody3D = _arms[0].hand
		var direction := _bow.global_basis.x.normalized()
		pose = {"bow_position":_bow.global_position,"bow_forward":direction,"desired_forward":_desired_direction,"command_forward":_direction,
			"bow_relative_pitch_degrees":rad_to_deg(atan2(direction.dot(torso.global_basis.y),direction.dot(torso.global_basis.x))),
			"desired_relative_pitch_degrees":rad_to_deg(atan2(_desired_direction.dot(torso.global_basis.y),_desired_direction.dot(torso.global_basis.x))),
			"command_relative_pitch_degrees":rad_to_deg(atan2(_direction.dot(torso.global_basis.y),_direction.dot(torso.global_basis.x))),
			"signed_aim_error_degrees":rad_to_deg(atan2(_plane_normal().dot(_desired_direction.cross(direction)),_desired_direction.dot(direction))),
			"holder_angular_velocity":holder.angular_velocity,"torso_angular_velocity":torso.angular_velocity,"relative_angular_velocity":holder.angular_velocity-torso.angular_velocity,"torso_velocity":torso.linear_velocity,
			"primary_grip_error":_arms[0].socket.global_position.distance_to(_bow.to_global(_bow.attachment_local_position)),
			"left_string_error":_arms[1].socket.global_position.distance_to(PLANAR.project(_arms[1],_bow.get_string_center().global_position)),
			"left_pose_error":_arms[1].socket.global_position.distance_to(_left_target)}
	return {"character":str(get_parent().get_path()),"physics_frame":Engine.get_physics_frames(),"time_ms":Time.get_ticks_msec(),"phase":Phase.keys()[phase],"reason":last_reason,"elapsed":_elapsed,"phase_elapsed":_phase_elapsed,"plan_sequence":_plan_sequence,"plan_physics_frame":_last_plan_frame,"plan_shift":_plan_shift,"pose":pose,
		"posture_locked":_posture_locked,"stable_elapsed":_stable_elapsed,"relative_bow_speed_degrees":rad_to_deg(_relative_bow_speed),"maximum_joint_speed_degrees":rad_to_deg(_maximum_joint_speed),"pose_pull":_pose_pull,"estimated_prepare_time":_estimated_prepare_time() if preset!=null else 0.0,"locked_prediction":_locked_prediction,
		"settings":{"pose_frequency":preset.pose_frequency,"pose_damping_ratio":preset.pose_damping_ratio,"maximum_pose_acceleration":preset.maximum_pose_acceleration,"maximum_pose_torque":preset.maximum_pose_torque,"joint_target_speed_degrees":preset.joint_target_speed_degrees,"recovery_time":preset.recovery_time,"draw_time":preset.draw_time,
			"aim_tolerance_degrees":preset.aim_tolerance_degrees,"target_plane_tolerance_degrees":preset.target_plane_tolerance_degrees,"aim_transition_speed_degrees":preset.aim_transition_speed_degrees,"settled_angular_speed_degrees":preset.settled_angular_speed_degrees,"settle_time":preset.settle_time,"string_release_time":preset.string_release_time,"maximum_prepare_time":preset.maximum_prepare_time,"maximum_recovery_time":preset.maximum_recovery_time} if preset!=null else {},
		"position_error":_position_error,"aim_error_degrees":rad_to_deg(_aim_error),"draw_ratio":_draw_ratio,
		"maximum_range_unlimited":true,"minimum_range":get_npc_attack_minimum_range(&"bow_shoot"),
		"charge_draw_ratio":_charge_draw_ratio,"posture_draw_distance":_pre_draw,"maximum_draw_distance":_full_draw,"planar_pose_feasible":_pose_feasible,"planar_solver_error":_solver_error,"left_target":_left_target,
		"string":_bow.get_string_diagnostics() if is_instance_valid(_bow) else {},
		"arm_joints":joints,
		"locked_point":locked_point,"attempts":attacks_started,"cancelled":cancelled_attacks,"shots":shots_fired,"impacts":hits,"damaging_hits":damaging_hits,"cooldown":_cooldown,"last_shot":last_shot,"last_impact":last_impact,
		"right_target":_right_target,"right_socket":_arms[0].socket.global_position if _valid() else Vector3.ZERO,
		"left_socket":_arms[1].socket.global_position if _valid() else Vector3.ZERO}
