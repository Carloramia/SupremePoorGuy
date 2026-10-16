extends SceneTree
const LabScene = preload("res://ui_module/shader_lab/demo/ShaderLab.tscn")
const WorkshopScene = preload("res://ui_module/shader_lab/demo/ComponentWorkshop.tscn")
const Cutout = preload("res://ui_module/shader_lab/components/paper_cutout.gd")
const Field = preload("res://ui_module/shader_lab/components/silhouette_field.gd")
var checks := 0
var failures: Array[String] = []
var capture := false
var output := "res://ui_module/shader_lab/tests/screenshots/"
var captures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("FAILED: " + message)

func frames() -> void:
	await process_frame
	await process_frame
	if capture:
		await RenderingServer.frame_post_draw

func snapshot(name: String) -> Image:
	await frames()
	var image := root.get_texture().get_image()
	check(image != null and not image.is_empty(), "Rendered image: " + name)
	check(image.save_png(output + name + ".png") == OK, "Write capture: " + name)
	captures.append(name + ".png")
	return image

func click_at(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func test_distance_field() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in range(4, 12):
		for x in range(4, 12):
			img.set_pixel(x, y, Color("#9c4938"))
	for y in range(6, 10):
		for x in range(6, 10):
			img.set_pixel(x, y, Color.TRANSPARENT)
	var texture := ImageTexture.create_from_image(img)
	var field := Field.build(texture, 8)
	var map := (field.texture as Texture2D).get_image()
	check(is_equal_approx(map.get_pixel(16, 16).r, 0.0), "Enclosed transparent hole belongs to whole white silhouette")
	check(absf(map.get_pixel(9, 9).r - (sqrt(18.0) - 0.5)) < 0.001, "Euclidean distance at diagonal corner")
	check(absf(map.get_pixel(10, 15).r - 1.5) < 0.001, "Exact distance on straight contour")
	check(Field.build(texture, 8).texture == field.texture, "Distance field is cached")
	return texture

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var synthetic := test_distance_field()
	var lab := LabScene.instantiate()
	root.add_child(lab)
	await frames()
	check(lab.profiles.size() == 5, "Five same-asset comparison groups")
	await click_at(lab.buttons[0].get_global_rect().get_center())
	check(lab.activation_count == 1, "Real GUI mouse input reaches native Button through decorative layers")
	lab.buttons[0].disabled = true
	await click_at(lab.buttons[0].get_global_rect().get_center())
	check(lab.activation_count == 1, "Disabled native Button rejects real GUI clicks")
	lab.buttons[0].disabled = false
	var expected := [[false, false, false], [true, false, false], [false, true, false], [false, false, true], [true, true, true]]
	for i in 5:
		var profile: Resource = lab.profiles[i]
		check([profile.s1_enabled, profile.s2_enabled, profile.s3_enabled] == expected[i], "Comparison toggles " + str(i))
		var button: Button = lab.buttons[i]
		check(button.material == null and not button.use_parent_material, "Text stays outside Shader " + str(i))
		for layer in ["Paper", "Ink", "Focus"]:
			check(button.get_node(layer).mouse_filter == Control.MOUSE_FILTER_IGNORE, "Visual ignores input: " + layer)
		var rect := button.get_rect()
		var seed: float = profile.seed
		button.mouse_entered.emit()
		button.button_down.emit()
		button.grab_focus()
		await process_frame
		check(button.get_rect() == rect and profile.seed == seed, "State retains layout and seed " + str(i))
		button.mouse_exited.emit()
		button.button_up.emit()
		var color_before: Color = button.get_node("Ink").modulate
		button.disabled = true
		await frames()
		check(button.get_node("Ink").modulate.a < color_before.a, "Disabled visual is distinct " + str(i))
		button.disabled = false
	# Remove pointer hover from captures and make keyboard navigation repeatable.
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(1250, 710)
	root.push_input(motion, true)
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	root.push_input(tab, true)
	await process_frame
	check(root.gui_get_focus_owner() != null, "Real Tab key retains native keyboard navigation")
	lab.buttons[4].grab_focus()
	var original_bounds: Rect2 = lab.buttons[4].get_rect()
	lab.profiles[4].line_width = 5.0
	lab.profiles[4].backing_width = 12.0
	await frames()
	check(lab.buttons[4].get_rect() == original_bounds, "Style parameters never alter native click area")
	lab.strength = 1
	await frames()
	if capture:
		var first := await snapshot("01_comparison_medium_1280x720")
		await frames()
		var second := root.get_texture().get_image()
		check(first.get_data() == second.get_data(), "Static texture and seed are pixel-stable across frames")
		for mode in [1, 2]:
			lab.background_mode = mode
			await snapshot("0%d_background_%s" % [mode + 1, "dark" if mode == 1 else "map"])
		lab.background_mode = 0
		for strength in [0, 2]:
			lab.strength = strength
			await snapshot("04_strength_%s" % ("light" if strength == 0 else "strong"))
		lab.strength = 1
		root.size = Vector2i(1920, 1080)
		var large := await snapshot("05_comparison_medium_1920x1080")
		check(large.get_size() == Vector2i(1920, 1080), "1920x1080 capture dimensions")
		root.size = Vector2i(1280, 720)
	root.remove_child(lab)
	lab.queue_free()
	var workshop := WorkshopScene.instantiate()
	root.add_child(workshop)
	await frames()
	var input_path := workshop.get_node("RitualPath")
	var authored: PackedVector2Array = input_path.path.duplicate()
	var points: PackedVector2Array = input_path.centerline()
	input_path.profile = input_path.profile.duplicate()
	input_path.profile.irregularity = 3.0
	input_path.profile.line_width = 8.0
	check(input_path.path == authored and input_path.centerline() == points, "Ritual centerline topology is unchanged")
	check(not input_path.allow_repeat and input_path.protect_centerline, "Accurate interaction lines protect continuous core")
	input_path.profile = preload("res://ui_module/shader_lab/presets/medium.tres")
	var narrow := workshop.get_node("NineSliceNarrow") as NinePatchRect
	var wide := workshop.get_node("NineSliceWide") as NinePatchRect
	check(narrow.texture == wide.texture and narrow.patch_margin_left == wide.patch_margin_left, "Nine-slice shares authored corner art")
	workshop.get_node("Hover").mouse_entered.emit()
	workshop.get_node("KeyboardFocus").grab_focus()
	await frames()
	check(workshop.get_node("KeyboardFocus/Focus").visible, "Keyboard focus has an independent ink indicator")
	if capture:
		await snapshot("06_states_and_nine_slice_1280x720")
		root.size = Vector2i(1920, 1080)
		await snapshot("07_states_and_nine_slice_1920x1080")
		root.size = Vector2i(1280, 720)
	root.remove_child(workshop)
	workshop.queue_free()
	var bg := ColorRect.new()
	bg.color = Color("#243e4a")
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	var cutout := Cutout.new()
	cutout.position = Vector2(100, 100)
	cutout.size = Vector2(128, 128)
	cutout.texture = synthetic
	cutout.profile = preload("res://ui_module/shader_lab/presets/medium.tres").duplicate()
	cutout.profile.backing_width = 6.0
	root.add_child(cutout)
	await frames()
	check(cutout.draw_padding >= 8.0 and cutout.size == Vector2(128, 128), "Backing has draw margin without changing control size")
	check(cutout.material.get_shader_parameter("field_padding") > 0, "Padded distance field is bound")
	var tiny := Cutout.new()
	tiny.size = Vector2.ONE
	tiny.texture = synthetic
	tiny.profile = cutout.profile.duplicate()
	tiny.profile.backing_width = 32.0
	root.add_child(tiny)
	check(tiny.material.get_shader_parameter("field_size").x < 180.0, "Tiny editor controls use bounded distance field allocations")
	root.remove_child(tiny)
	tiny.queue_free()
	if capture:
		var img := await snapshot("08_silhouette_probe")
		check(img.get_pixel(164, 164).r > 0.97 and img.get_pixel(164, 164).g > 0.97, "Transparent enclosed hole renders white backing")
		check(img.get_pixel(129, 160).r > 0.97 and img.get_pixel(129, 160).g > 0.97, "White contour is visibly outside subject")
		var outside := img.get_pixel(120, 160)
		check(outside.is_equal_approx(img.get_pixel(80, 160)), "No shadow or glow beyond backing")
		check(img.get_pixel(140, 140).g < 0.5, "Original art remains above backing")
		cutout.profile.s2_enabled = false
		await frames()
		img = root.get_texture().get_image()
		check(img.get_pixel(164, 164).is_equal_approx(img.get_pixel(80, 160)), "Backing toggle restores original transparent hole")
		# Touching-canvas input: margin is generated by geometry, never by the asset.
		var edge := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		edge.fill(Color("#9c4938"))
		cutout.texture = ImageTexture.create_from_image(edge)
		cutout.profile.s2_enabled = true
		await frames()
		img = root.get_texture().get_image()
		check(img.get_pixel(96, 160).r > 0.97, "Canvas-touching art backing extends outside control without clipping")
	var result := {"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(), "checks": checks, "failures": failures, "captures": captures, "capture": capture}
	var file := FileAccess.open("res://ui_module/shader_lab/tests/test_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("SHADER_LAB checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
