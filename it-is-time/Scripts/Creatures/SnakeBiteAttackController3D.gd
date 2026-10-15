extends Node3D

const DATA = preload("res://Scripts/Creatures/SnakeBiteAttackData.gd")
const PREDICTION = preload("res://Scripts/Creatures/NPCAttackPrediction3D.gd")
const HITBOX = preload("res://Scripts/Items/SnakeBiteHitbox3D.gd")
const PLAYER = preload("res://Scripts/Player/PlayerControlContext.gd")
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const ACTION: StringName = &"snake_lunge_bite"

@export var enabled := true
@export var data: DATA = preload("res://Resources/Attacks/SnakeBite.tres")
@export var diagnostic_logging := false
var movement: Node3D
var head: PhysicalBodyPart3D
var jaw: PhysicalBodyPart3D
var _jaw_joint: Generic6DOFJoint3D
var _jaw_rest := Quaternion.IDENTITY
var _jaw_anchor := Vector3.ZERO
var _joint_state: Dictionary = {}
var _mouth_collision_pairs: Array[Dictionary] = []
var _links: Array[Dictionary] = []
var _root_rest := Transform3D.IDENTITY
var _head_size := Vector3.ONE
var _head_forward_local := Vector3.RIGHT
var _head_rest_forward := Vector3.RIGHT
var _head_forward_source: StringName = &"local_x"
var _head_aim_error_degrees := 0.0
var _chain_length := 0.0
var _scale := 1.0
var _angles := PackedFloat32Array()
var _plan: Dictionary = {}
var _prediction_cache: Dictionary = {}
var _cached_plan: Dictionary = {}
var _plan_target: Node3D
var _plan_frame := -1000
var _plan_target_position := Vector3.ZERO
var _plan_origin := Vector3.ZERO
var _plan_heading := Vector3.RIGHT
var _plan_target_velocity := Vector3.ZERO
var _plan_aligned := false
var _plan_preparation_time := -1.0
var _velocity_target: Node3D
var _velocity_frame := -1
var _filtered_target_velocity := Vector3.ZERO
var _target_supported := false
var _alignment_elapsed := 0.0
var _target: PhysicalBodyPart3D
var _weapon: HITBOX
var _phase: StringName = &"idle"
var _elapsed := 0.0
var _total_elapsed := 0.0
var _cooldown := 0.0
var _log_elapsed := 0.0
var _character_enabled := true
var _origin := Vector3.ZERO
var _forward := Vector3.RIGHT
var _recovery_angles := PackedFloat32Array()
var _recovery_progress := 0.0
var _jaw_angle := 0.0
var _jaw_error := 0.0
var _jaw_torque := Vector3.ZERO
var _head_error := 0.0
var _last_reason: StringName = &"none"
var _last_hits := 0
var _last_contacts := 0
var _last_impulse := 0.0
var _perf := preload("res://Scripts/Debug/ControlPerformanceStats.gd").new()

func _ready() -> void:
	process_physics_priority = -35
	add_to_group(&"snake_attack_controllers")
	_perf.register(self)
	var console := get_node_or_null("/root/RuntimeConsole")
	if console != null: diagnostic_logging = console.is_snake_attack_tracking_enabled(get_parent())
	call_deferred("_initialize_parts")

func _initialize_parts() -> void:
	if _links.is_empty(): refresh_physics_query_cache()

func _alive(body: Node) -> bool:
	return is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion() and not body.is_broken

func refresh_physics_query_cache() -> void:
	cancel_action(&"regenerated")
	movement = get_parent().get_node_or_null("SnakeMovementController3D")
	head = null
	jaw = null
	_jaw_joint = null
	_links.clear()
	_chain_length = 0.0
	_prediction_cache.clear()
	_cached_plan = {}
	_velocity_target = null
	_velocity_frame = -1
	var container := get_parent().get_node_or_null("GeneratedParts")
	if movement == null or container == null or movement._belly.is_empty(): return
	var previous: PhysicalBodyPart3D = movement._belly[-1].body
	_root_rest = movement._belly[-1].rest
	var previous_pose := _root_rest
	for row: Dictionary in movement._parts:
		if row.belly: continue
		var child: PhysicalBodyPart3D = row.body
		var joint := _find_joint(container, previous, child)
		if joint == null: _links.clear(); return
		var frame_key: StringName = &"generated_joint_frame_a" if joint.get_node(joint.node_a) == previous else &"generated_joint_frame_b"
		var anchor: Transform3D = joint.get_meta(frame_key)
		var child_pose: Transform3D = row.rest
		_links.append({"body":child,"joint":joint,"relative":previous_pose.affine_inverse()*child_pose,
			"rest_pitch":atan2(child_pose.basis.x.y,child_pose.basis.x.x),
			"pivot":anchor.origin,
			"lower":joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)*0.9,
			"upper":joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)*0.9})
		_chain_length += previous_pose.origin.distance_to(child_pose.origin)
		previous = child
		previous_pose = child_pose
		if child.get_meta(&"generated_role", "") == "Head": head = child
	for node: Node in container.get_children():
		if node is PhysicalBodyPart3D and node.get_meta(&"generated_role", "") == "Jaw": jaw = node
	if not _alive(head) or not _alive(jaw): return
	_jaw_joint = _find_joint(container, head, jaw)
	if _jaw_joint == null: return
	var head_is_a: bool = _jaw_joint.get_node(_jaw_joint.node_a) == head
	_jaw_anchor = Transform3D(_jaw_joint.get_meta(&"generated_joint_frame_a" if head_is_a else &"generated_joint_frame_b")).origin
	_jaw_rest = _jaw_joint.get_meta(&"generated_rest_b_relative_a")
	if not head_is_a: _jaw_rest = _jaw_rest.inverse()
	_head_size = GEOMETRY.bounds(head).size
	_head_forward_local = Vector3.RIGHT
	_head_forward_source = &"local_x"
	var inlet := head.get_node_or_null("JointIn") as Node3D
	var outlet := head.get_node_or_null("JointOut") as Node3D
	if inlet != null and outlet != null:
		var direction := (outlet.position-inlet.position).slide(Vector3.BACK)
		if not direction.is_zero_approx():
			_head_forward_local = direction.normalized()
			_head_forward_source = &"joint_in_to_out"
	_head_rest_forward = (previous_pose.basis*_head_forward_local).normalized()
	_log(&"head_reference",{"source":_head_forward_source,"local_forward":_head_forward_local,"authored_forward":_head_rest_forward})
	_scale = _chain_length / data.reference_chain_length if data != null else 1.0
	_angles.resize(_links.size())
	_angles.fill(0.0)

