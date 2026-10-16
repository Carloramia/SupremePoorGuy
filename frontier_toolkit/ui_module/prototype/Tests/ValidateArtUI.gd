extends SceneTree
const Scene = preload("res://ui_module/prototype/Scenes/GameDemo.tscn")
const Rules = preload("res://ui_module/prototype/Scripts/Ritual/RuneRules.gd")
var checks := 0
var failures := 0
var app

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("ART UI FAILED: "+label)

func settled() -> void:
	await create_timer(0.4).timeout
	for i in 3:
		await process_frame

func _run() -> void:
	root.size = Vector2i(1280,720)
	app = Scene.instantiate()
	app.state.save_path = "user://native_art_test_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app._show("world")
	app._open_ritual()
	check(app.board_motion.busy,"opening animation starts")
	check(app.board_motion.shield.visible,"input shield active during animation")
	check(app.view.summon_book.disabled,"map blocked during modal")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_ESCAPE
	Input.parse_input_event(key)
	await process_frame
	check(app.modal_stack.size()==1,"escape during opening does not close")
	await settled()
	check(not app.board_motion.busy and not app.board_motion.shield.visible,"opening releases shield")
	check(app.board_motion.motion.position.is_zero_approx(),"board settles at authored position")
	check(app.board_motion.motion.scale==Vector2.ONE,"animation never scales layout")
	var before: Rect2 = app.board.get_global_rect()
	app._term("测试说明","不改动法阵与库存。")
	app._close_modal()
	await process_frame
	await process_frame
	check(app.board.get_global_rect()==before,"nested return preserves board rectangle")
	var surface: Control = app.overlay.get_node("BoardMotion/MotionRoot/Margin/BoardSurface")
	check(surface.get_node("Paper").texture != surface.get_node("WoodFrame").texture,"paper and wood are separate textures")
	check(surface.get_node("Clip").texture != surface.get_node("LeftRivet").texture,"clip and rivet are separate assets")
	check(surface.get_node("WoodFrame").draw_center==false,"frame has open center")
	for part in surface.get_children():
		check(part.mouse_filter==Control.MOUSE_FILTER_IGNORE,"decor does not intercept "+part.name)
	var btn_style: StyleBoxTexture = app.close_button.get_theme_stylebox("normal")
	check(btn_style.texture.resource_path.ends_with("button_paper_v1.png"),"button art is separate from text")
	for style_name in ["hover", "pressed", "disabled"]:
		var state_style: StyleBoxTexture = app.close_button.get_theme_stylebox(style_name)
		check(state_style.texture == btn_style.texture and state_style.region_rect == btn_style.region_rect,"button state registration stable: "+style_name)
	var frame_image: Image = surface.get_node("WoodFrame").texture.get_image()
	check(frame_image.get_pixel(frame_image.get_width()/2,frame_image.get_height()/2).a == 0,"frame center is truly transparent")
	var portrait = preload("res://ui_module/prototype/Scenes/UI/Components/MonsterPortrait.tscn").instantiate()
	root.add_child(portrait)
	for form_name in ["人形", "兽形", "蛇形"]:
		portrait.form = form_name
		portrait._sync_reference()
		check(portrait.get_node("ReferenceArt").visible and portrait.get_node("ReferenceArt").texture != null,"form illustration available: "+form_name)
		check(portrait.get_node("ReferenceCaption").visible,"reference disclaimer visible: "+form_name)
	var custom_image := Image.create(4,4,false,Image.FORMAT_RGBA8)
	custom_image.fill(Color.CORAL)
	var custom_texture := ImageTexture.create_from_image(custom_image)
	portrait.get_node("Artwork").texture = custom_texture
	portrait.form = "兽形"
	portrait._sync_reference()
	check(not portrait.get_node("ReferenceArt").visible and not portrait.get_node("ReferenceCaption").visible,"explicit artwork hides temporary example")
	check(portrait.get_node("Artwork").texture == custom_texture,"form update preserves explicit artwork")
	portrait.get_node("Artwork").texture = null
	portrait.use_reference_examples = false
	portrait._sync_reference()
	check(not portrait.get_node("ReferenceArt").visible,"reference switch restores vector fallback")
	portrait.queue_free()
	var cash: int = app.state.data.magic
	app._close_modal()
	check(app.modal_stack.is_empty() and app.overlay.visible and app.board_motion.busy,"exit retains visual board while closing")
	await settled()
	check(not app.overlay.visible and not app.view.summon_book.disabled,"closing hides board and unblocks map")
	check(app.state.data.magic==cash,"visual close does not change cost")
	app._warehouse()
	await settled()
	app._close_modal()
	app._open_ritual()
	await settled()
	check(app.overlay.visible and not app.board_motion.busy,"reopening cancels old exit safely")
	check(app.modal_stack.size()==1,"rapid reopen has correct stack")
	check(app.board_motion.motion.position.is_zero_approx(),"rapid reopen returns to zero")
	app._close_all()
	check(not app.overlay.visible and not app.board_motion.busy,"business route can close instantly")
	app.animate_panels = false
	app.board_motion.enabled = false
	app._warehouse()
	check(app.overlay.visible and not app.board_motion.busy,"reduced motion opens immediately")
	app._close_modal()
	check(not app.overlay.visible,"reduced motion closes immediately")
	app.animate_panels = true
	app.board_motion.enabled = true
	app._open_ritual()
	await settled()
	for c in Rules.RUNES[0].cells:
		app.rules.extend(c)
	app.rules.commit()
	app._refresh_ritual()
	app._summon()
	check(app.state.data.magic==296 and app.state.data.pending.size()==3,"animated route summons once")
	app.view.skip_eruption()
	await settled()
	var results: Control = app.modal_box.get_child(0)
	print("ART_RESULT_RECTS scroll=",app.modal_scroll.get_global_rect()," store=",results.get_node("%StoreAll").get_global_rect()," page=",results.get_global_rect())
	check(app.modal_scroll.get_global_rect().encloses(results.get_node("%StoreAll").get_global_rect()),"results primary action initially visible")
	var first_id: String = app.state.data.pending[0]
	app._detail(first_id)
	app._close_modal()
	check(app.state.data.pending.size()==3,"closing nested detail does not store batch")
	app._close_modal()
	check(app.state.data.pending.is_empty() and app.state.monsters("warehouse").size()==3,"animated exit stores same instances once")
	await settled()
	app.queue_free()
	await process_frame
	print("ART_UI_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
