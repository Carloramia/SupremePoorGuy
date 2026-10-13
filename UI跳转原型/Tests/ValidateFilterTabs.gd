extends SceneTree
const Scene = preload("res://Scenes/GameDemo.tscn")
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FILTER TABS: " + label)
func settle() -> void:
	for i in 10:
		await process_frame
func capture(label: String) -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://Tests/.runtime") + "/"+label+".png")
func run() -> void:
	root.size = Vector2i(1280,720)
	var app = Scene.instantiate()
	app.state.save_path = ProjectSettings.globalize_path("res://Tests/.runtime") + "/tabs_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app._show("world")
	app._open_ritual()
	await create_timer(0.6).timeout
	app.close_button.pressed.emit()
	await create_timer(0.12).timeout
	check(app.board_motion.motion.position.x < 0, "C exits toward left")
	check(app.board_motion.motion.modulate.a > 0 and app.board_motion.motion.modulate.a < 1, "C fades during exit")
	check(app.main_content.visible, "map visible beneath retreating paper")
	await create_timer(0.5).timeout
	check(not app.overlay.visible and not app.board_motion.busy, "C exit completes")
	for cell in Rules.RUNES[0].cells:
		app.rules.extend(cell)
	app.rules.commit()
	app.state.summon(app.rules,"forest","world")
	app.state.store_pending()
	for i in 3:
		app.state.data.monsters[i].form = ["人形","兽形","蛇形"][i]
	app._warehouse("")
	await create_timer(0.6).timeout
	var page = app.warehouse_page
	check(app.board_motion.motion.modulate.a == 1, "opacity resets when reopening")
	check(page.get_node("%WarehouseCount").text == "3" and page.get_node("%WarehouseTerm").text == "仓库", "name and count separate")
	var human = page.get_node("%Human")
	var beast = page.get_node("%Beast")
	var paper_edge: float = page.get_node("D2").get_global_rect().end.x + page.get_node("D2").get_theme_stylebox("panel").expand_margin_right
	check(paper_edge > 1140, "paper extends beyond reference line in 1280 viewport")
	for name in ["Warehouse","Team","Human","Beast","Serpent"]:
		var tab = page.get_node("%"+name)
		check(tab.global_position.x + tab.extension < paper_edge and tab.get_global_rect().end.x > paper_edge, "tab bridges paper edge even when extended: "+name)
		check(page.get_node("D2").z_index > tab.z_index + page.get_node("TagsRail/Tabs").z_index, "paper covers tab root: "+name)
	check(page.get_node("%WarehouseTerm").global_position.x > paper_edge, "term visible beyond paper")
	check(human.size.x < page.get_node("%Warehouse").size.x, "short form tabs")
	check(beast.position.y < human.position.y + human.size.y and beast.size.x > human.size.x, "two staggered overlapping rails")
	check(human.get_theme_stylebox("pressed") == human.get_theme_stylebox("normal"), "no selected color shift")
	await capture("tabs_neutral")
	human.set_pressed(true)
	await create_timer(0.22).timeout
	check(app.warehouse_page == page, "filter does not rebuild page")
	check(human.position.x == human.resting_x+12 and human.button_pressed, "active tab protrudes")
	check(page.get_node("%Cards").get_child_count() == 1, "human filter works")
	beast.set_pressed(true)
	await create_timer(0.22).timeout
	check(page.get_node("%Cards").get_child_count() == 2, "form filters combine")
	page.get_node("%Team").pressed.emit()
	await create_timer(0.22).timeout
	check(page.get_node("%Cards").get_child_count() == 0 and page.get_node("%DetailCommands").get_child_count() == 0, "empty filter clears stale detail operations")
	check(page.get_node("%Team").position.x == 12, "position filter protrudes")
	check(app.modal_scroll.get_global_rect().encloses(page.get_node("%Team").get_global_rect()), "extended tab not clipped by page viewport")
	check(page.get_node("D2/Paper").get_global_rect().end.x > paper_edge-20, "paper texture reaches expanded edge")
	await capture("tabs_active")
	page.get_node("%All").pressed.emit()
	await create_timer(0.22).timeout
	check(app.warehouse_filter.is_empty() and app.form_filters.is_empty(), "clear resets every condition")
	for name in ["Warehouse","Team","Human","Beast","Serpent"]:
		var tab = page.get_node("%"+name)
		check(tab.position.x == tab.resting_x and not tab.button_pressed, "clear retracts "+name)
	check(page.get_node("%Cards").get_child_count() == 3, "clear shows all monsters")
	await capture("tabs_reset")
	root.size = Vector2i(1120,680)
	await settle()
	page.get_node("%Warehouse").pressed.emit()
	await create_timer(0.22).timeout
	check(app.get_global_rect().encloses(page.get_node("%Warehouse").get_global_rect()), "extended tab fits minimum window")
	page.get_node("%Warehouse").pressed.emit()
	await create_timer(0.22).timeout
	check(app.warehouse_filter.is_empty() and page.get_node("%Warehouse").position.x == 0, "position filter toggles off")
	await capture("tabs_minimum")
	app.close_button.pressed.emit()
	await create_timer(0.12).timeout
	check(app.board_motion.motion.position.x < 0 and app.board_motion.motion.modulate.a < 1, "D exits left and fades")
	await create_timer(0.5).timeout
	check(not app.overlay.visible and app.main_content.visible, "D returns to original map")
	app.queue_free()
	await process_frame
	print("FILTER_TABS_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
