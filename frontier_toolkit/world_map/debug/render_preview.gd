extends SceneTree

var world: WorldMapController
var index: int = 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 800)
	world = load("res://world_map/demo/WorldMapDemo.tscn").instantiate()
	world.auto_load = false
	world.save_path = "res://.tools/preview_save.json"
	root.add_child(world)
	await world.initialized
	await capture("initial")
	world.set_move_target(Vector2(690, 220))
	await capture("navigation")
	world.player.cancel_movement("preview")
	world.player.global_position = world.get_location(&"town").interaction_point()
	world.select_location(&"town")
	await capture("settlement")
	world.resolve_location_interaction(&"town", {"success": true})
	for id: StringName in [&"herbs", &"monument", &"bandits"]:
		world.player.global_position = world.get_location(id).interaction_point()
		world.fog.update_vision(world.player.global_position)
		world.locations.detect(world.player.global_position, world.fog)
		world.select_location(id)
		await capture(String(id))
		if id == &"bandits":
			world.interaction.request_battle()
			await capture("fake_battle")
			(world.get_node("FakeBattleAdapter") as FakeBattleAdapter).return_result("defeat")
		else:
			world.resolve_location_interaction(id, {"success": true, "complete_location": true})
	# Overview is a debug visualization of all explored terrain, separate from startup.
	for hex in world.definition.enabled_cells():
		world.fog.update_vision(HexMath.axial_to_world(hex, world.definition.hex_size))
	world.locations.detect(world.player.global_position, world.fog)
	world.camera.mode = WorldMapCameraController.Mode.FREE
	world.camera.global_position = world.definition.world_rect().get_center()
	world.camera.zoom = Vector2(0.7, 0.7)
	world.terrain.show_hex_debug = true
	world.terrain.queue_redraw()
	await capture("overview")
	world.queue_free()
	quit()

func capture(label: String) -> void:
	for _frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://world_map/debug/preview_%s.png" % label)
	print("PREVIEW SAVED: " + label)
