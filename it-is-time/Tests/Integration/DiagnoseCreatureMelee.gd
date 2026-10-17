extends "res://Tests/Integration/SimulateCreatureMelee.gd"
## Adds observation only; keep this run separate from the original rate sample.

func run() -> void:
	var console := root.get_node("RuntimeConsole")
	console.execute_command("trackdamage")
	console.execute_command("trackwolfattacks on")
	console.execute_command("tracksnakeattacks on")
	console.execute_command("trackcharge")
	await super.run()

func _register_module(actor: Dictionary, node: Node, action: String, wolf: bool = false) -> void:
	super._register_module(actor, node, action, wolf)
	if not wolf: node.set("diagnostic_logging", true)
	if action == "wolf_bite" and is_instance_valid(node.joint):
		modules[-1]["initial_head_anchor"] = node.head.to_local(node.joint.global_position)

func sample() -> void:
	if collecting: print("MELEE_DIAG_TIME ", float(frames + 1) / Engine.physics_ticks_per_second)
	super.sample()
	if not collecting or frames % 6 != 0: return
	for row: Dictionary in modules:
		if not _active(row): continue
		var details := {"time": clock, "actor": row.actor.id, "action": row.action, "attack_id": row.current, "phase": _phase(row)}
		var result: Dictionary
		if row.wolf: result = row.node.diagnostics()
		elif row.action == "snake_lunge_bite": result = row.node.get_attack_diagnostics()
		elif row.action == "ground_charge": result = row.node.get_charge_diagnostics()
		else: result = row.node.get_action_diagnostics()
		for key: String in ["reason", "result", "attack_result", "recovery_result", "planning_revision", "reaim_count", "plan_stage", "plan_reference", "plan_root_pose", "close_reason", "advance_limit", "torso_advance", "angle_error_degrees", "pinned_feet", "front_relative_pitch_degrees", "preparation_pose", "plan", "alignment", "head_error", "head_aim_error_degrees", "peak_impulse", "contacted_parts", "hits"]:
			if result.has(key): details[key] = result[key]
		var target: Variant = row.node.get("target") if row.wolf else row.node.get("_target")
		if not is_instance_valid(target): target = row.actor.ai._target
		if target is RigidBody3D:
			details["target_part"] = str(target.get_path())
			details["target_position"] = target.global_position
			details["target_velocity"] = target.linear_velocity
			details["target_armor"] = target.armor
		if row.action == "wolf_bite":
			var body: Node3D = row.node.controller.torso
			details["torso_position"] = body.global_position
			details["jaw_position"] = row.node.jaw.global_position
			details["jaw_velocity"] = row.node.jaw.linear_velocity
			details["prediction_pivot"] = row.node.head.to_global(row.node._head_anchor)
			details["physical_head_anchor"] = row.node.head.to_global(row.initial_head_anchor)
			details["pivot_error"] = Vector3(details.prediction_pivot).distance_to(row.node.head.to_global(row.initial_head_anchor))
			var weapon: Variant = row.node.get("_weapon")
			if is_instance_valid(weapon):
				details["hitbox_origin"] = weapon.pose().origin
				details["hitbox_size"] = weapon.box.size
				if target is Node3D: details["target_in_hitbox_axes"] = weapon.pose().affine_inverse()*target.global_position
		if row.action == "ground_charge":
			details["z_tolerance"] = row.node.data.z_tolerance
			details["head_position"] = row.node._body.global_position
			details["target_check"] = row.node._target_check(target) if is_instance_valid(target) else {}
		if row.action == "spider_pounce":
			details["torso_position"] = row.node._movement._torso.global_position
		print("MELEE_DIAG_SAMPLE ", JSON.stringify(details))