func _find_joint(container: Node, a: Node, b: Node) -> Generic6DOFJoint3D:
	for candidate: Node in container.get_node("Joints").get_children():
		if not candidate is Generic6DOFJoint3D: continue
		var first: Node = candidate.get_node_or_null(candidate.node_a)
		var second: Node = candidate.get_node_or_null(candidate.node_b)
		if (first == a and second == b) or (first == b and second == a): return candidate
	return null

func has_npc_attack(action_id: StringName) -> bool:
	if action_id != ACTION or not enabled or not _character_enabled or data == null or not data.enabled or not data.is_valid(): return false
	if not _alive(head) or not _alive(jaw) or not is_instance_valid(_jaw_joint) or _jaw_joint.is_queued_for_deletion() or _links.is_empty() or movement == null or not movement.enabled or not movement.locomotion_enabled or not movement._character_enabled: return false
	var ai := get_parent().get_node_or_null("NPCStateMachine3D")
	return ai != null and ai.enabled and ai.attack_execution_enabled and not get_parent().is_temporarily_ragdolled() and get_parent().is_combat_alive() and movement.command_source == null

func _valid_target(target: Node3D) -> bool:
	if not is_inside_tree() or not target is PhysicalBodyPart3D or not _alive(target) or target.get_world_3d() != get_world_3d(): return false
	var actor := PLAYER.character_of(target)
	return actor != null and actor != get_parent() and actor.is_combat_alive() and actor.get_faction_id() != get_parent().get_faction_id()

func _time_scale() -> float: return sqrt(maxf(_scale, 0.01))
func _speed() -> float: return data.burst_speed * _time_scale()
func _mouth_offset() -> Vector3: return _head_size * data.damage_center_ratio
func _box() -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = (_head_size * data.damage_box_ratio).max(Vector3.ONE*0.02)
	return shape

func _root_pose() -> Transform3D:
	return movement.get_attack_root_pose(_root_rest) if is_instance_valid(movement) else _root_rest

## Pure forward kinematics: the live physical root is read once by the caller.
func _chain_poses(angles: PackedFloat32Array, root_pose: Transform3D) -> Array[Transform3D]:
	_perf.count(&"fk_evaluations")
	var result: Array[Transform3D] = []
	var parent_pose := root_pose
	for index: int in _links.size():
		var link: Dictionary = _links[index]
		var rotation := Basis(Vector3.BACK,angles[index])
		parent_pose = Transform3D(parent_pose.basis*rotation*Basis(link.relative.basis),parent_pose*(Vector3(link.pivot)+rotation*(Vector3(link.relative.origin)-Vector3(link.pivot))))
		result.append(parent_pose)
	return result

func _poses(angles: PackedFloat32Array, root_pose: Variant = null) -> Dictionary:
	var root: Transform3D = _root_pose() if root_pose == null else root_pose
	var chain := _chain_poses(angles,root)
	var result: Dictionary = {}
	for index: int in _links.size(): result[_links[index].body] = chain[index]
	return result

func _rotate_chain(poses: Array[Transform3D], index: int, pivot: Vector3, axis: Vector3, angle: float) -> void:
	if angle == 0.0: return
	var rotation := Basis(axis,angle)
	# A joint change rotates only its downstream rigid transforms about the same world pivot.
	for downstream: int in range(index,poses.size()):
		var pose := poses[downstream]
		poses[downstream] = Transform3D(rotation*pose.basis,pivot+rotation*(pose.origin-pivot))

func _solve(goal: Vector3, pitch: float, initial: PackedFloat32Array, aim_weight: float = 0.25, root_pose: Variant = null) -> PackedFloat32Array:
	var started := _perf.start()
	var root: Transform3D = _root_pose() if root_pose == null else root_pose
	var angles := initial.duplicate()
	var poses := _chain_poses(angles,root)
	var aim_length := maxf(_head_size.x*2.0,_chain_length*0.3)
	var aim_goal := goal+Vector3(cos(pitch),sin(pitch),0)*aim_length
	for iteration: int in 16:
		_perf.count(&"ik_iterations")
		for index: int in range(_links.size()-1, -1, -1):
			var parent_pose: Transform3D = root if index == 0 else poses[index-1]
			var pivot: Vector3 = parent_pose * Vector3(_links[index].pivot)
			var axis := parent_pose.basis.z.normalized()
			var tip: Vector3 = poses[-1].origin-pivot
			var desired := goal-pivot
			var tip_pose := poses[-1]
			var aim := tip_pose.origin+tip_pose.basis.x*aim_length-pivot
			var desired_aim := aim_goal-pivot
			var cross_sum := axis.dot(tip.cross(desired)+aim.cross(desired_aim)*aim_weight)
			var dot_sum := tip.slide(axis).dot(desired.slide(axis))+aim.slide(axis).dot(desired_aim.slide(axis))*aim_weight
			var angle := atan2(cross_sum,dot_sum)
			var lower: float = _links[index].lower-angles[index]
			var upper: float = _links[index].upper-angles[index]
			if index > 0 and index < floori(_links.size()*data.preserved_root_ratio):
				lower = maxf(lower,float(_links[index].lower)*0.3-angles[index])
				upper = minf(upper,float(_links[index].upper)*0.3-angles[index])
			var accumulated := 0.0
			for downstream: int in angles.size():
				accumulated += angles[downstream]
				if downstream < index: continue
				var absolute: float = _links[downstream].rest_pitch+accumulated
				lower = maxf(lower,-deg_to_rad(80.0)-absolute)
				upper = minf(upper,deg_to_rad(150.0)-absolute)
			if lower <= upper:
				var previous := angles[index]
				angles[index] += clampf(angle*0.75,lower,upper)
				_rotate_chain(poses,index,pivot,axis,angles[index]-previous)
	_perf.finish(&"ik_solve",started)
	return angles

