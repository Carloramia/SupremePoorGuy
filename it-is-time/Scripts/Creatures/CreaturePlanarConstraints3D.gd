extends Node3D
## Independent terrain support and pose forces; physical inter-part joints are suspended.
var reference: RigidBody3D
var saved_locks: Dictionary = {}
var guides: Dictionary = {}
var offsets: Dictionary = {}
var suspended_joints: Dictionary = {}
var suspended_springs: Dictionary = {}
var rest: Dictionary = {}
var phase: float = 0.0
var part_diagnostics: Array[Dictionary] = []

func _suspend_connections(container: Node) -> void:
	for node: Node in container.find_children("*","Joint3D",true,false):
		var joint := node as Joint3D
		suspended_joints[joint] = [joint.node_a,joint.node_b]
		# Keep NodePaths intact for damage topology and controller chain discovery.
		PhysicsServer3D.joint_clear(joint.get_rid())
	for node: Node in container.find_children("*","",true,false):
		if node.has_method("is_segment_spring"):
			suspended_springs[node] = node.is_physics_processing()
			node.set_physics_process(false)

func _restore_connections() -> void:
	for joint: Variant in suspended_joints:
		if not is_instance_valid(joint) or joint.is_queued_for_deletion(): continue
		var paths: Array = suspended_joints[joint]
		var a: Node = joint.get_node_or_null(paths[0])
		var b: Node = joint.get_node_or_null(paths[1])
		if a == null or b == null or a.get("is_broken") == true or b.get("is_broken") == true: continue
		joint.node_a = NodePath()
		joint.node_b = NodePath()
		joint.node_a = paths[0]
		joint.node_b = paths[1]
	for spring: Variant in suspended_springs:
		if is_instance_valid(spring) and not spring.is_queued_for_deletion(): spring.set_physics_process(suspended_springs[spring])
	suspended_joints.clear()
	suspended_springs.clear()


func clear_constraints() -> void:
	_restore_connections()
	rest.clear()
	part_diagnostics.clear()
	phase = 0.0
	for guide: Node in guides.values():
		if is_instance_valid(guide):
			remove_child(guide)
			guide.queue_free()
	guides.clear()
	for body: Variant in saved_locks:
		if not is_instance_valid(body): continue
		var locks: Vector2i = saved_locks[body]
		if body.get("is_broken") != true or body.get_meta(&"generated_role","") not in ["Leg","ForeLeg"]: body.axis_lock_angular_x = locks.x != 0
		body.axis_lock_angular_y = locks.y != 0
	saved_locks.clear()
	offsets.clear()
	reference = null
	set_physics_process(false)

func configure(container: Node) -> void:
	clear_constraints()
	var parts: Array[RigidBody3D] = []
	for node: Node in container.get_children():
		if node is RigidBody3D and node.get("is_broken") != true: parts.append(node)
	for body: RigidBody3D in parts:
		if body.get_meta(&"generated_role", "") == "Torso":
			reference = body
			break
	if reference == null and not parts.is_empty(): reference = parts[0]
	if reference == null: return
	_suspend_connections(container)
	var center := Vector3.ZERO
	var total_mass := 0.0
	var floor_y := INF
	for body: RigidBody3D in parts:
		center += body.global_position * body.mass
		total_mass += body.mass
		var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if collision != null and collision.shape is BoxShape3D:
			var box := collision.shape as BoxShape3D
			for x: float in [-0.5,0.5]:
				for y: float in [-0.5,0.5]:
					for z: float in [-0.5,0.5]:
						floor_y = minf(floor_y,(collision.global_transform * (box.size*Vector3(x,y,z))).y)
	if not is_finite(floor_y): floor_y = reference.global_position.y
	center /= maxf(total_mass,0.001)
	for body: RigidBody3D in parts:
		rest[body] = {"offset": body.global_position-center,"height": maxf(body.global_position.y-floor_y,0.0),"rotation": body.global_rotation.z}
		saved_locks[body] = Vector2i(int(body.axis_lock_angular_x),int(body.axis_lock_angular_y))
		body.axis_lock_angular_x = true
		body.axis_lock_angular_y = true
		body.angular_velocity = Vector3(0,0,body.angular_velocity.z)
		offsets[body] = body.global_position.z-reference.global_position.z
		# Relative depth is maintained by each body servo, without a Joint3D.
		if body.has_signal("broken"):
			var callback := _on_part_broken.bind(body)
			if not body.is_connected("broken",callback): body.connect("broken",callback)
	set_physics_process(true)

