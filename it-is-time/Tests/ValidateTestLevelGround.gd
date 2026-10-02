extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var level: Node3D = load("res://Scenes/Levels/TestLevel.tscn").instantiate()
	root.add_child(level)
	await process_frame
	var flat := level.get_node("Flat") as Node3D
	var ground := level.get_node("Flat/StaticBody3D") as StaticBody3D
	var collision := ground.get_node("CollisionShape3D") as CollisionShape3D
	var shape := collision.shape as BoxShape3D
	var navigation_region := level.get_node("NavigationRegion3D") as NavigationRegion3D
	assert(ground.get_parent() == flat)
	assert(shape.size.is_equal_approx(Vector3(200.0, 102.0, 200.0)))
	assert(ground.position.is_equal_approx(Vector3(0.0, -50.0, 0.0)))
	assert(is_equal_approx(ground.position.y + shape.size.y * 0.5, 1.0))
	assert(navigation_region.navigation_mesh != null)
	assert(navigation_region.navigation_mesh.get_polygon_count() == 1)
	print("TEST_LEVEL_GROUND_VALIDATION_PASSED")
	level.queue_free()
	quit()