## Aim the visual mouth axis with the tip joints; retain the root-side S and every saved limit.
func _aim_head(initial: PackedFloat32Array, target_point: Vector3, root_pose: Variant = null) -> PackedFloat32Array:
	var root: Transform3D = _root_pose() if root_pose == null else root_pose
	var angles := initial.duplicate()
	var poses := _chain_poses(angles,root)
	var first := maxi(_links.size()-4,floori(_links.size()*data.preserved_root_ratio))
	for iteration: int in 2:
		for index: int in range(_links.size()-1,first-1,-1):
			var pose := poses[-1]
			var parent_pose: Transform3D = root if index == 0 else poses[index-1]
			var pivot: Vector3 = parent_pose*Vector3(_links[index].pivot)
			var axis := parent_pose.basis.z.normalized()
			var forward := (pose.basis*_head_forward_local).normalized()
			var desired := (target_point-pose.origin).normalized()
			if desired.is_zero_approx(): return angles
			var error := atan2(axis.dot(forward.cross(desired)),forward.slide(axis).dot(desired.slide(axis)))
			var previous := angles[index]
			angles[index] = clampf(previous+error,_links[index].lower,_links[index].upper)
			_rotate_chain(poses,index,pivot,axis,angles[index]-previous)
	return angles

func _target_velocity(target: PhysicalBodyPart3D) -> Vector3:
	var frame := Engine.get_physics_frames()
	if _velocity_target == target and frame == _velocity_frame: return _filtered_target_velocity
	var velocity := PREDICTION.velocity(target)
	_target_supported = false
	var actor := PLAYER.character_of(target)
	for part: PhysicalBodyPart3D in actor._get_physical_body_parts():
		if not part.is_broken and not part.get_support_surface_contact().is_empty():
			_target_supported = true
			break
	if not _target_supported:
		for component: Node in actor.get_children():
			if component.has_method("get_combined_adhesion_surface_normal") and not Vector3(component.get_combined_adhesion_surface_normal()).is_zero_approx():
				_target_supported = true
				break
	# Contact-supported gait bobbing is not a constant vertical velocity for several seconds.
	if _target_supported: velocity.y = 0.0
	if _velocity_target != target or _velocity_frame < 0:
		_filtered_target_velocity = velocity
	else:
		var elapsed := float(frame-_velocity_frame)/Engine.physics_ticks_per_second
		_filtered_target_velocity = _filtered_target_velocity.lerp(velocity,1.0-exp(-elapsed/maxf(data.burst_response_time*2.0,0.1)))
	if _target_supported: _filtered_target_velocity.y = 0.0
	_velocity_target = target
	_velocity_frame = frame
	return _filtered_target_velocity

func _alignment(target: PhysicalBodyPart3D, aim_point: Vector3 = Vector3.INF, mouth_lateral: float = INF) -> Dictionary:
	var reference: Transform3D = movement.get_pose_reference(false)
	var center: Vector3 = movement.get_control_anchor().global_position
	if not aim_point.is_finite(): aim_point = target.global_position
	var direction := (aim_point-center).slide(Vector3.UP).normalized()
	if direction.is_zero_approx(): direction = reference.basis.x
	var lateral_offset: float = movement.get_attack_root_offset().z
	if is_finite(mouth_lateral): lateral_offset = mouth_lateral
	var distance := (aim_point-center).slide(Vector3.UP).length()
	if distance > absf(lateral_offset): direction = Basis(Vector3.UP,asin(lateral_offset/distance))*direction
	var angle := atan2(reference.basis.x.cross(direction).y,reference.basis.x.dot(direction))
	var half_width := 0.0
	var bounds := GEOMETRY.bounds(target)
	for corner: int in 8:
		half_width = maxf(half_width,absf(reference.basis.z.dot(target.to_global(bounds.get_endpoint(corner))-target.global_position)))
	var tolerance := maxf(half_width*0.6+_box().size.z*0.25,0.02*_time_scale())
	var lateral := (reference.affine_inverse()*aim_point).z-lateral_offset
	var aligned_basis := Basis(Vector3.UP,angle)*reference.basis
	var aligned := Transform3D(aligned_basis,center-aligned_basis*movement._rest_center)
	return {"reference":aligned,"forward":direction,"error":lateral,"tolerance":tolerance,
		"ready":absf(lateral)<=tolerance and absf(angle)<=deg_to_rad(data.aim_tolerance_degrees),
		"expected_duration":absf(angle)/maxf(deg_to_rad(movement.motion_data.turn_speed_degrees),0.01)+(movement.motion_data.path_transition_time if movement._path_ready else 0.0),
		"duration":absf(angle)/maxf(deg_to_rad(movement.motion_data.turn_speed_degrees),0.01)+movement.motion_data.turn_response_time*4.0+movement.motion_data.path_transition_time}

