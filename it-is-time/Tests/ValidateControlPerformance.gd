extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var console := root.get_node("RuntimeConsole")
	assert(not console.is_control_performance_tracking_enabled())
	console.execute_command("trackcontrolperf")
	var world := Node3D.new()
	root.add_child(world)
	var character: Node3D = load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate()
	world.add_child(character)
	for body: Node in character.find_children("*", "RigidBody3D", true, false): body.freeze = true
	var cursor: TerrainCursor3D = load("res://Scenes/Input/TerrainCursor3D.tscn").instantiate()
	world.add_child(cursor)
	# Components created after the command must inherit the diagnostic switch.
	assert(cursor._control_perf.enabled)
	cursor.controlled_character = null
	cursor.movement_anchor = null
	var projection := cursor._get_character_projection(character)
	assert(not projection.is_empty())
	var cursor_stats := cursor.consume_control_performance_stats()
	assert(cursor_stats.timings.projection.calls == 1)
	assert(cursor_stats.counters.projection_shapes_used >= 6)
	assert(cursor_stats.counters.projection_corners == cursor_stats.counters.projection_shapes_used * 8)
	assert(cursor.consume_control_performance_stats().timings.is_empty())
	var player: Node3D = load("res://Scenes/Player/Controller.tscn").instantiate()
	player.terrain_cursor = cursor
	character.add_child(player)
	await process_frame
	assert(player._control_perf.enabled)
	player.get_control_anchor()
	var controller_stats: Dictionary = player.consume_control_performance_stats()
	assert(controller_stats.timings.anchor_lookup.calls > 0)
	assert(controller_stats.timings.movement_lookup.calls > 0)
	assert(controller_stats.counters.movement_lookup_nodes > 0)
	var generated: Node3D = load("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn").instantiate()
	generated.generate_on_ready = false
	world.add_child(generated)
	assert(generated._control_perf.enabled)
	var generator := generated.get_node("CreatureGenerator")
	generator.feets = 4
	generator.unsymmetrie = 0.0
	generator.neck_number = 1
	generator.torso_core_extra_blocks = 0
	generator.max_limb_end_height_difference = 0.3
	generator._random.seed = 42
	assert(generated.generate_creature())
	var generation_stats: Dictionary = generated.consume_control_performance_stats()
	assert(generation_stats.timings.generation_total.calls == 1)
	assert(generation_stats.timings.physics_assembly.calls == 1)
	assert(generation_stats.timings.collision_exceptions.calls == 1)
	assert(generation_stats.counters.generated_parts > 0)
	var parts: int = generation_stats.counters.generated_parts
	assert(generation_stats.counters.collision_exception_pairs == parts * (parts - 1) / 2)
	# Preserve a real sample for the console formatter, then verify disabling clears and stops collection.
	cursor._get_character_projection(generated)
	player.get_control_anchor()
	console._process(1.1)
	var output := "\n".join(console._output_lines)
	assert(output.contains("[trackcontrolperf]") and output.contains("anchor_lookup{") and output.contains("projection_corners"))
	var generated_movement := generated.get_node("GeneratedLegStepMovementController3D")
	generated_movement.consume_control_performance_stats()
	generated_movement.set_performance_tracking_enabled(true)
	console.performance_tracking_interval = 10.0
	for frame: int in range(30): await physics_frame
	var gait_phases: Dictionary = generated_movement.consume_control_performance_stats()
	var gait_total: Dictionary = generated_movement.consume_performance_stats()
	assert(gait_phases.timings.torso_tilt.calls > 0)
	assert(gait_phases.timings.movement_generated_full.calls == gait_phases.timings.movement_base.calls)
	assert(gait_total.physics_frames == gait_phases.timings.movement_generated_full.calls)
	assert(gait_total.total_usec >= gait_phases.timings.movement_base.total_usec)
	print("GENERATED_UPDATE_TIMING avg_ms=%.3f tilt_avg_ms=%.3f parts=%d" % [float(gait_total.total_usec) / maxi(int(gait_total.physics_frames), 1) / 1000.0,
		float(gait_phases.timings.torso_tilt.total_usec) / int(gait_phases.timings.torso_tilt.calls) / 1000.0, parts])
	console.execute_command("trackperformance")
	assert("\n".join(console._output_lines).contains("movement_component="))
	console.execute_command("trackperformance")
	console.execute_command("trackcontrolperf")
	assert(not cursor._control_perf.enabled and not player._control_perf.enabled and not generated._control_perf.enabled)
	cursor._get_character_projection(generated)
	player.get_control_anchor()
	assert(cursor.consume_control_performance_stats().timings.is_empty())
	assert(player.consume_control_performance_stats().counters.is_empty())
	world.queue_free()
	await process_frame
	print("CONTROL_PERFORMANCE_VALIDATION_PASSED")
	quit()
