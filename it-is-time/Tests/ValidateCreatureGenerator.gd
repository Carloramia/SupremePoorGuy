extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var generator := load("res://Scenes/Creatures/Generators/CreatureGenerator.tscn").instantiate() as Node3D
	root.add_child(generator)
	generator.max_limb_end_height_difference = 0.3
	# Use fixed validation parameters instead of the user's live Inspector overrides.
	generator.max_torso_overlap_percent = 100.0
	generator.torso_connection_distance = 0.3
	generator._random.seed = 123
	var found_button := false
	for property: Dictionary in generator.get_property_list():
		if property.name == &"generate_torso_button":
			found_button = property.hint_string.contains("生成随机框架")
	assert(found_button, "Inspector must expose the generation button")
	var first_size := Vector3.ZERO
	var changed := false
	for iteration: int in range(6):
		assert(generator.generate_torso_button.call())
		_validate_torso_coverage(generator)
		var torso := generator.get_node("SubTorso") as Node3D
		assert(torso.owner == generator)
		var wireframe := torso.get_node("Wireframe") as MeshInstance3D
		var mesh := wireframe.mesh as ArrayMesh
		assert(mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_LINES)
		assert(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 24, "A cuboid must have 12 edges")
		var size := mesh.get_aabb().size
		for axis: int in range(3):
			assert(size[axis] >= generator.minimum_size[axis] - 0.0001)
			assert(size[axis] <= generator.maximum_size[axis] + 0.0001)
		if iteration == 0:
			first_size = size
		else:
			changed = changed or not first_size.is_equal_approx(size)
		var label := torso.get_node("NameLabel") as Label3D
		assert(label.text == "SubTorso")
		assert(label.billboard == BaseMaterial3D.BILLBOARD_ENABLED)
		assert(label.position.y > size.y * 0.5)
		assert(label.owner == generator and wireframe.owner == generator)
	assert(changed, "Repeated clicks must sample new dimensions")
	_validate_feet(generator)
	_validate_role_sampling(generator)
	_validate_narrowty(generator)
	_validate_limb_lengths(generator)
	_validate_limb_block_overlap(generator)
	_validate_torso_planning(generator)
	# Persist the generated geometry, not just the tool script.
	var packed := PackedScene.new()
	assert(packed.pack(generator) == OK)
	var test_path := "res://Tests/.creature_generator_roundtrip.tscn"
	assert(not FileAccess.file_exists(test_path))
	assert(ResourceSaver.save(packed, test_path) == OK)
	var restored := (load(test_path) as PackedScene).instantiate() as Node3D
	root.add_child(restored)
	assert(restored.get_node("SubTorso/NameLabel").text == "SubTorso")
	assert(restored.get_node("Feets").get_child_count() == generator.feets + 1)
	_validate_limb_frames(restored.get_node("Feets"), generator)
	_validate_torso_coverage(restored)
	var restored_mesh := restored.get_node("SubTorso/Wireframe").mesh as ArrayMesh
	assert(restored_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 24)
	assert(DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path)) == OK)
	assert(generator._sample_dimension(-2.0, -1.0) > 0.0)
	assert(generator._sample_dimension(3.0, 1.0) >= 1.0)
	print("CREATURE_GENERATOR_VALIDATION_PASSED")
	generator.queue_free()
	restored.queue_free()
	quit()

