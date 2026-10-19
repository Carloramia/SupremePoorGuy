extends Node3D

const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
@export var enabled: bool = true
## Disable travel and turning without disabling gravity compensation or pose support.
@export var locomotion_enabled: bool = true
@export var motion_data: SnakeMotionData = preload("res://Resources/Movement/SnakeMotion.tres")
## PlayerController overrides the sibling NPC command source while attached.
@export var command_source: Node
var _character_enabled := true
var _parts: Array[Dictionary] = []
var _belly: Array[Dictionary] = []
var _torsos: Array[Dictionary] = []
var _rest_center := Vector3.ZERO
var _rest_basis := Basis.IDENTITY
var _rest_heading := Vector3.RIGHT
var _materials_active := false
var _support_blend := 0.0
var _direction := Vector3.ZERO
var _actual_velocity := Vector3.ZERO
var _drive_force := Vector3.ZERO
var _turn_rate := 0.0
var _actual_yaw_speed := 0.0
var _contact_count := 0
var _traction_count := 0
var _attack_owner: Node
var _attack_poses: Dictionary = {}
var _attack_velocity := Vector3.ZERO
var _attack_facing := Vector3.ZERO
var _attack_acceleration := 0.0
var _attack_pose_acceleration := 0.0
var _attack_angular_acceleration := 0.0
var _attack_response_time := 0.1
var _attack_pose_speed_multiplier := 1.0
var _attack_support_locked := false
var _attack_support_reference := Transform3D.IDENTITY
var _attack_ground_error := 0.0
var _attack_pose_velocities: Dictionary = {}
var _attack_entry_poses: Dictionary = {}
var _attack_entry_elapsed := 0.0
var _attack_slide_release_pending := false
var _attack_ground_poses: Dictionary = {}
var _attack_ground_world_poses: Dictionary = {}
var _idle_ground_poses: Dictionary = {}
var _held_heading := Vector3.RIGHT
var _connection_diagnostics: Dictionary = {}
var _connection_recovery_active := false
var _connection_recovery_resume_path := false
var _connection_recovery_reference := Transform3D.IDENTITY
var _connection_settle_time := 0.0
var _sway_chain: Array[Dictionary] = []
var _sway_time := 0.0
var _sway_amplitude := 0.0
var _sway_phase := 0.0
var _sway_period := 0.0
var _sway_links := 0
var _sway_max_ground_offset := 0.0
var _sway_max_amplitude := 0.0
var _sway_strength := 0.0
var _sway_travel_blend := 0.0
var _sway_travelling := false
var _jaw: RigidBody3D
var _trajectory_time := 0.0
var _orbit_time := 0.0
var _orbit_radius := 0.0
var _ground_path := preload("res://Scripts/Creatures/SnakeGroundPath.gd").new()
var _path_ready := false
var _path_progress := 0.0
var _path_blend := 0.0
var _path_speed := 0.0
var _path_amplitude := 0.0
var _path_length := 0.0
var _path_leader: Dictionary = {}
var _path_frequency := 0.0
var _path_turning := false
var _path_reversing := false
var _path_slides_expanded := false
var _path_max_amplitude := 0.0
var _path_pose_basis := Basis.IDENTITY
var _path_pose_yaw_speed := 0.0
var _path_execution_speed_scale := 1.0
var _command_heading := Vector3.RIGHT
var _raised_heading := Vector3.RIGHT
var _raised_root_index := -1
var _path_facing_command := Vector3.RIGHT
var _spacing_pairs: Array[Dictionary] = []
var _spacing_anchor := 0
var _spacing_phase := 0.0
var _spacing_phase_rate := 0.0
var _spacing_blend := 0.0
var _spacing_ratio := 0.0
var _spacing_shape_amplitude := 0.0
var _spacing_limit_reason := "inactive"
var _spacing_acceleration_bound := 0.0
var _control_perf := preload("res://Scripts/Debug/ControlPerformanceStats.gd").new()
@onready var _anchor: Node3D = $NavigationOrigin

func _ready() -> void:
	add_to_group(&"snake_movement_controllers")
	_control_perf.register(self)
	call_deferred("_initialize_saved_parts")

func _initialize_saved_parts() -> void:
	if _parts.is_empty(): refresh_parts()

func _exit_tree() -> void:
	_set_path_slide_limits(false)
	_configure_contacts(false)

func _configure_contacts(active: bool) -> void:
	if active == _materials_active: return
	_materials_active = active
	for row: Dictionary in _torsos:
		if not is_instance_valid(row.body): continue
		row.body.surface_contact_tracking = active and not row.body.is_broken
		row.body.surface_contact_terrain_only = active and not row.body.is_broken
		row.body.physics_material_override = row.grip_material if active and not row.body.is_broken else row.material

func _on_part_broken(_source: Node, body: PhysicalBodyPart3D) -> void:
	body.surface_contact_tracking = false
	body.surface_contact_terrain_only = false
	for row: Dictionary in _torsos:
		if row.body == body: body.physics_material_override = row.material

func refresh_parts() -> void:
	_set_path_slide_limits(false)
	end_attack_control(_attack_owner)
	_configure_contacts(false)
	_parts.clear()
	_belly.clear()
	_torsos.clear()
	_sway_chain.clear()
	_path_slides_expanded = false
	_attack_slide_release_pending = false
	_jaw = null
	_rest_center = Vector3.ZERO
	_support_blend = 0.0
	var container := get_parent().get_node_or_null("GeneratedParts") as Node3D
	if container == null: return
	_rest_basis = get_parent().global_basis.orthonormalized()
	var torsos: Array[PhysicalBodyPart3D] = []
	for node: Node in container.get_children():
		if node is PhysicalBodyPart3D and node.get_meta(&"generated_role", "") == "Torso": torsos.append(node)
	torsos.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	var generator := get_parent().get_node("SnakeGenerator")
	var ground_count := torsos.size() - clampi(roundi(torsos.size() * generator.raised_body_ratio), 3, torsos.size()-1)
	var belly_mass := 0.0
	for index: int in torsos.size():
		var body := torsos[index]
		var layout: Dictionary = body.get_meta(&"generated_layout", {})
		var size := GEOMETRY.bounds(body).size
		var grounded: bool = layout.get("snake_grounded", index < ground_count)
		var row := {"body": body, "rest": body.transform, "size": size,
			"belly": grounded,
			"material": body.physics_material_override}
		_parts.append(row)
		_torsos.append(row)
		var material := PhysicsMaterial.new()
		material.friction = 0.03
		material.bounce = row.material.bounce if row.material != null else 0.0
		row["grip_material"] = material
		var callback := _on_part_broken.bind(body)
		if not body.broken.is_connected(callback): body.broken.connect(callback)
		if grounded:
			_belly.append(row)
			_rest_center += body.position * body.mass
			belly_mass += body.mass
	if belly_mass > 0.0: _rest_center /= belly_mass
	for node: Node in container.get_children():
		if node is PhysicalBodyPart3D and node.get_meta(&"generated_role", "") == "Jaw": _jaw = node
		if node is PhysicalBodyPart3D and node.get_meta(&"generated_role", "") == "Head":
			_parts.append({"body": node, "rest": node.transform, "size": GEOMETRY.bounds(node).size,
				"belly": false, "material": node.physics_material_override})
	var frame := _update_anchor()
	if not frame.is_empty(): _rest_heading = frame.heading
	_held_heading = _rest_heading
	_cache_trajectory_chain(container)
	_raised_root_index = _parts.find(_belly[-1])+1 if not _belly.is_empty() else -1
	_cache_sway_chain()
	_configure_contacts(enabled and _character_enabled)
	cancel_motion()

func get_control_anchor() -> Node3D:
	for row: Dictionary in _torsos:
		if _live(row): return _anchor
	return null

func get_torso_parts() -> Array[RigidBody3D]:
	var result: Array[RigidBody3D] = []
	for row: Dictionary in _parts:
		if _live(row) and PhysicalBodyPart3D.BodyPartTag.Torso in row.body.tags: result.append(row.body)
	return result

func _live(row: Dictionary) -> bool:
	var body: Variant = row.get("body")
	return is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion() and not body.is_broken

func _live_joint(row: Dictionary, key: StringName = &"incoming_joint") -> Generic6DOFJoint3D:
	var joint: Variant = row.get(key)
	if not is_instance_valid(joint) or not joint is Generic6DOFJoint3D or joint.is_queued_for_deletion(): return null
	return joint

func _on_joint_exiting(joint: Generic6DOFJoint3D) -> void:
	# Keep rest poses and row order; rebuilding them would adopt the damaged pose.
	for row: Dictionary in _parts:
		for key: StringName in [&"incoming_joint",&"follow_joint",&"sway_joint"]:
			if row.get(key) != joint: continue
			row[key] = null
			if key == &"follow_joint": row.leader = {}
			row.erase("connection_target")
			row["connection_error"] = Vector3.ZERO
			row["connection_relative_velocity"] = Vector3.ZERO
			row["connection_span_force"] = Vector3.ZERO
			row["pair_force"] = Vector3.ZERO

func _source() -> Node:
	if is_instance_valid(command_source): return command_source
	var ai := get_parent().get_node_or_null("NPCStateMachine3D")
	return ai if ai != null and ai.is_physics_processing() else null

func get_input_movement_direction() -> Vector3:
	if not locomotion_enabled: return Vector3.ZERO
	var source := _source()
	if source == null or not source.has_method("get_movement_direction"): return Vector3.ZERO
	var direction: Vector3 = source.get_movement_direction()
	return direction.slide(Vector3.UP).limit_length(1.0) if direction.is_finite() else Vector3.ZERO

func _update_anchor() -> Dictionary:
	var center := Vector3.ZERO
	var velocity := Vector3.ZERO
	var heading := Vector3.ZERO
	var yaw_speed := 0.0
	var mass := 0.0
	var wave_velocity := 0.0
	var references := _belly if _belly.any(_live) else _torsos
	_rest_center = Vector3.ZERO
	for row: Dictionary in references:
		if not _live(row): continue
		var body: PhysicalBodyPart3D = row.body
		center += body.global_position * body.mass
		velocity += body.linear_velocity * body.mass
		heading += (body.global_basis*Basis(row.rest.basis).inverse()).x.slide(Vector3.UP)*body.mass
		_rest_center += (Vector3(row.rest.origin)+Vector3(0,0,row.get("sway_offset",0.0)))*body.mass
		wave_velocity += float(row.get("sway_velocity",0.0))*body.mass
		yaw_speed += body.angular_velocity.y * body.mass
		mass += body.mass
	if mass <= 0.0: return {}
	center /= mass
	_rest_center /= mass
	velocity /= mass
	if heading.is_zero_approx(): heading = _rest_basis.x
	var yaw := atan2(_rest_heading.cross(heading.normalized()).y, _rest_heading.dot(heading.normalized()))
	var basis := Basis(Vector3.UP, yaw)*_rest_basis if locomotion_enabled else _rest_basis
	velocity -= basis.z*(wave_velocity/mass)
	var travel_velocity := velocity
	if motion_data != null and (motion_data.sway_enabled or _sway_strength > 0.0):
		# Internal waving moves the belly center; the complete body's momentum measures actual travel.
		travel_velocity = Vector3.ZERO
		var total_mass := 0.0
		for row: Dictionary in _parts:
			if not _live(row): continue
			travel_velocity += row.body.linear_velocity*row.body.mass
			total_mass += row.body.mass
		if is_instance_valid(_jaw) and not _jaw.is_broken:
			travel_velocity += _jaw.linear_velocity*_jaw.mass
			total_mass += _jaw.mass
		if total_mass > 0.0: travel_velocity /= total_mass
	_anchor.global_position = center
	return {"center": center, "velocity": velocity, "travel_velocity": travel_velocity, "heading": heading.normalized(), "mass": mass, "yaw_speed": yaw_speed / mass}

## World frame for authored local poses, following the living belly rather than the scene root.
func get_pose_reference(use_attack_facing: bool = true) -> Transform3D:
	if _connection_recovery_active: return _connection_recovery_reference
	if is_attack_support_locked(): return _attack_support_reference
	var frame := _update_anchor()
	if frame.is_empty(): return global_transform
	if _independent_path_turning():
		var root := _raised_turn_pivot()
		var raised_basis := _turn_basis(_raised_heading)
		return Transform3D(raised_basis,Vector3(root.world)-raised_basis*Vector3(root.rest))
	var heading: Vector3 = _attack_facing if use_attack_facing and is_instance_valid(_attack_owner) and not _attack_facing.is_zero_approx() else frame.heading
	if not is_instance_valid(_attack_owner) and not _idle_ground_poses.is_empty(): heading = _held_heading
	var yaw := atan2(_rest_heading.cross(heading).y, _rest_heading.dot(heading))
	var basis := Basis(Vector3.UP, yaw) * _rest_basis if locomotion_enabled else _rest_basis
	return Transform3D(basis, frame.center - basis * _rest_center)

func _independent_path_turning() -> bool:
	return locomotion_enabled and motion_data != null and motion_data.ground_path_enabled and motion_data.sway_enabled and motion_data.trajectory_following_enabled and not motion_data.head_orbit_enabled

func _turn_basis(heading: Vector3) -> Basis:
	return Basis(Vector3.UP,atan2(_rest_heading.cross(heading).y,_rest_heading.dot(heading)))*_rest_basis

