extends SceneTree
const Preview = preload("res://TA/Scenes/NativeSkinPreview.tscn")
const Comparison = preload("res://TA/Scenes/ShaderComparison.tscn")
const Field = preload("res://TA/SilhouetteField.gd")
const Binding = preload("res://TA/ShaderSkinBinding.gd")
const Library = preload("res://TA/PresetLibrary.gd")
const SlotsScene = preload("res://Scenes/UI/Components/UISkinSlots.tscn")
var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var capture := false
var clicks := 0
var capture_root := "res://Tests/TA/screenshots/"

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error("TA SHADERS: " + label)

func settle() -> void:
	for i in 5:
		await process_frame
	if capture:
		await RenderingServer.frame_post_draw

func snapshot(name_value: String) -> Image:
	await settle()
	var image := root.get_texture().get_image()
	check(image != null and not image.is_empty(), "Render " + name_value)
	check(image.save_png(capture_root + name_value + ".png") == OK, "Capture " + name_value)
	captures.append(name_value + ".png")
	return image

func geometry(node: Node) -> Dictionary:
	var result := {}
	for item in node.find_children("*", "Control", true, false):
		# These are visual layers supplied by the existing contract/addon.
		if item.name in ["Surface", "Outline", "TAFocus", "TASurface", "TAOutline"]:
			continue
		var value := {"rect": item.get_global_rect(), "minimum": item.get_combined_minimum_size()}
		if item is Label or item is Button:
			value["text"] = item.text
			value["font"] = item.get_theme_font("font")
			value["font_size"] = item.get_theme_font_size("font_size")
		result[str(node.get_path_to(item))] = value
	return result

func mouse_at(position_value: Vector2, pressed: bool, send_click := true) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position_value
	root.push_input(motion, true)
	if send_click:
		var event := InputEventMouseButton.new()
		event.position = position_value
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame

func _run() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_root))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Tests/.runtime"))
	root.size = Vector2i(1280, 720)
	var preview := Preview.instantiate()
	root.add_child(preview)
	await settle()
	preview._apply(false)
	await settle()
	var short: Button = preview.get_node("%ShortButton")
	var long: Button = preview.get_node("%LongButton")
	var paper: Control = preview.get_node("%PreviewPaper")
	var book: Button = preview.get_node("%Book")
	var normal := short.get_theme_stylebox("normal")
	var focus_style := short.get_theme_stylebox("focus")
	var original_texture: Texture2D = paper.get_node("Paper").texture
	var original_region: Rect2 = paper.get_node("Paper").region_rect
	for extent in [Vector2i(1120, 680), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = extent
		await settle()
		preview._apply(false)
		await settle()
		var before := geometry(preview)
		if capture:
			await snapshot("native_before_%d" % extent.x)
		preview.select_preset(1, 4)
		await settle()
		check(geometry(preview) == before, "Every original Control rect/minimum/font/text remains unchanged at %d" % extent.x)
		check(short.material == null and long.material == null and paper.material == null, "Native text parents have no material at %d" % extent.x)
		var surface: NinePatchRect = short.get_node("VisualSkin/Surface")
		var outline: NinePatchRect = short.get_node("VisualSkin/Outline")
		check(surface.mouse_filter == Control.MOUSE_FILTER_IGNORE and outline.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Visual layers never intercept mouse at %d" % extent.x)
		check(surface.material != preview.preview_preset.surface_material, "Per-component material copy at %d" % extent.x)
		check(surface.material != long.get_node("VisualSkin/Surface").material, "Wide and narrow materials are isolated at %d" % extent.x)
		var rendered: NinePatchRect = short.get_node("TAVisuals/TASurface")
		check(rendered.material.get_shader_parameter("ui_size_px") == rendered.size, "Actual rendered pixel extent forwarded at %d" % extent.x)
		check(rendered.global_position.is_equal_approx(short.global_position), "Rendered layer follows native button transform at %d" % extent.x)
		check(rendered.size == short.size and rendered.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Rendered layer matches actual native click extent at %d" % extent.x)
		check(outline.material.get_shader_parameter("ui_seed") == 42, "Stable seed forwarded at %d" % extent.x)
		check(book.get_node("Icon").material.get_shader_parameter("ui_prepared") == true, "Existing native book slot has prepared complete silhouette at %d" % extent.x)
		check(book.get_node("Caption").material == null, "Book caption is independent at %d" % extent.x)
		var panel := paper.get_theme_stylebox("panel") as StyleBoxFlat
		check(panel.shadow_size == 0 and not panel.draw_center, "Legacy panel shadow/fill removed only while active at %d" % extent.x)
		if capture:
			await snapshot("native_combined_%d" % extent.x)
		preview._apply(false)
		await settle()
		check(short.get_theme_stylebox("normal") == normal and short.get_theme_stylebox("focus") == focus_style, "Normal and keyboard focus restore exactly at %d" % extent.x)
		check(paper.get_node("Paper").texture == original_texture and paper.get_node("Paper").region_rect == original_region, "Paper texture/atlas crop restore at %d" % extent.x)
		check(book.get_node("Icon").material == null, "Cutout material restores at %d" % extent.x)
	root.size = Vector2i(1280, 720)
	preview.select_preset(1, 4)
	await settle()
	short.pressed.connect(func(): clicks += 1)
	var position_value := short.get_global_rect().get_center()
	await mouse_at(position_value, true)
	await mouse_at(position_value, false)
	check(clicks == 1, "Real GUI input reaches skinned native button")
	var seed = short.get_node("VisualSkin/Outline").material.get_shader_parameter("ui_seed")
	short.disabled = true
	await mouse_at(position_value, true)
	await mouse_at(position_value, false)
	check(clicks == 1, "Disabled native button rejects real GUI input")
	await settle()
	check(short.get_node("VisualSkin/Surface").material.get_shader_parameter("ui_state_tint").a < 1.0, "Disabled surface state remains distinct")
	short.disabled = false
	short.grab_focus()
	await settle()
	check(short.get_node("TAVisuals/TAFocus").visible, "Keyboard focus uses same authored ink")
	check(short.get_node("VisualSkin/Outline").material.get_shader_parameter("ui_seed") == seed, "Hover/press/disable/focus never reseed")
	var component_slots := short.get_node("VisualSkin")
	component_slots.enabled = false
	await settle()
	check(short.get_node_or_null("TAVisuals") == null and short.get_theme_stylebox("normal") == normal, "Per-component Enabled=false restores adapter layers and upstream styles")
	component_slots.enabled = true
	await settle()
	check(short.get_node("TAVisuals/TASurface").global_position.is_equal_approx(short.global_position), "Per-component re-enable restores correct drawing coordinates")
	var local := Library.variant(0, 2)
	local.stable_seed = 101
	component_slots.local_preset = local
	await settle()
	check(short.get_node("TAVisuals/TAOutline").material.get_shader_parameter("ui_seed") == 101, "Local Preset controls the individual component seed")
	check(short.get_node("TAVisuals/TAFocus").material.get_shader_parameter("ui_seed") == 101, "Local Preset also updates keyboard ink seed")
	check(long.get_node("TAVisuals/TAOutline").material.get_shader_parameter("ui_seed") == 42, "Local Preset does not mutate the shared sibling")
	for i in 4:
		preview.select_preset(i % 3, 4)
		preview._apply(false)
	preview.select_preset(1, 4)
	await settle()
	check(short.get_theme_stylebox("normal") is StyleBoxEmpty, "Rapid apply/restore leaves one valid skin")
	preview._apply(false)
	await settle()
	check(short.get_theme_stylebox("normal") == normal, "Rapid apply/restore still restores original")
	root.remove_child(preview)
	preview.queue_free()
	var comparison := Comparison.instantiate()
	root.add_child(comparison)
	await settle()
	check(comparison.specimens.size() == 5, "Five comparison groups share the actual upstream components")
	for i in 5:
		var col: Control = comparison.specimens[i]
		check(col.get_node("Action").get_script() == null, "Comparison uses native ActionButton instance " + str(i))
		check(col.get_node("Page/Body").material == null, "Comparison body stays clear " + str(i))
		check(col.get_node("Portrait/Artwork").texture == preload("res://TA/Assets/monster.svg"), "Same unbacked monster art " + str(i))
		check(comparison.presets[i].cutout_material.get_shader_parameter("backing_enabled") == (i in [2, 4]), "S2 switch " + str(i))
	if capture:
		await mouse_at(Vector2(1270, 710), false, false)
		var first := await snapshot("comparison_medium_1280x720")
		await settle()
		check(first.get_data() == root.get_texture().get_image().get_data(), "Static frame is byte-for-byte stable")
		for bg in [1, 2]:
			comparison.background_mode = bg
			await snapshot("comparison_%s" % ("dark" if bg == 1 else "map"))
		comparison.background_mode = 0
		for strength in [0, 2]:
			comparison.strength = strength
			await snapshot("comparison_%s" % ("light" if strength == 0 else "strong"))
		comparison.strength = 1
		root.size = Vector2i(1920, 1080)
		var large := await snapshot("comparison_medium_1920x1080")
		check(large.get_size() == Vector2i(1920, 1080), "1080p image dimensions")
		root.size = Vector2i(1280, 720)
		comparison.buttons[2].toggle_mode = true
		comparison.buttons[2].button_pressed = true
		comparison.buttons[4].grab_focus()
		await mouse_at(comparison.buttons[1].get_global_rect().get_center(), false, false)
		await snapshot("comparison_native_states")
	root.remove_child(comparison)
	comparison.queue_free()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	await _probe_cutout()
	var result := {"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(), "checks": checks, "failures": failures, "capture": capture, "screenshots": captures}
	var file := FileAccess.open("res://Tests/.runtime/ta_shader_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("TA_SHADER_VALIDATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _probe_cutout() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#243e4a")
	bg.size = Vector2(1280, 720)
	root.add_child(bg)
	var host := Control.new()
	host.position = Vector2(100, 100)
	host.size = Vector2(128, 128)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(host)
	var art := TextureRect.new()
	art.name = "Artwork"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.size = host.size
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var source := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	source.fill(Color.TRANSPARENT)
	for y in range(4, 12):
		for x in range(4, 12):
			source.set_pixel(x, y, Color("#9c4938"))
	for y in range(6, 10):
		for x in range(6, 10):
			source.set_pixel(x, y, Color.TRANSPARENT)
	art.texture = ImageTexture.create_from_image(source)
	host.add_child(art)
	var slots := SlotsScene.instantiate()
	slots.surface_target = NodePath("__none__")
	slots.illustration_targets.assign([NodePath("Artwork")])
	host.add_child(slots)
	var binder := Binding.new()
	host.add_child(binder)
	binder.rescan()
	binder.apply_preset(Library.variant())
	await settle()
	check(art.size == Vector2(128, 128) and host.size == Vector2(128, 128), "S2 leaves Control and click extents intact")
	var field := Field.build(art.texture, 8)
	var map := (field.texture as Texture2D).get_image()
	check(is_zero_approx(map.get_pixel(16, 16).r), "Whole silhouette fills enclosed alpha holes")
	check(absf(map.get_pixel(9, 9).r - (sqrt(18.0) - 0.5)) < 0.001, "Exact Euclidean distance at corners")
	check(Field.build(art.texture, 8).texture == field.texture, "Mask construction is cached")
	if capture:
		var image := await snapshot("cutout_alpha_probe")
		check(image.get_pixel(164, 164).r > 0.97 and image.get_pixel(164, 164).g > 0.97, "Transparent interior has white paper backing")
		check(image.get_pixel(129, 160).r > 0.97 and image.get_pixel(129, 160).g > 0.97, "White paper extends beyond complete subject")
		check(image.get_pixel(120, 160).is_equal_approx(image.get_pixel(80, 160)), "No shadow or halo beyond white backing")
		check(image.get_pixel(140, 140).g < 0.5, "Subject ink/fill remains intact")
		source.set_pixel(0, 7, Color("#9c4938"))
		art.texture = ImageTexture.create_from_image(source)
		await settle()
		image = root.get_texture().get_image()
		check(image.get_pixel(96, 160).r > 0.97, "Canvas-edge art receives unclipped vertex-expanded backing")
		binder.restore()
		await settle()
		image = root.get_texture().get_image()
		check(image.get_pixel(164, 164).is_equal_approx(image.get_pixel(80, 160)), "Restore removes backing and returns exact original alpha")