func _make_plan(target: PhysicalBodyPart3D, aligned: bool = false, preparation_remaining: float = -1.0) -> Dictionary:
	var started := _perf.start()
	_perf.count(&"plan_requests")
	var reference: Transform3D = movement.get_pose_reference()
	var velocity := _target_velocity(target)
	var preparation_time := data.preparation_time*_time_scale() if preparation_remaining < 0.0 else preparation_remaining
	var duration := data.lunge_time*_time_scale()/data.head_extension_speed_multiplier
	var alignment := _alignment(target)
	var positioning: bool = aligned and not movement.is_attack_support_locked()
	var alignment_time := float(alignment.expected_duration) if positioning and not is_npc_attack_active() else 0.0
	var contact_time := alignment_time+preparation_time+duration
	var aim := target.global_position+velocity*contact_time
	if positioning:
		alignment = _alignment(target,aim)
		reference = alignment.reference
	var root_pose := _root_pose()
	if root_pose.origin.distance_to(Transform3D(_cached_plan.get("root_pose",root_pose)).origin) < _chain_length*0.02 and _plan_aligned == aligned and _plan_target == target and is_equal_approx(_plan_preparation_time,preparation_time) and Engine.get_physics_frames()-_plan_frame < 12 and reference.basis.x.dot(_plan_heading) > cos(deg_to_rad(1.0)) and reference.origin.distance_to(_plan_origin) < _chain_length*0.02 and target.global_position.distance_to(_plan_target_position) < _chain_length*0.02 and velocity.distance_to(_plan_target_velocity) < 0.1 and not _cached_plan.is_empty():
		_perf.count(&"plan_cache_hits")
		_perf.finish(&"attack_planning",started)
		return _cached_plan
	_perf.count(&"plan_builds")
	var zeros := PackedFloat32Array()
	zeros.resize(_links.size())
	var rest: Transform3D = _poses(zeros,root_pose)[head]
	var prepare_goal := rest.origin+Vector3(-_chain_length*data.retract_ratio,_chain_length*data.lift_ratio,0)
	var preparation := zeros.duplicate()
	var strike := zeros.duplicate()
	var end_pose := rest
	var extension_distance := 0.0
	var timing_ready := false
	# A slower Head may need longer to extend. Recompute its intercept at that same time.
	# Reject a nonconverging pursuit instead of claiming a hit at an inconsistent future point.
	for iteration: int in 6:
		contact_time = alignment_time+preparation_time+duration
		aim = target.global_position+velocity*contact_time
		if positioning:
			alignment = _alignment(target,aim)
			reference = alignment.reference
		var target_point: Vector3 = reference.affine_inverse()*aim
		var pitch := atan2(target_point.y-prepare_goal.y,target_point.x-prepare_goal.x)
		preparation = _angles.duplicate() if is_zero_approx(preparation_time) and is_npc_attack_active() else _solve(prepare_goal,pitch,zeros,0.25,root_pose)
		if preparation_time > 0.0: preparation = _aim_head(preparation,target_point,root_pose)
		var prepared: Transform3D = _poses(preparation,root_pose)[head]
		var goal := target_point+Vector3(_head_size.x*data.extension_ratio,0,0)
		strike = _solve(goal-_mouth_offset(),0.0,preparation,0.25,root_pose)
		end_pose = _poses(strike,root_pose)[head]
		# The fixed root supplies no travel; prioritize the mouth position over an ideal tip pitch.
		strike = _solve(goal-end_pose.basis*_mouth_offset(),0.0,strike,0.05,root_pose)
		end_pose = _poses(strike,root_pose)[head]
		extension_distance = prepared.origin.distance_to(end_pose.origin)
		var speed_time := extension_distance/(_speed()*data.head_extension_speed_multiplier)
		if speed_time <= duration+0.001:
			timing_ready = true
			break
		if iteration < 5: duration = speed_time
	_cached_plan = {"preparation":preparation,"strike":strike,"distance":extension_distance,"duration":duration,"extension_duration":duration,
		"limit":duration+data.lunge_extra_wait*_time_scale(),"alignment_duration":float(alignment.duration),"alignment_time":alignment_time,
		"preparation_time":preparation_time,"contact_time":contact_time,"timing_ready":timing_ready,"target_velocity":velocity,"target_supported":_target_supported,
		"reference":reference,"root_pose":root_pose,"forward":reference.basis.x.normalized(),"speed":_speed()*data.head_extension_speed_multiplier,
		"aim":aim,"reach":(reference*(end_pose*_mouth_offset())-movement.get_control_anchor().global_position).slide(Vector3.UP).length(),
		"pose_error":reference*(end_pose*_mouth_offset())-aim}
	_plan_target = target
	_plan_frame = Engine.get_physics_frames()
	_plan_target_position = target.global_position
	_plan_origin = reference.origin
	_plan_heading = reference.basis.x
	_plan_target_velocity = velocity
	_plan_aligned = aligned
	_plan_preparation_time = preparation_time
	_perf.finish(&"attack_planning",started)
	return _cached_plan

func uses_dynamic_npc_attack_range(_action_id: StringName) -> bool: return true
func uses_navigation_attack_gate() -> bool: return true
func get_npc_attack_minimum_range(_action_id: StringName) -> float: return 0.0
func get_npc_attack_distance_tolerance(_action_id: StringName) -> float: return maxf(_head_size.x*0.05, 0.1)
func get_npc_attack_maximum_range(_action_id: StringName, _target_node: Node3D = null) -> float:
	if not _alive(head) or movement == null or data == null: return 0.0
	var root: Vector3 = movement.get_pose_reference()*movement.get_attack_root_pose(_root_rest).origin
	return root.distance_to(movement.get_control_anchor().global_position)+_chain_length+_head_size.length()

func get_npc_attack_preferred_distance(_action_id: StringName, target: Node3D) -> float:
	if not _valid_target(target) or _links.is_empty() or data == null or not data.is_valid(): return 5.0
	var started := _perf.start()
	var maximum := get_npc_attack_maximum_range(ACTION,target)
	if target.global_position.distance_to(movement.get_control_anchor().global_position) > maximum:
		# Cross into the conservative reach envelope before reserving an exact IK stand-off.
		_perf.count(&"coarse_range_estimates")
		_perf.finish(&"attack_range_estimate",started)
		return maxf(maximum*0.8,_head_size.x)
	var plan := _make_plan(target,true)
	_perf.finish(&"attack_range_estimate",started)
	return maxf(float(plan.reach)-Vector3(plan.target_velocity).dot(plan.forward)*float(plan.contact_time),_head_size.x)