func _raised_turn_pivot() -> Dictionary:
	if _belly.is_empty() or not _live(_belly[-1]): return {"world":global_position,"rest":_rest_center}
	var root: Dictionary = _belly[-1]
	var local := Vector3.ZERO
	var index := _raised_root_index
	if index>=0 and index < _parts.size():
		var joint := _live_joint(_parts[index])
		if joint != null: local = Transform3D(joint.get_meta(&"generated_joint_frame_a")).origin
	return {"world":root.body.global_position+_part_turn_basis(root)*Basis(root.rest.basis)*local,"rest":Transform3D(root.rest)*local}

func _part_turn_basis(row: Dictionary) -> Basis:
	return _turn_basis(row.get("turn_heading",_rest_heading)) if row.belly and _independent_path_turning() else _path_pose_basis

func _update_path_turning(delta: float, facing: Vector3) -> void:
	if not _independent_path_turning() or is_attack_support_locked() or _connection_recovery_active: return
	var error := atan2(_raised_heading.cross(facing).y,_raised_heading.dot(facing))
	if absf(error) > deg_to_rad(175.0): error = -absf(error) if _rest_heading.dot(facing)<0.0 else absf(error)
	_turn_rate = clampf(error/motion_data.turn_response_time,-deg_to_rad(motion_data.turn_speed_degrees),deg_to_rad(motion_data.turn_speed_degrees))
	var change := clampf(_turn_rate*delta,-absf(error),absf(error))
	_raised_heading = (Basis(Vector3.UP,change)*_raised_heading).normalized()
	_path_pose_basis = _turn_basis(_raised_heading)
	_path_pose_yaw_speed = change/delta
	_path_turning = absf(error)>deg_to_rad(5.0)
	if is_instance_valid(_attack_owner): return
	for index: int in _belly.size():
		var row: Dictionary = _belly[index]
		if not _live(row): continue
		if not _direction.is_zero_approx() or _path_ready: row.erase("idle_turn_anchor")
		elif absf(error)>deg_to_rad(1.0) and row.grounded and not row.has("idle_turn_anchor"): row["idle_turn_anchor"] = row.body.global_position
		var goal: Vector3 = row.get("turn_heading",_rest_heading)
		if _path_ready and row.has("path_distance"):
			var radius := maxf(row.body.linear_velocity.length()*delta*2.0,_ground_path.step*2.0)
			row["turn_distance"] = _ground_path.project(row.body.global_position,float(row.get("turn_distance",row.path_distance)),radius,true)
			goal = _ground_path.facing_at(float(row.turn_distance))
		var previous: Vector3 = row.get("turn_heading",_rest_heading)
		var angle := atan2(previous.cross(goal).y,previous.dot(goal))
		if absf(angle)>deg_to_rad(175.0): angle = -absf(angle) if _rest_heading.dot(goal)<0.0 else absf(angle)
		var step := clampf(angle/motion_data.turn_response_time*delta,-deg_to_rad(motion_data.turn_speed_degrees)*delta,deg_to_rad(motion_data.turn_speed_degrees)*delta)
		var heading := (Basis(Vector3.UP,step)*previous).normalized()
		# A marked piece waits for its neighbor instead of fighting the passive yaw stop.
		var joint := _live_joint(row)
		if index>0 and joint!=null and _live(_belly[index-1]):
			var neighbor: Vector3 = _belly[index-1].get("turn_heading",_rest_heading)
			var relative := atan2(neighbor.cross(heading).y,neighbor.dot(heading))
			var allowance := maxf(minf(absf(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)),absf(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)))-deg_to_rad(3.0),0.0)
			heading = Basis(Vector3.UP,clampf(relative,-allowance,allowance))*neighbor
		row["turn_goal"] = goal
		row["turn_rate"] = atan2(previous.cross(heading).y,previous.dot(heading))/delta
		row["turn_heading"] = heading

func set_attack_control(owner_node: Node, poses: Dictionary, velocity: Vector3, facing: Vector3, acceleration: float, pose_acceleration: float, angular_acceleration: float = 60.0, response_time: float = 0.1, delta: float = 0.0, pose_speed_multiplier: float = 1.0, lock_ground: bool = false, support_reference: Transform3D = Transform3D.IDENTITY) -> bool:
	if not locomotion_enabled or _connection_recovery_active: return false
	if not is_instance_valid(owner_node) or (is_instance_valid(_attack_owner) and _attack_owner != owner_node): return false
	if _attack_owner != owner_node:
		_attack_support_locked = false
		var old_inverse := get_pose_reference(false).affine_inverse()
		_attack_ground_poses.clear()
		_attack_ground_world_poses.clear()
		for row: Dictionary in _belly:
			if not _live(row): continue
			var position: Vector3 = old_inverse*row.body.global_position
			position.y = row.rest.origin.y
			# Preserve the ground S footprint, not transient roll/pitch from the last contact.
			var pose := Transform3D(row.rest.basis,position)
			_attack_ground_poses[row.body] = pose
			_attack_ground_world_poses[row.body] = row.body.global_transform
		for row: Dictionary in _parts: row.erase("connection_target")
		_idle_ground_poses.clear()
		_attack_entry_elapsed = 0.0
		_attack_slide_release_pending = true
		_attack_entry_poses.clear()
		_attack_owner = owner_node
		_attack_facing = facing
		var inverse := get_pose_reference().affine_inverse()
		for row: Dictionary in _parts:
			if _live(row): _attack_entry_poses[row.body] = inverse*row.body.global_transform
	if lock_ground and not _attack_support_locked:
		# The caller can commit the exact world frame already validated by its attack plan.
		_attack_support_reference = get_pose_reference() if support_reference == Transform3D.IDENTITY else support_reference
		var inverse := _attack_support_reference.affine_inverse()
		for row: Dictionary in _belly:
			if not _live(row): continue
			var position: Vector3 = inverse*row.body.global_position
			position.y = row.rest.origin.y
			_attack_ground_poses[row.body] = Transform3D(row.rest.basis,position)
			_attack_ground_world_poses[row.body] = row.body.global_transform
		for row: Dictionary in _parts:
			if _live(row): _attack_entry_poses[row.body] = inverse*row.body.global_transform
		_attack_entry_elapsed = 0.0
		_attack_support_locked = true
	_attack_entry_elapsed += delta
	var blend := smoothstep(0.0,motion_data.path_transition_time,_attack_entry_elapsed)
	var blended: Dictionary = {}
	var ground_inverse := get_pose_reference().affine_inverse()
	for row: Dictionary in _parts:
		if _live(row): blended[row.body] = Transform3D(_attack_entry_poses.get(row.body,row.rest)).interpolate_with(_attack_ground_poses.get(row.body,poses.get(row.body,row.rest)),blend)
		if _live(row) and row.belly and _independent_path_turning() and _attack_ground_world_poses.has(row.body):
			# Re-express a fixed world footprint as the independent upper reference turns.
			_attack_ground_poses[row.body] = ground_inverse*Transform3D(_attack_ground_world_poses[row.body])
			blended[row.body] = _attack_ground_poses[row.body]
	_attack_pose_velocities.clear()
	if delta > 0.0 and _attack_owner == owner_node:
		for body: Node in blended:
			if not _attack_poses.has(body): continue
			var previous: Transform3D = _attack_poses[body]
			var next: Transform3D = blended[body]
			var rotation := next.basis.get_rotation_quaternion()*previous.basis.get_rotation_quaternion().inverse()
			if rotation.w < 0.0: rotation = -rotation
			_attack_pose_velocities[body] = {"linear":(next.origin-previous.origin)/delta,"angular":rotation.get_axis()*rotation.get_angle()/delta}
	_attack_owner = owner_node
	_attack_poses = blended
	_attack_velocity = velocity
	_attack_facing = facing
	_attack_acceleration = acceleration
	_attack_pose_acceleration = pose_acceleration
	_attack_angular_acceleration = angular_acceleration
	_attack_response_time = response_time
	_attack_pose_speed_multiplier = pose_speed_multiplier
	return true

func is_attack_support_locked() -> bool:
	return _attack_support_locked and is_instance_valid(_attack_owner)

func end_attack_control(owner_node: Node) -> void:
	if is_instance_valid(_attack_owner) and _attack_owner != owner_node: return
	var was_attacking := is_instance_valid(_attack_owner)
	if was_attacking:
		_idle_ground_poses = _attack_ground_poses.duplicate()
		_held_heading = _attack_facing
		_attack_slide_release_pending = true
	_attack_owner = null
	_attack_ground_poses.clear()
	_attack_ground_world_poses.clear()
	_attack_poses.clear()
	_attack_pose_velocities.clear()
	_attack_entry_poses.clear()
	_attack_entry_elapsed = 0.0
	_attack_velocity = Vector3.ZERO
	_attack_pose_speed_multiplier = 1.0
	_attack_support_locked = false
	if was_attacking: _begin_connection_recovery()

func is_connection_recovering() -> bool:
	return _connection_recovery_active

func _begin_connection_recovery() -> void:
	if _connection_recovery_active or not is_inside_tree() or not _belly.any(_live): return
	# Attack/idle pose ownership pauses execution without invalidating the visited route.
	_connection_recovery_resume_path = _path_ready and not _ground_path.points.is_empty()
	var reference := get_pose_reference()
	if _idle_ground_poses.is_empty():
		var inverse := reference.affine_inverse()
		for row: Dictionary in _belly:
			if not _live(row): continue
			var position: Vector3 = inverse*row.body.global_position
			position.y = row.rest.origin.y
			_idle_ground_poses[row.body] = Transform3D(row.rest.basis,position)
	_idle_ground_poses = _constrain_connection_poses(_idle_ground_poses,true)
	_connection_recovery_reference = reference
	_held_heading = reference.basis.x.slide(Vector3.UP).normalized()
	_connection_recovery_active = true
	_connection_settle_time = 0.0
	_attack_slide_release_pending = true
	_path_ready = false
	_path_blend = 0.0
	_path_speed = 0.0
	_sway_strength = 0.0
	for row: Dictionary in _parts:
		row.sway_offset = 0.0
		row.sway_velocity = 0.0
		row.trajectory_offset = Vector3.ZERO
		row.trajectory_velocity = Vector3.ZERO

func _joint_slide_bounds(row: Dictionary, expanded: bool) -> Dictionary:
	var joint := _live_joint(row)
	if joint == null: return {}
	var x := maxf(absf(row.base_x_lower),absf(row.base_x_upper))
	var z := maxf(absf(row.base_slide_lower),absf(row.base_slide_upper))
	if expanded:
		# Rest geometry bounds the extra travel; an already stretched body never enlarges it.
		var yaw := maxf(absf(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)),absf(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)))
		yaw = minf(yaw,PI*0.5)
		x = maxf(x,float(row.rest_gap)*(1.0-cos(yaw)))
		z = maxf(z*motion_data.path_joint_slide_widths,float(row.rest_gap)*sin(yaw))
		if row.ground_pair:
			# Ground pieces may reverse order on the route while retaining their authored facing.
			# Their center-distance envelope, below, prevents this anchor travel becoming a gap.
			x = maxf(x,float(row.rest_gap)*2.2)
			z = maxf(z,float(row.rest_gap)*2.2)
	return {"lower":Vector3(-x,joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT),-z),
		"upper":Vector3(x,joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT),z),
		"maximum_center_distance":float(row.rest_gap)*1.15 if row.ground_pair else -1.0}

func _constrain_connection_poses(poses: Dictionary, ground_only: bool) -> Dictionary:
	var result := poses.duplicate()
	if _belly.is_empty(): return result
	var anchor := 0
	for index: int in _parts.size():
		if _parts[index].body == _belly[-1].body: anchor = index; break
	for direction: int in [-1,1]:
		var index := anchor+direction
		while index>=0 and index<_parts.size():
			var child_index := index if direction>0 else index+1
			var a: Dictionary = _parts[child_index-1]
			var b: Dictionary = _parts[child_index]
			var joint := _live_joint(b)
			if _live(a) and _live(b) and joint != null and (not ground_only or (a.belly and b.belly)):
				var pa: Transform3D = result.get(a.body,a.rest)
				var pb: Transform3D = result.get(b.body,b.rest)
				var fa: Transform3D = pa*Transform3D(joint.get_meta(&"generated_joint_frame_a"))
				var fb: Transform3D = pb*Transform3D(joint.get_meta(&"generated_joint_frame_b"))
				var offset: Vector3 = fa.affine_inverse()*fb.origin
				var bounds := _joint_slide_bounds(b,true)
				var limited := offset.clamp(bounds.lower,bounds.upper)
				limited.y = offset.y
				var correction := fa.basis*(limited-offset)
				if direction>0: pb.origin += correction
				else: pa.origin -= correction
				if b.ground_pair:
					var gap := pb.origin-pa.origin
					var center_correction := gap.limit_length(float(bounds.maximum_center_distance))-gap
					if direction>0: pb.origin += center_correction
					else: pa.origin -= center_correction
				result[b.body if direction>0 else a.body] = pb if direction>0 else pa
			index += direction
	return result

func get_attack_root_offset() -> Vector3:
	if _belly.is_empty(): return Vector3.ZERO
	var row: Dictionary = _belly[-1]
	return get_attack_root_pose(row.rest).origin-Vector3(row.rest.origin)

