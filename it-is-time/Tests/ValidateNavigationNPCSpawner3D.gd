extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var level := load("res://Scenes/Levels/TestLevel.tscn").instantiate() as Node3D
	root.add_child(level)
	for _frame: int in range(10):
		await physics_frame
	var spawner := level.get_node("NavigationNPCSpawner3D")
	var npc := spawner.try_spawn_npc() as Node3D
	assert(npc != null)
	assert(npc.get_parent() == level.get_node("Flat"))
	assert(spawner.get_spawned_npc_count() == 1)
	var navigation_mesh := (level.get_node("NavigationRegion3D") as NavigationRegion3D).navigation_mesh
	var closest_point := NavigationServer3D.map_get_closest_point(
		(level.get_node("NavigationRegion3D") as NavigationRegion3D).get_navigation_map(),
		npc.global_position
	)
	assert(is_equal_approx(npc.global_position.y - closest_point.y, spawner.spawn_height))
	await physics_frame
	var state_machine := npc.get_node("NPCStateMachine3D")
	assert(state_machine.get("current_state") == state_machine.State.MOVE_TO_TARGET)
	assert(state_machine.get("_target") == level.get_node("Flat/CharacterTest2/Torso"))
	assert(navigation_mesh.get_polygon_count() > 0)
	print("NAVIGATION_NPC_SPAWNER_VALIDATION_PASSED")
	level.queue_free()
	quit()