func is_npc_target_in_attack_range(action_id: StringName, target: Node3D) -> bool:
	return action_id == ACTION and _valid_target(target) and movement != null and target.global_position.distance_to(movement.get_control_anchor().global_position) <= get_npc_attack_maximum_range(action_id,target)

func predict_npc_attack(action_id: StringName, target: Node3D, _charge: float, samples: int = 16, margin: float = 0.1, completing_alignment: bool = false, preparation_remaining: float = -1.0) -> Dictionary:
	if not has_npc_attack(action_id) or not _valid_target(target): return {"hit":false,"reason":&"unavailable_or_invalid_target"}
	if movement.is_connection_recovering(): return {"hit":false,"reason":&"connections_recovering"}
	if (is_npc_attack_active() and not completing_alignment) or _cooldown > 0.0: return {"hit":false,"reason":&"busy_or_cooldown"}
	if not completing_alignment and not is_npc_target_in_attack_range(action_id,target):
		_perf.count(&"prediction_range_rejects")
		return {"hit":false,"reason":&"outside_fixed_root_reach"}
	var grounded := 0
	for row: Dictionary in movement._belly:
		if movement._live(row) and not row.body.get_support_surface_contact().is_empty(): grounded += 1
	if grounded == 0: return {"hit":false,"reason":&"no_ground_support"}
	var key := target.get_instance_id()
	var cached: Dictionary = _prediction_cache.get(key, {})
	if cached.get("frame", -1) == Engine.get_physics_frames(): return cached.result
	_prediction_cache.clear()
	var plan := _make_plan(target,true,preparation_remaining)
	var alignment := _alignment(target,plan.aim)
	var result: Dictionary = {"hit":false,"reason":&"snake_sweep_misses","plan":plan}
	if not plan.timing_ready:
		result.reason = &"intercept_time_unstable"
	elif Vector3(plan.pose_error).length() > _head_size.length()+GEOMETRY.bounds(target).size.length():
		result.reason = &"outside_fixed_root_reach"
	else:
		var sweep_started := _perf.start()
		var shape := _box()
		var excluded: Array[RID] = []
		excluded.assign(get_parent().get_physical_body_rids())
		excluded.append_array(PLAYER.character_of(target).get_physical_body_rids())
		for index: int in range(clampi(samples,8,24)):
			var progress := float(index)/float(clampi(samples,8,24)-1)
			var elapsed := float(plan.limit)*progress
			var pose: Transform3D = plan.reference*_poses(_blend(plan.preparation,plan.strike,smoothstep(0.0,float(plan.extension_duration),elapsed)),plan.root_pose)[head]
			pose.origin = pose*_mouth_offset()
			var time := float(plan.alignment_time)+float(plan.preparation_time)+elapsed
			_perf.count(&"prediction_shape_queries")
			if PREDICTION.terrain_blocked(get_world_3d().direct_space_state,shape,pose,excluded):
				result.reason = &"terrain_blocks_bite"
				break
			var query_pose := pose
			query_pose.origin -= Vector3(plan.target_velocity)*time
			_perf.count(&"prediction_shape_queries")
			if PREDICTION.target_hit(get_world_3d().direct_space_state,shape,query_pose,target,0.0,margin):
				result.merge({"hit":true,"reason":&"predicted_snake_bite","confidence":0.85,"contact_time":time,
					"requires_alignment":not alignment.ready or movement._path_ready},true)
				break
		_perf.finish(&"prediction_sweep",sweep_started)
	_prediction_cache[key] = {"frame":Engine.get_physics_frames(),"result":result}
	return result

func _blend(a: PackedFloat32Array, b: PackedFloat32Array, weight: float) -> PackedFloat32Array:
	var result := a.duplicate()
	for index: int in result.size(): result[index] = lerpf(a[index],b[index],clampf(weight,0.0,1.0))
	return result

func try_start_npc_attack(action_id: StringName, target: Node3D, charge: float) -> bool:
	var prediction := predict_npc_attack(action_id,target,charge)
	if not prediction.get("hit",false): return false
	_plan = Dictionary(prediction.plan).duplicate(true)
	_target = target
	_forward = _plan.forward
	_origin = movement.get_control_anchor().global_position
	_last_hits = 0
	_last_contacts = 0
	_last_impulse = 0.0
	_total_elapsed = 0.0
	_recovery_progress = 0.0
	_alignment_elapsed = 0.0
	_angles.fill(0.0)
	_joint_state = {"limit":_jaw_joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT),
		"spring":_jaw_joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING),"motor":_jaw_joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR),
		"lower":_jaw_joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),"upper":_jaw_joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)}
	_jaw_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,true)
	_jaw_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING,false)
	_jaw_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR,false)
	_jaw_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,minf(_joint_state.lower,-deg_to_rad(data.jaw_open_degrees+5.0)))
	_jaw_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,maxf(_joint_state.upper,deg_to_rad(data.jaw_open_degrees+5.0)))
	_weapon = HITBOX.new()
	_weapon.name = "SnakeBiteHitbox"
	_weapon.head = head
	_weapon.setup(jaw,get_parent(),_box().size,_mouth_offset(),data.impulse_multiplier,0.0)
	add_child(_weapon)
	# The query-only bite must not wedge the small Jaw inside a victim's solid collider.
	for part: RigidBody3D in PLAYER.character_of(target)._get_physical_body_parts():
		for mouth: RigidBody3D in [head,jaw]:
			_mouth_collision_pairs.append({"mouth":mouth,"part":part,"mouth_had":part in mouth.get_collision_exceptions(),"part_had":mouth in part.get_collision_exceptions()})
			mouth.add_collision_exception_with(part)
			part.add_collision_exception_with(mouth)
	_set_phase(&"positioning")
	if not movement.set_attack_control(self,_poses(_angles),Vector3.ZERO,_forward,data.maximum_acceleration,data.maximum_pose_acceleration,data.maximum_angular_acceleration,data.burst_response_time):
		cancel_action(&"movement_owned")
		return false
	return true