func get_attack_root_pose(fallback: Transform3D) -> Transform3D:
	if _belly.is_empty(): return fallback
	# The upper reference already follows the live root pivot; importing belly yaw would turn it twice.
	if _independent_path_turning(): return fallback
	var poses := _attack_ground_poses if is_instance_valid(_attack_owner) else _idle_ground_poses
	if poses.is_empty() and _path_ready and _live(_belly[-1]):
		var position: Vector3 = get_pose_reference().affine_inverse()*_belly[-1].body.global_position
		position.y = fallback.origin.y
		return Transform3D(fallback.basis,position)
	return poses.get(_belly[-1].body,fallback)

func _held_root_delta() -> Transform3D:
	if _belly.is_empty() or _idle_ground_poses.is_empty(): return Transform3D.IDENTITY
	return get_attack_root_pose(_belly[-1].rest)*Transform3D(_belly[-1].rest).affine_inverse()

func _connection_pose(row: Dictionary) -> Transform3D:
	if _path_ready and _uses_ground_path():
		# Relative pair targets are frame-invariant; avoid rebuilding the belly frame per link.
		return Transform3D(_part_turn_basis(row)*Basis(row.rest.basis),row.path_target)
	if _independent_path_turning() and not is_instance_valid(_attack_owner) and not _connection_recovery_active and row.belly:
		return Transform3D(_part_turn_basis(row)*Basis(row.rest.basis),row.body.global_position)
	var pose: Transform3D = _attack_poses.get(row.body,row.rest) if is_instance_valid(_attack_owner) else _idle_ground_poses.get(row.body,row.rest)
	if not is_instance_valid(_attack_owner):
		if not row.belly: pose = _held_root_delta()*pose
		pose.origin += Vector3(row.trajectory_offset)+Vector3(0,0,row.sway_offset)
	return pose

func _restore_bend_limit(joint: Generic6DOFJoint3D, actual: Basis, requested: Basis, angular_speed: float, delta: float) -> bool:
	if joint.has_meta(&"snake_raised_turn_limits"): return true
	var standing: Dictionary = joint.get_meta(&"snake_bend_restore",{})
	if standing.is_empty() or (is_instance_valid(_attack_owner) and not standing.restoring): return true
	var limits: Vector2 = standing.limits
	var angle := actual.orthonormalized().get_euler(EULER_ORDER_XYZ).z
	var desired := requested.orthonormalized().get_euler(EULER_ORDER_XYZ).z
	# Never contract through the current bend or a still-outstretched recovery target.
	var margin := deg_to_rad(2.0)+absf(angular_speed)*delta
	var lower := minf(limits.x,minf(angle-margin,desired))
	var upper := maxf(limits.y,maxf(angle+margin,desired))
	var rate: float = standing.speed*delta
	lower = minf(move_toward(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),lower,rate),angle-margin)
	upper = maxf(move_toward(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT),upper,rate),angle+margin)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,lower)
	joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,upper)
	if not is_equal_approx(lower,limits.x) or not is_equal_approx(upper,limits.y): return false
	joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,standing.enabled)
	joint.remove_meta(&"snake_bend_restore")
	return true

## Tighten each joint around a reachable target, never through its current solver anchors.
func _update_connections(delta: float) -> void:
	var ready := true
	var limits_ready := true
	var maximum_error := 0.0
	var maximum_excess := 0.0
	var maximum_error_ratio := 0.0
	var maximum_pose_error := 0.0
	var maximum_separation_speed := 0.0
	var worst: StringName = &"none"
	var blocked := 0
	var bend_limits_restoring := 0
	var structural_failure := false
	var structure_settled := true
	var blocked_parts: Array[StringName] = []
	for index: int in range(1,_parts.size()):
		var a: Dictionary = _parts[index-1]
		var b: Dictionary = _parts[index]
		if not _live(a) or not _live(b): continue
		var joint := _live_joint(b)
		if joint == null: continue
		var fa: Transform3D = a.body.global_transform*Transform3D(joint.get_meta(&"generated_joint_frame_a"))
		var fb: Transform3D = b.body.global_transform*Transform3D(joint.get_meta(&"generated_joint_frame_b"))
		var desired_a := _connection_pose(a)*Transform3D(joint.get_meta(&"generated_joint_frame_a"))
		var desired_b := _connection_pose(b)*Transform3D(joint.get_meta(&"generated_joint_frame_b"))
		if a.belly and not b.belly:
			var requested := desired_a.basis.inverse()*desired_b.basis
			var actual_rotation := fa.basis.inverse()*fb.basis
			var limit := minf(absf(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)),absf(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)))
			var needs_swivel := _independent_path_turning() and requested.get_rotation_quaternion().get_angle()>maxf(limit-deg_to_rad(3.0),0.0)
			if needs_swivel:
				# This joint's local Y may be tilted; free its angular stops while pose forces steer the upper chain.
				var saved: Array = []
				for axis: String in ["x","y","z"]:
					saved.append(joint.call("get_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT))
					joint.call("set_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,false)
				if not joint.has_meta(&"snake_raised_turn_limits"): joint.set_meta(&"snake_raised_turn_limits",saved)
			elif joint.has_meta(&"snake_raised_turn_limits"):
				var inside := true
				var angles := actual_rotation.get_euler()
				for axis: int in 3:
					var method: String = "get_param_"+["x","y","z"][axis]
					inside = inside and angles[axis]>=joint.call(method,Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT)-deg_to_rad(1.0) and angles[axis]<=joint.call(method,Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)+deg_to_rad(1.0)
				if inside:
					var saved: Array = joint.get_meta(&"snake_raised_turn_limits")
					for axis: int in 3: joint.call("set_flag_"+["x","y","z"][axis],Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,saved[axis])
					joint.remove_meta(&"snake_raised_turn_limits")
		if joint.has_meta(&"snake_bend_restore"):
			var angular_speed: float = (fa.basis.inverse()*(b.body.angular_velocity-a.body.angular_velocity)).z
			if not _restore_bend_limit(joint,fa.basis.inverse()*fb.basis,desired_a.basis.inverse()*desired_b.basis,angular_speed,delta):
				bend_limits_restoring += 1
				ready = false
				limits_ready = false
				structure_settled = false
		var desired := desired_a.affine_inverse()*desired_b.origin
		var bounds := _joint_slide_bounds(b,_path_ready or is_instance_valid(_attack_owner) or not _idle_ground_poses.is_empty())
		desired = desired.clamp(bounds.lower,bounds.upper)
		var actual := fa.affine_inverse()*fb.origin
		var error := Vector3(desired.x-actual.x,0,desired.z-actual.z)
		var velocity_a: Vector3 = a.body.linear_velocity+a.body.angular_velocity.cross(fa.origin-a.body.global_position)
		var velocity_b: Vector3 = b.body.linear_velocity+b.body.angular_velocity.cross(fb.origin-b.body.global_position)
		var relative_velocity: Vector3 = fa.basis.inverse()*(velocity_b-velocity_a-a.body.angular_velocity.cross(fb.origin-fa.origin))
		relative_velocity -= (desired-Vector3(b.get("connection_target",desired)))/delta
		b["connection_target"] = desired
		b["connection_error"] = error
		b["connection_relative_velocity"] = relative_velocity
		var width := minf(float(a.size.z),float(b.size.z))
		var length := minf(float(a.size.x),float(b.size.x))
		var tolerance := maxf(maxf(width*0.3+length*0.05,float(b.base_x_upper)),0.01)
		# Thin paper parts still need solver tolerance proportional to their anchor lever arms.
		var margin := maxf(maxf(width*0.1,length*0.05),0.005)
		var excess := 0.0
		if b.ground_pair: excess = maxf(0.0,a.body.global_position.distance_to(b.body.global_position)-float(bounds.maximum_center_distance))
		for axis: String in ["x","z"]:
			var component := 0 if axis == "x" else 2
			var lower: float = bounds.lower[component]
			var upper: float = bounds.upper[component]
			excess = maxf(excess,maxf(lower-actual[component],actual[component]-upper))
			var rate := maxf(length,width)*delta*4.0
			var current_lower: float = joint.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT)
			var current_upper: float = joint.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
			var next_lower := move_toward(current_lower,lower,rate)
			var next_upper := move_toward(current_upper,upper,rate)
			if not is_equal_approx(current_lower,next_lower): joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,next_lower)
			if not is_equal_approx(current_upper,next_upper): joint.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,next_upper)
			if absf(next_lower-lower)>margin*2.5 or absf(next_upper-upper)>margin*2.5:
				ready = false
				limits_ready = false
			if axis == "z":
				b.slide_lower = next_lower
				b.slide_upper = next_upper
		if error.length() > maximum_error:
			maximum_error = error.length()
			worst = b.body.name
		maximum_excess = maxf(maximum_excess,excess)
		structural_failure = structural_failure or excess>maxf(margin*2.0,float(b.rest_gap)*0.25)
		var center_delta: Vector3 = b.body.global_position-a.body.global_position
		var separation_speed: float = absf((b.body.linear_velocity-a.body.linear_velocity).dot(center_delta.normalized()))
		maximum_separation_speed = maxf(maximum_separation_speed,separation_speed)
		structure_settled = structure_settled and excess<=margin*2.0 and separation_speed<=maxf(length*0.3,0.15)
		maximum_pose_error = maxf(maximum_pose_error,Vector3(b.get("pose_error",Vector3.ZERO)).length()/maxf(Vector3(b.size).length()*0.04,0.01))
		maximum_error_ratio = maxf(maximum_error_ratio,maxf(error.length()/tolerance,maxf(excess,0.0)/(margin*2.0)))
		if excess>margin*2.0 or error.length()>tolerance or relative_velocity.slide(Vector3.UP).length()>maxf(length*0.3,0.15):
			ready = false
			blocked += 1
			if blocked_parts.size()<5: blocked_parts.append(b.body.name)
		# One bounded relative correction supplements the absolute pose controller.
		var acceleration := (error*motion_data.raised_pose_strength-relative_velocity.slide(Vector3.UP)*motion_data.raised_pose_damping).limit_length(motion_data.maximum_pose_acceleration)
		var reduced_mass: float = a.body.mass*b.body.mass/(a.body.mass+b.body.mass)
		var force := fa.basis*acceleration*reduced_mass*_support_blend
		b["connection_span_force"] = Vector3.ZERO
		if b.ground_pair and center_delta.length()>float(bounds.maximum_center_distance):
			var normal := center_delta.normalized()
			var response := maxf(motion_data.velocity_response_time*0.5,delta)
			var excess_distance := center_delta.length()-float(bounds.maximum_center_distance)
			var outward_speed := maxf((b.body.linear_velocity-a.body.linear_velocity).dot(normal),0.0)
			var span_acceleration := minf((excess_distance/(response*response)+outward_speed*2.0/response)/(1.0+2.0*delta/response+delta*delta/(response*response)),motion_data.maximum_pose_acceleration)
			var span_force := -normal*span_acceleration*reduced_mass*_support_blend
			# This radial safety acts at the centers, without adding a new twisting couple.
			a.body.apply_central_force(-span_force)
			b.body.apply_central_force(span_force)
			b.connection_span_force = span_force
		# A common anchor midpoint keeps the relative correction free of a net twisting couple.
		var midpoint := (fa.origin+fb.origin)*0.5
		a.body.apply_force(-force,midpoint-a.body.global_position)
		b.body.apply_force(force,midpoint-b.body.global_position)
	_connection_diagnostics = {"ready":ready,"limits_ready":limits_ready,"maximum_error":maximum_error,"maximum_excess":maximum_excess,"maximum_error_ratio":maximum_error_ratio,"worst_part":worst,"blocked_joints":blocked,"blocked_parts":blocked_parts,
		"maximum_pose_error_ratio":maximum_pose_error,"maximum_separation_speed":maximum_separation_speed,"structure_settled":structure_settled,"recovering":_connection_recovery_active,"settle_time":_connection_settle_time,"bend_limits_restoring":bend_limits_restoring,
		"profile":"attack" if is_instance_valid(_attack_owner) else "rejoining" if _connection_recovery_active else "locomotion" if _path_ready else "idle_hold"}
	if not is_instance_valid(_attack_owner) and not _connection_recovery_active and (_path_ready or _attack_slide_release_pending) and structural_failure:
		_begin_connection_recovery()
	if _connection_recovery_active:
		_connection_settle_time = _connection_settle_time+delta if structure_settled else 0.0
		if _connection_settle_time>=minf(0.2,motion_data.path_transition_time):
			_connection_recovery_active = false
			if _connection_recovery_resume_path and not _ground_path.points.is_empty():
				# Keep the visited route through rejoining; rebuilding a straight history would unfold a reversed belly.
				_idle_ground_poses.clear()
				_attack_slide_release_pending = false
				_path_ready = true
				_path_blend = 1.0
				for row: Dictionary in _parts:
					if not _live(row): continue
					row.path_target = row.body.global_position
					row.path_velocity = row.body.linear_velocity.slide(Vector3.UP)
					row.path_acceleration = Vector3.ZERO
					row.path_drive_acceleration = Vector3.ZERO
					row.erase("connection_target")
				for row: Dictionary in _parts:
					if row.belly or not _live(row): continue
					var offset: Vector3 = _path_pose_basis.inverse()*(Vector3(row.path_target)-Vector3(_path_leader.path_target))
					var rest_offset: Vector3 = row.rest.origin-_path_leader.rest.origin
					offset.x = rest_offset.x
					offset.y = rest_offset.y
					row.path_target = Vector3(_path_leader.path_target)+_path_pose_basis*offset
			_connection_recovery_resume_path = false
	if ready and not is_instance_valid(_attack_owner) and not _connection_recovery_active:
		_attack_slide_release_pending = false
		_path_slides_expanded = false
	_connection_diagnostics.recovering = _connection_recovery_active
	_connection_diagnostics.settle_time = _connection_settle_time
	_connection_diagnostics.profile = "attack" if is_instance_valid(_attack_owner) else "rejoining" if _connection_recovery_active else "locomotion" if _path_ready else "idle_hold"

