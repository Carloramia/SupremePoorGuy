extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: WorldMapController = load("res://world_map/demo/WorldMapDemo.tscn").instantiate()
	world.auto_load = false
	root.add_child(world)
	await world.initialized
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)]:
		print("TILE ", cell, " center=", world.terrain.map_to_local(cell), " axialworld=", HexMath.axial_to_world(HexMath.cell_to_axial(cell), 64))
	for time in 3:
		print("iteration ", NavigationServer2D.map_get_iteration_id(world.navigation.region.get_navigation_map()))
		for point: Vector2 in [Vector2(690, 220), Vector2(670, 260), Vector2(690, 500), Vector2(120, 220)]:
			var closest := NavigationServer2D.map_get_closest_point(world.navigation.region.get_navigation_map(), point)
			print(point, " hex=", HexMath.world_to_axial(point, 64), " valid=", world.definition.contains(point), " closest=", closest, " dist=", closest.distance_to(point), " path=", world.navigation.legal_path(Vector2(120, 220), point))
		for _index in 5:
			await physics_frame
	world.free()
	quit()
