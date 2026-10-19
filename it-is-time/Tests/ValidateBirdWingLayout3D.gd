extends SceneTree

const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")
const NPC = preload("res://Scenes/Creatures/Characters/Generate_Bird_NPC.tscn")
const POSE_TOLERANCE := 0.15
var failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func frames(count: int) -> void:
	for index: int in count: await physics_frame

func freeze_parts(actor: Node) -> void:
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is RigidBody3D: part.freeze = true

func check_open_layout(actor: Node) -> void:
	var wing := actor.get_node("WingPoseController3D")
	check(wing.bindings.size() == 12, "Authored Bird must retain six blocks per wing")
	var lengths := {}
	var expanded := {}
	var ordered: Array = wing.bindings.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(str(a.b.name).get_slice("_",1))*100+int(str(a.b.name).get_slice("_",3)) < int(str(b.b.name).get_slice("_",1))*100+int(str(b.b.name).get_slice("_",3)))
	for binding: Dictionary in ordered:
		var section: String = binding.b.get_meta("generated_part_type")
		lengths[section] = float(lengths.get(section,0.0)) + binding.b.get_node("JointIn").position.distance_to(binding.b.get_node("JointOut").position)
		if binding.has_wing_parent:
			check(Basis(binding.open).y.dot(Vector3.UP) > 0.99999, "Expanded wing sections must extend along their parent: " + str(binding.b.name))
		wing._get_expanded_relative_pose(binding)
		check(not binding.target_limited, "Physical limits must admit the expanded pose")
		var parent: Quaternion = expanded.get(binding.a,binding.a.transform.basis.get_rotation_quaternion())
		expanded[binding.b] = parent * wing._get_expanded_relative_pose(binding)
		if str(binding.b.name).ends_with("_Tip_6"):
			var direction: Vector3 = Basis(expanded[binding.b]).y
			check(absf(rad_to_deg(atan2(direction.y,-direction.x))-40.0) < 0.01,"Static expanded wing tip must match the whitebox's 40-degree accumulated elevation")
	for section: String in ["WingRoot","WingMiddle","WingTip"]:
		var expected: float = {"WingRoot":2.4,"WingMiddle":3.0,"WingTip":3.4}[section]
		check(absf(float(lengths[section])-expected) < 0.0001,"Section lengths must match the whitebox, independently of paper model bounds")

func round_trip(actor: Node) -> void:
	var wing := actor.get_node("WingPoseController3D")
	var expected := {}
	for links: Array in [wing.bindings, wing.feather_bindings]:
		for binding: Dictionary in links: expected[str(binding.b.name)] = binding.open
	var poses := {}
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D: poses[str(part.name)] = part.transform
	# Child joints may appear before their parents in an edited scene tree.
	var joints := actor.get_node("GeneratedParts/Joints")
	for joint: Node in joints.get_children(): joints.move_child(joint, 0)
	for cycle: int in 3:
		check(actor._capture_manual_layout(), "Wing layout capture must succeed")
		check(actor.generate_creature(), "Captured Bird must regenerate")
		freeze_parts(actor)
		for links: Array in [wing.bindings, wing.feather_bindings]:
			for binding: Dictionary in links:
				check(binding.open.angle_to(expected[str(binding.b.name)]) < 0.001, "Repeated capture must preserve unfolded targets: " + str(binding.b.name))
		for part: Node in actor.get_node("GeneratedParts").get_children():
			if part is PhysicalBodyPart3D: check(part.transform.is_equal_approx(poses[str(part.name)]), "Capture must preserve authored body transforms")
		check_open_layout(actor)

func pose_error(wing: Node, unfolded: bool) -> float:
	var maximum_error := 0.0
	for binding: Dictionary in wing.bindings:
		var relative: Quaternion = binding.a.global_basis.orthonormalized().get_rotation_quaternion().inverse() * binding.b.global_basis.orthonormalized().get_rotation_quaternion()
		var target: Quaternion = wing._get_expanded_relative_pose(binding) if unfolded else binding.closed
		maximum_error = maxf(maximum_error, relative.angle_to(target))
	return maximum_error

func check_pose(wing: Node, unfolded: bool) -> void:
	var maximum_error := pose_error(wing, unfolded)
	check(maximum_error < POSE_TOLERANCE, "Wings must physically reach their unfolded/folded targets")
	print("BIRD_WING_POSE character=", wing.get_parent().name, " unfolded=", unfolded, " maximum_error_degrees=", rad_to_deg(maximum_error))

func wait_for_stable_pose(wing: Node, unfolded: bool) -> bool:
	var stable_frames := 0
	for frame: int in 360:
		await physics_frame
		stable_frames = stable_frames+1 if pose_error(wing,unfolded) < POSE_TOLERANCE else 0
		if stable_frames >= 30: return true
	return false

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var preset: Resource = load("res://Resources/Generators/BirdParts/Bird1Layout.tres")
	for connection: Dictionary in preset.blueprint.connections:
		if connection.kind != "Wing": continue
		var parent: Dictionary = preset.blueprint.parts[connection.a]
		var child: Dictionary = preset.blueprint.parts[connection.b]
		if parent.has("wing_open_basis"):
			check(parent.wing_open_basis.y.dot(child.wing_open_basis.y) > 0.99999, "Reusable Bird preset must retain continuous expanded wings")
	for packed: PackedScene in [BIRD, NPC]:
		var actor := packed.instantiate()
		actor.generate_on_ready = false
		actor.position.y = 30.0
		root.add_child(actor)
		freeze_parts(actor)
		check_open_layout(actor)
		round_trip(actor)
		# Exercise flight from a fresh saved instance, independently of the reordered capture fixture.
		actor.free()
		actor = packed.instantiate()
		actor.generate_on_ready = false
		actor.position.y = 30.0
		root.add_child(actor)
		for node: Node in actor.find_children("*", "", true, false): node.set_physics_process(false)
		actor.get_node("NPCStateMachine3D").enabled = false
		actor.get_node("BirdDiveAttackController3D").enabled = false
		var wing := actor.get_node("WingPoseController3D")
		wing.flight_sway_enabled = false
		wing.set_physics_process(true)
		var flight := actor.get_node("BirdFlightController3D")
		flight.set_physics_process(true)
		for part: Node in actor.get_node("GeneratedParts").get_children():
			if part is RigidBody3D: part.freeze = false
		await frames(300)
		check(flight.is_airborne() and is_equal_approx(wing.unfold_ratio, 1.0), "Flight must automatically unfold both wings")
		check(await wait_for_stable_pose(wing,true), "Long wings must settle near their unfolded pose")
		check_pose(wing, true)
		flight.set_physics_process(false)
		flight.set_character_control_enabled(false)
		for part: Node in actor.get_node("GeneratedParts").get_children():
			if part is PhysicalBodyPart3D:
				part.gravity_scale = 0.0
		await frames(360)
		# Long articulated wings may still be settling after the interpolation finishes.
		check(await wait_for_stable_pose(wing,false), "Folded long wings must settle and remain near their rest pose")
		check(is_zero_approx(wing.unfold_ratio), "Leaving flight must refold the wings")
		check_pose(wing, false)
		actor.queue_free()
		await frames(3)
	print("BIRD_WING_LAYOUT_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
