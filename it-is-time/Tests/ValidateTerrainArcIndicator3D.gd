extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var level := load("res://Scenes/Levels/TestLevel.tscn").instantiate() as Node3D
	root.add_child(level)
	var cursor: Node3D = level.get_node("TerrainCursor3D")
	var indicator: Node3D = level.get_node("TerrainArcIndicator3D")
	var anchor: Node3D = level.get_node("Flat/CharacterTest2/Torso")
	assert(indicator.movement_anchor == anchor)
	assert(indicator.terrain_cursor == cursor)
	var ring := indicator.get_node("Ring") as MeshInstance3D
	var glow := indicator.get_node("Glow") as MeshInstance3D
	assert(ring.mesh is ArrayMesh and ring.mesh.get_surface_count() == 1)
	assert(glow.mesh is ArrayMesh and glow.mesh.get_surface_count() == 1)
	assert((ring.material_override as StandardMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED)
	assert((glow.material_override as StandardMaterial3D).cull_mode == BaseMaterial3D.CULL_DISABLED)
	cursor.set_cursor_world_position(anchor.global_position + Vector3(5.0, 0.0, 0.0))
	for _frame: int in 6:
		await physics_frame
	assert(cursor.has_valid_ground_position())
	assert(indicator.has_valid_ground_projection())
	assert(indicator.visible)
	var expected_direction := cursor.global_position - indicator.global_position
	expected_direction = expected_direction.slide(indicator.global_basis.y).normalized()
	assert(indicator.get_facing_direction().dot(expected_direction) > 0.95)
	print("TERRAIN_ARC_INDICATOR_3D_VALIDATION_PASSED")
	level.queue_free()
	quit()