func get_attack_connection_diagnostics() -> Dictionary:
	return _connection_diagnostics

func _physics_process(delta: float) -> void:
	var started := _control_perf.start()
	_tick(delta)
	_control_perf.finish(&"snake_motion", started)

func _tick(delta: float) -> void:
	_drive_force = Vector3.ZERO
	_contact_count = 0
	_traction_count = 0
	var frame := _update_anchor()
	if frame.is_empty() or not enabled or not _character_enabled or motion_data == null or not motion_data.is_valid():
		_configure_contacts(false)
		cancel_motion()
		return
	if get_parent().is_temporarily_ragdolled() or not get_parent().is_combat_alive():
		_configure_contacts(false)
		cancel_motion()
		return
	_configure_contacts(true)
	_direction = get_input_movement_direction()
	if _connection_recovery_active: _direction = Vector3.ZERO
	_actual_velocity = frame.travel_velocity
	_actual_yaw_speed = frame.yaw_speed
	var source := _source() if locomotion_enabled else null
	var speed := motion_data.target_speed
	if source != null and source.has_method("get_npc_movement_speed_scale"): speed *= source.get_npc_movement_speed_scale(speed)
	var target_velocity := _direction * speed
	if not _connection_recovery_active and not _direction.is_zero_approx() and not is_instance_valid(_attack_owner) and not _idle_ground_poses.is_empty():
		_idle_ground_poses.clear()
		_attack_slide_release_pending = false
		_path_slides_expanded = false
	var facing: Vector3 = source.get_generated_facing_direction(delta) if source != null and source.has_method("get_generated_facing_direction") else (_held_heading if locomotion_enabled else frame.heading)
	var attacking := is_instance_valid(_attack_owner)
	if attacking:
		target_velocity = Vector3.ZERO if _attack_support_locked else _attack_velocity
		facing = _attack_facing
		_direction = target_velocity.normalized()
	if not facing.is_finite() or facing.is_zero_approx(): facing = _held_heading
	facing = facing.slide(Vector3.UP).normalized()
	if _connection_recovery_active: facing = _held_heading
	_held_heading = facing
	_command_heading = facing
	var angle := atan2(frame.heading.cross(facing).y, frame.heading.dot(facing))
	_turn_rate = clampf(angle / motion_data.turn_response_time, -deg_to_rad(motion_data.turn_speed_degrees), deg_to_rad(motion_data.turn_speed_degrees))
	if is_attack_support_locked(): _turn_rate = 0.0
	if _connection_recovery_active: _turn_rate = 0.0
	_update_path_turning(delta,facing)
	for row: Dictionary in _torsos:
		if not _live(row): continue
		var contact: Dictionary = row.body.get_support_surface_contact()
		row["grounded"] = not contact.is_empty()
		if not contact.is_empty() and (not is_attack_support_locked() or row.belly):
			_contact_count += 1
	_traction_count = _contact_count
	var load_fraction := 1.0 if _contact_count > 0 else 0.0
	_support_blend = load_fraction if load_fraction >= _support_blend else move_toward(_support_blend, load_fraction, delta / maxf(motion_data.support_release_time, delta))
	_control_perf.count(&"torso_contacts", _contact_count)
	_update_sway(delta)
	_update_trajectories(delta)
	_update_ground_path(delta, speed, frame)
	for row: Dictionary in _parts: row["path_horizontal_force"] = Vector3.ZERO
	_apply_movement(frame, target_velocity)
	_apply_pose(frame, delta)
	_apply_path_pair_forces()
	_apply_path_horizontal_forces(delta)
	_update_connections(delta)

func _cache_trajectory_chain(container: Node) -> void:
	var rows: Dictionary = {}
	for row: Dictionary in _parts:
		rows[row.body] = row
		row["leader"] = {}
		row["incoming_joint"] = null
		row["follow_joint"] = null
		row["grounded"] = false
		row["trajectory_offset"] = Vector3.ZERO
		row["trajectory_velocity"] = Vector3.ZERO
		row["history"] = []
		row["movement_force"] = Vector3.ZERO
	for joint: Generic6DOFJoint3D in container.get_node("Joints").get_children():
		if joint.get_meta(&"generated_connection_kind", "") not in ["SnakeSpine", "SnakeHead"]: continue
		var a := joint.get_node(joint.node_a)
		var b := joint.get_node(joint.node_b)
		if not rows.has(a) or not rows.has(b): continue
		rows[a].leader = rows[b]
		rows[a].follow_joint = joint
		rows[b].incoming_joint = joint
		var callback := _on_joint_exiting.bind(joint)
		if not joint.tree_exiting.is_connected(callback): joint.tree_exiting.connect(callback)

func _sample_trajectory(row: Dictionary, time: float) -> Vector3:
	var history: Array = row.history
	if history.is_empty(): return Vector3.ZERO
	if time <= float(history[0].time): return history[0].offset
	for index: int in range(1, history.size()):
		if float(history[index].time) < time: continue
		var before: Dictionary = history[index-1]
		var after: Dictionary = history[index]
		return Vector3(before.offset).lerp(after.offset, (time-float(before.time))/maxf(float(after.time)-float(before.time), 0.00001))
	return history[-1].offset

func _update_trajectories(delta: float) -> void:
	if _uses_ground_path() or not _idle_ground_poses.is_empty():
		# The world route owns horizontal targets; do not chase delayed local-frame errors too.
		for row: Dictionary in _parts:
			row.trajectory_offset = Vector3.ZERO
			row.trajectory_velocity = Vector3.ZERO
		return
	_trajectory_time += delta
	var reference := get_pose_reference()
	var inverse := reference.affine_inverse()
	var active := not is_instance_valid(_attack_owner) and _contact_count > 0
	if active and motion_data.head_orbit_enabled: _orbit_time += delta
	_orbit_radius = 0.0
	for row: Dictionary in _parts:
		if not _live(row): continue
		var history: Array = row.history
		history.append({"time":_trajectory_time,"offset":inverse*row.body.global_position-Vector3(row.rest.origin)})
		while history.size() > 2 and float(history[1].time) < _trajectory_time-motion_data.trajectory_follow_delay-delta: history.pop_front()
	for row: Dictionary in _parts:
		if not _live(row): continue
		var desired := Vector3.ZERO
		var leader: Dictionary = row.leader
		if active and motion_data.trajectory_following_enabled and not leader.is_empty() and _live(leader) and is_instance_valid(row.follow_joint) and not row.follow_joint.is_queued_for_deletion():
			desired = _sample_trajectory(leader, _trajectory_time-motion_data.trajectory_follow_delay)
			if row.grounded: desired = Vector3(desired.x,0,0)
		elif active and motion_data.head_orbit_enabled and leader.is_empty() and row.body.get_meta(&"generated_role", "") == "Head":
			_orbit_radius = float(row.size.z)*motion_data.head_orbit_radius_widths
			var phase := TAU*_orbit_time/motion_data.head_orbit_period
			desired = Vector3(cos(phase),sin(phase),0)*_orbit_radius*smoothstep(0.0,0.5,_orbit_time)
		# Z has one owner; delayed actual Z samples would otherwise apply the wave twice.
		if motion_data.sway_enabled or _sway_strength > 0.0: desired.z = 0.0
		row["previous_trajectory_offset"] = row.trajectory_offset
		row.trajectory_offset = desired
	# Anchor the lateral follower targets at Head instead of accumulating solver drift down the chain.
	for index: int in range(_parts.size()-2,-1,-1):
		var row: Dictionary = _parts[index]
		if not _live(row) or row.grounded or row.leader.is_empty() or not _live(row.leader): continue
		var joint := _live_joint(row,&"follow_joint")
		if joint == null: continue
		var desired: Vector3 = row.trajectory_offset
		desired.z = clampf(desired.z, float(row.leader.trajectory_offset.z)-joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), float(row.leader.trajectory_offset.z)-joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT))
		row.trajectory_offset = desired
	# The chain is stored tail-to-head; restrict targets to each joint's reachable sliding range.
	for index: int in _parts.size():
		var row: Dictionary = _parts[index]
		if not _live(row): continue
		var joint := _live_joint(row)
		if index > 0 and not row.leader.is_empty() and joint != null:
			var parent: Dictionary = _parts[index-1]
			if _live(parent):
				var desired: Vector3 = row.trajectory_offset
				var x_slack := joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
				var y_slack := joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
				desired.x = clampf(desired.x, float(parent.trajectory_offset.x)-x_slack, float(parent.trajectory_offset.x)+x_slack)
				if not row.grounded: desired.y = clampf(desired.y, float(parent.trajectory_offset.y)-y_slack, float(parent.trajectory_offset.y)+y_slack)
				row.trajectory_offset = desired
		row.trajectory_velocity = (Vector3(row.trajectory_offset)-Vector3(row.previous_trajectory_offset))/delta if active else Vector3.ZERO

func _apply_movement(frame: Dictionary, target_velocity: Vector3) -> void:
	if is_attack_support_locked() or _connection_recovery_active:
		for row: Dictionary in _parts: row.movement_force = Vector3.ZERO
		return
	var reference := get_pose_reference()
	var attacking := is_instance_valid(_attack_owner)
	var relative_mean := Vector3.ZERO
	var mass := 0.0
	var rotation_center := Vector3.ZERO
	for row: Dictionary in _parts:
		if not _live(row): continue
		relative_mean += (Vector3(row.trajectory_velocity)+Vector3(0,0,row.sway_velocity))*row.body.mass
		rotation_center += row.body.global_position*row.body.mass
		mass += row.body.mass
	if mass > 0.0: relative_mean = reference.basis*relative_mean/mass
	# Turning around the belly instead of the driven mass center adds unintended lateral travel.
	rotation_center = rotation_center/mass if mass > 0.0 and motion_data.sway_enabled else Vector3(frame.center)
	for row: Dictionary in _parts:
		row.movement_force = Vector3.ZERO
		if not _live(row) or _contact_count == 0 or not locomotion_enabled: continue
		# Legacy attacks own the raised-chain velocity through their pose controller.
		if attacking and not row.belly: continue
		if attacking and _independent_path_turning() and row.belly: continue
		var body: PhysicalBodyPart3D = row.body
		var radius := body.global_position-rotation_center
		var relative_velocity: Vector3 = reference.basis*(Vector3(row.trajectory_velocity)+Vector3(0,0,row.sway_velocity))-relative_mean
		if attacking and _attack_pose_velocities.has(body): relative_velocity = reference.basis*Vector3(_attack_pose_velocities[body].linear)
		var motion_velocity := target_velocity+Vector3.UP.cross(radius)*_turn_rate
		if _independent_path_turning() and not attacking:
			motion_velocity = target_velocity
			if not row.belly: motion_velocity += Vector3.UP.cross(body.global_position-Vector3(_raised_turn_pivot().world))*_turn_rate
		var desired_velocity := motion_velocity+relative_velocity
		if _path_ready and _uses_ground_path():
			desired_velocity = Vector3(row.path_velocity)
			motion_velocity = desired_velocity
		var damping := body.linear_damp
		if body.linear_damp_mode == RigidBody3D.DAMP_MODE_COMBINE: damping += float(ProjectSettings.get_setting("physics/3d/default_linear_damp", 0.1))
		var response := _attack_response_time if attacking else motion_data.velocity_response_time
		var cap := _attack_acceleration if attacking else motion_data.maximum_acceleration
		var acceleration := ((desired_velocity-body.linear_velocity).slide(Vector3.UP)/response+motion_velocity*damping).limit_length(cap)
		if _path_ready and _uses_ground_path():
			# Curved travel needs acceleration even at constant speed; waiting for an error flattens the S.
			acceleration = (acceleration+Vector3(row.path_acceleration)).limit_length(cap)
		row.movement_force = acceleration*body.mass
		if _path_ready and _uses_ground_path(): row.path_horizontal_force += Vector3(row.movement_force).slide(Vector3.UP)
		else: body.apply_central_force(row.movement_force)
		_drive_force += Vector3(row.movement_force)

func _cache_sway_chain() -> void:
	_sway_chain.clear()
	_sway_links = 0
	var rows := {}
	var seen := {}
	for row: Dictionary in _parts:
		rows[row.body] = row
		row["sway_offset"] = 0.0
		row["sway_velocity"] = 0.0
	if _parts.is_empty(): return
	var row: Dictionary = _parts[-1]
	while not row.is_empty() and not seen.has(row.body):
		seen[row.body] = true
		row["sway_distance"] = _sway_chain.size()
		if row.belly and _sway_links == 0: _sway_links = _sway_chain.size()
		var joint := _live_joint(row)
		row["sway_joint"] = joint
		row["slide_lower"] = joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT) if joint != null else 0.0
		row["slide_upper"] = joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT) if joint != null else 0.0
		row["base_x_lower"] = joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT) if joint != null else 0.0
		row["base_x_upper"] = joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT) if joint != null else 0.0
		row["base_slide_lower"] = row.slide_lower
		row["base_slide_upper"] = row.slide_upper
		var previous: Node3D = joint.get_node(joint.node_a) if joint != null else null
		row["rest_gap"] = Vector3(row.rest.origin-rows[previous].rest.origin).length() if rows.has(previous) else 0.0
		row["ground_pair"] = rows.has(previous) and row.belly and rows[previous].belly
		_sway_chain.append(row)
		row = rows.get(joint.get_node(joint.node_a), {}) if joint != null else {}
	_update_wave_limits()

