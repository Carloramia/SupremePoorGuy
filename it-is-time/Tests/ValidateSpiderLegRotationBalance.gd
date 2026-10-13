extends SceneTree

var failed := false

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var actor = load("res://Scenes/Creatures/Characters/Generate_Spider.tscn").instantiate()
	actor.spider_leg_joints_suspended = true
	root.add_child(actor)
	await process_frame
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	movement.set_physics_process(false)
	actor.get_node("CreatureRecoveryStateMachine3D").set_physics_process(false)
	for body: Node in actor.get_node("GeneratedParts").get_children():
		if body is RigidBody3D: body.freeze = true
	var foot: RigidBody3D = movement.get_leg_parts()[0]
	var rest: Basis = foot.global_basis.orthonormalized()
	foot.freeze = false
	foot.gravity_scale = 0.0
	foot.angular_damp = 0.0
	foot.global_basis = Basis(Vector3.RIGHT, 0.4) * rest
	await physics_frame
	movement._apply_spider_leg_rotation_balance()
	check(movement._spider_leg_balance.has(foot), "Detached foot must receive its own balance torque")
	var row: Dictionary = movement._spider_leg_balance.get(foot, {})
	check(Vector3(row.get("torque", Vector3.ZERO)).x < 0.0, "Balance torque must oppose the imposed rotation")
	check(Vector3(row.get("torque", Vector3.ZERO)).length() <= movement.leg_rotation_balance_maximum_torque + 0.001, "Balance torque must respect its configured ceiling")
	var initial_error: float = row.get("angle_error_degrees", 0.0)
	for tick: int in 120:
		movement._apply_spider_leg_rotation_balance()
		await physics_frame
	movement._apply_spider_leg_rotation_balance()
	var final_error: float = movement._spider_leg_balance[foot].angle_error_degrees
	print("SPIDER_LEG_BALANCE initial_error=", initial_error, " final_error=", final_error)
	check(final_error < initial_error * 0.2, "Detached foot must physically recover its authored orientation")
	var torso: RigidBody3D = movement._chains[foot].root
	torso.global_basis = Basis(Vector3.UP, 0.5) * torso.global_basis
	movement._apply_spider_leg_rotation_balance()
	var target: Basis = movement._spider_leg_balance[foot].target_basis
	check(target.is_equal_approx(Basis(Vector3.UP, 0.5) * rest), "Foot balance target must follow actual torso yaw")
	movement._begin_leg_motion(foot, foot.global_position + Vector3.RIGHT * 0.1, Vector3.UP, Vector3.RIGHT)
	var swing_target := Basis(Vector3.FORWARD, 0.2) * rest
	movement._current_step.extra["spider_pose_guide"] = {"valid": true, "foot_basis": swing_target}
	movement.leg_rotation_balance_maximum_torque = 0.001
	movement._apply_spider_leg_rotation_balance()
	row = movement._spider_leg_balance[foot]
	check(Basis(row.target_basis).is_equal_approx(swing_target), "Stepping foot must track the planned swing pose rather than fight it")
	check(is_equal_approx(Vector3(row.torque).length(), 0.001), "A low configured torque ceiling must actively clamp the servo")
	movement.leg_rotation_balance_enabled = false
	movement._apply_spider_leg_rotation_balance()
	check(movement._spider_leg_balance.is_empty(), "Disabling balance must stop applying its torque")
	actor.free()
	if not failed: print("PASS: Spider detached leg rotation recovery, yaw following, torque cap and switch.")
	quit(1 if failed else 0)
