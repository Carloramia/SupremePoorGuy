extends SceneTree
const GENERATED = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
const PART = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCreature_Part.tscn")
class SelectionSource extends Node3D:
	var target: Node3D
	func get_controlled_character() -> Node3D: return target
	func get_movement_direction() -> Vector3: return Vector3.ZERO
var failed: bool = false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var actor := GENERATED.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator := actor.get_node("CreatureGenerator")
	generator.rear_leg_count = maxi((6) - 2, 0)
	generator.foreleg_count = mini((6), 2)
	generator.overall_scale = 1.0
	generator.unsymmetrie = 0.0
	generator.neck_number = 1

	generator._random.seed = 42
	check(actor.generate_creature(), "Generation must succeed")
	actor.get_node("GeneratedLegStepMovementController3D").set_physics_process(false)
	actor.get_node("CreatureRecoveryStateMachine3D").set_physics_process(false)
	var source := SelectionSource.new()
	root.add_child(source)
	source.add_to_group(&"player_controller_3d")
	source.target = actor
	var console := root.get_node("RuntimeConsole")
	var body_count := 0
	var broken: PhysicalBodyPart3D
	for body: RigidBody3D in actor._get_physical_body_parts():
		body.freeze = true
		body_count += 1
		if body.get_meta(&"generated_role", "") == "Limb" and broken == null: broken = body
	check(broken != null, "Generated untagged Limb must exist")
	broken.is_broken = true
	broken.current_hp = 0.0
	broken.linear_velocity = Vector3(1, 2, 3)
	broken.angular_velocity = Vector3(0.5, 0, 0)
	var lines: Array[String] = console._collect_motion_snapshot()
	var rows := 0
	var has_leg_details := false
	var has_head := false
	var has_neck := false
	var has_broken := false
	var support_rows := 0
	var joint_rows := 0
	for line: String in lines:
		if " part=" in line: rows += 1
		if " stance_support=" in line:
			support_rows += 1
			check('"torso_mass"' in line and '"support_balanced"' in line, "Support summary must include load and balance")
		if " stance_joint=" in line:
			joint_rows += 1
			check('"required_torque"' in line and '"commanded_along_load"' in line and '"load_compensation_acceleration_limited"' in line, "Joint diagnostics must include load, direction and acceleration limits")
			check('"estimate_valid": false' in line, "Inactive controller must not claim a valid current load estimate")
		if " leg=" in line: has_leg_details = true
		if "role=Head" in line: has_head = true
		if "role=Neck" in line: has_neck = true
		if "id=%d " % broken.get_instance_id() in line:
			has_broken = "broken=true" in line and "velocity=(1.000, 2.000, 3.000)" in line and "angular_velocity=(0.500, 0.000, 0.000)" in line
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	var expected_joints := 0
	for chain: Dictionary in movement._chains.values(): expected_joints += chain.joints.size()
	check(support_rows == 1 and joint_rows == expected_joints and joint_rows > 0, "Every Leg and ForeLeg chain joint must be logged: summary=%d rows=%d expected=%d" % [support_rows, joint_rows, expected_joints])
	movement.maximum_stance_torque = 200.0
	var first_chain: Dictionary = movement._chains.values()[0]
	movement._stance_joint_loads[first_chain.joints[0]] = Vector3(400, 0, 0)
	var diagnostic: Dictionary = movement.get_stance_support_diagnostics()
	var found_load := false
	for row: Dictionary in diagnostic.joints:
		if row.joint == first_chain.joints[0].name:
			found_load = is_equal_approx(row.required_torque, 400.0) and is_equal_approx(row.capacity_ratio, 0.5) and row.commanded_torque == 0.0
	check(found_load, "Known load must expose the hard torque cap without inventing applied torque")
	check(rows == body_count, "Every part must have exactly one common motion row")
	check(has_leg_details and has_head and has_neck and has_broken, "Leg details, Head, Neck and broken untagged Limb must all be covered")
	var second := Node3D.new()
	second.name = "SecondControlledActor"
	root.add_child(second)
	for label: String in ["Torso", "Arm", "Head"]:
		var body := PART.instantiate() as PhysicalBodyPart3D
		body.name = label
		body.freeze = true
		second.add_child(body)
	source.target = second
	lines = console._collect_motion_snapshot()
	check(lines.size() == 4, "Control handoff must immediately select only the second actor")
	for line: String in lines: check("character=SecondControlledActor" in line, "Uncontrolled actors must not be logged")
	console._output_lines.clear()
	console._emit_motion_snapshot()
	check(console._output_lines.size() == 4, "Batched UI update must preserve individual log lines")
	source.target = null
	lines = console._collect_motion_snapshot()
	check(lines.size() == 1 and "No controlled character" in lines[0], "Detached Controller must not fall back to another actor")
	check(is_equal_approx(console.motion_tracking_interval, 0.1), "Sampling interval must remain 0.1 seconds")
	actor.queue_free()
	second.queue_free()
	source.queue_free()
	await process_frame
	if not failed: print("CONTROLLED_PART_MOTION_TRACKING_VALIDATION_PASSED")
	quit(1 if failed else 0)