func _update_wave_limits() -> void:
	_sway_max_ground_offset = 0.0
	_sway_max_amplitude = 0.0
	_sway_period = _sway_links*motion_data.sway_segment_delay if motion_data != null else 0.0
	if _sway_links < 2 or _sway_period <= 0.0: return
	var phase_step := TAU/_sway_links
	var moving_difference := 2.0*sin(phase_step*0.5)
	var maximum := INF
	for index: int in _sway_chain.size()-1:
		var row := _sway_chain[index]
		if not _live(row) or not _live(_sway_chain[index+1]) or not is_instance_valid(row.sway_joint) or row.sway_joint.is_queued_for_deletion(): return
		var travel := minf(-float(row.base_slide_lower),float(row.base_slide_upper))
		if index < _sway_links: _sway_max_ground_offset += travel
		var a := maxf(1.0-float(index)/_sway_links,0.0)
		var b := maxf(1.0-float(index+1)/_sway_links,0.0)
		var idle_difference := sqrt(maxf(a*a+b*b-2.0*a*b*cos(phase_step),0.0))
		# Both endpoint envelopes must fit; every blend between them then fits too.
		maximum = minf(maximum,travel/maxf(maxf(moving_difference,idle_difference),0.00001))
	if is_finite(maximum): _sway_max_amplitude = maxf(maximum,0.0)

func _update_sway(delta: float) -> void:
	_sway_amplitude = 0.0
	if _sway_chain.is_empty(): return
	_update_wave_limits()
	var attacking := is_instance_valid(_attack_owner)
	var active := motion_data.sway_enabled and not attacking and not _connection_recovery_active and _idle_ground_poses.is_empty() and _support_blend > 0.0 and _sway_max_amplitude > 0.0
	if not locomotion_enabled or not active:
		_sway_travelling = false
	elif not _direction.is_zero_approx():
		_sway_travelling = true
	elif _actual_velocity.slide(Vector3.UP).length() <= motion_data.sway_stop_speed:
		_sway_travelling = false
	_sway_strength = move_toward(_sway_strength,1.0 if active else 0.0,delta/motion_data.sway_transition_time) if not attacking else 0.0
	_sway_travel_blend = move_toward(_sway_travel_blend,1.0 if _sway_travelling else 0.0,delta/motion_data.sway_transition_time)
	if active:
		_sway_time += delta
		_sway_phase = fposmod(_sway_phase+TAU*delta/_sway_period,TAU)
	_sway_amplitude = _sway_max_amplitude*motion_data.sway_amplitude_ratio*smoothstep(0.0,1.0,_sway_strength)
	var blend := 0.0 if _uses_ground_path() else smoothstep(0.0,1.0,_sway_travel_blend)
	for index: int in _sway_chain.size():
		var row := _sway_chain[index]
		var idle_weight := maxf(1.0-float(index)/maxi(_sway_links,1),0.0)
		var weight := lerpf(idle_weight,1.0,blend)
		var phase := _sway_phase-TAU*index/maxi(_sway_links,1)
		var offset := _sway_amplitude*weight*sin(phase) if _live(row) else 0.0
		row.sway_velocity = (offset-float(row.sway_offset))/delta if not attacking else 0.0
		row.sway_offset = offset

func _uses_ground_path() -> bool:
	return motion_data != null and motion_data.ground_path_enabled and motion_data.sway_enabled \
		and motion_data.trajectory_following_enabled and not motion_data.head_orbit_enabled \
		and not is_instance_valid(_attack_owner) and not _connection_recovery_active and _idle_ground_poses.is_empty() and locomotion_enabled

func _set_path_slide_limits(active: bool) -> void:
	if is_instance_valid(_attack_owner) or not _idle_ground_poses.is_empty() or _attack_slide_release_pending: return
	if active == _path_slides_expanded: return
	if not active:
		if is_instance_valid(_attack_owner): return
		# Contract only after the physical anchors have returned inside the original travel.
		for row: Dictionary in _sway_chain:
			var joint := _live_joint(row,&"sway_joint")
			if joint == null: continue
			var a := joint.get_node_or_null(joint.node_a) as Node3D
			var b := joint.get_node_or_null(joint.node_b) as Node3D
			if a == null or b == null or not a.is_inside_tree() or not b.is_inside_tree(): continue
			var fa: Transform3D = a.global_transform*Transform3D(joint.get_meta(&"generated_joint_frame_a"))
			var fb: Transform3D = b.global_transform*Transform3D(joint.get_meta(&"generated_joint_frame_b"))
			var offset: Vector3 = fa.affine_inverse()*fb.origin
			if offset.x < float(row.base_x_lower)*0.9 or offset.x > float(row.base_x_upper)*0.9: return
			if offset.z < float(row.base_slide_lower)*0.9 or offset.z > float(row.base_slide_upper)*0.9: return
	_path_slides_expanded = active
	if not active: _attack_slide_release_pending = false
	for row: Dictionary in _sway_chain:
		var joint := _live_joint(row,&"sway_joint")
		if joint == null: continue
		var bounds := _joint_slide_bounds(row,active)
		if bounds.is_empty(): continue
		row.sway_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,bounds.lower.x)
		row.sway_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,bounds.upper.x)
		row.slide_lower = bounds.lower.z
		row.slide_upper = bounds.upper.z
		row.sway_joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,row.slide_lower)
		row.sway_joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,row.slide_upper)

func _cache_spacing_wave() -> void:
	_spacing_pairs.clear()
	_spacing_shape_amplitude = 0.0
	_spacing_anchor = _parts.find(_path_leader)
	_spacing_phase = deg_to_rad(motion_data.spacing_wave_phase_degrees)
	_spacing_blend = 0.0
	_spacing_ratio = 0.0
	var coordinates: Array[float] = [0.0]
	for index: int in _parts.size():
		_spacing_pairs.append({})
		if index > 0: coordinates.append(coordinates[-1]+Vector3(_parts[index].rest.origin-_parts[index-1].rest.origin).length())
	var k := TAU*motion_data.spacing_wave_frequency_ratio/_ground_path.wavelength
	for index: int in _parts.size():
		_parts[index]["raised_wave_distance"] = maxf(coordinates[index]-coordinates[_spacing_anchor],0.0)
	for index: int in range(1,_parts.size()):
		var a: Dictionary = _parts[index-1]
		var b: Dictionary = _parts[index]
		if not a.belly or not b.belly: continue
		var gap := maxf(float(a.path_gap)-float(b.path_gap),0.001)
		_spacing_pairs[index] = {"a":index-1,"b":index,"gap":gap,"amplitude":gap*0.15,
			"phase":k*((coordinates[index]+coordinates[index-1])*0.5-coordinates[_spacing_anchor])}
	_update_spacing_envelope()

func _update_spacing_envelope() -> void:
	_spacing_shape_amplitude = 0.0
	# Bound the maximum accumulated displacement of the arc-length spacing wave.
	for direction: int in [-1,1]:
		var cosine := 0.0
		var sine := 0.0
		var index := _spacing_anchor+direction
		while index >= 0 and index < _parts.size():
			var pair: Dictionary = _spacing_pairs[index if direction > 0 else index+1]
			if pair.is_empty() or not _live(_parts[index]): break
			cosine += float(pair.amplitude)*cos(pair.phase)
			sine += float(pair.amplitude)*sin(pair.phase)
			_spacing_shape_amplitude = maxf(_spacing_shape_amplitude,sqrt(cosine*cosine+sine*sine))
			index += direction

func _spacing_sample(index: int, distance: float, reference: Transform3D, drive_speed: float = 0.0, yaw_speed: float = 0.0) -> Dictionary:
	var row: Dictionary = _parts[index]
	var position := Vector3.ZERO
	var tangent := Vector3.ZERO
	var frame_velocity := Vector3(row.path_idle_velocity)
	if row.belly:
		var sample: Dictionary = _ground_path.sample(distance)
		position = sample.position
		tangent = sample.tangent
	else:
		# Preserve backward bends in the authored XY layout; only the Z wave travels along the upper chain.
		var anchor: Dictionary = _ground_path.sample(_path_progress)
		var k := TAU/_ground_path.wavelength
		var phase := k*float(anchor.u)
		var upper_phase := phase+k*float(row.raised_wave_distance)
		var wave := _path_amplitude*(sin(upper_phase)-sin(phase))
		var phase_speed := k*drive_speed*Vector3(anchor.tangent).dot(anchor.forward)
		var wave_speed := _path_amplitude*phase_speed*(cos(upper_phase)-cos(phase))
		var root := _raised_turn_pivot()
		var offset := reference.basis*(Vector3(row.rest.origin)-Vector3(root.rest)+Vector3(0,0,wave))
		position = Vector3(root.world)+(Vector3(anchor.position)-_path_leader.body.global_position).slide(Vector3.UP)+offset
		frame_velocity += Vector3(anchor.tangent)*drive_speed+reference.basis.z*wave_speed+Vector3.UP.cross(offset)*yaw_speed
		distance = _path_progress
	position.y = (reference*Vector3(row.rest.origin)).y
	position += Vector3(row.path_idle_offset)
	return {"distance":distance,"position":position,"tangent":tangent,"frame_velocity":frame_velocity,"velocity":Vector3.ZERO}

func _plan_spacing_wave(reference: Transform3D, drive_speed: float, strength: float, strength_rate: float, yaw_speed: float, _delta: float = 0.0) -> Array[Dictionary]:
	var samples: Array[Dictionary] = []
	for index: int in _parts.size():
		var sample := _spacing_sample(index,_path_progress-float(_parts[index].path_gap),reference,drive_speed,yaw_speed)
		sample["route_position"] = sample.position
		sample["route_velocity"] = Vector3(sample.tangent)*drive_speed+Vector3(sample.frame_velocity)
		sample["wave_offset"] = Vector3.ZERO
		sample["wave_velocity"] = Vector3.ZERO
		sample["s_speed"] = drive_speed
		sample["velocity"] = sample.route_velocity
		samples.append(sample)
		if not _parts[index].belly:
			_parts[index]["spacing_target_s"] = 0.0
			_parts[index]["spacing_amplitude"] = 0.0
			_parts[index]["spacing_offset_world"] = Vector3.ZERO
			_parts[index]["spacing_axis_world"] = Vector3.ZERO
	_parts[_spacing_anchor]["spacing_offset_world"] = Vector3.ZERO
	_parts[_spacing_anchor]["spacing_target_s"] = 0.0
	_parts[_spacing_anchor]["spacing_axis_world"] = samples[_spacing_anchor].tangent
	for direction: int in [-1,1]:
		var index := _spacing_anchor+direction
		while index >= 0 and index < _parts.size():
			var pair: Dictionary = _spacing_pairs[index if direction > 0 else index+1]
			var neighbor: int = index-direction
			if pair.is_empty() or not _live(_parts[index]) or not _live(_parts[neighbor]): break
			var phase: float = _spacing_phase+float(pair.phase)
			var extra_gap: float = float(pair.amplitude)*strength*sin(phase)
			var distance: float = float(samples[neighbor].distance)+direction*(float(pair.gap)+extra_gap)
			var candidate := _spacing_sample(index,distance,reference,drive_speed,yaw_speed)
			candidate["route_position"] = samples[index].route_position
			candidate["wave_offset"] = Vector3(candidate.position)-Vector3(candidate.route_position)
			var gap_speed: float = float(pair.amplitude)*(strength_rate*sin(phase)+strength*_spacing_phase_rate*cos(phase))
			candidate["s_speed"] = float(samples[neighbor].s_speed)+direction*gap_speed
			candidate["route_velocity"] = samples[index].route_velocity
			candidate["velocity"] = Vector3(candidate.tangent)*float(candidate.s_speed)+Vector3(candidate.frame_velocity)
			candidate["wave_velocity"] = Vector3(candidate.velocity)-Vector3(candidate.route_velocity)
			samples[index] = candidate
			_parts[pair.b]["spacing_target_s"] = extra_gap
			_parts[pair.b]["spacing_amplitude"] = float(pair.amplitude)*strength
			_parts[index]["spacing_axis_world"] = candidate.tangent
			_parts[index]["spacing_offset_world"] = candidate.wave_offset
			index += direction
	return samples

