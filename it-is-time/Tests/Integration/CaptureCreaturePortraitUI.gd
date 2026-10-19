extends SceneTree
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const OUTPUT := "D:/GameJamWorkspace/Reports/CreatureHeadPortraits_2026-10-18"
var failed := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)

func wait_portrait(ui: Node) -> void:
	for frame: int in 600:
		await process_frame
		if is_instance_valid(ui._portrait_renderer) and not ui._portrait_renderer._busy and ui._portrait_renderer._queue.is_empty(): break
	await RenderingServer.frame_post_draw

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	root.size = Vector2i(1280,800)
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.use_delivery_map = false
	app.save_path = OUTPUT+"/ui_capture_"+str(Time.get_ticks_usec())+".json"
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	app.start_new_game()
	for tick: int in 600:
		if app.phase=="world": break
		await physics_frame
	check(app.phase=="world","Application world is ready")
	app.ui._close_all()
	for id: String in FACTORY.SUMMON_POOL:
		var record := FACTORY.template(id)
		record.merge({"id":"portrait_"+id,"position":"team" if id=="wolf" else "warehouse","traits":[]},true)
		app.session.data.monsters.append(record)
	check(app.session.save(),"Isolated test save accepts portrait-enabled creatures")
	app.ui._warehouse("warehouse")
	await wait_portrait(app.ui)
	var portrait: Control = app.ui.warehouse_page.get_node("%DetailBody").find_child("Portrait",true,false)
	check(portrait!=null and not portrait.use_reference_examples,"Warehouse details use the real saved creature")
	check(portrait.get_node("Artwork").texture != app.ui._portrait_renderer._placeholder,"Warehouse has finished rendering its portrait")
	check(root.get_texture().get_image().save_png(OUTPUT+"/warehouse.png")==OK,"Save actual warehouse interface")
	app.ui._close_all()
	app.ui._warehouse("team")
	await wait_portrait(app.ui)
	portrait = app.ui.warehouse_page.get_node("%DetailBody").find_child("Portrait",true,false)
	var wolf_texture: Texture2D = portrait.get_node("Artwork").texture
	check(wolf_texture!=app.ui._portrait_renderer._placeholder,"Deployed member details use the Wolf screenshot")
	check(root.get_texture().get_image().save_png(OUTPUT+"/party.png")==OK,"Save deployed-member interface")
	var card_host := VBoxContainer.new()
	app.ui.add_child(card_host)
	app.ui._monster_card(card_host,app.session.monster_by_id("portrait_wolf"),true)
	var card := card_host.get_child(0)
	check(card.get_node("%Portrait/Artwork").texture==wolf_texture,"Summon result cards reuse the same real portrait cache")
	card_host.free()
	app.ui._close_all()
	app.free()
	await process_frame
	if not failed: print("CREATURE_PORTRAIT_UI_VALIDATION_PASSED")
	quit(1 if failed else 0)
