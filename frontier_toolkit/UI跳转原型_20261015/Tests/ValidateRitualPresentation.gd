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
		push_error("RITUAL PRESENTATION: "+label)
func settle() -> void:
	for i in 10:
		await process_frame
func run() -> void:
	root.size = Vector2i(1280,720)
	var app = Scene.instantiate()
	app.animate_panels = false
	app.state.save_path = ProjectSettings.globalize_path("res://Tests/.runtime")+"/ritual_presentation_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app._show("world")
	app._open_ritual()
	var previous_radius := 0.0
	for stage in range(1,5):
		app.rules.stage = stage
		app.state.data.array_stage = stage
		app._render_modal()
		await settle()
		var board = app.board
		var radius: float = board.grid_radius()
		check(radius > previous_radius,"successive upgrades enlarge the array")
		check(radius/minf(board.size.x,board.size.y) <= 0.401,"array leaves paper breathing room")
		check(board.backdrop_radius() > radius and board.backdrop_radius()*1.04 < minf(board.size.x,board.size.y)*0.5,"ink backdrop surrounds cells and fits sheet")
		check(board.cell_at(board.point([stage,0])) == [stage,0],"outer unlocked cell remains clickable")
		for cell in Rules.cells(stage):
			for vertex in board.polygon(cell):
				check(vertex.distance_to(board.size*0.5) < board.backdrop_radius(),"all hex vertices inside backdrop")
		var input := InputEventMouseButton.new()
		input.button_index = MOUSE_BUTTON_LEFT
		input.pressed = true
		input.position = board.point([0,0])
		board._gui_input(input)
		input.pressed = false
		board._gui_input(input)
		check(app.rules.draft == [[0,0]],"scaled board input matches drawing")
		app.rules.draft.clear()
		previous_radius = radius
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://Tests/screenshots/"+("ritual_handdrawn_stage_%d.png" % stage))
	var page = app.ritual_page
	app.animate_panels = true
	for i in 6:
		page.get_node("%RelicTab").pressed.emit()
		check(page.get_node("%Relics").visible and not page.get_node("%References").visible,"relic tab closes runes")
		page.get_node("%RuneTab").pressed.emit()
		check(page.get_node("%References").visible and not page.get_node("%Relics").visible,"rune tab closes relics")
	page.get_node("%RuneTab").pressed.emit()
	check(page.get_node("%References").visible,"active tab stays open on repeat click")
	await create_timer(0.3).timeout
	check(page.get_node("%References").modulate.a == 1.0,"rapid switching settles fully visible")
	app.animate_panels = false
	page.get_node("%RelicTab").pressed.emit()
	app._term("说明","返回后保持奇物页")
	app._close_modal()
	await settle()
	check(app.ritual_page.get_node("%Relics").visible and not app.ritual_page.get_node("%References").visible,"nested return restores exclusive active tab")
	var relic_rows = app.ritual_page.get_node("%Relics")
	check(relic_rows.get_child_count()==3,"all relics keep reference rows")
	for i in 3:
		var row = relic_rows.get_child(i)
		var preview = row.get_node("%Preview")
		check(preview.preview_outline_only and preview.read_only,"relic preview contains only a silhouette")
		check(preview.footprint_edges().size()==[12,14,10][i],"shared hex edges removed from relic outline")
		check(row.get_node("%Open").text.contains("\n") and row.get_node("%Open").get_theme_font_size("font_size")==16,"relic name and effect share rune row format")
	var bone = relic_rows.get_child(2).get_node("%Open")
	bone.pressed.emit()
	check(app.board.selected_relic=="bone-die","reference button selects actual relic")
	var drop_point: Vector2 = app.board.point([0,0])
	check(app.board._can_drop_data(drop_point,{"relic":bone.relic_id}),"existing relic drag payload accepted")
	app.board._drop_data(drop_point,{"relic":bone.relic_id})
	check(app.rules.relics.size()==1 and app.rules.relics[0].cells.size()==2,"drop places actual footprint")
	await settle()
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://Tests/screenshots/relic_reference_outline.png")
	app.queue_free()
	await process_frame
	print("RITUAL_PRESENTATION_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
