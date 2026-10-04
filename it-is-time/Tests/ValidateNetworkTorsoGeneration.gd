extends SceneTree

# Reject the first segment pass to verify that planning retries the same network.
class RetryGenerator extends "res://Scripts/Creatures/CreatureGenerator.gd":
	var legality_calls := 0

	func _torso_overlap_is_legal(candidate: AABB, existing: Array[Dictionary]) -> bool:
		legality_calls += 1
		# The first two calls validate the two anchor boxes.
		if legality_calls > 2 and legality_calls <= 2 + MAX_GENERATION_ATTEMPTS:
			return false
		return super._torso_overlap_is_legal(candidate, existing)

const GEOMETRY = preload("res://Scripts/Creatures/CreatureBoxGeometry.gd")

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var a := GEOMETRY.box(Vector3.ONE, Transform3D.IDENTITY)
	var b := GEOMETRY.box(Vector3.ONE, Transform3D(Basis.IDENTITY, Vector3(1.25, 0, 0)))
	assert(is_equal_approx(GEOMETRY.distance(a, b), 0.25))
	assert(not GEOMETRY.connected(a, b, 0.25), "Threshold is strictly less-than")
	assert(GEOMETRY.connected(a, b, 0.26))
	var inside := GEOMETRY.box(Vector3.ONE * 0.1, Transform3D.IDENTITY)
	assert(GEOMETRY.connected(a, inside, 0.0), "Overlapping volumes connect even at zero threshold")
	var rotation := Basis(Vector3.FORWARD, PI / 4.0)
	var thin_a := GEOMETRY.box(Vector3(4, 0.2, 0.2), Transform3D(rotation, Vector3.ZERO))
	var thin_b := GEOMETRY.box(Vector3(4, 0.2, 0.2), Transform3D(rotation, rotation.y * 0.6))
	assert(thin_a.aabb.intersects(thin_b.aabb))
	assert(not GEOMETRY.overlaps(thin_a, thin_b), "Overlapping AABBs do not imply rotated-box overlap")
	assert(is_equal_approx(GEOMETRY.distance(thin_a, thin_b), 0.4))
	assert(not GEOMETRY.connected(thin_a, thin_b, 0.3))
	assert(GEOMETRY.connected(thin_a, thin_b, 0.5))
	assert(is_equal_approx(GEOMETRY._segment_distance(Vector3(-1,0,0), Vector3(1,0,0), Vector3(0,1,-1), Vector3(0,1,1)), 1.0))
	var retry_generator := RetryGenerator.new()
	root.add_child(retry_generator)
	retry_generator._random.seed = 42
	retry_generator.torso_minimum_size = Vector3.ONE
	retry_generator.torso_maximum_size = Vector3.ONE
	retry_generator.max_torso_overlap_percent = 100.0
	var retry_anchors: Array[Dictionary] = [{"size": Vector3.ONE, "position": Vector3.ZERO}, {"size": Vector3.ONE, "position": Vector3(3, 0, 0)}]
	var retry_plan := retry_generator._plan_network_torsos(retry_anchors, PackedVector3Array([Vector3.ZERO, Vector3(3, 0, 0)]))
	assert(not retry_plan.is_empty(), "A failed first pass must retry the network and connect the anchors")
	assert(retry_generator.legality_calls > 2 + retry_generator.MAX_GENERATION_ATTEMPTS)
	retry_generator.free()
	var generator := (load("res://Scripts/Creatures/CreatureGenerator.gd") as GDScript).new() as Node3D
	root.add_child(generator)
	var cube := AABB(Vector3.ZERO, Vector3.ONE)
	assert(is_equal_approx(generator._torso_overlap_volume(cube, cube), 1.0))
	var thin := AABB(Vector3.ZERO, Vector3(10, 0.1, 0.1))
	assert(is_equal_approx(generator._torso_overlap_volume(thin, thin), 0.1), "Long thin overlap must use volume rather than diameter")
	var test_boxes: Array[Dictionary] = [{"aabb": cube}]
	generator.max_torso_overlap_percent = 20.0
	assert(not generator._torso_overlap_is_legal(cube, test_boxes), "Complete overlap exceeds 20 percent")
	assert(generator._torso_overlap_is_legal(AABB(Vector3(0.8,0,0), Vector3.ONE), test_boxes), "Equality is allowed")
	assert(not generator._torso_overlap_is_legal(AABB(Vector3(0.79,0,0), Vector3.ONE), test_boxes), "21 percent exceeds threshold")
	var scaled_boxes: Array[Dictionary] = [{"aabb": AABB(Vector3.ZERO, Vector3.ONE * 0.01)}]
	assert(generator._torso_overlap_is_legal(AABB(Vector3(0.008,0,0), Vector3.ONE * 0.01), scaled_boxes), "Percentage must be invariant under uniform scale")
	var large := AABB(Vector3.ZERO, Vector3.ONE * 10.0)
	assert(not generator._torso_overlap_is_legal(large, test_boxes), "Small existing box must not be swallowed by a large candidate")
	var large_boxes: Array[Dictionary] = [{"aabb": large}]
	assert(not generator._torso_overlap_is_legal(cube, large_boxes), "A small candidate must not be swallowed either")
	generator.max_torso_overlap_percent = 0.0
	assert(generator._torso_overlap_is_legal(AABB(Vector3(1,0,0), Vector3.ONE), test_boxes), "Face contact has zero volume")
	assert(not generator._torso_overlap_is_legal(AABB(Vector3(0.99,0,0), Vector3.ONE), test_boxes), "Zero threshold rejects positive overlap")
	generator.max_torso_overlap_percent = 100.0
	assert(generator._torso_overlap_is_legal(cube, test_boxes), "100 percent allows complete overlap")
	generator.max_torso_overlap_percent = 20.0
	var strict_anchors: Array[Dictionary] = [{"size": Vector3.ONE, "position": Vector3.ZERO}, {"size": Vector3.ONE, "position": Vector3(3, 0, 0)}]
	generator.torso_minimum_size = Vector3.ONE
	generator.torso_maximum_size = Vector3.ONE
	generator._random.seed = 42
	var strict_plan: Array[Dictionary] = generator._plan_network_torsos(strict_anchors, PackedVector3Array([Vector3.ZERO, Vector3(3, 0, 0)]))
	assert(not strict_plan.is_empty(), "20 percent limit must still permit a connected simple network")
	var strict_boxes: Array[Dictionary] = []
	for anchor: Dictionary in strict_anchors: strict_boxes.append(GEOMETRY.box(anchor.size, Transform3D(Basis.IDENTITY, anchor.position)))
	for torso: Dictionary in strict_plan:
		var next := GEOMETRY.box(torso.size, Transform3D(Basis.IDENTITY, torso.position))
		assert(generator._torso_overlap_is_legal(next.aabb, strict_boxes), "Every generated box must satisfy the strict percentage")
		strict_boxes.append(next)
	generator.torso_minimum_size = Vector3(0.6, 0.6, 0.3)
	generator.torso_maximum_size = Vector3(1.4, 1.4, 0.5)
	# Connectivity stress cases use a permissive threshold; ratio edge cases above test strict limits.
	generator.max_torso_overlap_percent = 100.0
	generator._random.seed = 333
	generator.max_limb_end_height_difference = 0.3
	generator.narrowty = 200.0
	generator.unsymmetrie = 100.0
	for count: int in [2, 6, 10]:
		generator.feets = count
		assert(generator.generate_torso())
		_validate_graph(generator)
	# A diagonal network must still connect, even with anisotropic axis-aligned boxes.
	generator.torso_minimum_size = Vector3(0.4, 1.2, 0.6)
	generator.torso_maximum_size = generator.torso_minimum_size
	var diagonal := PackedVector3Array([Vector3.ZERO, Vector3(3, 4, 5)])
	var anchors: Array[Dictionary] = [{"size": Vector3.ONE, "position": diagonal[0]}, {"size": Vector3.ONE, "position": diagonal[1]}]
	var planned: Array[Dictionary] = generator._plan_network_torsos(anchors, diagonal)
	assert(planned.size() > 1)
	for torso: Dictionary in planned:
		assert(torso.basis.is_equal_approx(Basis.IDENTITY))
		assert(torso.position.cross(diagonal[1]).length() < 0.0001)
	# Restore the settings used to build the scene before validating its roundtrip.
	generator.torso_minimum_size = Vector3(0.6, 0.6, 0.3)
	generator.torso_maximum_size = Vector3(1.4, 1.4, 0.5)
	var packed := PackedScene.new()
	assert(packed.pack(generator) == OK)
	var path := "res://Tests/.network_torso_roundtrip.tscn"
	assert(not FileAccess.file_exists(path))
	assert(ResourceSaver.save(packed, path) == OK)
	var restored := (load(path) as PackedScene).instantiate() as Node3D
	_validate_graph(restored)
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK)
	restored.free()
	# Thin boxes cannot reach a SubTorso far away from all network segments.
	var impossible: Array[Dictionary] = [{"size": Vector3.ONE, "position": Vector3(0, 100, 0)}]
	generator.torso_minimum_size = Vector3.ONE * 0.01
	generator.torso_maximum_size = generator.torso_minimum_size
	assert(generator._plan_network_torsos(impossible, PackedVector3Array([Vector3.ZERO, Vector3(0.1,0,0)])).is_empty())
	generator.queue_free()
	print("NETWORK_TORSO_GENERATION_VALIDATION_PASSED")
	quit()

