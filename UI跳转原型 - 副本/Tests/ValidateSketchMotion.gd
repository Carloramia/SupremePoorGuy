extends SceneTree
const Scene = preload("res://Scenes/GameDemo.tscn")
const Rules = preload("res://Scripts/Ritual/RuneRules.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SKETCH MOTION FAILED: "+label)
func _run() -> void:
	root.size = Vector2i(1280,720)
	var app = Scene.instantiate()
	app.state.save_path = ProjectSettings.globalize_path("res://Tests/.runtime") + "/native_motion_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app._show("world")
	await create_timer(0.1).timeout
	app._open_ritual()
	check(app.board_motion.horizontal,"C page slides horizontally")
	await create_timer(0.6).timeout
	check(not app.main_content.visible,"outgoing map no longer behind C")
	app._close_all()
	for cell in Rules.RUNES[0].cells:
		app.rules.extend(cell)
	app.rules.commit()
	check(app.state.summon(app.rules,"forest","world"),"fixture summoned once")
	app.state.store_pending()
	app._warehouse()
	await create_timer(0.6).timeout
	check(app.board_motion.horizontal,"D page slides horizontally")
	var id: String = app.state.data.monsters[0].id
	app._confirm("回收怪物？","测试",func(): app._recycle_monster(id))
	app._recycle_monster(id)
	await create_timer(0.1).timeout
	var fragments := 0
	for child in app.overlay.get_children():
		if child.get_script() == preload("res://Scripts/UI/PaperTear.gd"):
			fragments += 1
	check(fragments == 1,"paper tear visual starts after saved removal")
	await create_timer(0.4).timeout
	check(app.warehouse_page.get_node("%Cards").get_child_count()==2,"tear finishes with two notes")
	app._close_all()
	app._show("battle")
	await create_timer(0.6).timeout
	if DisplayServer.get_name() != "headless":
		check(is_instance_valid(app.curtain_snapshot) and not app.curtain_snapshot.visible,"battle curtain settles")
	var header_before: Rect2 = app.header.get_global_rect()
	app._warehouse()
	var start_x: float = app.outgoing_page.position.x
	check(app.outgoing_page.get_meta("source_mode") == "battle","outgoing page freezes the small map")
	await create_timer(0.12).timeout
	check(app.outgoing_page.position.x > start_x and app.board_motion.motion.position.x < 0,"small map and incoming book both travel right")
	check(app.header.get_global_rect() == header_before,"A1 stays fixed during horizontal transition")
	await create_timer(0.5).timeout
	app._close_all()
	app._skip_battle()
	await create_timer(0.6).timeout
	check(app.route == "battle" and app.view.mode == "battle" and not app.curtain_busy,"settlement stays above battle until confirmed")
	app.modal_box.get_child(0).get_node("%Commands").get_child(0).pressed.emit()
	check(app.modal_stack.is_empty(),"confirmation closes settlement first")
	if DisplayServer.get_name() != "headless":
		check(app.curtain_busy and app.view.mode == "battle","battle remains beneath descending map")
		check(app.curtain_snapshot.mode == "world" and app.curtain_snapshot.position.y < 0,"actual large map descends from above")
	await create_timer(0.6).timeout
	check(app.view.mode == "world" and not app.curtain_busy,"large map activates only after curtain completes")
	app.queue_free()
	await process_frame
	print("SKETCH_MOTION_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)


