extends SceneTree

var scene: ScenarioController
var results: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func settle(frames: int = 60) -> void:
	for frame in frames:
		await physics_frame
	await RenderingServer.frame_post_draw

func capture(name: String) -> Image:
	var image := root.get_texture().get_image()
	image.save_png("res://scenario_2_5d/debug/preview_" + name + ".png")
	return image

func differences(a: Image, b: Image, region: Rect2i) -> int:
	var count: int = 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			if absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b) > 0.08:
				count += 1
	return count

func check(name: String, passed: bool, pixels: int = 0) -> void:
	results.append({"name": name, "pass": passed, "changed_pixels": pixels})
	print("PASS " if passed else "FAIL ", name, " changed_pixels=", pixels)

func run() -> void:
	root.size = Vector2i(1920, 1080)
	scene = load("res://scenario_2_5d/demo/Scenario25DDemo.tscn").instantiate()
	root.add_child(scene)
	var hero: Node3D = scene.get_node("Actors/Hero")
	var camera := scene.camera_controller.camera
	await settle()
	var fade := capture("fade")
	var region := Rect2i(Vector2i(camera.unproject_position(hero.global_position + Vector3(0, 1.3, 0))) - Vector2i(65, 65), Vector2i(130, 130))
	scene.occlusion_controller.enabled = false
	await settle()
	var behind := capture("depth_behind")
	hero.hide()
	await settle(5)
	var without_hero := root.get_texture().get_image()
	var hidden_pixels := differences(behind, without_hero, region)
	check("behind_building_true_depth", hidden_pixels < 15, hidden_pixels)
	var faded_pixels := differences(fade, behind, region)
	check("fade_reveals_target", faded_pixels > 150, faded_pixels)
	hero.show()
	hero.position = Vector3(-5, 0, 4)
	await settle(5)
	var front := capture("depth_front")
	region.position = Vector2i(camera.unproject_position(hero.global_position + Vector3(0, 1.3, 0))) - Vector2i(65, 65)
	hero.hide()
	await settle(5)
	var no_front := root.get_texture().get_image()
	var front_pixels := differences(front, no_front, region)
	check("front_visible", front_pixels > 150, front_pixels)
	hero.show()
	scene.interaction_controller.select_object(scene.get_node("Actors/Crate"))
	await settle(5)
	capture("selected")
	check("info_panel_rendered", scene.get_node("DemoUI").info_panel.visible)
	root.size = Vector2i(1280, 720)
	await settle(5)
	capture("resize")
	var ui: CanvasLayer = scene.get_node("DemoUI")
	check("resize_ui_inside_viewport", ui.info_panel.get_global_rect().end.x <= 1920 and ui.info_panel.get_global_rect().position.x > 0)
	var failed: int = results.filter(func(row: Dictionary) -> bool: return not row.pass).size()
	var file := FileAccess.open("res://scenario_2_5d/debug/render_test_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed": results.size() - failed, "failed": failed, "tests": results}, "\t"))
	scene.queue_free()
	await process_frame
	quit(0 if failed == 0 else 1)