func _on_part_broken(_source: Node, body: RigidBody3D) -> void:
	if not saved_locks.has(body): return
	if body == reference:
		clear_constraints()
		call_deferred("_rebuild_after_break")
		return
	if guides.has(body):
		var guide: Node = guides[body]
		if is_instance_valid(guide):
			remove_child(guide)
			guide.queue_free()
		guides.erase(body)
	body.axis_lock_angular_y = saved_locks[body].y != 0
	if not body.has_meta(&"generated_role") or body.get_meta(&"generated_role") not in ["Leg","ForeLeg"]: body.axis_lock_angular_x = saved_locks[body].x != 0
	saved_locks.erase(body)
	offsets.erase(body)
	rest.erase(body)
	_recenter_offsets()

func _recenter_offsets() -> void:
	var weighted := Vector3.ZERO
	var total_mass := 0.0
	for body: Variant in rest:
		if not is_instance_valid(body) or body.get("is_broken") == true: continue
		weighted += Vector3(rest[body].offset)*body.mass
		total_mass += body.mass
	weighted /= maxf(total_mass,0.001)
	for body: Variant in rest: rest[body].offset = Vector3(rest[body].offset)-weighted

func _rebuild_after_break() -> void:
	var actor := get_parent()
	if actor.is_planar_mode_active() and actor.has_node("GeneratedParts"):
		configure(actor.get_node("GeneratedParts"))
		actor._configure_body_part_collision_exceptions()

func _physics_process(_delta: float) -> void:
	# Broken parts must detach from these auxiliary links too. Do not reconnect
	# detached pieces through a replacement reference body.
	var rebuild: bool = not is_instance_valid(reference) or reference.get("is_broken") == true
	for body: Variant in saved_locks.keys():
		if is_instance_valid(body) and body.get("is_broken") != true: continue
		if guides.has(body):
			var guide: Node = guides[body]
			if is_instance_valid(guide):
				remove_child(guide)
				guide.queue_free()
			guides.erase(body)
		if is_instance_valid(body):
			body.axis_lock_angular_x = saved_locks[body].x != 0
			body.axis_lock_angular_y = saved_locks[body].y != 0
		saved_locks.erase(body)
		offsets.erase(body)
		rest.erase(body)
	if rebuild:
		var actor := get_parent()
		if actor.has_node("GeneratedParts"): configure(actor.get_node("GeneratedParts"))

func get_diagnostics() -> Dictionary:
	var error := 0.0
	if is_instance_valid(reference):
		for body: Variant in offsets:
			if is_instance_valid(body): error = maxf(error,absf(body.global_position.z-reference.global_position.z-float(offsets[body])))
	return {"enabled": is_instance_valid(reference),"parts": saved_locks.size(),"guides": guides.size(),"suspended_joints": suspended_joints.size(),"independent_parts": part_diagnostics,"reference": reference.name if is_instance_valid(reference) else &"","maximum_depth_error": error}

