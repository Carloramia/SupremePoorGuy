extends SceneTree
const Demo = preload("res://ui_module/demo/UIWorldMapDemo.tscn")
const Rules = preload("res://ui_module/prototype/Scripts/Ritual/RuneRules.gd")
var checks := 0
var failures := 0
var world: WorldMapController
var bridge: WorldMapUIBridge
var app: GameUI
var screenshots := false

func _initialize() -> void:
	call_deferred("run")
	create_timer(60).timeout.connect(func():
		push_error("UI module test timed out")
		quit(1))

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("UI MODULE FAILED: "+description)

func frames(count: int = 4) -> void:
	for i in count:
		await process_frame

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion,true)
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
	await frames(4)

func button(control: Control) -> void:
	await click(control.get_global_rect().get_center())

func capture(name: String) -> void:
	if screenshots:
		await frames(8)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://ui_module/tests/screenshots/"+name+".png")

func run() -> void:
	screenshots = "--capture" in OS.get_cmdline_user_args()
	root.size = Vector2i(1280,800)
	world = Demo.instantiate()
	world.auto_load = false
	world.save_path = "res://.tools/ui_module_world_test_save.json"
	bridge = world.get_node("GameUILayer")
	bridge.session_save_path = "user://native_ui_host_test_%d.json" % Time.get_ticks_usec()
	root.add_child(world)
	await world.initialized
	await frames(8)
	app = bridge.app
	check(app != null and app.route == "world","integrated UI starts above real map")
	check(app.state.save_path == bridge.session_save_path,"one isolated UI session")
	app.animate_panels = false
	app.board_motion.enabled = false
	check(not world.ui.get_node("Root/MapHeader").visible,"legacy HUD yields to module")
	check(not app.view.markers[0].visible and app.view.hosted_world,"placeholder map markers removed")
	check(not world.paused and app.view.mouse_filter == Control.MOUSE_FILTER_IGNORE,"map exposed through transparent UI")
	await capture("01_world")
	# Real GUI input must pass through the transparent central area into navigation.
	var target := Vector2(200,490)
	var screen_point: Vector2 = world.get_viewport().get_canvas_transform() * world.to_global(target)
	await click(screen_point)
	check(world.player.has_target,"click through UI starts real map movement")
	world.cancel_movement("fixture")
	var hex := HexMath.world_to_axial(world.to_local(world.player.global_position),world.definition.hex_size)
	world.grid.cells[hex].terrain = &"forest"
	app.view.summon_book.grab_focus()
	await button(app.view.summon_book)
	check(app.overlay.visible and app.modal_stack.size() == 1,"real book button opens ritual")
	check(world.paused and world.player.map_paused and world.camera.map_paused,"modal freezes map and camera")
	check(app.location == "forest" and app.context.hex == [hex.x,hex.y],"summon context follows actual player cell")
	check(not app.open_warehouse(),"duplicate system entry rejected while modal open")
	var position := world.player.global_position
	await click(Vector2(20,600))
	await frames(6)
	check(world.player.global_position == position and not world.set_move_target(target),"modal input cannot command background movement")
	for cell in Rules.RUNES[0].cells:
		await click(app.board.get_global_transform() * app.board.point(cell))
	check(app.rules.draft.size() == 4,"real board clicks create connected rune")
	app._commit_rune()
	check(app.rules.placed.size() == 1 and not app.summon_button.disabled,"rune enables summon")
	await capture("02_ritual")
	await button(app.summon_button)
	check(app.route == "eruption" and world.paused,"summon holds map pause throughout eruption")
	check(app.state.data.magic == 296 and app.state.data.pending.size() == 3,"one debit and three saved instances")
	check(app.state.data.monsters[0].source_context.hex == [hex.x,hex.y],"actual source context persisted with results")
	app.view.skip_eruption()
	await frames()
	check(app.overlay.visible and app.route == "world" and world.paused,"skipping opens results without resuming map")
	check(app.state.data.magic == 296 and app.state.data.monsters.size() == 3,"skip neither recharges nor regenerates")
	await capture("03_results")
	await button(app.close_button)
	check(app.state.data.pending.is_empty() and app.state.monsters("warehouse").size() == 3,"closing results stores same instances")
	check(not world.paused and app.view.summon_book.has_focus(),"close resumes map and restores book focus")
	await button(app.base.get_node("%Warehouse"))
	await frames()
	var page := app.modal_box.get_child(0)
	await button(page.get_node("%Team"))
	check(app.modal_box.get_child(0).get_node("%Empty").visible,"warehouse tabs switch without losing panel")
	page = app.modal_box.get_child(0)
	await button(page.get_node("%All"))
	page = app.modal_box.get_child(0)
	check(page.get_node("%Cards").get_child_count() == 3,"all tab retains unique monsters")
	var card := page.get_node("%Cards").get_child(0)
	await button(card.get_node("%Move"))
	check(app.state.monsters("team").size() == 1 and app.state.monsters("warehouse").size() == 2,"party and warehouse share one state")
	page = app.modal_box.get_child(0)
	card = page.get_node("%Cards").get_child(0)
	await button(card.get_node("%Detail"))
	await frames()
	page = app.modal_box.get_child(0)
	page.get_node("%NameInput").text = "林间旅伴"
	await button(page.get_node("%Save"))
	check(app.state.data.monsters[0].name == "林间旅伴","detail rename persists on same monster ID")
	app._term("攻击","属性说明")
	check(app.modal_stack.size() == 3,"warehouse/detail/description stack")
	app._close_modal()
	check(app.modal_stack.size() == 2 and world.paused,"one back closes only upper layer")
	app._close_all()
	check(not world.paused,"close all resumes travel")
	app.open_warehouse()
	await capture("04_warehouse")
	app._close_all()
	app.open_summon(bridge.current_context())
	for resolution in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(1024,768),Vector2i(1920,800)]:
		root.size = resolution
		await frames(8)
		var rect: Rect2 = app.board.get_global_rect()
		check(absf(rect.size.x-rect.size.y)<1 and app.modal_scroll.get_global_rect().encloses(rect),"hosted board fits "+str(resolution))
		check(app.overlay.get_global_rect().encloses(app.summon_button.get_global_rect()),"hosted summon button fits "+str(resolution))
	root.size = Vector2i(1280,800)
	await frames(8)
	app._close_all()
	# Exit animation must finish before pause is released.
	app.animate_panels = true
	app.board_motion.enabled = true
	app.open_warehouse()
	check(app.board_motion.busy and world.paused,"opening animation blocks background")
	await create_timer(0.4).timeout
	app._close_modal()
	check(world.paused and app.overlay.visible,"closing animation retains pause")
	await create_timer(0.4).timeout
	check(not world.paused and not app.overlay.visible,"completed exit releases pause")
	app.animate_panels = false
	app.board_motion.enabled = false
	# Existing town and 2.5D integration keep ownership of their own pause.
	var town := world.get_location(&"town")
	check(world.interaction.begin(town),"existing location interaction still opens")
	check(app.external_blocked and not app.open_summon(),"UI cannot steal location interaction")
	world.resolve_location_interaction(&"town",{"success":true,"complete_location":false})
	check(not app.external_blocked and not world.paused,"location return re-enables UI")
	check(world.interaction.begin(town),"town opens repeatedly")
	world.interaction.request_scenario()
	var scenario = world.get_node("ScenarioOverlay")
	await frames(8)
	check(scenario.overlay != null and app.external_blocked,"existing 2.5D overlay coexists with UI")
	scenario.finish_scenario(&"ui_test")
	await frames()
	check(not world.paused and not app.external_blocked,"2.5D return restores map and UI")
	# Pending recovery uses the stored source, not the new traveller position.
	app.open_summon(bridge.current_context())
	app._summon()
	app.view.running = false
	var pending_ids: Array = app.state.data.pending.duplicate()
	var money: int = app.state.data.magic
	var save_path: String = app.state.save_path
	app._close_all()
	bridge.remove_child(app)
	app.queue_free()
	await frames()
	var restored = preload("res://ui_module/demo/UIModuleDemo.tscn").instantiate()
	restored.embedded_world = true
	restored.session_save_path = save_path
	restored.animate_panels = false
	root.add_child(restored)
	restored._resume_pending()
	restored.view.skip_eruption()
	check(restored.state.data.pending == pending_ids and restored.state.data.magic == money,"restart recovers exact pending results without a new debit")
	check(restored.location == "forest","pending recovery preserves biome context")
	restored._close_modal()
	restored.queue_free()
	world.queue_free()
	await frames()
	print("UI_MODULE_INTEGRATION checks=%d failures=%d" % [checks,failures])
	var result := {"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,"upstream":"43f4e54f9beaa0341f7dc58a0e35680b27c513de"}
	var report := FileAccess.open("res://ui_module/tests/integration_test_results.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(result,"\t"))
	report.close()
	quit(1 if failures else 0)
