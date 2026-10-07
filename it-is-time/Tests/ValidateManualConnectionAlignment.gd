extends SceneTree
const SCENE = preload("res://Scenes/Creatures/Characters/Generate_StumpBeast.tscn")
const STUMP = preload("res://Scripts/Creatures/Generators/StumpBeastGenerator.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var defaults := STUMP.new()
	assert(defaults.get_part_scene_rule("SubTorso","SubTorso").part_scene.resource_path.ends_with("01_body_light_plate.tscn"))
	defaults.free()
	var actor := SCENE.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	actor.get_node("GeneratedParts/Torso").position += Vector3(0.2,-0.15,0)
	var poses: Dictionary = {}
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D: poses[str(part.name)] = part.transform
	assert(actor._align_manual_connections())
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D: assert(part.transform == poses[str(part.name)])
	for joint: Node in actor.get_node("GeneratedParts/Joints").get_children():
		if not joint is Joint3D or joint.has_meta(&"segment_rotation_constraint"): continue
		var a := joint.get_node(joint.node_a) as PhysicalBodyPart3D
		var b := joint.get_node(joint.node_b) as PhysicalBodyPart3D
		var anchor_a: Vector3 = actor._capture_joint_anchor(a,joint,&"generated_joint_frame_a")
		var anchor_b: Vector3 = actor._capture_joint_anchor(b,joint,&"generated_joint_frame_b")
		assert(anchor_a.distance_to(anchor_b) < 0.00001)
		assert(anchor_a.distance_to(joint.global_position) < 0.00001)
	assert(actor._capture_manual_layout())
	assert(actor.generate_creature())
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if not part is PhysicalBodyPart3D: continue
		assert(part.transform.is_equal_approx(poses[str(part.name)]))
		if PhysicalBodyPart3D.BodyPartTag.SubTorso in part.tags:
			assert(part.get_meta(&"generated_scene_path").ends_with("01_body_light_plate.tscn"))
	# Invalid endpoint detection must happen before any anchors are changed.
	var joint: Joint3D = actor.get_node("GeneratedParts/Joints").get_child(0)
	var previous: Vector3 = joint.position
	actor.get_node("GeneratedParts/Head_1").is_broken = true
	assert(not actor._align_manual_connections())
	assert(joint.position == previous)
	actor.free()
	print("MANUAL_ALIGNMENT_VALIDATION_PASSED")
	quit()
