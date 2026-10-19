extends SceneTree
## Geometry assertions supplement route tests: a visible Label can still be fully clipped.
const APP = preload("res://Scenes/Application/GameRoot.tscn")
const SERVICE = preload("res://Scripts/Events/StoryService.gd")
const CATALOG = preload("res://Scripts/Events/StoryCatalog.gd")
const OUTPUT := "res://Tests/.runtime/story-text-layout/"
var checks := 0
var failures := 0
var records: Array = []
var app: Node
var capture := false

func _initialize() -> void:
	create_timer(90).timeout.connect(func():push_error("STORY_TEXT_TIMEOUT");quit(1))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("STORY_TEXT_FAIL: "+label)

func frames(count := 6) -> void:
	for index: int in count: await process_frame

func show_node(id: String, node_id: String, cursor := 0) -> void:
	app.ui._close_all()
	var bindings: Array = CATALOG.bindings(id)
	var context: Dictionary = bindings[0] if not bindings.is_empty() else {"source_id":"layout_summoning_hut","entry_role":"opening","trigger_mode":"on_game_start"}
	var row := SERVICE.new_entry(id,context)
	row.node=node_id
	row.cursor=cursor
	SERVICE.ensure(app.session.data).entries[id]=row
	app.story_controller._present(id)
	await frames()

func description() -> Label:
	return app.ui.modal_box.find_child("Description",true,false)

func inspect(label: String) -> void:
	var text := description()
	check(is_instance_valid(text),"Text control exists: "+label)
	if not is_instance_valid(text): return
	var scroll: ScrollContainer = text.get_parent()
	var commands: Control = scroll.get_parent().get_node("%Commands")
	var rect := scroll.get_global_rect()
	check(not text.text.is_empty(),"Source text is nonempty: "+label)
	check(text.is_visible_in_tree() and text.visible_ratio==1.0 and text.modulate.a>0.0,"Text drawing is enabled: "+label)
	check(rect.size.y>=text.get_theme_font_size("font_size") and rect.size.x>200,"Text viewport has usable area, not zero height: "+label)
	check(rect.intersection(app.ui.modal_scroll.get_global_rect()).size.y>=text.get_theme_font_size("font_size"),"Text viewport is not clipped by outer scroll: "+label)
	check(commands.get_global_rect().position.y>=rect.end.y-1.0,"Commands remain below text viewport: "+label)
	check(app.ui.modal_scroll.vertical_scroll_mode==ScrollContainer.SCROLL_MODE_DISABLED,"Story owns inner scrolling instead of nested scrolling: "+label)
	records.append({"case":label,"text_length":text.text.length(),"scroll_size":[scroll.size.x,scroll.size.y],"font_size":text.get_theme_font_size("font_size"),"logical_size":str(root.content_scale_size),"viewport_size":str(root.get_visible_rect().size)})

func screenshot(name: String) -> void:
	if not capture or DisplayServer.get_name()=="headless": return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT+name+".png")==OK,"Actual viewport capture saved: "+name)

func run() -> void:
	capture="--capture" in OS.get_cmdline_user_args()
	root.get_node("RuntimeConsole").auto_getlogs_enabled=false
	root.get_node("GameLocalization").set_locale("zh_CN",false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	app=APP.instantiate()
	app.save_path=OUTPUT+"isolated_%d.json" % Time.get_ticks_usec()
	app.display_settings_path=OUTPUT+"display.cfg"
	root.add_child(app)
	app.ui.animate_panels=false
	app.ui.board_motion.enabled=false
	app.story_controller.set_process(false)
	app.start_new_game()
	for frame: int in 600:
		if app.phase=="world": break
		await process_frame
	check(app.phase=="world","Isolated real application enters world")
	for size: Vector2i in [Vector2i(1120,680),Vector2i(1366,768),Vector2i(1920,1080)]:
		# Change logical render size directly: no real display preference or player save.
		root.content_scale_size=size
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
		root.size=size
		await frames()
		check(root.get_visible_rect().size.is_equal_approx(Vector2(size)),"Viewport matches requested resolution without aspect expansion")
		for id: String in CATALOG.flows():
			if id.begins_with("AUX_"): continue
			await show_node(id,CATALOG.definition(id).start)
			inspect(id+"_"+str(size))
			if id==SERVICE.LIBRARY: await screenshot("library_"+str(size.x))
			if size==Vector2i(1120,680):
				var flow: Dictionary = CATALOG.definition(id)
				for key: String in flow.nodes:
					if key==flow.start or flow.nodes[key].type not in ["dialogue","choice","action"]: continue
					await show_node(id,key)
					inspect(id+":"+key)
		await show_node(SERVICE.LIBRARY,"intro")
		var reading_size: Vector2 = app.ui.modal_box.get_parent().get_parent().size
		check(app.story_controller.show_location({"id":CATALOG.bindings(SERVICE.LIBRARY)[0].source_id,"name":"福斯特镇"}),"Actual shared town menu opens")
		await frames()
		check(app.ui.modal_stack.back().kind=="event","Comparison uses actual event menu, not the previous story")
		check(app.ui.modal_box.get_parent().get_parent().size.is_equal_approx(reading_size),"Event menu and short story share the same large reading sheet")
		app.ui._close_all()
		await show_node(SERVICE.LIBRARY,"intro")
		var original := description().text
		app.ui._settings()
		await frames()
		app.ui._close_modal()
		await frames()
		check(description().text==original,"Returning from settings preserves current prose")
		inspect("settings_return_"+str(size))
		# Long prose fixture only; no change to authored content or event progression.
		var long_text: String = (original+"\n").repeat(80)+"正文末尾验收标记"
		var text := description()
		text.text=long_text
		await frames()
		inspect("long_prose_"+str(size))
		var scroll: ScrollContainer = text.get_parent()
		var bar := scroll.get_v_scroll_bar()
		check(bar.max_value>bar.page and scroll.size.y>0,"Long prose overflows inside a positive-height viewport")
		scroll.scroll_vertical=int(bar.max_value)
		await frames()
		check(scroll.scroll_vertical>0 and is_equal_approx(float(scroll.scroll_vertical)+bar.page,bar.max_value),"Long prose can scroll fully to its end")
		check(scroll.get_global_rect().intersects(Rect2(text.global_position+Vector2(0,text.size.y-text.get_theme_font_size("font_size")),Vector2(text.size.x,text.get_theme_font_size("font_size")))),"Final text line reaches the visible viewport")
		await screenshot("long_prose_end_"+str(size.x))
	# Resize the already open story, without rebuilding it or changing its paragraph.
	root.content_scale_size=Vector2i(1280,720)
	await frames()
	inspect("live_resize")
	check(description().text.ends_with("正文末尾验收标记"),"Live resize preserves text")
	var file := FileAccess.open(OUTPUT+("graphical" if capture else "geometry")+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records},"  "))
	file.close()
	app.queue_free()
	await process_frame
	print("STORY_TEXT_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