func is_npc_attack_active() -> bool: return _phase != &"idle"
func get_npc_attack_maximum_duration(_action_id: StringName) -> float:
	return (data.preparation_time+data.preparation_extra_wait+data.lunge_extra_wait+data.jaw_close_time+data.recovery_time+data.recovery_extra_wait*2.0)*_time_scale()+maxf(data.lunge_time*_time_scale(),float(_plan.get("duration",0.0)))+float(_plan.get("alignment_duration",4.5))+1.0

func _set_phase(value: StringName, reason: StringName = &"ready") -> void:
	_phase = value
	_elapsed = 0.0
	_last_reason = reason
	if value == &"lunging":
		_plan["launched"] = true
		_origin = head.global_position
	if value == &"recovering":
		_recovery_angles = _angles.duplicate()
		_recovery_progress = 0.0
	_log(&"phase_changed",get_attack_diagnostics())

func _physics_process(delta: float) -> void:
	var started := _perf.start()
	_tick(delta)
	_perf.finish(&"snake_attack",started)

func _tick(delta: float) -> void:
	_cooldown = maxf(_cooldown-delta,0.0)
	if not is_npc_attack_active():
		if has_npc_attack(ACTION) and movement._support_blend > 0.0: _drive_jaw(0.0,delta)
		return
	if not has_npc_attack(ACTION): cancel_action(&"character_unavailable"); return
	if not _valid_target(_target) and _phase not in [&"recovering",&"rejoining"]: _set_phase(&"recovering",&"target_lost")
	for link: Dictionary in _links:
		if not _alive(link.body) or not is_instance_valid(link.joint): cancel_action(&"chain_broken"); return
	if movement.is_attack_support_locked() and movement._contact_count == 0 and movement._support_blend <= 0.0:
		cancel_action(&"ground_support_lost")
		return
	if _phase in [&"preparing",&"lunging"]:
		var remaining := maxf(float(_plan.duration)-(_elapsed if _phase == &"lunging" else 0.0),0.0)
		if _phase == &"preparing": remaining += maxf(data.preparation_time*_time_scale()-_elapsed,0.0)
		var future := _target.global_position+_target_velocity(_target)*remaining
		var reference: Transform3D = movement.get_pose_reference()
		var lateral := (reference.affine_inverse()*future).z-Transform3D(_poses(_angles)[head]).origin.z
		var bounds := GEOMETRY.bounds(_target)
		var half_width := 0.0
		for corner: int in 8:
			half_width = maxf(half_width,absf(reference.basis.z.dot(_target.to_global(bounds.get_endpoint(corner))-_target.global_position)))
		if absf(lateral) > half_width+_box().size.z*0.5+maxf(_head_size.x*0.1,0.1):
			_set_phase(&"recovering",&"target_left_attack_plane")
	_elapsed += delta
	_total_elapsed += delta
	var time_scale := _time_scale()
	var velocity := Vector3.ZERO
	var opening := 0.0
	if _phase == &"positioning":
		_alignment_elapsed = _elapsed
		var alignment := _alignment(_target)
		_forward = _plan.forward
		var reference: Transform3D = movement.get_pose_reference()
		var desired: Transform3D = reference*_poses(_angles)[head]
		_head_error = head.global_position.distance_to(desired.origin)
		var head_heading := head.global_basis.x.slide(Vector3.UP).normalized()
		var planned_heading := desired.basis.x.slide(Vector3.UP).normalized()
		var head_aimed := head_heading.dot(planned_heading) >= cos(deg_to_rad(data.aim_tolerance_degrees))
		var connections: Dictionary = movement.get_attack_connection_diagnostics()
		var chain_aligned: bool = float(connections.get("maximum_error_ratio",INF)) < 2.0
		# Judge the physically settled Head, not the walking belly's averaged residual yaw.
		var frame: Dictionary = movement._update_anchor()
		var stopped: bool = Vector3(frame.velocity).slide(Vector3.UP).length()<maxf(_head_size.x*0.05,0.1) and absf(frame.yaw_speed)<deg_to_rad(5.0)
		if stopped and chain_aligned and head_aimed and _elapsed >= movement.motion_data.path_transition_time and _head_error < maxf(minf(_chain_length*0.04,float(alignment.tolerance)*0.5),_head_size.length()*0.05):
			movement.set_attack_control(self,_poses(_angles),Vector3.ZERO,_forward,data.maximum_acceleration,data.maximum_pose_acceleration,data.maximum_angular_acceleration,data.burst_response_time,0.0,1.0,true)
			_prediction_cache.clear()
			_cached_plan = {}
			var prediction := predict_npc_attack(ACTION,_target,0.0,16,0.1,true)
			if prediction.get("hit",false):
				_plan = Dictionary(prediction.plan).duplicate(true)
				_forward = _plan.forward
				_set_phase(&"preparing")
			else: _set_phase(&"recovering",prediction.get("reason",&"alignment_failed"))
		elif _elapsed >= float(_plan.alignment_duration): _set_phase(&"recovering",&"alignment_timeout")
	elif _phase == &"preparing":
		var progress := smoothstep(0.0,data.preparation_time*time_scale,_elapsed)
		var zeros := _angles.duplicate()
		zeros.fill(0.0)
		var reference: Transform3D = movement.get_pose_reference()
		var preparation := _aim_head(_plan.preparation,reference.affine_inverse()*_target.global_position)
		_angles = _blend(zeros,preparation,progress)
		var poses := _poses(_angles)
		opening = data.jaw_open_degrees*progress
		var desired: Transform3D = reference*Transform3D(poses[head])
		_head_error = head.global_position.distance_to(desired.origin)
		_head_aim_error_degrees = rad_to_deg((head.global_basis*_head_forward_local).angle_to(_target.global_position-head.global_position))
		var aimed := _head_aim_error_degrees <= data.aim_tolerance_degrees
		if _elapsed >= data.preparation_time*time_scale and aimed and _head_error <= maxf(_chain_length*0.06,0.1) and absf(_jaw_error) < 10.0 and float(movement.get_attack_connection_diagnostics().get("maximum_error_ratio",INF)) < 2.0:
			_prediction_cache.clear()
			_cached_plan = {}
			var prediction := predict_npc_attack(ACTION,_target,0.0,16,0.1,true,0.0)
			if prediction.get("hit",false):
				_plan = Dictionary(prediction.plan).duplicate(true)
				_forward = _plan.forward
				_set_phase(&"lunging")
			else: _set_phase(&"recovering",prediction.get("reason",&"intercept_changed"))
		elif _elapsed >= (data.preparation_time+data.preparation_extra_wait)*time_scale:
			_set_phase(&"recovering",&"preparation_not_ready")
	elif _phase == &"lunging":
		var progress := smoothstep(0.0,float(_plan.extension_duration),_elapsed)
		_angles = _blend(_plan.preparation,_plan.strike,progress)
		opening = data.jaw_open_degrees
		var mouth := Transform3D(head.global_basis.orthonormalized(),head.to_global(_mouth_offset()))
		var contact := PREDICTION.target_hit(get_world_3d().direct_space_state,_box(),mouth,_target,0.0,0.0)
		if contact or _weapon.hit_count > 0:
			_plan["closing_angles"] = _angles.duplicate()
			_set_phase(&"closing",&"mouth_contact")
		elif _elapsed >= float(_plan.limit):
			_plan["closing_angles"] = _angles.duplicate()
			_set_phase(&"closing",&"lunge_limit")
	elif _phase == &"closing":
		_angles = _plan.closing_angles
		opening = data.jaw_open_degrees*(1.0-smoothstep(0.0,data.jaw_close_time*time_scale,_elapsed))
		if _elapsed >= data.jaw_close_time*time_scale: _set_phase(&"recovering")
	elif _phase in [&"recovering",&"rejoining"]:
		var zeros := _angles.duplicate()
		zeros.fill(0.0)
		var connections: Dictionary = movement.get_attack_connection_diagnostics()
		var tracking_error := 0.0
		var reference: Transform3D = movement.get_pose_reference()
		for body: Node3D in movement._attack_poses:
			if is_instance_valid(body) and not body.is_broken: tracking_error = maxf(tracking_error,body.global_position.distance_to(reference*Transform3D(movement._attack_poses[body]).origin))
		var pace := clampf(1.0-tracking_error/maxf(_chain_length*0.08,0.01),0.15,1.0)
		if float(connections.get("maximum_error_ratio",0.0)) > 2.0: pace = minf(pace,0.15)
		_recovery_progress = minf(_recovery_progress+delta/(data.recovery_time*time_scale)*pace,1.0)
		_angles = _blend(_recovery_angles,zeros,smoothstep(0.0,1.0,_recovery_progress))
		var desired: Transform3D = movement.get_pose_reference()*_poses(_angles)[head]
		_head_error = head.global_position.distance_to(desired.origin)
		var settled: bool = _recovery_progress >= 1.0 and Vector3(movement._update_anchor().velocity).length() < 0.5 and _head_error < _head_size.length()*0.15 and absf(_jaw_angle) < 5.0 and connections.get("ready",false)
		if _phase == &"recovering" and (_recovery_progress >= 1.0 or _elapsed >= (data.recovery_time+data.recovery_extra_wait)*time_scale):
			_set_phase(&"rejoining",&"checking_connections")
		elif _phase == &"rejoining":
			if settled:
				cancel_action(&"completed")
				return
			if _elapsed >= data.recovery_extra_wait*time_scale:
				cancel_action(&"rejoin_timeout")
				return
	var pose_rate := data.head_extension_speed_multiplier if _phase == &"lunging" else 1.0
	movement.set_attack_control(self,_poses(_angles),velocity,_forward,data.maximum_acceleration,data.maximum_pose_acceleration,data.maximum_angular_acceleration,data.burst_response_time,delta,pose_rate,_phase != &"positioning")
	_drive_jaw(opening,delta)
	_weapon.update_hitbox(delta,_phase in [&"lunging",&"closing"])
	_log_elapsed += delta
	if diagnostic_logging and _log_elapsed >= 0.1:
		_log_elapsed = 0.0
		_log(&"snapshot",get_attack_diagnostics())