func _start_ground_path(_speed: float) -> void:
	_set_path_slide_limits(true)
	_path_leader = _sway_chain[_sway_links]
	var raised_length := 0.0
	var max_slope := 0.3
	var shortest := INF
	_path_length = 0.0
	for index: int in _sway_chain.size()-1:
		var a: Dictionary = _sway_chain[index]
		var b: Dictionary = _sway_chain[index+1]
		var distance := Vector3(a.rest.origin).distance_to(b.rest.origin)
		if index < _sway_links: raised_length += distance
		var dx := absf(float(a.rest.origin.x)-float(b.rest.origin.x))
		var width := minf(-float(a.base_slide_lower),float(a.base_slide_upper))*motion_data.path_joint_slide_widths
		if dx > 0.00001: max_slope = minf(max_slope,width*0.8/dx)
		if a.belly and b.belly:
			_path_length += dx
			shortest = minf(shortest,dx)
			var slack: float = a.base_x_upper
			# Keep the original S-wave amplitude while the path uses wider emergency joint travel.
			max_slope = minf(max_slope,sqrt(maxf(2.0*slack/maxf(dx,0.00001),0.0))*0.8)
	var wavelength := maxf(raised_length*motion_data.path_wavelength_ratio,0.1)
	_path_max_amplitude = max_slope*wavelength/TAU
	_path_amplitude = _path_max_amplitude*motion_data.path_amplitude_ratio
	var spacing := maxf(minf(shortest*0.15,wavelength/80.0),0.005)
	var forward: Vector3 = _part_turn_basis(_path_leader).x.slide(Vector3.UP).normalized()
	if not _independent_path_turning():
		_path_pose_basis = _turn_basis(forward)
		_path_pose_yaw_speed = 0.0
	_path_execution_speed_scale = 1.0
	for row: Dictionary in _parts:
		row["path_gap"] = float(_path_leader.rest.origin.x)-float(row.rest.origin.x)
		row["path_target"] = row.body.global_position
		row["path_start_position"] = row.body.global_position
		row["path_velocity"] = row.body.linear_velocity.slide(Vector3.UP)
		row["path_raw_target"] = row.path_target
		row["path_raw_velocity"] = row.path_velocity
		row["path_acceleration"] = Vector3.ZERO
		row["path_drive_acceleration"] = Vector3.ZERO
		row["path_applied_force"] = Vector3.ZERO
		row.erase("path_relative_offset")
		row["path_distance"] = -float(row.path_gap)
		row["turn_distance"] = row.path_distance
		row["path_idle_offset"] = Vector3.ZERO
	var gap := 0.0
	for index: int in range(_sway_links+1,_sway_chain.size()):
		var a: Dictionary = _sway_chain[index-1]
		var b: Dictionary = _sway_chain[index]
		gap += Vector3(a.rest.origin-b.rest.origin).slide(Vector3.UP).length()
		b.path_gap = gap
	_ground_path.reset(_path_leader.body.global_position,forward,maxf(_path_length*3.0,wavelength*2.0),wavelength,_path_amplitude,spacing)
	_path_facing_command = _path_leader.get("turn_heading",_rest_heading)
	_ground_path.turn_markers[0].facing = _path_facing_command
	_path_reversing = false
	_cache_spacing_wave()
	_path_progress = 0.0
	_path_blend = 0.0
	_path_speed = 0.0
	_path_frequency = 0.0
	_path_ready = true

func _clear_spacing_wave() -> void:
	_spacing_pairs.clear()
	_spacing_phase = 0.0
	_spacing_phase_rate = 0.0
	_spacing_blend = 0.0
	_spacing_ratio = 0.0
	_spacing_shape_amplitude = 0.0
	_spacing_acceleration_bound = 0.0
	_spacing_limit_reason = "inactive"
	for row: Dictionary in _parts:
		row["spacing_target_s"] = 0.0
		row["spacing_amplitude"] = 0.0
		row["spacing_offset_world"] = Vector3.ZERO
		row["spacing_axis_world"] = Vector3.ZERO
		row["pair_force"] = Vector3.ZERO

func _update_ground_path(delta: float, speed: float, frame: Dictionary) -> void:
	if _connection_recovery_active: return
	if is_instance_valid(_attack_owner):
		# Preserve route history and per-part progress while the attack owns physical targets.
		_path_speed = 0.0
		_path_frequency = 0.0
		_spacing_phase_rate = 0.0
		return
	if not _uses_ground_path() or _sway_links <= 0 or _sway_links >= _sway_chain.size():
		if not _spacing_pairs.is_empty(): _clear_spacing_wave()
		_set_path_slide_limits(false)
		_path_ready = false
		_path_blend = 0.0
		_path_speed = 0.0
		_path_frequency = 0.0
		_path_reversing = false
		return
	if not _path_ready:
		if _direction.is_zero_approx() or _contact_count == 0: return
		_start_ground_path(speed)
	if not _live(_path_leader):
		_set_path_slide_limits(false)
		_path_ready = false
		return
	var guide: Dictionary = _ground_path.sample(_path_progress)
	var heading: Vector3 = guide.forward
	if not _direction.is_zero_approx():
		heading = _direction.normalized()
		if not _path_reversing and heading.dot(guide.forward) < -0.5:
			_path_reversing = true
		if _path_reversing and heading.dot(guide.forward) > 0.98:
			_path_reversing = false
	var preview := maxf(_ground_path.wavelength,_path_length*0.5)
	var occupied_high := _path_progress
	for row: Dictionary in _belly:
		if _live(row): occupied_high = maxf(occupied_high,float(row.path_distance))
	_ground_path.ensure(_path_progress,preview,heading,occupied_high)
	var previous_progress := _path_progress
	var radius := maxf(_path_leader.body.linear_velocity.length()*delta*2.0,_ground_path.step*2.0)
	_path_progress = _ground_path.project(_path_leader.body.global_position,_path_progress,radius,true)
	if _path_facing_command.dot(_command_heading)<0.999:
		var marker_distance := maxf(occupied_high,_path_progress)
		for row: Dictionary in _belly:
			if not _live(row): continue
			var actual := _ground_path.project(row.body.global_position,float(row.path_distance),maxf(float(row.size.x)*2.0,_ground_path.step*2.0),true)
			marker_distance = maxf(marker_distance,actual)
		_ground_path.mark_turn(marker_distance+_ground_path.step,_command_heading)
		_path_facing_command = _command_heading
	_path_speed = (_path_progress-previous_progress)/delta
	var phase_travel := float(_ground_path.sample(_path_progress).u)-float(guide.u)
	_path_frequency = absf(phase_travel)/delta/_ground_path.wavelength
	var k := TAU*motion_data.spacing_wave_frequency_ratio/_ground_path.wavelength
	_spacing_phase_rate = k*phase_travel/delta
	_spacing_phase = fposmod(_spacing_phase+k*phase_travel,TAU)
	_path_blend = move_toward(_path_blend,1.0,delta/motion_data.path_transition_time)
	var blend := smoothstep(0.0,1.0,_path_blend)
	var reference := get_pose_reference()
	var drive_speed := speed*_direction.length() if _contact_count > 0 else 0.0
	_path_execution_speed_scale = 1.0
	# Give cornering followers time to catch up instead of stretching the chain at full speed.
	for row: Dictionary in _belly:
		if not _live(row) or not row.has("path_raw_target"): continue
		var lag: float = Vector3(row.path_target-row.path_raw_target).slide(Vector3.UP).length()
		var allowance: float = row.size.z*motion_data.path_corner_rounding_widths
		_path_execution_speed_scale = minf(_path_execution_speed_scale,sqrt(allowance/maxf(lag,allowance)))
	drive_speed *= _path_execution_speed_scale
	# The raised frame turns independently; grounded frames consume the route's turn markers.
	reference.basis = _path_pose_basis
	# The moving belly reference must not add last frame's vertical stretch a second time.
	var wave_height := 0.0
	var belly_mass := 0.0
	for row: Dictionary in _belly:
		if not _live(row): continue
		wave_height += Vector3(row.get("spacing_offset_world",Vector3.ZERO)).y*row.body.mass
		belly_mass += row.body.mass
	if belly_mass > 0.0: reference.origin.y -= wave_height/belly_mass
	_update_spacing_envelope()
	var previous_strength := _spacing_ratio*smoothstep(0.0,1.0,_spacing_blend)
	var active := motion_data.spacing_wave_enabled and not _direction.is_zero_approx() and _contact_count > 0
	_spacing_blend = move_toward(_spacing_blend,1.0 if active else 0.0,delta/motion_data.path_transition_time)
	var validated_speed := maxf(maxf(speed,motion_data.target_speed),absf(_path_speed))
	var omega := k*validated_speed
	var base_acceleration := validated_speed*validated_speed*_path_amplitude*pow(TAU/_ground_path.wavelength,2.0)
	var budget := maxf(motion_data.maximum_acceleration*0.8-base_acceleration,0.0)
	var requested_ratio := motion_data.spacing_wave_amplitude_ratio
	var safe_ratio := minf(requested_ratio,budget/maxf(omega*omega*_spacing_shape_amplitude,0.000001))
	_spacing_limit_reason = "acceleration" if safe_ratio < requested_ratio-0.000001 else "none"
	if not motion_data.spacing_wave_enabled: _spacing_limit_reason = "disabled"
	_spacing_ratio = minf(safe_ratio,move_toward(_spacing_ratio,safe_ratio,delta*0.8/motion_data.path_transition_time))
	_spacing_acceleration_bound = omega*omega*_spacing_shape_amplitude*_spacing_ratio
	var strength := _spacing_ratio*smoothstep(0.0,1.0,_spacing_blend)
	var strength_rate := (strength-previous_strength)/delta
	for row: Dictionary in _parts:
		if not _live(row): continue
		# Idle sway fades into the shared path, with zero weight and zero slope at the ground boundary.
		var raised_weight := smoothstep(0.0,1.0,maxf(1.0-float(row.sway_distance)/_sway_links,0.0))
		var idle := _sway_amplitude*0.5*(1.0-smoothstep(0.0,1.0,_sway_travel_blend))*raised_weight*sin(_sway_phase-TAU*float(row.sway_distance)/_sway_links)
		var idle_offset := reference.basis.z*idle
		row["path_idle_velocity"] = (idle_offset-Vector3(row.path_idle_offset))/delta
		row.path_idle_offset = idle_offset
	# Followers' positions advance with measured leader progress, not the requested speed.
	var samples := _plan_spacing_wave(reference,_path_speed,strength,strength_rate,_path_pose_yaw_speed,delta)
	samples[_spacing_anchor].velocity = Vector3(samples[_spacing_anchor].tangent)*drive_speed+Vector3(samples[_spacing_anchor].frame_velocity)
	for index: int in _parts.size():
		var row: Dictionary = _parts[index]
		if not _live(row): continue
		var sample: Dictionary = samples[index]
		var initial: Vector3 = reference*(Vector3(row.rest.origin)+Vector3(0,0,row.sway_offset))
		if row.belly: initial = row.path_start_position
		row["path_raw_target"] = initial.lerp(Vector3(sample.position),blend)
		row["path_route_target"] = sample.route_position
		row.path_distance = sample.distance
		var velocity: Vector3 = Vector3(guide.tangent)*drive_speed*(1.0-blend)+Vector3(sample.velocity)*blend
		row["path_raw_velocity"] = velocity
	_smooth_path_targets(delta,drive_speed)

func _smooth_path_targets(delta: float, drive_speed: float) -> void:
	var previous: Dictionary = {}
	for row: Dictionary in _belly:
		previous[row.body] = {"position":row.path_target,"velocity":row.path_velocity,"acceleration":row.path_acceleration}
	var cap := motion_data.maximum_acceleration
	var response := motion_data.path_execution_response_time
	var jerk := motion_data.path_maximum_jerk
	var rounding: float = _path_leader.size.z*motion_data.path_corner_rounding_widths
	var limit := _ground_path.corner_speed_limit(_path_progress,drive_speed,cap,jerk,rounding)
	_path_leader["path_corner_speed_limit"] = limit
	for row: Dictionary in _belly:
		if not _live(row): continue
		var desired: Vector3 = row.path_raw_velocity
		if row.body == _path_leader.body and drive_speed > 0.0: desired *= limit/drive_speed
		desired = _ground_path.anticipate_velocity(row.path_distance,desired,cap,jerk)
		row["path_corner_speed"] = desired.length()
		row["path_desired_velocity"] = desired
		var position: Vector3 = row.path_target
		var velocity: Vector3 = row.path_velocity
		var acceleration: Vector3 = row.path_acceleration
		# Substeps keep the same stable integration when a tool/test supplies a long frame.
		var steps := maxi(ceili(delta*60.0),1)
		var dt := delta/steps
		for step_index: int in steps:
			var error: Vector3 = (Vector3(row.path_raw_target)-position).slide(Vector3.UP)
			# Position feedback must be able to cancel feed-forward when real route progress stalls.
			var correction := error/response
			var requested := ((desired+correction-velocity)*(2.0/response)).limit_length(cap)
			var next_acceleration := acceleration.move_toward(requested,jerk*dt).limit_length(cap)
			var next_velocity := velocity+(acceleration+next_acceleration)*(dt*0.5)
			position += (velocity+next_velocity)*(dt*0.5)
			velocity = next_velocity
			acceleration = next_acceleration
		position.y = row.path_raw_target.y
		row.path_target = position
		row.path_velocity = velocity
		row.path_acceleration = acceleration
	var poses: Dictionary = {}
	for row: Dictionary in _parts:
		poses[row.body] = Transform3D(_part_turn_basis(row)*Basis(row.rest.basis),row.path_target)
	var constrained := _constrain_connection_poses(poses,true)
	for row: Dictionary in _belly:
		var pose: Transform3D = constrained[row.body]
		row["path_constraint_offset"] = pose.origin-Vector3(row.path_target)
		if Vector3(row.path_constraint_offset).is_zero_approx(): continue
		row.path_target = pose.origin
		var old: Dictionary = previous[row.body]
		var desired := ((pose.origin-Vector3(old.position))/delta).limit_length(maxf(drive_speed,Vector3(row.path_raw_velocity).length()))
		var acceleration := ((desired-Vector3(old.velocity))/delta).limit_length(cap)
		row.path_acceleration = Vector3(old.acceleration).move_toward(acceleration,jerk*delta).limit_length(cap)
		row.path_velocity = Vector3(old.velocity)+Vector3(row.path_acceleration)*delta
	for row: Dictionary in _parts:
		if row.belly or not _live(row): continue
		# The raised chain shares the executed anchor, preserving every authored backward XY bend.
		var offset: Vector3 = Vector3(row.path_raw_target)-Vector3(_path_leader.path_raw_target)
		var relative_velocity := (offset-Vector3(row.get("path_relative_offset",offset)))/delta
		var velocity: Vector3 = Vector3(_path_leader.path_velocity)+relative_velocity
		row.path_target = Vector3(_path_leader.path_target)+offset
		row.path_acceleration = (velocity-Vector3(row.path_velocity))/delta
		row.path_velocity = velocity
		row.path_relative_offset = offset