func _validate_feet(generator: Node3D) -> void:
	for count: int in range(2, 11):
		for profile: Vector3 in [Vector3.ZERO, Vector3(25, 50, 0.2), Vector3(50, 100, 0.5), Vector3(100, 100, 2.0)]:
			generator.feets = count
			generator.unsymmetrie = profile.x
			generator.inhomogeneity = profile.y
			generator.minimum_feet_distance = profile.z
			assert(generator.generate_torso_button.call(), "A valid layout must be found")
			var frames := generator.get_node("Feets") as Node3D
			assert(frames.get_child_count() == count + 1)
			var radius: float = frames.get_meta("variation_radius")
			var circle_mesh := frames.get_node("VariationRange").mesh as ArrayMesh
			var circle_vertices: PackedVector3Array = circle_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			assert(circle_vertices.size() == 128)
			for vertex: Vector3 in circle_vertices:
				assert(is_zero_approx(vertex.y) and is_equal_approx(vertex.length(), radius))
			var strength := profile.x / 100.0
			var furthest_corner := 0.0
			var torso := generator.get_node("SubTorso") as Node3D
			var torso_bounds: AABB = torso.transform * torso.get_node("Wireframe").mesh.get_aabb()
			var foot_bounds: Array[AABB] = []
			for index: int in range(count):
				var foot := _get_limb_by_index(frames, index)
				var initial: Vector2 = foot.get_meta("initial_position")
				var target: Vector2 = foot.get_meta("target_position")
				var fraction: float = foot.get_meta("travel_fraction")
				var final := Vector2(foot.position.x, foot.position.z)
				assert(target.length() <= radius + 0.0001)
				assert(initial.distance_to(target) <= strength * radius + 0.0001)
				assert(fraction >= 0.0 and fraction <= strength + 0.0001)
				assert(final.is_equal_approx(initial.lerp(target, fraction)))
				assert(final.distance_to(initial) <= strength * strength * radius + 0.0001)
				var mesh := foot.get_node("Wireframe").mesh as ArrayMesh
				var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
				assert(vertices.size() == 24, "Feet must now be a cuboid with 12 edges")
				var bounds := foot.transform * mesh.get_aabb()
				assert(is_zero_approx(bounds.position.y), "Feet bottom must sit on Y = 0")
				assert(bounds.size.y > 0.0)
				assert(torso_bounds.position.y > bounds.end.y)
				assert(not torso_bounds.intersects(bounds))
				if profile.y == 0.0:
					assert(bounds.size.is_equal_approx(generator.base_foot_size))
				for axis: int in range(3):
					var low: float = lerpf(generator.base_foot_size[axis], minf(generator.base_foot_size[axis], minf(generator.minimum_foot_size[axis], generator.maximum_foot_size[axis])), profile.y / 100.0)
					var high: float = lerpf(generator.base_foot_size[axis], maxf(generator.base_foot_size[axis], maxf(generator.minimum_foot_size[axis], generator.maximum_foot_size[axis])), profile.y / 100.0)
					assert(bounds.size[axis] >= low - 0.0001 and bounds.size[axis] <= high + 0.0001)
				for previous: AABB in foot_bounds:
					assert(not previous.intersects(bounds))
					var dx := maxf(maxf(previous.position.x - bounds.end.x, bounds.position.x - previous.end.x), 0.0)
					var dz := maxf(maxf(previous.position.z - bounds.end.z, bounds.position.z - previous.end.z), 0.0)
					assert(Vector2(dx, dz).length() >= profile.z - 0.0001)
				foot_bounds.append(bounds)
				for vertex: Vector3 in vertices:
					var corner := initial + Vector2(vertex.x, vertex.z)
					furthest_corner = maxf(furthest_corner, corner.length())
				assert(foot.get_node("NameLabel").text == str(foot.name))
				if index % 2 == 1:
					var previous := _get_limb_by_index(frames, index - 1)
					var paired: Vector2 = previous.get_meta("initial_position")
					assert(initial.is_equal_approx(Vector2(paired.x, -paired.y)))
					assert(paired.y > 0.0 and initial.y < 0.0)
					if strength == 0.0:
						assert(is_equal_approx(foot.position.x, previous.position.x))
						assert(is_equal_approx(foot.position.z, -previous.position.z))
				if strength == 0.0:
					assert(final.is_equal_approx(initial))
			assert(is_equal_approx(radius, furthest_corner))
			_validate_limb_frames(frames, generator)
			_validate_torso_coverage(generator)
	# Validate rejection independently of the sampler.
	var first := {"size": Vector3.ONE, "final_position": Vector2.ZERO}
	var overlap := {"size": Vector3.ONE, "final_position": Vector2(0.1, 0.0)}
	assert(not generator._feet_separated(first, overlap, 0.0))
	var too_close := {"size": Vector3.ONE, "final_position": Vector2(1.1, 0.0)}
	assert(not generator._feet_separated(first, too_close, 0.2))
	var layouts: Array[Dictionary] = [first]
	assert(not generator._is_layout_valid(AABB(Vector3(-0.5, 0.5, -0.5), Vector3.ONE), layouts, 0.0))
	# Failed generation must retain the prior successful mesh and transform.
	var old_torso := generator.get_node("SubTorso") as Node3D
	var old_mesh: Mesh = old_torso.get_node("Wireframe").mesh
	var old_transform := old_torso.transform
	generator.minimum_feet_distance = INF
	assert(not generator.generate_torso())
	assert(old_torso.get_node("Wireframe").mesh == old_mesh and old_torso.transform == old_transform)
	generator.minimum_feet_distance = 0.2
	generator.feets = 2
	generator.unsymmetrie = 0.0
	generator.inhomogeneity = 0.0
	assert(generator.generate_torso())
	assert(generator.get_node("Feets").get_child_count() == 3)