func _drive_jaw(opening: float, delta: float) -> void:
	var relative := (head.global_basis.orthonormalized().inverse()*jaw.global_basis.orthonormalized()).get_rotation_quaternion()
	var desired := Quaternion(Vector3.BACK,-deg_to_rad(opening))*_jaw_rest
	var error := desired*relative.inverse()
	if error.w < 0.0: error = -error
	var local_error := error.get_axis()*error.get_angle()
	var axis := head.global_basis.z.normalized()
	_jaw_error = rad_to_deg(local_error.z)
	var actual := relative*_jaw_rest.inverse()
	_jaw_angle = rad_to_deg(actual.get_axis().z*actual.get_angle())
	var rate := (jaw.angular_velocity-head.angular_velocity).dot(axis)
	var inverse := jaw.get_inverse_inertia_tensor()
	if absf(inverse.determinant()) < 1e-18: return
	# Joint nodes stay at their authored scene transform while their physical anchors travel.
	var radius := jaw.global_position-head.to_global(_jaw_anchor)
	var inertia := axis.dot(inverse.inverse()*axis)+jaw.mass*radius.slide(axis).length_squared()
	var acceleration := (local_error.z*data.angular_strength-rate*data.angular_damping)/(1.0+data.angular_damping*delta+data.angular_strength*delta*delta)
	var cap: float = movement.motion_data.maximum_pose_torque
	var torque := axis*clampf(acceleration*inertia,-cap,cap)
	_jaw_torque = torque
	jaw.apply_central_force(-jaw.get_gravity()*jaw.mass*movement._support_blend)
	jaw.apply_torque(torque)
	head.apply_torque(-torque)

