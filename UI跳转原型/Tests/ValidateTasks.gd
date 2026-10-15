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
		push_error("TASKS: "+label)
func settle() -> void:
	for i in 10:
		await process_frame
func capture(name: String) -> void:
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://Tests/screenshots/"+name+".png")
func run() -> void:
	var app = Scene.instantiate()
	app.animate_panels = false
	app.state.save_path = ProjectSettings.globalize_path("res://Tests/.runtime") + "/tasks_%d.json" % Time.get_ticks_usec()
	root.add_child(app)
	app._show("world")
	app._tasks()
	var font = app.header.get_theme_font("font")
	var glyphs_ok := true
	for character in "待办事项完成记录召唤妖兽仓库出战森林沙漠草原魔力生命攻击护甲移速余烬回潮壁垒疾风天钉回环双峰0123456789":
		glyphs_ok = glyphs_ok and font.has_char(character.unicode_at(0))
	check(glyphs_ok,"common Chinese and numeric glyph coverage")
	for resolution in [Vector2i(1120,680),Vector2i(1280,720),Vector2i(1920,1080)]:
		root.size = resolution
		await settle()
		var page = app.modal_box.get_child(0)
		check(page.get_node("%PendingRows").get_child_count()==3, "three objectives grouped")
		check(page.get_node("%ListScroll").get_v_scroll_bar().max_value <= page.get_node("%ListScroll").size.y+1, "three short tasks need no scrolling")
		for row in page.get_node("%PendingRows").get_children():
			check(app.modal_scroll.get_global_rect().encloses(row.get_node("%Go").get_global_rect()), "task shortcut inside window "+str(resolution))
		check(app.header.get_theme_font("font").resource_path.ends_with("Xiaolai-Regular.ttf"), "global bundled handwriting")
		check(page.get_node("%Summary").get_theme_font("font")==app.header.get_theme_font("font"), "task and global font consistent")
		if resolution.x==1280:
			await capture("14_tasks")
	var page = app.modal_box.get_child(0)
	page.get_node("%PendingRows").get_child(0).get_node("%Go").pressed.emit()
	check(app.modal_stack.size()==1 and app.modal_stack.back().kind=="event", "task shortcut opens original event once")
	app.modal_box.get_child(0).get_node("%Commands").get_child(0).pressed.emit()
	app._tasks()
	await settle()
	page = app.modal_box.get_child(0)
	check(page.get_node("%PendingRows").get_child_count()==2, "event progress updates task groups")
	check(page.get_node("%Summary").text == "待办 2", "summary shows only outstanding count")
	page.get_node("%PendingRows").get_child(0).get_node("%Go").pressed.emit()
	check(app.modal_stack.size()==1 and app.modal_stack.back().title.begins_with("六相召唤阵"), "summon shortcut uses book flow")
	app._close_all()
	for cell in Rules.RUNES[0].cells:
		app.rules.extend(cell)
	app.rules.commit()
	app.state.summon(app.rules,"grassland","world")
	app.state.store_pending()
	app.state.move_monster(app.state.data.monsters[0].id,"team")
	app._tasks()
	root.size = Vector2i(1280,720)
	await settle()
	page=app.modal_box.get_child(0)
	check(page.get_node("%PendingRows").get_child_count()==0, "summon and party completion derives from state")
	check(page.get_node("%PendingEmpty").visible, "all complete message")
	await capture("15_tasks_complete")
	var many: Array = []
	for i in 20:
		many.append({"title":"长列表事项%d" % i,"description":"供正式任务列表扩展时验证。","done":false})
	page.present_tasks(many)
	await settle()
	check(page.get_node("%ListScroll").get_v_scroll_bar().max_value > page.get_node("%ListScroll").size.y, "long tasks scroll independently")
	check(app.modal_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "outer window does not scroll away header")
	app.close_button.pressed.emit()
	check(app.modal_stack.is_empty(), "task close functional")
	app.queue_free()
	await process_frame
	print("TASKS_VALIDATION checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