func _get_limb_by_index(frames: Node3D, index: int) -> Node3D:
	for child: Node in frames.get_children():
		if child.has_meta("foot_index") and int(child.get_meta("foot_index")) == index:
			return child as Node3D
	assert(false, "Generated limb index must exist")
	return null

func _validate_limb_frames(frames: Node3D, generator: Node3D) -> void:
	var limbs: Array[Node3D] = []
	for child: Node in frames.get_children():
		if child.has_meta("foot_index"):
			limbs.append(child as Node3D)
	assert(limbs.size() == generator.feets)
	limbs.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return int(a.get_meta("foot_index")) < int(b.get_meta("foot_index")) if a.position.x == b.position.x else a.position.x < b.position.x
	)
	var extra: int = frames.get_meta("extra_leg_count")
	assert(extra >= 0 and extra <= maxi(limbs.size() - 4, 0))
	if generator.unsymmetrie == 0.0:
		assert(extra % 2 == 0)
	if generator.unsymmetrie == 100.0 and limbs.size() > 4:
		assert(extra % 2 == 1)
	var front_count := mini(2, limbs.size() - 2)
	for index: int in range(limbs.size()):
		var limb := limbs[index]
		var expected_role := "Leg" if index < 2 + extra else "ForeLeg"
		if index >= limbs.size() - front_count:
			expected_role = "ForeLeg"
		var role: String = limb.get_meta("limb_type")
		if generator.unsymmetrie > 0.0 or limbs.size() % 2 == 0:
			assert(role == expected_role, "Rear-most limbs must be Legs; front-most limbs must be ForeLegs")
		else:
			# For odd symmetric layouts, the center Feet stays on-plane; mirror partners share roles.
			var original_index: int = limb.get_meta("foot_index")
			if original_index < limbs.size() - 1:
				var partner := _get_limb_by_index(frames, original_index ^ 1)
				assert(partner.get_meta("limb_type") == role)
		assert(str(limb.name).begins_with(role + "_"))
		assert(not str(limb.name).begins_with("Feet_"))
		var points: PackedVector3Array = limb.get_meta("limb_points")
		assert(points.size() == (3 if role == "ForeLeg" else 4))
		var total := 0.0
		for segment: int in range(1, points.size()):
			total += points[segment - 1].distance_to(points[segment])
		assert(is_equal_approx(total, float(limb.get_meta("limb_length"))), "Actual polyline length must match its preset")
		var box_size: Vector3 = limb.get_node("Wireframe").mesh.get_aabb().size
		assert(points[0].is_equal_approx(Vector3(0.0, box_size.y * 0.5, 0.0)))
		for point: int in range(1, points.size()):
			assert(points[point].y > points[point - 1].y)
			assert(is_zero_approx(points[point].z))
		assert(points[1].x < points[0].x)
		assert(points[2].x > points[1].x)
		if role == "ForeLeg":
			assert(points[2].x < points[0].x)
		else:
			assert(points[3].x < points[2].x)
			assert(points[3].x > points[1].x)
		var mesh := limb.get_node("Limb").mesh as ArrayMesh
		assert(mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_LINES)
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		assert(vertices.size() == 2 * (points.size() - 1))
		for segment: int in range(points.size() - 1):
			assert(vertices[segment * 2].is_equal_approx(points[segment]))
			assert(vertices[segment * 2 + 1].is_equal_approx(points[segment + 1]))
		assert(limb.get_node("Limb").owner == frames.owner)
		var limb_node := limb.get_node("Limb") as MeshInstance3D
		assert(limb_node.get_child_count() == points.size() - 1)
		for segment: int in range(points.size() - 1):
			var block := limb_node.get_node("Segment_%d" % (segment + 1)) as MeshInstance3D
			assert(block.owner == frames.owner and block.has_meta("generated_limb_block"))
			var block_mesh := block.mesh as ArrayMesh
			assert(block_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 24)
			var size := block_mesh.get_aabb().size
			var length := points[segment].distance_to(points[segment + 1])
			assert(size.is_equal_approx(limb.get_meta("limb_block_sizes")[segment]))
			assert((block.transform * Vector3(0, -length * 0.5, 0)).is_equal_approx(points[segment]))
			assert((block.transform * Vector3(0, length * 0.5, 0)).is_equal_approx(points[segment + 1]))

