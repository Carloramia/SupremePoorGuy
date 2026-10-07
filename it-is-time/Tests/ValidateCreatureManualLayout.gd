extends SceneTree
const SCENE = preload("res://Scenes/Creatures/Characters/Generate_StumpBeast.tscn")
const LAYOUT = preload("res://Scripts/Creatures/Generators/CreatureManualLayout.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var actor := SCENE.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator: Node3D = actor.get_node(actor.generator_path)
	# Existing authored scenes without the new metadata must also be capturable.
	assert(actor._capture_manual_layout())
	assert(actor.generate_creature())
	var container: Node3D = actor.get_node("GeneratedParts")
	# Arbitrary rigid translation of the complete assembly and a leaf pivot edit.
	for part: Node in container.get_children():
		if part is PhysicalBodyPart3D: part.position += Vector3(0.7, 0.4, -0.2)
	var leaf: PhysicalBodyPart3D = container.get_node("Leg_1")
	var pivot := Vector3.ZERO
	for child: Node in leaf.get_children():
		if child.has_meta(&"generated_connection_port"): pivot = child.global_position
	var rotation := Basis(Vector3.FORWARD, 0.2)
	leaf.global_position = pivot + rotation * (leaf.global_position - pivot)
	leaf.global_basis = rotation * leaf.global_basis
	assert(actor._capture_manual_layout())
	var poses: Dictionary = {}
	for part: Node in container.get_children():
		if part is PhysicalBodyPart3D: poses[str(part.name)] = part.transform
	var captured: LAYOUT = generator.manual_layout
	var path := "res://Tests/.manual_layout_roundtrip.tres"
	assert(ResourceSaver.save(captured, path) == OK)
	generator.manual_layout = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	assert(actor.generate_creature())
	container = actor.get_node("GeneratedParts")
	for part: Node in container.get_children():
		if part is PhysicalBodyPart3D: assert(part.transform.is_equal_approx(poses[str(part.name)]), "Manual pose did not survive generation/save")
	assert(generator.has_node("ManualLayout"))
	var packed := PackedScene.new()
	assert(packed.pack(actor) == OK)
	var restored := packed.instantiate()
	restored.generate_on_ready = false
	root.add_child(restored)
	var restored_generator: Node3D = restored.get_node(restored.generator_path)
	assert(restored_generator.use_manual_layout)
	assert(restored_generator.manual_layout != generator.manual_layout, "Scene instances must have independent snapshots")
	assert(restored.generate_creature())
	for part: Node in restored.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D: assert(part.transform.is_equal_approx(poses[str(part.name)]))
	restored.free()
	# Scaling is applied once; layout retains base units.
	generator.overall_scale *= 2.0
	assert(actor.generate_creature())
	container = actor.get_node("GeneratedParts")
	for part: Node in container.get_children():
		if part is PhysicalBodyPart3D:
			var expected: Transform3D = poses[str(part.name)]
			expected.origin *= 2.0
			assert(part.transform.is_equal_approx(expected))
	# A separated connector must not overwrite the last valid snapshot.
	var previous: LAYOUT = generator.manual_layout
	container.get_node("Leg_1").position.x += 0.5
	assert(not actor._capture_manual_layout())
	assert(generator.manual_layout == previous)
	generator.clear_manual_layout()
	assert(not generator.use_manual_layout and generator.manual_layout == null)
	assert(actor.generate_creature())
	assert(not generator.has_node("ManualLayout"))
	assert(not generator._capture_default_parameters().has(&"manual_layout"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	actor.free()
	for scene_path: String in ["res://Scenes/Creatures/Characters/Generate_Bird.tscn", "res://Scenes/Creatures/Characters/Generate_Beast.tscn"]:
		var other: Node3D = load(scene_path).instantiate()
		other.generate_on_ready = false
		root.add_child(other)
		assert(other.generate_creature())
		assert(other._capture_manual_layout())
		var snapshot: Dictionary = {}
		for part: Node in other.get_node("GeneratedParts").get_children():
			if part is PhysicalBodyPart3D: snapshot[str(part.name)] = part.transform
		assert(other.generate_creature())
		for part: Node in other.get_node("GeneratedParts").get_children():
			if part is PhysicalBodyPart3D: assert(part.transform.is_equal_approx(snapshot[str(part.name)]))
		other.free()
	print("PASS: manual layout capture, pivot edit, resource round-trip, scale, validation and procedural fallback")
	quit()