func _apply_pose(frame: Dictionary, delta: float) -> void:
	_attack_ground_error = 0.0
	if _support_blend <= 0.0: return
	var reaction := Vector3.ZERO
	var reference_pose := get_pose_reference()
	var ground_wave := (motion_data.sway_enabled or _sway_strength > 0.0) and not is_instance_valid(_attack_owner)
	for row: Dictionary in _parts:
		if not _live(row): continue
		var body: PhysicalBodyPart3D = row.body
		var rate := _attack_pose_speed_multiplier if is_instance_valid(_attack_owner) and not row.belly else 1.0
		var gain: float = motion_data.raised_pose_strength*rate*rate
		var damping: float = motion_data.raised_pose_damping*rate
		var held: bool = is_attack_support_locked() or _connection_recovery_active or (_independent_path_turning() and is_instance_valid(_attack_owner) and row.belly)
		if held and row.belly:
			var support_response := (_attack_response_time if is_attack_support_locked() else motion_data.velocity_response_time)*0.5
			if _independent_path_turning(): support_response = minf(support_response,_attack_response_time*0.5)
			gain = 1.0/(support_response*support_response)
			damping = 2.0/support_response
		var denominator := 1.0+damping*delta+gain*delta*delta
		var local_pose: Transform3D = _attack_poses.get(body, row.rest) if is_instance_valid(_attack_owner) else _idle_ground_poses.get(body,row.rest)
		if not is_instance_valid(_attack_owner) and not row.belly: local_pose = _held_root_delta()*local_pose
		if not is_instance_valid(_attack_owner):
			local_pose.origin += Vector3(row.trajectory_offset)
			local_pose.origin.z += float(row.sway_offset)
		var target_pose := reference_pose * local_pose
		var world_path := _path_ready and _uses_ground_path()
		if world_path: target_pose.origin = row.path_target
		var target_basis := target_pose.basis
		if world_path: target_basis = _part_turn_basis(row)*Basis(row.rest.basis)
		if _independent_path_turning() and not is_instance_valid(_attack_owner) and not _connection_recovery_active and row.belly:
			target_basis = _part_turn_basis(row)*Basis(row.rest.basis)
			if not world_path:
				var anchor: Vector3 = row.get("idle_turn_anchor",body.global_position)
				target_pose.origin.x = anchor.x
				target_pose.origin.z = anchor.z
		# Keep the authored pitch/roll; damp yaw toward the shared grounded turn rate.
		var error := target_basis.get_rotation_quaternion() * body.global_basis.orthonormalized().get_rotation_quaternion().inverse()
		if error.w < 0.0: error = -error
		var angular_error := error.get_axis() * error.get_angle()
		if locomotion_enabled and not _independent_path_turning() and not is_instance_valid(_attack_owner) and not world_path and _idle_ground_poses.is_empty(): angular_error = angular_error.slide(Vector3.UP)
		var desired_linear := Vector3.ZERO
		if not is_instance_valid(_attack_owner): desired_linear = reference_pose.basis*(Vector3(row.trajectory_velocity)+Vector3(0,0,row.sway_velocity))
		var desired_angular := Vector3.ZERO
		desired_angular.y = _turn_rate if _contact_count > 0 else 0.0
		if _independent_path_turning() and row.belly and not is_instance_valid(_attack_owner): desired_angular.y = float(row.get("turn_rate",0.0))
		if is_instance_valid(_attack_owner) and _attack_pose_velocities.has(body):
			desired_linear = reference_pose.basis*Vector3(_attack_pose_velocities[body].linear)
			desired_angular = reference_pose.basis*Vector3(_attack_pose_velocities[body].angular)
			desired_angular.y = _turn_rate if _contact_count > 0 else 0.0
		if _independent_path_turning() and is_instance_valid(_attack_owner) and row.belly:
			desired_linear = Vector3.ZERO
			desired_angular = Vector3.ZERO
		var angular_cap := _attack_angular_acceleration if is_instance_valid(_attack_owner) else motion_data.maximum_angular_acceleration
		var angular_acceleration := ((angular_error * gain + (desired_angular-body.angular_velocity) * damping) / denominator).limit_length(angular_cap)
		var inverse := body.get_inverse_inertia_tensor()
		var torque := Vector3.ZERO
		if absf(inverse.determinant()) > 1e-18:
			torque = (inverse.inverse() * angular_acceleration * _support_blend).limit_length(motion_data.maximum_pose_torque)
			body.apply_torque(torque)
		var force := Vector3.ZERO
		var position_error := Vector3.ZERO
		position_error = target_pose.origin - body.global_position
		if is_attack_support_locked() and row.belly: _attack_ground_error = maxf(_attack_ground_error,position_error.slide(Vector3.UP).length())
		if row.grounded and not world_path:
			position_error = position_error.slide(reference_pose.basis.y) if ground_wave or is_instance_valid(_attack_owner) else reference_pose.basis.x*position_error.dot(reference_pose.basis.x)
		var cap := _attack_pose_acceleration if is_instance_valid(_attack_owner) else motion_data.maximum_pose_acceleration
		if held and row.belly: cap = _attack_acceleration if is_instance_valid(_attack_owner) else motion_data.maximum_pose_acceleration
		var moving_frame_velocity := Vector3(frame.velocity)+Vector3.UP.cross(body.global_position-Vector3(frame.center))*float(frame.yaw_speed)
		if held: moving_frame_velocity = Vector3.ZERO
		if _independent_path_turning() and row.belly and row.has("idle_turn_anchor"): moving_frame_velocity = Vector3.ZERO
		if _independent_path_turning() and is_instance_valid(_attack_owner) and row.belly: moving_frame_velocity = Vector3.ZERO
		var velocity_error := moving_frame_velocity+desired_linear-body.linear_velocity
		if world_path: velocity_error = Vector3(row.path_velocity)-body.linear_velocity
		if row.grounded and not world_path:
			velocity_error = velocity_error.slide(reference_pose.basis.y) if ground_wave or is_instance_valid(_attack_owner) else reference_pose.basis.x*velocity_error.dot(reference_pose.basis.x)
		var correction: Vector3 = ((position_error * gain + velocity_error * damping) / denominator).limit_length(cap)
		force = (correction-(body.get_gravity() if not row.grounded else Vector3.ZERO))*body.mass*_support_blend
		if world_path:
			row.path_horizontal_force += force.slide(Vector3.UP)
			body.apply_central_force(Vector3.UP*force.y)
		else: body.apply_central_force(force)
		# World-route tracking is an external drive; cancelling its horizontal reaction would oppose it.
		# Fixed belly tracking is external ground support; cancelling it would release the anchor.
		if not held or not row.belly:
			reaction -= (Vector3.UP*correction.y if world_path else correction)*body.mass*_support_blend
		row["pose_error"] = position_error
		row["posture_torque"] = torque
		row["support_force"] = force
	# Posture corrections are internal; only gravity compensation supplies net lift.
	if is_instance_valid(_attack_owner):
		# A supported attack absorbs upward return reactions instead of launching the belly off the floor.
		reaction.y = minf(reaction.y,0.0)
	var support_mass := 0.0
	for row: Dictionary in _torsos:
		if _live(row) and row.grounded and (not is_attack_support_locked() or row.belly): support_mass += row.body.mass
	if support_mass > 0.0:
		for row: Dictionary in _torsos:
			if _live(row) and row.grounded and (not is_attack_support_locked() or row.belly): row.body.apply_central_force(reaction*row.body.mass/support_mass)

func _apply_path_pair_forces() -> void:
	if not _path_ready or not _uses_ground_path() or _contact_count == 0: return
	for index: int in range(1,_parts.size()):
		var a: Dictionary = _parts[index-1]
		var b: Dictionary = _parts[index]
		if not _live(a) or not _live(b) or _live_joint(b) == null: continue
		var body_a: RigidBody3D = a.body
		var body_b: RigidBody3D = b.body
		var desired: Vector3 = Vector3(b.path_target)-Vector3(a.path_target)
		var actual: Vector3 = body_b.global_position-body_a.global_position
		var velocity_error: Vector3 = Vector3(b.path_velocity)-Vector3(a.path_velocity)-(body_b.linear_velocity-body_a.linear_velocity)
		var reduced_mass := body_a.mass*body_b.mass/maxf(body_a.mass+body_b.mass,0.001)
		# Upper connections use authored relative poses, while ground pairs use path spacing targets.
		var force := (desired-actual)*motion_data.raised_pose_strength+velocity_error*motion_data.raised_pose_damping
		force = force.limit_length(motion_data.maximum_acceleration*0.5)*reduced_mass
		a.path_horizontal_force -= force.slide(Vector3.UP)
		b.path_horizontal_force += force.slide(Vector3.UP)
		body_a.apply_central_force(-Vector3.UP*force.y)
		body_b.apply_central_force(Vector3.UP*force.y)
		b["pair_force"] = force

func _apply_path_horizontal_forces(delta: float) -> void:
	if not _path_ready or not _uses_ground_path(): return
	_drive_force = Vector3.ZERO
	# One final budget prevents three independent controllers from adding three acceleration spikes.
	var cap := maxf(motion_data.maximum_acceleration,motion_data.maximum_pose_acceleration)
	for row: Dictionary in _parts:
		if not _live(row): continue
		if _contact_count == 0 and _support_blend <= 0.0:
			row.path_drive_acceleration = Vector3.ZERO
			row.path_applied_force = Vector3.ZERO
			continue
		var requested: Vector3 = (Vector3(row.path_horizontal_force)/float(row.body.mass)).limit_length(cap)
		var acceleration: Vector3 = Vector3(row.path_drive_acceleration).move_toward(requested,motion_data.path_maximum_jerk*delta).limit_length(cap)
		row.path_drive_acceleration = acceleration
		row["path_applied_force"] = acceleration*row.body.mass
		row.body.apply_central_force(row.path_applied_force)
		_drive_force += Vector3(row.path_applied_force)

func cancel_motion(_reason: StringName = &"cancelled") -> void:
	_set_path_slide_limits(false)
	end_attack_control(_attack_owner)
	_connection_recovery_active = false
	_connection_recovery_resume_path = false
	_connection_settle_time = 0.0
	_idle_ground_poses.clear()
	_attack_ground_poses.clear()
	_attack_slide_release_pending = false
	_path_slides_expanded = false
	_connection_diagnostics.clear()
	_path_ready = false
	_ground_path.points.clear()
	_ground_path.corners.clear()
	_ground_path.turn_markers.clear()
	_path_progress = 0.0
	_path_blend = 0.0
	_path_speed = 0.0
	_path_frequency = 0.0
	_path_max_amplitude = 0.0
	_path_reversing = false
	_path_execution_speed_scale = 1.0
	_clear_spacing_wave()
	_path_turning = false
	_sway_time = 0.0
	_sway_amplitude = 0.0
	_sway_phase = 0.0
	_sway_strength = 0.0
	_sway_travel_blend = 0.0
	_sway_travelling = false
	_trajectory_time = 0.0
	_orbit_time = 0.0
	_orbit_radius = 0.0
	for row: Dictionary in _parts:
		var heading := _rest_heading
		if _live(row): heading = (row.body.global_basis*Basis(row.rest.basis).inverse()).x.slide(Vector3.UP).normalized()
		row["turn_heading"] = heading
		row["turn_goal"] = heading
		row["turn_rate"] = 0.0
		row["sway_offset"] = 0.0
		row["sway_velocity"] = 0.0
		row["trajectory_offset"] = Vector3.ZERO
		row["trajectory_velocity"] = Vector3.ZERO
		row["movement_force"] = Vector3.ZERO
		row["grounded"] = false
		row["history"] = []
		row.erase("connection_target")
		row.erase("idle_turn_anchor")
	if not _parts.is_empty(): _raised_heading = _parts[-1].get("turn_heading",_rest_heading)
	_path_pose_basis = _turn_basis(_raised_heading)
	_path_pose_yaw_speed = 0.0
	_direction = Vector3.ZERO
	_drive_force = Vector3.ZERO
	_turn_rate = 0.0
	_support_blend = 0.0
	_contact_count = 0
	_traction_count = 0