func _validate_role_sampling(generator: Node3D) -> void:
	# Isolate the classifier from geometry; initial order deliberately differs from final X order.
	for strength: float in [0.0, 50.0, 100.0]:
		generator.unsymmetrie = strength
		var layouts: Array[Dictionary] = []
		for x: float in [4.0, -3.0, 2.0, -1.0, -2.0, 3.0, 0.0, 1.0]:
			layouts.append({"final_position": Vector2(x, 0.0)})
		var extra: int = generator._assign_limb_roles(layouts)
		assert(layouts[1].role == "Leg" and layouts[4].role == "Leg")
		assert(layouts[0].role == "ForeLeg" and layouts[5].role == "ForeLeg")
		assert(extra >= 0 and extra <= 4)
		if strength == 0.0:
			assert(extra % 2 == 0)
		elif strength == 100.0:
			assert(extra % 2 == 1)
	# Verify actual even-count probability with a fixed reproducible seed.
	generator._random.seed = 42
	for strength: float in [0.0, 25.0, 50.0, 75.0, 100.0]:
		generator.unsymmetrie = strength
		var even_count := 0
		for draw: int in range(2000):
			var count: int = generator._sample_extra_leg_count(6)
			assert(count >= 0 and count <= 6)
			if count % 2 == 0:
				even_count += 1
		assert(absf(float(even_count) / 2000.0 - (1.0 - strength / 100.0)) < 0.05)
	generator.unsymmetrie = 0.0

func _validate_narrowty(generator: Node3D) -> void:
	generator.feets = 6
	generator.inhomogeneity = 0.0
	generator.unsymmetrie = 0.0
	generator.narrowty = 0.0
	generator._random.seed = 123
	var baseline: Array[Dictionary] = generator._sample_initial_feet(Vector3(2, 3, 1), 0.2)
	assert(baseline.size() == 6)
	var base_spread: Vector2 = baseline[0].allowed_spread
	for value: float in [0.0, 100.0, 200.0]:
		generator.narrowty = value
		var expected := Vector2(1.0 + value / 100.0, 1.0 / (1.0 + value / 100.0))
		assert(generator._get_distribution_scale().is_equal_approx(expected))
		generator._random.seed = 123
		var sampled: Array[Dictionary] = generator._sample_initial_feet(Vector3(2, 3, 1), 0.2)
		assert(sampled.size() == 6)
		assert(sampled[0].allowed_spread.is_equal_approx(base_spread * expected))
		if value == 0.0:
			for index: int in range(6):
				assert(sampled[index].position == baseline[index].position)
		for count: int in [2, 3, 6, 10]:
			for asymmetry: float in [0.0, 100.0]:
				generator.feets = count
				generator.unsymmetrie = asymmetry
				assert(generator.generate_torso())
				var frames := generator.get_node("Feets") as Node3D
				var limit: Vector2 = frames.get_meta("allowed_spread")
				var layouts: Array[Dictionary] = []
				for index: int in range(count):
					var foot := _get_limb_by_index(frames, index)
					var final := Vector2(foot.position.x, foot.position.z)
					if value > 0.0:
						assert(absf(final.x) <= limit.x and absf(final.y) <= limit.y)
					var size: Vector3 = foot.get_node("Wireframe").mesh.get_aabb().size
					assert(size.is_equal_approx(generator.base_foot_size), "Narrowty must not resize cuboids")
					layouts.append({"final_position": final, "size": size, "allowed_spread": limit})
				var torso := generator.get_node("SubTorso") as Node3D
				assert(generator._is_layout_valid(torso.transform * torso.get_node("Wireframe").mesh.get_aabb(), layouts, generator.minimum_feet_distance))
				_validate_limb_frames(frames, generator)
			_validate_torso_coverage(generator)
		generator.feets = 6
		generator.unsymmetrie = 0.0
	generator.narrowty = 100.0
	var empty_layouts: Array[Dictionary] = []
	assert(not generator._foot_fits({"final_position": Vector2(0, 2), "allowed_spread": Vector2.ONE, "size": Vector3.ONE}, empty_layouts, 0.2), "Unsymmetrie cannot escape the narrowed width")
	var old_mesh: Mesh = generator.get_node("SubTorso/Wireframe").mesh
	generator.narrowty = 100000.0
	assert(not generator.generate_torso(), "An impossible narrow width must fail safely")
	assert(generator.get_node("SubTorso/Wireframe").mesh == old_mesh)
	generator.narrowty = 0.0
	generator.feets = 2
	generator.unsymmetrie = 0.0
	assert(generator.generate_torso())

