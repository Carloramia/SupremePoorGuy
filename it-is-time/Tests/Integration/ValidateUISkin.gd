extends SceneTree
const BINDING = preload("res://Modules/PaperUI/TA/ShaderSkinBinding.gd")
const PRESET = preload("res://Modules/PaperUI/TA/Presets/medium.tres")
const ACTION = preload("res://Modules/PaperUI/Scenes/UI/Components/ActionButton.tscn")
const FACTORY = preload("res://Tests/Integration/ApplicationFixtures.gd")
var output := "D:/GameJamWorkspace/Reports/UISkin_2026-10-17"
var failed := false
var checks := 0
var capture_enabled := false
var app: Node
var differences: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("UI_SKIN_CHECK " + message)

func settle() -> void:
	for frame: int in 8: await process_frame

func snapshot(node: Node, base: Node, result: Dictionary) -> void:
	if node is SubViewport or node is Window or node.has_meta(&"ta_visual") or node.get_script() == BINDING.SlotsScript: return
	# Legacy visual layers are hidden when their new copies are drawn; still compare their geometry.
	if node is Control:
		result[str(base.get_path_to(node))] = {"rect":node.get_global_rect(),"minimum":node.get_combined_minimum_size(),"text":node.get("text"),"font_size":node.get_theme_font_size("font_size")}
	for child: Node in node.get_children(): snapshot(child,base,result)

func capture(label: String) -> void:
	if not capture_enabled: return
	RenderingServer.force_draw()
	var picture := root.get_texture().get_image()
	check(picture != null and not picture.is_empty(),"Actual GPU capture "+label)
	if picture != null: check(picture.save_png(output+"/"+label+".png") == OK,"Save "+label)

func compare(label: String) -> void:
	app.ui.set_visual_preset(null)
	await settle()
	var before := {}
	snapshot(app.ui,app.ui,before)
	await capture(label+"_before")
	var data := JSON.stringify(app.session.data)
	app.ui.set_visual_preset(PRESET)
	await settle()
	var after := {}
	snapshot(app.ui,app.ui,after)
	for path: String in before:
		check(after.has(path),label+" preserved control "+path)
		if not after.has(path): continue
		var a: Dictionary = before[path]
		var b: Dictionary = after[path]
		var same: bool = a.rect.is_equal_approx(b.rect) and a.minimum.is_equal_approx(b.minimum) and a.text == b.text and a.font_size == b.font_size
		if not same: differences.append({"page":label,"control":path,"before":str(a),"after":str(b)})
		check(same,label+" preserved geometry/text "+path)
	check(JSON.stringify(app.session.data) == data,label+" does not change session data")
	await capture(label+"_after")
	print("UI_SKIN_PAGE ",label," controls=",before.size())

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point; motion.global_position = point
	root.push_input(motion,true)
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point; event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		root.push_input(event,true)
		await process_frame

func lifecycle() -> void:
	var host := Control.new()
	host.position = Vector2(-1000,-1000)
	root.add_child(host)
	var button := ACTION.instantiate()
	host.add_child(button)
	var slots: Node = button.get_node("VisualSkin")
	var local := preload("res://Modules/PaperUI/Assets/UI/PaperRelief/DefaultSkin.tres").duplicate()
	var shared: Resource = slots.shared_preset
	slots.local_preset = local
	slots.enabled = false
	var binder := BINDING.new()
	binder.initial_preset = PRESET
	host.add_child(binder)
	await settle()
	check(slots.local_preset == local and not slots.enabled,"Preserve authored local preset and disabled state")
	var option := OptionButton.new()
	option.add_item("Resolution")
	var popup_style := option.get_popup().get_theme_stylebox("panel")
	var popup_font := option.get_popup().get_theme_color("font_color")
	host.add_child(option)
	await settle()
	check(option.has_node("VisualSkin"),"New controls receive a skin after creation")
	check(option.get_popup().get_theme_stylebox("panel") is StyleBoxTexture,"Native option popup uses new paper")
	check(option.get_popup().get_theme_color("font_color").get_luminance() < 0.2,"Native popup text contrasts with light paper")
	check(option.get_theme_color("font_hover_pressed_color").get_luminance() < 0.2,"Hovered pressed native button text contrasts with light paper")
	option.get_node("VisualSkin").enabled = false
	await settle()
	check(option.get_popup().get_theme_stylebox("panel") == popup_style,"Disabling one component restores its native popup")
	check(option.get_popup().get_theme_color("font_color") == popup_font,"Restore native popup text color")
	option.get_node("VisualSkin").enabled = true
	await settle()
	check(option.get_popup().get_theme_stylebox("panel") is StyleBoxTexture,"Re-enabling one component restores its new popup")
	var primary := ACTION.instantiate()
	primary.theme_type_variation = &"PrimaryButton"
	host.add_child(primary)
	await settle()
	var primary_tint: Color = primary.get_node("TAVisuals/TASurface").material.get_shader_parameter("ui_state_tint")
	check(primary_tint.get_luminance() < 0.5 and primary.get_theme_color("font_color").get_luminance() > 0.5,"Primary action preserves light text on dark paper")
	primary.queue_free()
	await settle()
	for iteration: int in 3:
		binder.restore()
		await settle()
		check(slots.local_preset == local and slots.shared_preset == shared and not slots.enabled,"Restore exact slot state")
		check(not option.has_node("TAVisuals"),"Remove generated visuals on restore")
		check(option.get_popup().get_theme_stylebox("panel") == popup_style,"Restore native popup style")
		binder.apply_preset(PRESET)
		await settle()
		check(option.get_node("TAVisuals").get_child_count() == 3,"No duplicate surface/outline/focus layers")
	option.queue_free()
	await settle()
	check(binder.slots_nodes.size() == 1,"Prune freed dynamic controls")
	binder.restore()
	host.queue_free()
	await settle()