func _validate_graph(generator: Node3D) -> void:
	var boxes: Array[Dictionary] = []
	var new_count := 0
	for child: Node in generator.get_children():
		if not child.has_meta("generated_torso") and not child.has_meta("generated_network_torso"):
			continue
		var torso := child as Node3D
		var size: Vector3 = torso.get_node("Wireframe").mesh.get_aabb().size
		var next_box := GEOMETRY.box(size, torso.transform)
		for existing: Dictionary in boxes:
			var intersection: AABB = next_box.aabb.intersection(existing.aabb)
			if intersection.size.x > 0 and intersection.size.y > 0 and intersection.size.z > 0:
				var volume := intersection.get_volume()
				var limit: float = generator.max_torso_overlap_percent / 100.0
				assert(volume / next_box.aabb.get_volume() <= limit + 0.000001 and volume / existing.aabb.get_volume() <= limit + 0.000001, "Both boxes must satisfy the pairwise overlap percentage")
		boxes.append(next_box)
		assert(torso.get_node("NameLabel").text == str(torso.name))
		if child.has_meta("generated_network_torso"):
			new_count += 1
			var segment: PackedVector3Array = torso.get_meta("source_segment")
			var direction := (segment[1] - segment[0]).normalized()
			assert(torso.basis.is_equal_approx(Basis.IDENTITY), "Edges are no longer aligned to the selected segment")
			assert((torso.position - segment[0]).cross(direction).length() < 0.0001)
			var along := (torso.position - segment[0]).dot(direction)
			assert(along >= -0.00001 and along <= segment[0].distance_to(segment[1]) + 0.00001)
			var vertices: PackedVector3Array = generator.get_node("LimbNetwork").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var actual_segment := false
			for index: int in range(0, vertices.size(), 2):
				actual_segment = actual_segment or (segment[0] == vertices[index] and segment[1] == vertices[index + 1]) or (segment[1] == vertices[index] and segment[0] == vertices[index + 1])
			assert(actual_segment, "Source segment must really exist on the network")
			for axis: int in range(3):
				assert(size[axis] >= generator.torso_minimum_size[axis] - 0.00001 and size[axis] <= generator.torso_maximum_size[axis] + 0.00001)
	assert(new_count >= 1 and generator.has_node("Torso"))
	var visited: Dictionary = {0: true}
	var pending: Array[int] = [0]
	while not pending.is_empty():
		var first: int = pending.pop_back()
		for second: int in range(boxes.size()):
			if not visited.has(second) and GEOMETRY.connected(boxes[first], boxes[second], generator.torso_connection_distance):
				visited[second] = true
				pending.append(second)
	assert(visited.size() == boxes.size(), "Every Torso and SubTorso must belong to one connected component")