func _validate_limb_lengths(generator: Node3D) -> void:
	generator._random.seed = 456
	generator.feets = 8
	generator.base_limb_length = 3.5
	for profile: Vector2 in [Vector2.ZERO, Vector2(0, 100), Vector2(100, 0), Vector2(100, 100)]:
		generator.unsymmetrie = profile.x
		generator.inhomogeneity = profile.y
		assert(generator.generate_torso())
		var frames := generator.get_node("Feets") as Node3D
		_validate_limb_frames(frames, generator)
		var different_pair := false
		var different_side := false
		var first_length: float = _get_limb_by_index(frames, 0).get_meta("limb_length")
		for index: int in range(8):
			var foot := _get_limb_by_index(frames, index)
			assert(foot.has_node("Limb") and not foot.has_node("LimbPolyline"))
			var length: float = foot.get_meta("limb_length")
			assert(length >= 3.5 * 0.25 and length <= 3.5 * 2.25)
			if profile == Vector2.ZERO:
				assert(is_equal_approx(length, 3.5))
			if index % 2 == 0:
				different_pair = different_pair or not is_equal_approx(length, first_length)
			else:
				var paired: float = _get_limb_by_index(frames, index - 1).get_meta("limb_length")
				different_side = different_side or not is_equal_approx(length, paired)
				if profile.x == 0.0:
					assert(is_equal_approx(length, paired), "Mirror partners must have identical total lengths at zero Unsymmetrie")
		if profile.y > 0.0:
			assert(different_pair, "Inhomogeneity must vary lengths between front/rear pairs")
		if profile.x > 0.0:
			assert(different_side, "Unsymmetrie must allow independent lengths on each side")
	generator.unsymmetrie = 0.0
	generator.inhomogeneity = 0.0
	var shortest: PackedVector3Array = generator._create_limb_points("ForeLeg", 1.2, 0.0025)
	var shortest_total := 0.0
	for index: int in range(1, shortest.size()):
		shortest_total += shortest[index - 1].distance_to(shortest[index])
	assert(absf(shortest_total - 0.0025) < 0.000001)
	generator.base_limb_length = 2.0
	generator.feets = 2
	assert(generator.generate_torso())

func _validate_torso_coverage(generator: Node3D) -> void:
	var torsos: Array[AABB] = []
	var feet := generator.get_node("Feets") as Node3D
	for child: Node in generator.get_children():
		if child.has_meta("generated_torso"):
			var torso := child as Node3D
			var bounds: AABB = torso.transform * torso.get_node("Wireframe").mesh.get_aabb()
			assert(torso.owner == generator)
			assert(torso.get_node("NameLabel").text == str(torso.name))
			var covers_any := false
			for foot: Node3D in feet.get_children():
				if not foot.has_meta("foot_index"):
					continue
				var part_bounds: AABB = foot.transform * foot.get_node("Wireframe").mesh.get_aabb()
				var points: PackedVector3Array = foot.get_meta("limb_points")
				var endpoint := foot.position + points[points.size() - 1]
				covers_any = covers_any or generator._point_to_torso_distance(endpoint, bounds) <= generator.max_limb_end_height_difference + 0.00001
				assert(bounds.position.y > part_bounds.end.y)
			for previous: AABB in torsos:
				assert(not previous.intersects(bounds), "Torso volumes must not overlap")
			assert(covers_any, "Every Torso must be near at least one Limb endpoint")
			torsos.append(bounds)
	assert(torsos.size() >= 1 and torsos.size() <= 2 * (feet.get_child_count() - 1), "A mirrored batch may add a partner for an already covered endpoint")
	var generated_count := 0
	for child: Node in generator.get_children():
		if child.has_meta("generated_network_torso"):
			generated_count += 1
	assert(generated_count >= 1)
	var neck_count := 0
	for child: Node in generator.get_children():
		if child.has_meta(&"generated_neck_line"):
			neck_count += 1
	assert(generator.get_child_count() == torsos.size() + generated_count + neck_count + 2, "Regeneration must remove stale Torsos")
	for foot: Node3D in feet.get_children():
		if not foot.has_meta("foot_index"):
			continue
		var points: PackedVector3Array = foot.get_meta("limb_points")
		var endpoint := foot.position + points[points.size() - 1]
		var covered := false
		for bounds: AABB in torsos:
			covered = covered or generator._point_to_torso_distance(endpoint, bounds) <= generator.max_limb_end_height_difference + 0.00001
		assert(covered, "Every Limb endpoint must have a nearby Torso")

