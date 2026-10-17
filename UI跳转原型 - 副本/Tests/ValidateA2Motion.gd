extends SceneTree
const Scene = preload("res://Scenes/GameDemo.tscn")
var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("A2 MOTION: "+label)
func settle() -> void:
	for i in 8:
		await process_frame
func capture(label: String) -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://Tests/.runtime") + "/a2_"+label+".png")
func run() -> void:
	root.size = Vector2i(1280,720)
	var app = Scene.instantiate()
	app.state.save_path = ProjectSettings.globalize_path("res://Tests/.runtime") + "/a2_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app._show("world")
	await settle()
	for name in ["Tasks","Summon","Warehouse","Party","ReturnMap"]:
		var button = app.base.get_node("%"+name)
		var normal = button.get_theme_stylebox("normal")
		for state in ["hover","pressed","hover_pressed","disabled"]:
			check(button.get_theme_stylebox(state) == normal, "same paper geometry "+name+" "+state)
	check(not app.base.get_node("%PartySlot").visible, "battle bookmark hidden in world")
	var summon = app.base.get_node("%Summon")
	var before: Rect2 = summon.get_global_rect()
	app._show("battle")
	var party = app.base.get_node("%Party")
	var slot = app.base.get_node("%PartySlot")
	var width: float = party.size.x
	check(slot.visible and party.position.x < 0, "new button begins left of its slot")
	var first: float = party.position.x
	await create_timer(0.08).timeout
	check(party.position.x > first and party.position.x < 0, "button enters left to right")
	check(party.size.x == width and party.scale == Vector2.ONE, "entry does not stretch button")
	check(summon.get_global_rect() == before, "existing A2 buttons do not reflow")
	await capture("enter")
	await create_timer(0.55).timeout
	check(party.position.x == 0 and party.modulate.a == 1, "entry settles")
	app._show("world")
	await create_timer(0.1).timeout
	check(slot.visible and party.position.x < 0, "button exits right to left before removing slot")
	check(party.size.x == width and party.scale == Vector2.ONE, "exit does not stretch button")
	await capture("exit")
	await create_timer(0.5).timeout
	check(not slot.visible and not app.base.get_node("%ReturnMapSlot").visible, "exit completes before slots collapse")
	app._show("battle")
	await create_timer(0.06).timeout
	app._show("world")
	await create_timer(0.06).timeout
	app._show("battle")
	await create_timer(0.6).timeout
	check(slot.visible and party.position.x == 0 and party.modulate.a == 1, "rapid reversal settles without orphan animation")
	for mode in ["ritual","warehouse"]:
		await RenderingServer.frame_post_draw
		var expected := get_root().get_texture().get_image().get_region(Rect2i(app.main_content.get_global_rect()))
		app._open_ritual() if mode == "ritual" else app._warehouse()
		check(app.outgoing_page is TextureRect, "outgoing visual cannot reflow "+mode)
		var frozen = app.outgoing_page.texture.get_image()
		check(frozen.get_data() == expected.get_data(), "outgoing first frame matches rendered A2 "+mode)
		var outgoing_size: Vector2 = app.outgoing_page.size
		await create_timer(0.1).timeout
		check(app.outgoing_page.size == outgoing_size, "outgoing A2 dimensions stable "+mode)
		await capture(mode)
		await create_timer(0.5).timeout
		app.close_button.pressed.emit()
		await create_timer(0.6).timeout
		check(summon.get_global_rect() == before, "A2 restored to original bounds "+mode)
	app.animate_panels = false
	app._show("world")
	check(not slot.visible, "reduced motion hides instantly")
	app._show("battle")
	check(slot.visible and party.position.x == 0 and party.mouse_filter == Control.MOUSE_FILTER_STOP, "reduced motion restores clickable button")
	app.queue_free()
	await process_frame
	print("A2_MOTION_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
