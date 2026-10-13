extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	for scene: String in ["Generate_Wolf", "Generate_Wolf_NPC"]:
		var actor = load("res://Scenes/Creatures/Characters/" + scene + ".tscn").instantiate()
		actor.generate_on_ready = false
		root.add_child(actor)
		actor.process_mode = Node.PROCESS_MODE_DISABLED
		var move = actor.get_node("GeneratedLegStepMovementController3D")
		move.slow_gait_data = move.slow_gait_data.duplicate()
		move.fast_gait_data = move.slow_gait_data
		var data = move.slow_gait_data
		assert(data.limb_plane_stabilization_enabled and not data.world_rotation_constraints_enabled)
		assert(move._wolf_plane_links.size() == 18, "Include all feet, limb blocks and four SubTorsos")
		for body in actor.get_node("GeneratedParts").get_children():
			if body is RigidBody3D: body.freeze = true
		var foot = move._legs[0]
		foot.freeze = false
		move._segment_heading_initialized = true
		move._segment_goal_yaw = 0.0
		move._update_wolf_plane_constraints(0.1)
		assert(not foot.axis_lock_angular_y, "Lock only after a stable confirmation interval")
		move._update_wolf_plane_constraints(0.1)
		assert(foot.axis_lock_angular_y)
		move._torso.angular_velocity.y = deg_to_rad(3.0)
		move._update_wolf_plane_constraints(0.2)
		assert(foot.axis_lock_angular_y, "Small torso drift must not release the foot")
		move._torso.angular_velocity = Vector3.ZERO
		var rest: Basis = foot.global_basis
		foot.global_basis = Basis(Vector3.UP, deg_to_rad(10.0)) * rest
		move._update_wolf_plane_constraints(0.05)
		assert(foot.axis_lock_angular_y, "A short deviation must not immediately release the foot")
		move._update_wolf_plane_constraints(0.08)
		assert(not foot.axis_lock_angular_y)
		foot.global_basis = rest
		foot.freeze = true
		var limb = actor.get_node("GeneratedParts/ForeLeg_1_Limb_2")
		var root_body = move._torso
		limb.freeze = false
		root_body.freeze = false
		var limb_rest: Basis = limb.global_basis
		limb.global_basis = Basis(Vector3.UP, deg_to_rad(15.0)) * limb_rest
		move._update_wolf_plane_constraints(0.016)
		var row: Dictionary = {}
		for item: Dictionary in move._wolf_plane_rows:
			if item.a == root_body.name and item.b == limb.name: row = item
		assert(not row.is_empty() and row.plane_error_degrees > 14.9)
		assert(row.b_torque.y < 0.0 and Vector3(row.a_torque + row.b_torque).length() < 0.000001)
		assert(absf(Vector3(row.b_torque).dot(root_body.global_basis.z)) < 0.000001, "Plane alignment must not oppose Z hinge motion")
		assert(not limb.axis_lock_angular_x and not limb.axis_lock_angular_y, "Do not restore the canceled world locks")
		limb.global_basis = Basis(Vector3.FORWARD, deg_to_rad(35.0)) * limb_rest
		move._update_wolf_plane_constraints(0.016)
		for item: Dictionary in move._wolf_plane_rows:
			if item.a == root_body.name and item.b == limb.name:
				assert(item.plane_error_degrees < 0.001 and Vector3(item.b_torque).length() < 0.000001)
		move._segment_goal_yaw = PI
		move._turn_command_pending = true
		move._wolf_turn_state_frame = -1
		move._update_wolf_heading_state(0.016)
		move._update_wolf_plane_constraints(0.016)
		assert(move._foot_heading_previous_locks.is_empty(), "Deliberate turns must release foot heading locks")
		for item: Dictionary in move._wolf_plane_rows:
			var body: RigidBody3D = actor.get_node("GeneratedParts/" + str(item.b))
			assert(move._has_body_tag(body, move.SUB_TORSO_TAG), "Only the torso structure may retain paired plane correction during a deliberate turn")
		move._segment_goal_yaw = 0.0
		move._wolf_deliberate_turn = false
		move.recovery_control_active = true
		move._update_wolf_plane_constraints(0.016)
		assert(move._wolf_plane_rows.is_empty())
		move.recovery_control_active = false
		limb.is_broken = true
		move._update_wolf_plane_constraints(0.016)
		for item: Dictionary in move._wolf_plane_rows:
			assert(item.a != limb.name and item.b != limb.name)
		actor.free()
	print("PASS: Wolf/NPC paired plane alignment, free Z swing, no world locks, foot lock hysteresis, turn/recovery release and broken exclusion.")
	quit()