func cancel_action(reason: StringName = &"cancelled") -> void:
	var was_active := is_npc_attack_active()
	if is_instance_valid(movement): movement.end_attack_control(self)
	if is_instance_valid(_weapon):
		_last_hits = _weapon.hit_count
		_last_contacts = _weapon.contacted_parts.size()
		_last_impulse = _weapon.peak_impulse
		_weapon.dispose()
	_weapon = null
	for pair: Dictionary in _mouth_collision_pairs:
		if not is_instance_valid(pair.mouth) or not is_instance_valid(pair.part): continue
		if not pair.mouth_had: pair.mouth.remove_collision_exception_with(pair.part)
		if not pair.part_had: pair.part.remove_collision_exception_with(pair.mouth)
	_mouth_collision_pairs.clear()
	if is_instance_valid(_jaw_joint) and not _joint_state.is_empty():
		_jaw_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,_joint_state.limit)
		_jaw_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING,_joint_state.spring)
		_jaw_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_MOTOR,_joint_state.motor)
		_jaw_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,_joint_state.lower)
		_jaw_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,_joint_state.upper)
	_joint_state.clear()
	_phase = &"idle"
	_target = null
	_prediction_cache.clear()
	_cached_plan = {}
	if was_active:
		_cooldown = data.cooldown if data != null else 0.0
		_last_reason = reason
		if diagnostic_logging and is_inside_tree(): _log(&"ended",get_attack_diagnostics())

func cancel_npc_attack() -> void: cancel_action(&"npc_cancelled")
func set_character_control_enabled(value: bool) -> void:
	_character_enabled = value
	if not value: cancel_action(&"character_disabled")
	set_physics_process(value)
func _exit_tree() -> void: cancel_action(&"removed")

func get_npc_attack_range_diagnostics(action_id: StringName, target: Node3D) -> Dictionary:
	var result := get_attack_diagnostics()
	result["maximum_range"] = get_npc_attack_maximum_range(action_id,target)
	result["target_distance"] = head.global_position.distance_to(target.global_position) if _alive(head) and is_instance_valid(target) else -1.0
	return result

func get_attack_diagnostics() -> Dictionary:
	return {"phase":_phase,"phase_elapsed":_elapsed,"attack_elapsed":_total_elapsed,"reason":_last_reason,
		"alignment_elapsed":_alignment_elapsed,"alignment":_alignment(_target) if _valid_target(_target) and is_instance_valid(movement) and movement.get_control_anchor() != null else {},
		"target":str(_target.get_path()) if is_instance_valid(_target) and _target.is_inside_tree() else "none","chain_length":_chain_length,"scale":_scale,
		"head_position":head.global_position if _alive(head) else Vector3.ZERO,"head_error":_head_error,
		"head_forward_source":_head_forward_source,"head_forward_local":_head_forward_local,"head_rest_forward":_head_rest_forward,
		"head_forward_world":(head.global_basis*_head_forward_local).normalized() if _alive(head) else Vector3.ZERO,"head_aim_error_degrees":_head_aim_error_degrees,
		"jaw_angle_degrees":_jaw_angle,"jaw_error_degrees":_jaw_error,"burst_speed":_speed() if data != null else 0.0,
		"jaw_torque":_jaw_torque,"jaw_velocity":jaw.angular_velocity if _alive(jaw) else Vector3.ZERO,"jaw_sleeping":jaw.sleeping if _alive(jaw) else false,
		"body_velocity":movement._update_anchor().get("velocity",Vector3.ZERO) if is_instance_valid(movement) else Vector3.ZERO,
		"planned_distance":_plan.get("distance",0.0),"head_traveled":head.global_position.distance_to(_origin) if _alive(head) and _plan.get("launched",false) else 0.0,
		"support_locked":movement.is_attack_support_locked() if is_instance_valid(movement) else false,"ground_displacement":movement._attack_ground_error if is_instance_valid(movement) else 0.0,
		"planned_lunge_time":_plan.get("duration",0.0),"lunge_time_limit":_plan.get("limit",0.0),
		"head_extension_time":_plan.get("extension_duration",0.0),"head_extension_speed_multiplier":data.head_extension_speed_multiplier if data != null else 1.0,
		"planned_contact_time":_plan.get("contact_time",0.0),"expected_alignment_time":_plan.get("alignment_time",0.0),
		"recovery_progress":_recovery_progress,"connections":movement.get_attack_connection_diagnostics() if is_instance_valid(movement) else {},
		"intercept_aim":_plan.get("aim",Vector3.ZERO),"intercept_pose_error":_plan.get("pose_error",Vector3.ZERO),
		"predicted_target_velocity":_plan.get("target_velocity",Vector3.ZERO),"target_supported":_plan.get("target_supported",false),
		"hits":_weapon.hit_count if is_instance_valid(_weapon) else _last_hits,
		"contacted_parts":_weapon.contacted_parts.size() if is_instance_valid(_weapon) else _last_contacts,
		"peak_impulse":_weapon.peak_impulse if is_instance_valid(_weapon) else _last_impulse,"cooldown":_cooldown}

func _log(event: StringName, details: Dictionary) -> void:
	if diagnostic_logging: print("[snake_attack] character=",get_parent().get_path()," event=",event," data=",details)

func set_control_performance_tracking_enabled(value: bool) -> void: _perf.set_enabled(value)
func consume_control_performance_stats() -> Dictionary: return _perf.consume()