func _validate_torso_planning(generator: Node3D) -> void:
	var layouts: Array[Dictionary] = []
	for x: float in [-20.0, 0.0, 20.0]:
		layouts.append({"final_position": Vector2(x, 0.0), "size": Vector3.ONE, "limb_points": PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0, 2.5, 0)])})
	var torsos: Array[Dictionary] = generator._plan_torsos(layouts)
	assert(torsos.size() == 3, "Separated parts must force multiple Torsos")
	var same_x: Array[Dictionary] = [
		{"final_position": Vector2(0, -2), "size": Vector3.ONE, "limb_points": PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0, 2.5, 0)])},
		{"final_position": Vector2(0, 2), "size": Vector3.ONE, "limb_points": PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0, 2.5, 0)])}
	]
	assert(generator._plan_torsos(same_x).size() == 2, "Shared X alone cannot cover separated Z endpoints")
	assert(not generator._overlaps_x(AABB(Vector3.ZERO, Vector3.ONE), AABB(Vector3(1, 0, 0), Vector3.ONE)))
	# Force narrow Torsos whose X projections overlap but cannot cover both part centers.
	var old_min: Vector3 = generator.minimum_size
	var old_max: Vector3 = generator.maximum_size
	generator.minimum_size = Vector3(0.8, 1.0, 1.0)
	generator.maximum_size = generator.minimum_size
	var close: Array[Dictionary] = [
		{"final_position": Vector2(0, -2), "size": Vector3(0.01, 1, 1), "limb_points": PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0, 2.5, 0)])},
		{"final_position": Vector2(0.6, 2), "size": Vector3(0.01, 1, 1), "limb_points": PackedVector3Array([Vector3(0, 0.5, 0), Vector3(0, 2.5, 0)])}
	]
	var stacked: Array[Dictionary] = generator._plan_torsos(close)
	assert(stacked.size() == 2)
	assert(not stacked[0].bounds.intersects(stacked[1].bounds))
	assert(absf(stacked[0].position.z) > 0.0 and absf(stacked[1].position.z) > 0.0)
	generator.minimum_size = old_min
	generator.maximum_size = old_max
	# Roundtrip validation should include multiple Torso meshes and labels.
	generator.feets = 10
	generator.narrowty = 200.0
	generator._random.seed = 444
	assert(generator.generate_torso())
	_validate_torso_coverage(generator)
	var torso_count := 0
	for child: Node in generator.get_children():
		if child.has_meta("generated_torso"):
			torso_count += 1
	assert(torso_count > 1)

func _validate_limb_block_overlap(generator: Node3D) -> void:
	generator.limb_minimum_size = Vector3(100.0, 0.6, 100.0)
	generator.limb_maximum_size = generator.limb_minimum_size
	assert(generator.generate_torso(), "Limb block overlaps must not reject a valid frame")
	_validate_limb_frames(generator.get_node("Feets"), generator)
	var blocks: Array[AABB] = []
	for foot: Node3D in generator.get_node("Feets").get_children():
		if not foot.has_meta("limb_points"):
			continue
		var block := foot.get_node("Limb/Segment_1") as MeshInstance3D
		blocks.append(foot.transform * block.transform * block.mesh.get_aabb())
	assert(blocks[0].intersects(blocks[1]), "Test must actually include overlapping Limb blocks")
	generator.limb_minimum_size = Vector3(0.25, 0.4, 0.25)
	generator.limb_maximum_size = Vector3(0.25, 0.8, 0.25)
	assert(generator.generate_torso())