func cancel_action(reason: StringName = &"cancelled") -> void:
	cancel_motion(reason)
	_configure_contacts(false)

func set_character_control_enabled(value: bool) -> void:
	_character_enabled = value
	if not value:
		cancel_motion(&"character_disabled")
		_configure_contacts(false)
	set_physics_process(value)

func get_ground_path_debug_snapshot(maximum_points: int = 128) -> Dictionary:
	if not (_path_ready or _connection_recovery_resume_path) or _ground_path.points.is_empty() or not enabled or not _character_enabled or not _live(_path_leader): return {}
	var points := PackedVector3Array()
	var distances := PackedFloat32Array()
	var start := _path_progress-_path_length
	for row: Dictionary in _parts: start = minf(start,float(row.get("path_distance",start)))
	var end := _path_progress+maxf(_ground_path.wavelength,_path_length*0.5)
	var count := clampi(maximum_points,2,256)
	for i: int in count:
		var distance := lerpf(start,end,float(i)/(count-1))
		points.append(_ground_path.sample(distance).position)
		distances.append(distance)
	var excludes: Array[RID] = []
	var top: float = _path_leader.body.global_position.y
	var bottom := top
	for row: Dictionary in _parts:
		if not is_instance_valid(row.body): continue
		excludes.append(row.body.get_rid())
		top = maxf(top,row.body.global_position.y+Vector3(row.size).length())
		bottom = minf(bottom,row.body.global_position.y-Vector3(row.size).length())
	if is_instance_valid(_jaw): excludes.append(_jaw.get_rid())
	var turns: Array[Dictionary] = []
	for marker: Dictionary in _ground_path.turn_markers:
		if float(marker.s)<start or float(marker.s)>end: continue
		turns.append({"distance":marker.s,"position":_ground_path.sample(float(marker.s)).position,"facing":marker.facing})
	return {"points":points,"distances":distances,"progress":_path_progress,"excludes":excludes,
		"turns":turns,
		"ray_top":top+2.0,"ray_bottom":bottom-100.0,
		"line_width":clampf(float(_path_leader.size.z)*0.5,0.06,0.25)}

func get_snake_motion_diagnostics(include_parts: bool = true) -> Dictionary:
	var rows: Array[Dictionary] = []
	var reference := get_pose_reference().affine_inverse() if include_parts else Transform3D.IDENTITY
	for index: int in _parts.size() if include_parts else 0:
		var row: Dictionary = _parts[index]
		if not _live(row): continue
		var detail := {"part": row.body.name, "raised": not row.belly,
			"turn_heading":row.get("turn_heading",_raised_heading) if row.belly else _raised_heading,"turn_goal":row.get("turn_goal",_command_heading) if row.belly else _command_heading,"turn_distance":row.get("turn_distance",0.0),"turn_rate_degrees":rad_to_deg(float(row.get("turn_rate",0.0))) if row.belly else rad_to_deg(_turn_rate),
			"grounded": row.grounded, "leader": row.leader.body.name if not row.leader.is_empty() and _live(row.leader) else &"none",
			"trajectory_offset": row.trajectory_offset, "trajectory_velocity": row.trajectory_velocity,
			"actual_motion_offset": reference*row.body.global_position-Vector3(row.rest.origin),
			"movement_force": row.movement_force if _contact_count > 0 and can_process() else Vector3.ZERO,
			"sway_offset": row.sway_offset, "sway_velocity": row.sway_velocity,
			"sway_distance_from_head": row.get("sway_distance",-1),
			"actual_sway_offset": (reference * row.body.global_position - Vector3(row.rest.origin)).z,
			"slide_lower": row.get("slide_lower", 0.0), "slide_upper": row.get("slide_upper", 0.0),
			"pose_error": row.get("pose_error", Vector3.ZERO),
			"posture_torque": row.get("posture_torque", Vector3.ZERO) if _support_blend > 0.0 else Vector3.ZERO,
			"support_force": row.get("support_force", Vector3.ZERO) if _support_blend > 0.0 else Vector3.ZERO}
		detail.merge({"connection_target":row.get("connection_target",Vector3.ZERO),
			"connection_error":row.get("connection_error",Vector3.ZERO),"connection_relative_velocity":row.get("connection_relative_velocity",Vector3.ZERO),"connection_span_force":row.get("connection_span_force",Vector3.ZERO)})
		var joint := _live_joint(row)
		if joint != null:
			detail["structural_slide_bounds"] = _joint_slide_bounds(row,true)
			var a := joint.get_node(joint.node_a) as RigidBody3D
			var fa: Transform3D = joint.get_meta(&"generated_joint_frame_a")
			var fb: Transform3D = joint.get_meta(&"generated_joint_frame_b")
			if a != null:
				var actual: Vector3 = (a.global_transform*fa).affine_inverse()*(row.body.global_transform*fb).origin
				detail.merge({"joint_anchor_offset":actual,"spacing_amplitude":row.get("spacing_amplitude",0.0),
					"spacing_center_distance":a.global_position.distance_to(row.body.global_position),"pair_force":row.get("pair_force",Vector3.ZERO)})
		if _path_ready:
			if index > 0 and _live(_parts[index-1]):
				var previous: Dictionary = _parts[index-1]
				var pair: Dictionary = _spacing_pairs[index] if index < _spacing_pairs.size() else {}
				if not pair.is_empty():
					var radius := maxf(float(pair.gap)*2.0,_ground_path.step*2.0)
					var actual_a := _ground_path.project(previous.body.global_position,float(previous.path_distance),radius)
					var actual_b := _ground_path.project(row.body.global_position,float(row.path_distance),radius)
					var actual_extra := actual_b-actual_a-float(pair.gap)
					detail.merge({"spacing_target_s":row.get("spacing_target_s",0.0),"spacing_actual_s":actual_extra,
						"spacing_error_s":float(row.get("spacing_target_s",0.0))-actual_extra})
				if not row.belly or not previous.belly: detail["connection_rule"] = "rest_pose"
				else: detail["connection_rule"] = "path_arc_length"
			if not row.belly and _live(_path_leader):
				var rest_offset: Vector3 = row.rest.origin-_path_leader.rest.origin
				var inverse := _path_pose_basis.inverse()
				if _independent_path_turning():
					var pivot := _raised_turn_pivot()
					rest_offset = Vector3(row.rest.origin)-Vector3(pivot.rest)+inverse*(Vector3(pivot.world)-_path_leader.body.global_position)
				var actual_offset: Vector3 = inverse*(row.body.global_position-_path_leader.body.global_position)
				var target_offset: Vector3 = inverse*(Vector3(row.path_target)-Vector3(_path_leader.path_target))
				detail.merge({"raised_rest_offset":rest_offset,"raised_target_offset":target_offset,
					"raised_actual_offset":actual_offset,"raised_layout_error_xy":Vector2(actual_offset.x-rest_offset.x,actual_offset.y-rest_offset.y)})
			detail.merge({"path_role":"ground" if row.belly else "raised_rest",
				"path_target":row.get("path_target",Vector3.ZERO),"path_distance":row.get("path_distance",0.0),
				"path_raw_target":row.get("path_raw_target",Vector3.ZERO),
				"path_raw_velocity":row.get("path_raw_velocity",Vector3.ZERO),
				"path_desired_velocity":row.get("path_desired_velocity",Vector3.ZERO) if row.belly else row.path_velocity,
				"path_execution_offset":Vector3(row.path_target)-Vector3(row.get("path_raw_target",row.path_target)),
				"path_constraint_offset":row.get("path_constraint_offset",Vector3.ZERO),
				"path_corner_speed":row.get("path_corner_speed",0.0) if row.belly else _path_leader.get("path_corner_speed",0.0),
				"path_applied_force":row.get("path_applied_force",Vector3.ZERO),
				"path_drive_acceleration":row.get("path_drive_acceleration",Vector3.ZERO),
				"path_route_target":row.get("path_route_target",Vector3.ZERO),
				"path_velocity":row.get("path_velocity",Vector3.ZERO),"path_acceleration":row.get("path_acceleration",Vector3.ZERO),
				"path_error":row.body.global_position-Vector3(row.get("path_target",row.body.global_position)),
				"spacing_axis_world":row.get("spacing_axis_world",Vector3.ZERO),"spacing_offset_world":row.get("spacing_offset_world",Vector3.ZERO)})
		if row.body.get_meta(&"generated_role", "") == "Torso":
			var contact: Dictionary = row.body.get_support_surface_contact()
			detail.merge({"surface_normal": contact.get("normal", Vector3.ZERO)})
		rows.append(detail)
	return {"enabled": enabled and _character_enabled and can_process(), "requested_speed": motion_data.target_speed if motion_data != null and locomotion_enabled else 0.0,
		"connection_recovery":_connection_diagnostics,"connection_recovering":_connection_recovery_active,"idle_shape_hold":not _idle_ground_poses.is_empty(),"held_heading":_held_heading,
		"attack_support_locked":is_attack_support_locked(),"attack_ground_error":_attack_ground_error,
		"locomotion_enabled": locomotion_enabled, "sway_enabled": motion_data != null and motion_data.sway_enabled,
		"sway_time": _sway_time, "sway_amplitude": _sway_amplitude,
		"ground_path_active": _path_ready and _uses_ground_path(), "path_progress":_path_progress,
		"ground_path_retained":(_path_ready or _connection_recovery_resume_path) and not _ground_path.points.is_empty(),"path_resume_pending":_connection_recovery_resume_path,
		"raised_path_mode":"authored_xy", "spacing_scope":"grounded_layout",
		"path_turning":_path_turning,"path_reversing":_path_reversing,
		"turn_mode":"raised_independent_ground_markers" if _independent_path_turning() else "shared_heading","raised_heading":_raised_heading,"path_turn_markers":_ground_path.turn_markers.duplicate(true),
		"path_speed":_path_speed,"path_amplitude":_path_amplitude,"path_wavelength":_ground_path.wavelength,
		"path_points":_ground_path.points.size(),"path_blend":_path_blend,
		"path_execution":"acceleration_and_jerk_limited", "path_corners":_ground_path.corners.size(),
		"path_maximum_jerk":motion_data.path_maximum_jerk if motion_data != null else 0.0,
		"path_execution_speed_scale":_path_execution_speed_scale,
		"path_corner_speed_limit":_path_leader.get("path_corner_speed_limit",0.0),
		"path_max_amplitude":_path_max_amplitude,"path_joint_slide_widths":motion_data.path_joint_slide_widths if motion_data != null else 1.0,
		"path_frequency":_path_frequency,
		"spacing_wave_active":_path_ready and _uses_ground_path() and _spacing_blend > 0.0 and _spacing_ratio > 0.0,
		"spacing_axis_mode":"path_arc_length",
		"spacing_requested_ratio":motion_data.spacing_wave_amplitude_ratio if motion_data != null else 0.0,
		"spacing_effective_ratio":_spacing_ratio*smoothstep(0.0,1.0,_spacing_blend),
		"spacing_wave_frequency_ratio":motion_data.spacing_wave_frequency_ratio if motion_data != null else 0.0,
		"spacing_wave_phase":_spacing_phase,"spacing_wave_frequency":absf(_spacing_phase_rate)/TAU,
		"spacing_wave_phase_rate":_spacing_phase_rate,"spacing_wave_blend":_spacing_blend,
		"spacing_limit_reason":_spacing_limit_reason,"spacing_acceleration_bound":_spacing_acceleration_bound,
		"full_raised_links": _sway_links, "full_raised_period": _sway_period,
		"full_raised_frequency": 1.0/_sway_period if _sway_period > 0.0 else 0.0,
		"maximum_ground_z_offset_from_fixed_head": _sway_max_ground_offset,
		"maximum_sine_amplitude": _sway_max_amplitude, "sway_phase": _sway_phase,
		"sway_travel_blend": smoothstep(0.0,1.0,_sway_travel_blend),
		"head_orbit_enabled": motion_data != null and motion_data.head_orbit_enabled,
		"orbit_time": _orbit_time, "orbit_radius": _orbit_radius,
		"trajectory_following_enabled": motion_data != null and motion_data.trajectory_following_enabled,
		"trajectory_follow_delay": motion_data.trajectory_follow_delay if motion_data != null else 0.0,
		"orbit_period": motion_data.head_orbit_period if motion_data != null else 0.0,
		"drive_allowed": enabled and _character_enabled and can_process() and _contact_count > 0 and locomotion_enabled and not _connection_recovery_active,
		"driven_parts": _parts.filter(func(row: Dictionary) -> bool: return _live(row) and (not is_instance_valid(_attack_owner) or row.belly)).size() if enabled and can_process() and _contact_count > 0 and locomotion_enabled and not _connection_recovery_active else 0,
		"valid_settings": motion_data != null and motion_data.is_valid(),
		"direction": _direction, "actual_velocity": _actual_velocity, "actual_speed": _actual_velocity.slide(Vector3.UP).length(),
		"ground_contacts": _contact_count, "traction_contacts": _traction_count, "support_blend": _support_blend,
		"drive_force": _drive_force, "requested_turn_rate_degrees": rad_to_deg(_turn_rate),
		"actual_turn_rate_degrees": rad_to_deg(_actual_yaw_speed), "parts": rows}

func set_control_performance_tracking_enabled(value: bool) -> void:
	_control_perf.set_enabled(value)

func consume_control_performance_stats() -> Dictionary:
	return _control_perf.consume()