func apply_independent_motion(movement: Node, target: Vector3, delta: float) -> Dictionary:
	var center := Vector3.ZERO
	var total_mass := 0.0
	var actual := Vector3.ZERO
	var exclude: Array[RID] = []
	for body: Variant in rest:
		if not is_instance_valid(body): continue
		exclude.append(body.get_rid())
		if body.get("is_broken") == true or body.freeze: continue
		center += body.global_position*body.mass
		actual += body.linear_velocity*body.mass
		total_mass += body.mass
	center /= maxf(total_mass,0.001)
	actual /= maxf(total_mass,0.001)
	var horizontal := Vector3(actual.x,0,actual.z)
	var moving := horizontal.length() > 0.01
	if moving: phase = fmod(phase + delta * movement.planar_step_frequency * TAU,TAU)
	var feet: Array = movement.get_leg_parts()
	part_diagnostics.clear()
	for body: Variant in rest:
		if not is_instance_valid(body) or body.get("is_broken") == true or body.freeze: continue
		var initial: Dictionary = rest[body]
		var step := Vector3.ZERO
		var step_velocity := Vector3.ZERO
		var index := feet.find(body)
		var limb_weight := 1.0
		if index < 0:
			for foot_index: int in range(feet.size()):
				var chain: Dictionary = movement._chains.get(feet[foot_index],{})
				if chain.is_empty(): continue
				var link_index: int = chain.bodies.find(body)
				if link_index > 0 and link_index < chain.bodies.size()-1:
					index = foot_index
					limb_weight = 1.0-float(link_index)/float(chain.bodies.size()-1)
					break
		if index >= 0 and moving:
			var angle := phase + index*TAU/maxf(feet.size(),1)
			var rate: float = movement.planar_step_frequency*TAU
			step = Vector3(sin(angle)*movement.planar_step_stride,maxf(sin(angle),0.0)*movement.planar_step_height,0)
			step_velocity.x = cos(angle)*movement.planar_step_stride*rate
			if sin(angle)>0: step_velocity.y = cos(angle)*movement.planar_step_height*rate
		step *= limb_weight
		step_velocity *= limb_weight
		var query := PhysicsRayQueryParameters3D.create(body.global_position+Vector3.UP*movement.planar_ground_tolerance,body.global_position-Vector3.UP*(float(initial.height)+movement.planar_step_height+movement.planar_ground_tolerance))
		query.exclude = exclude
		query.collision_mask = movement.terrain_collision_mask
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		var supported := not hit.is_empty() and Vector3(hit.normal).dot(Vector3.UP)>0.25
		var support_force := Vector3.ZERO
		var gait_force := Vector3.ZERO
		var balance_torque := Vector3.ZERO
		var desired := center + Vector3(initial.offset) + step
		var planar_error := Vector3(desired.x-body.global_position.x,0,desired.z-body.global_position.z)
		var drive: Vector3 = (target-Vector3(body.linear_velocity.x,0,body.linear_velocity.z))*movement.planar_move_gain
		if supported:
			desired.y = Vector3(hit.position).y+float(initial.height)+step.y
			var gravity: Vector3 = body.get_gravity()
			var support_acceleration: float = -gravity.y + (desired.y-body.global_position.y)*movement.planar_support_gain + (step_velocity.y-body.linear_velocity.y)*movement.planar_support_damping
			support_force = Vector3.UP*clampf(support_acceleration,0,movement.planar_maximum_acceleration)*body.mass
			gait_force = (planar_error*movement.planar_pose_gain+Vector3(step_velocity.x,0,0)*movement.planar_move_gain)*body.mass
			var rotation_error := wrapf(float(initial.rotation)-body.global_rotation.z,-PI,PI)
			var angular_acceleration: float = clampf(rotation_error*movement.planar_balance_gain-body.angular_velocity.z*movement.planar_balance_damping,-movement.planar_maximum_acceleration,movement.planar_maximum_acceleration)
			var inverse: Basis = body.get_inverse_inertia_tensor()
			var inverse_z := Vector3.BACK.dot(inverse*Vector3.BACK)
			if inverse_z>0.000001: balance_torque.z = clampf(angular_acceleration/inverse_z,-movement.planar_maximum_torque,movement.planar_maximum_torque)
		var force: Vector3 = support_force+(drive*body.mass+gait_force).limit_length(movement.planar_maximum_acceleration*body.mass)
		body.apply_central_force(force)
		body.apply_torque(balance_torque)
		part_diagnostics.append({"part": body.name,"supported": supported,"step_offset": step,"support_force": support_force,"gait_force": gait_force,"balance_torque": balance_torque,"total_force": force})
	return {"mode": &"independent_force_gait","target_velocity": target,"actual_velocity": horizontal,"suspended_joints": suspended_joints.size(),"parts": part_diagnostics}
