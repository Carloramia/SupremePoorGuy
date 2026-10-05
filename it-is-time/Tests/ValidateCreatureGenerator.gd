extends SceneTree

const GENERATOR = preload("res://Scripts/Creatures/CreatureGenerator.gd")
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var generator = GENERATOR.new()
	root.add_child(generator)
	generator._random.seed = 417
	for counts: Vector2i in [Vector2i(2, 2), Vector2i(3, 1), Vector2i(0, 4), Vector2i(4, 0), Vector2i(0, 0), Vector2i(10, 10)]:
		generator.rear_leg_count = counts.x
		generator.foreleg_count = counts.y
		generator.body_length = 12.0 if counts.x + counts.y > 8 else 4.0
		for torso_count: int in [1, 3, 8]:
			generator.torso_count = torso_count
			for segments: int in range(4):
				generator.neck_segment_count = segments
				var plan: Dictionary = generator._create_valid_plan()
				assert(not plan.is_empty(), "Counts %s, torso=%d, neck=%d" % [counts, torso_count, segments])
				assert(plan.torsos.size() == counts.x + counts.y and plan.network_torsos.size() == torso_count)
				assert(plan.layouts.size() == counts.x + counts.y)
				var rear := 0
				var front := 0
				for foot: Dictionary in plan.layouts:
					if foot.role == "Leg": rear += 1
					else: front += 1
					assert(foot.limb_points.size() == (4 if foot.role == "Leg" else 3))
					assert(foot.limb_block_sizes.size() == foot.limb_points.size() - 1)
					var tip: Vector3 = generator._limb_endpoint(foot)
					assert(generator._nearest_neck_torso_distance(tip, plan.torsos.slice(foot.sub_torso_index, foot.sub_torso_index + 1)) < 0.0001)
					for torso: Dictionary in plan.network_torsos:
						assert(torso.position.y - torso.size.y * 0.5 > foot.size.y)
					if foot.partner_index >= 0:
						var other: Dictionary = plan.layouts[foot.partner_index]
						assert(foot.final_position.is_equal_approx(Vector2(other.final_position.x, -other.final_position.y)))
						for point: int in range(foot.limb_points.size()):
							assert(foot.limb_points[point].is_equal_approx(generator._mirror_point(other.limb_points[point])))
				assert(rear == counts.x and front == counts.y)
				var bodies: Array = plan.network_torsos
				var extent: float = bodies[-1].position.x + bodies[-1].size.x * 0.5 - bodies[0].position.x + bodies[0].size.x * 0.5
				assert(is_equal_approx(extent, generator.body_length))
				for body: Dictionary in bodies:
					assert(is_zero_approx(body.position.z) and not body.sub_torso)
				assert(plan.necks[0].points.size() == segments + 1)
				assert(plan.necks[0].blocks.size() == segments + 1)
				assert(plan.necks[0].blocks[-1].name == "Head")
				if segments == 0:
					assert(generator._nearest_neck_torso_distance(plan.necks[0].points[0], bodies) < 0.0001)
	generator.rear_leg_count = 2
	generator.foreleg_count = 2
	generator.torso_count = 4
	generator.body_length = 4.0
	for overlap: float in [0.0, 20.0, 60.0, 95.0]:
		generator.torso_overlap_percent = overlap
		var plan: Dictionary = generator._create_valid_plan()
		assert(not plan.is_empty())
		var first: Dictionary = plan.network_torsos[0]
		var second: Dictionary = plan.network_torsos[1]
		var intersection: float = first.position.x + first.size.x * 0.5 - second.position.x + second.size.x * 0.5
		assert(is_equal_approx(intersection / first.size.x, overlap / 100.0))
	# Test actual saved scene overrides and the physical blueprint, including head-only necks.
	var actor = CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var embedded = actor.get_node("CreatureGenerator")
	embedded._random.seed = 51
	for segments: int in range(4):
		embedded.neck_segment_count = segments
		var emitted: Array[Dictionary] = []
		var callback := func(plan: Dictionary) -> void: emitted.append(plan)
		embedded.framework_generated.connect(callback)
		assert(actor.generate_creature())
		embedded.framework_generated.disconnect(callback)
		var blueprint: Dictionary = actor._build_blueprint(emitted[0], embedded.torso_connection_distance)
		assert(not blueprint.is_empty())
		var count := 0
		for part: Dictionary in blueprint.parts:
			if part.role == "Torso" and not part.sub_torso:
				count += 1
		assert(count == embedded.torso_count)
		assert(blueprint.connections.size() == blueprint.parts.size() - 1)
	assert(generator.generate_torso())
	var nodes := generator.get_child_count()
	assert(generator.generate_torso() and generator.get_child_count() == nodes)
	var old_count := generator.get_child_count()
	generator.body_length = NAN
	assert(not generator.generate_torso() and generator.get_child_count() == old_count)
	actor.free()
	generator.free()
	print("CREATURE_GENERATOR_LAYOUT_VALIDATION_PASSED")
	quit()
