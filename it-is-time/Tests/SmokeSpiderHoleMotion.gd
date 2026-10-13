extends SceneTree

var failed := false

class Commands extends Node:
	var direction := Vector3.RIGHT
	var facing := Vector3.RIGHT
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta: float) -> Vector3: return facing
	func is_jump_requested() -> bool: return false
	func is_fast_requested() -> bool: return false

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(160, 1, 160)
	collision.shape = shape
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-70, 0, -70), Vector3(-70, 0, 70), Vector3(70, 0, 70), Vector3(70, 0, -70)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	level.add_child(region)
	var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_Spider_NPC.tscn").instantiate()
	if "scale2" in OS.get_cmdline_user_args(): actor.get_node(actor.generator_path).overall_scale *= 2.0
	level.add_child(actor)
	await process_frame
	var parts := actor.get_node("GeneratedParts") as Node3D
	var torso := parts.get_node("Torso_Front") as RigidBody3D
	var commands: Commands
	if "facing" in OS.get_cmdline_user_args():
		commands = Commands.new()
		commands.direction = Vector3.ZERO
		actor.add_child(commands)
		actor.get_node("NPCStateMachine3D").enabled = false
		actor.get_node("GeneratedLegStepMovementController3D").command_source = commands
	var scale: float = actor.get_node(actor.generator_path).overall_scale
	var maximum_hole_gap := 0.0
	var maximum_knee_gap := 0.0
	var maximum_root_gap := 0.0
	var maximum_tilt := 0.0
	var first_root_failure := false
	var start := Vector3.ZERO
	var path_distance := 0.0
	var speed_sum := 0.0
	var planned_speed_sum := 0.0
	var speed_samples := 0
	var previous_position := torso.global_position
	var gait: Dictionary = {}
	var tracked_steps: Dictionary = {}
	for tick: int in 1560:
		if tick == 180:
			start = torso.global_position
			actor.get_node("NPCStateMachine3D").move_to_position(start + Vector3(110, 0, 0))
			if commands != null: commands.direction = Vector3.RIGHT
		if "reverse" in OS.get_cmdline_user_args() and tick == 720:
			actor.get_node("NPCStateMachine3D").move_to_position(torso.global_position + Vector3(-110, 0, 0))
		if commands != null and tick == 720:
			commands.facing = Vector3.LEFT
			commands.direction = Vector3.LEFT
		await physics_frame
		if tick > 180: path_distance += torso.global_position.distance_to(previous_position)
		previous_position = torso.global_position
		var controller := actor.get_node("GeneratedLegStepMovementController3D")
		# Use the same settled walking window as the speed measurement. A
		# requested reversal cancels the old step sequence deliberately.
		var settled_direction: bool = tick < 720 or (commands == null and not "reverse" in OS.get_cmdline_user_args()) or tick >= 1140
		var sample_walk: bool = tick >= 480 and settled_direction and not controller._foot_heading_turn_active()
		if sample_walk:
			for foot: RigidBody3D in controller._legs:
				if not gait.has(foot.name): gait[foot.name] = {"finished": 0, "incomplete": 0, "maximum_step_time": 0.0, "sliding_samples": 0, "stance_samples": 0}
				var row: Dictionary = gait[foot.name]
				var motion = controller._find_step_motion_for_spider(foot)
				if tracked_steps.has(foot) and (motion == null or motion.sequence != tracked_steps[foot].sequence):
					var old: Dictionary = tracked_steps[foot]
					var touchdown: Dictionary = controller._spider_last_touchdowns.get(foot, {})
					row.finished += 1
					if touchdown.get("sequence", -1) != old.sequence or not touchdown.get("completed", false): row.incomplete += 1
					if ("trace" in OS.get_cmdline_user_args() or "failtrace" in OS.get_cmdline_user_args()) and (touchdown.get("sequence", -1) != old.sequence or not touchdown.get("completed", false)):
						print("SPIDER_FAILED ", JSON.stringify({"tick":tick,"foot":foot.name,"touchdown":touchdown,"last_motion":old.get("extra",{}),"toe":controller._get_foot_world_position(foot),"rotation":foot.global_rotation_degrees}))
					row.maximum_step_time = maxf(row.maximum_step_time, float(tick - old.tick) / 60.0)
					tracked_steps.erase(foot)
				if motion != null and not tracked_steps.has(foot): tracked_steps[foot] = {"sequence": motion.sequence, "tick": tick}
				if motion != null and ("trace" in OS.get_cmdline_user_args() or "failtrace" in OS.get_cmdline_user_args()): tracked_steps[foot]["extra"] = motion.extra.duplicate(true)
				if motion == null and controller.is_leg_grounded(foot):
					row.stance_samples += 1
					if controller._get_ground_contact_velocity(foot, {}).slide(Vector3.UP).length() > 0.35: row.sliding_samples += 1
		else:
			tracked_steps.clear()
		for alignment: Dictionary in controller._spider_axis_alignment.values():
			if absf(Vector3(alignment.angular_acceleration).dot(alignment.hinge_axis)) > 0.001:
				failed = true
				push_error("Hinge reinforcement must leave the intended Z bend free")
		if tick >= 480 and (tick < 720 or (commands == null and not "reverse" in OS.get_cmdline_user_args()) or tick >= 1140):
			speed_sum += torso.linear_velocity.slide(Vector3.UP).length()
			planned_speed_sum += controller.get_expected_horizontal_speed()
			speed_samples += 1
		if "trace" in OS.get_cmdline_user_args() and tick % 120 == 0:
			print("SPIDER_BUDGET_TRACE tick=", tick, " ", JSON.stringify(controller.get_automatic_motion_diagnostics()))
		maximum_tilt = maxf(maximum_tilt, rad_to_deg(torso.global_basis.y.angle_to(Vector3.UP)))
		actor._update_spider_limb_visuals()
		for index: int in range(1, 9):
			var upper := parts.get_node("Leg_%d_Limb_1" % index) as PhysicalBodyPart3D
			var foot := parts.get_node("Leg_%d" % index) as PhysicalBodyPart3D
			var model: Node3D = upper.get_node("Model")
			if not is_equal_approx(model.scale.x, model.scale.y): failed = true
			if "trace" in OS.get_cmdline_user_args() and tick % 120 == 0:
				var movement := actor.get_node("GeneratedLegStepMovementController3D")
				var support: Dictionary = movement.get_support_foot_diagnostics(foot)
				print("SPIDER_TRACE ", JSON.stringify({"tick": tick, "foot": foot.name, "torso": torso.global_position, "torso_speed": torso.linear_velocity.length(), "foot_position": foot.global_position, "moving": movement.is_leg_stepping(foot), "grounded": movement.is_leg_grounded(foot), "pin": support.locked, "admission": support.gallop.admission, "landing": support.spider_landing, "liftoff": support.spider_liftoff, "toe": movement._get_foot_world_position(foot)}))
			var a: Vector3 = upper.get_node("JointIn").global_position
			var b: Vector3 = foot.get_node("JointIn").global_position
			maximum_hole_gap = maxf(maximum_hole_gap, (a - b).slide(upper.global_basis.z.normalized()).length())
			if upper.is_broken or foot.is_broken or not upper.transform.is_finite() or not foot.transform.is_finite(): failed = true
		for joint: Generic6DOFJoint3D in parts.get_node("Joints").get_children():
			if not joint.has_meta(&"spider_axial_slide"): continue
			var a := joint.get_node(joint.node_a) as Node3D
			var b := joint.get_node(joint.node_b) as Node3D
			var frame_a: Transform3D = joint.get_meta(&"generated_joint_frame_a")
			var frame_b: Transform3D = joint.get_meta(&"generated_joint_frame_b")
			var gap := a.to_global(frame_a.origin).distance_to(b.to_global(frame_b.origin))
			if joint.get_meta(&"spider_axial_slide").connection == "root":
				maximum_root_gap = maxf(maximum_root_gap, gap)
				if gap > 0.2 * scale and not first_root_failure:
					first_root_failure = true
					print("SPIDER_ROOT_FAILURE tick=", tick, " root=", joint.name, " gap=", gap, " torso_rotation=", torso.global_rotation_degrees, " upper=", a.global_position, " torso=", torso.global_position)
			else:
				maximum_knee_gap = maxf(maximum_knee_gap, gap)
	var travelled := torso.global_position.distance_to(start)
	var mean_speed := speed_sum / maxi(speed_samples, 1)
	print("SPIDER_SPEED mean=", mean_speed, " planned_mean=", planned_speed_sum / maxi(speed_samples, 1), " target=", actor.get_node("GeneratedLegStepMovementController3D")._get_gait_data().target_speed, " samples=", speed_samples)
	print("SPIDER_GAIT ", JSON.stringify(gait), " timeouts=", actor.get_node("GeneratedLegStepMovementController3D")._failed_step_count)
	if "gait" in OS.get_cmdline_user_args():
		if gait.size() != 8:
			failed = true
			push_error("Gait verification must sample all eight Spider legs")
		for name: StringName in gait:
			var row: Dictionary = gait[name]
			if row.finished < 5 or float(row.incomplete) / maxf(row.finished, 1) > 0.05 or row.sliding_samples > row.stance_samples * 0.02:
				failed = true
				push_error("Each Spider leg must complete at least 95 percent of steps and keep planted contact stable: " + str(name))
	if "speed" in OS.get_cmdline_user_args() and mean_speed < 2.85:
		failed = true
		push_error("Spider steady walking must reach at least 95 percent of its 3.0 target speed")
	if commands != null and absf(wrapf(PI - actor.get_node("GeneratedLegStepMovementController3D")._get_physical_heading_yaw(), -PI, PI)) > deg_to_rad(10.0):
		failed = true
		push_error("Spider must complete the requested physical turn")
	print("SPIDER_HOLE_MOTION physical_hole_gap=", maximum_hole_gap, " knee_joint_gap=", maximum_knee_gap, " root_joint_gap=", maximum_root_gap, " distance=", travelled, " path_distance=", path_distance, " maximum_tilt_degrees=", maximum_tilt, " final_yaw=", rad_to_deg(actor.get_node("GeneratedLegStepMovementController3D")._get_physical_heading_yaw()), " steps=", actor.get_node("GeneratedLegStepMovementController3D")._step_sequence)
	if maximum_hole_gap > 0.15 * scale or maximum_knee_gap > 0.15 * scale or maximum_root_gap > 0.2 * scale or path_distance < 15.0 or not actor._spider_stretch_rows.is_empty():
		failed = true
		push_error("Spider must sustain walking with bounded roots, aligned physical holes and original visual proportions")
	level.free()
	await process_frame
	if not failed: print("PASS: Spider sustains 23 seconds of walking with bounded physical roots/knees and original visual proportions.")
	quit(1 if failed else 0)