func run() -> void:
	var binding_script: Script = load("res://Modules/PaperUI/TA/ShaderSkinBinding.gd")
	if not binding_script.can_instantiate():
		push_error("UI skin binding did not compile")
		quit(1)
		return
	capture_enabled = "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	DirAccess.make_dir_recursive_absolute(output)
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	root.size = Vector2i(1280,720)
	for path: String in ["res://Modules/PaperUI/TA/Scenes/NativeSkinPreview.tscn","res://Modules/PaperUI/TA/Scenes/ShaderComparison.tscn"]:
		var preview: Control = load(path).instantiate()
		root.add_child(preview)
		await settle()
		check(preview.is_inside_tree(),"Standalone preview runs: "+path)
		preview.queue_free()
		await settle()
	await lifecycle()
	app = preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.use_delivery_map = false
	app.ui_skin_preset = null
	app.save_path = output+"/session_"+str(Time.get_ticks_usec())+".json"
	app.display_settings_path = output+"/display_test.cfg"
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	await settle()
	await compare("01_main")
	await click(app.ui.main_menu.get_node("%Start"))
	check(app.ui.overlay.visible,"Actual mouse click still opens new-game confirmation")
	await settle()
	await compare("02_confirmation")
	app.ui._close_all()
	app.start_new_game()
	for tick: int in 600:
		if app.phase == "world": break
		await physics_frame
	check(app.phase == "world","Normal new-game flow reaches world")
	FACTORY.add_human(app.session)
	app.session.data.monsters[0].position = "warehouse"
	check(app.session.save(),"Save isolated populated warehouse fixture")
	await settle()
	await compare("03_world")
	app.ui._warehouse()
	await settle()
	if DisplayServer.get_name() != "headless":
		for frame: int in 120:
			if not is_instance_valid(app.ui._portrait_renderer) or not app.ui._portrait_renderer._busy: break
			await process_frame
	var portrait: Control = app.ui.warehouse_page.get_node("%DetailBody").find_child("Portrait",true,false)
	check(portrait != null,"Populated warehouse retains the creature portrait")
	var artwork: TextureRect = portrait.get_node("Artwork") if portrait != null else null
	var portrait_texture: Texture2D = artwork.texture if artwork != null else null
	await compare("04_warehouse")
	if artwork != null:
		check(artwork.texture == portrait_texture,"Skin does not replace real creature artwork")
		check(artwork.texture.get_image().detect_alpha() == Image.ALPHA_NONE,"Portrait keeps opaque white background")
		check(artwork.material.get_shader_parameter("ui_prepared") == false,"No cutout mask is invented for an opaque portrait")
	app.ui._close_all()
	app.ui._open_ritual()
	await settle()
	await compare("05_ritual")
	app.ui._close_all()
	app.ui._tasks()
	await settle()
	await compare("06_tasks")
	app.ui._close_all()
	app.ui._settings()
	await settle()
	await compare("07_settings")
	var options: Array[Node] = app.ui.find_children("Resolution","OptionButton",true,false)
	check(options.size() == 1,"Resolution control is retained")
	if not options.is_empty():
		await click(options[0])
		await settle()
		check(options[0].get_popup().visible,"Native dropdown responds to mouse")
		await capture("07_settings_popup")
		options[0].get_popup().hide()
	app.ui._close_all()
	for size: Vector2i in [Vector2i(1120,680),Vector2i(1920,1080)]:
		root.size = size
		root.content_scale_size = size
		app.ui._warehouse()
		await settle()
		await compare("08_warehouse_"+str(size.x))
		app.ui._close_all()
	var binder: Node = app.ui.skin_binding
	var started := Time.get_ticks_usec()
	for iteration: int in 100: binder._process(0.0)
	var idle_usec := float(Time.get_ticks_usec()-started)/100.0
	var record := {"checks":checks,"failed":failed,"renderer":RenderingServer.get_current_rendering_method(),"geometry_differences":differences,"warm_adapter_update_usec":idle_usec}
	var file := FileAccess.open(output+"/"+("render" if capture_enabled else "headless")+"_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(record,"\t"))
	file.close()
	app.queue_free()
	await settle()
	print("UI_SKIN_VALIDATION_", "FAILED" if failed else "PASSED", " checks=",checks," warm_update_usec=",idle_usec)
	quit(1 if failed else 0)
