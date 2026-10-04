extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var generator := (load("res://Scripts/Creatures/CreatureGenerator.gd") as GDScript).new() as Node3D
	root.add_child(generator)
	generator._random.seed = 345
	generator.max_limb_end_height_difference = 0.3
	generator.minimum_size = Vector3(0.5, 0.5, 0.5)
	generator.maximum_size = Vector3.ONE
	generator.narrowty = 200.0
	for count: int in [2, 6, 10]:
		for asymmetry: float in [0.0, 100.0]:
			generator.feets = count
			generator.unsymmetrie = asymmetry
			generator.inhomogeneity = asymmetry
			assert(generator.generate_torso())
			var endpoints := PackedVector3Array()
			for foot: Node3D in generator.get_node("Feets").get_children():
				if not foot.has_meta("limb_points"):
					continue
				var points: PackedVector3Array = foot.get_meta("limb_points")
				endpoints.append(foot.position + points[points.size() - 1])
			var torso_bounds: Array[AABB] = []
			var moved_z := false
			for child: Node in generator.get_children():
				if child.has_meta("generated_torso"):
					var torso := child as Node3D
					torso_bounds.append(torso.transform * torso.get_node("Wireframe").mesh.get_aabb())
					moved_z = moved_z or not is_zero_approx(torso.position.z)
			assert(moved_z, "Torso Z must follow endpoint positions")
			for endpoint: Vector3 in endpoints:
				var nearest_distance := INF
				for bounds: AABB in torso_bounds:
					nearest_distance = minf(nearest_distance, _surface_distance(endpoint, bounds))
				assert(nearest_distance <= 0.30001)
	# Test shell distance: the cube center is half a unit from its surface.
	var box := AABB(Vector3.ZERO, Vector3.ONE)
	assert(is_equal_approx(generator._point_to_torso_distance(Vector3(0.5, 0.5, 0.5), box), 0.5))
	assert(is_equal_approx(generator._point_to_torso_distance(Vector3(0.1, 0.5, 0.5), box), 0.1))
	assert(is_zero_approx(generator._point_to_torso_distance(Vector3(0, 0.5, 0.5), box)))
	assert(is_equal_approx(generator._point_to_torso_distance(Vector3(0.5, 0.5, 2), box), 1.0))
	assert(is_equal_approx(generator._point_to_torso_distance(Vector3(2, 2, 2), box), sqrt(3.0)))
	var layouts: Array[Dictionary] = [{"size": Vector3.ONE, "final_position": Vector2.ZERO, "limb_points": PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0, 2.5, 0)])}]
	generator.minimum_size = Vector3.ONE
	generator.maximum_size = Vector3.ONE
	generator.max_limb_end_height_difference = 0.0
	var matched: Array[Dictionary] = generator._plan_torsos(layouts)
	assert(matched.size() == 1)
	assert(is_zero_approx(generator._point_to_torso_distance(Vector3(0, 3, 0), matched[0].bounds)))
	# A Limb ending just above the Feet cannot accommodate a tall Torso at zero difference.
	layouts[0].limb_points = PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0, 0.51, 0)])
	assert(generator._plan_torsos(layouts).is_empty())
	var old_torso := generator.get_node("SubTorso")
	var old_mesh: Mesh = old_torso.get_node("Wireframe").mesh
	generator.base_limb_length = 0.01
	assert(not generator.generate_torso())
	assert(generator.get_node("SubTorso") == old_torso and old_torso.get_node("Wireframe").mesh == old_mesh)
	generator.queue_free()
	print("TORSO_LIMB_DISTANCE_VALIDATION_PASSED")
	quit()

# Independent reference: project to each of the six rectangular faces and take the minimum.
func _surface_distance(point: Vector3, bounds: AABB) -> float:
	var distance := INF
	for axis: int in range(3):
		for boundary: float in [bounds.position[axis], bounds.end[axis]]:
			var face_point := point.clamp(bounds.position, bounds.end)
			face_point[axis] = boundary
			distance = minf(distance, point.distance_to(face_point))
	return distance
