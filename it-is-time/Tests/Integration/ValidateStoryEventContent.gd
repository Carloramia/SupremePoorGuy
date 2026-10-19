extends SceneTree
const CONTENT = preload("res://Scripts/Events/StoryEventContent.gd")
const PRESENTER = preload("res://Scripts/Events/StoryEventPresenter.gd")
var checks := 0
var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failed = true; push_error(message)
func text(pages: Array) -> String:
	return "\n".join(pages.map(func(p): return p.text))
func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var content := CONTENT.new()
	check(content.events.size()==20 and content.catalog.bindings.size()==25,"Patch contains exactly 20 events and 25 authored entrances")
	var city := content.bindings_for_site("layout_sargate_city")
	check(city.size()==4,"City interact entries preserve center, enchanter, merchant and city auxiliary")
	check(content.bindings_for_site("layout_sargate_city","on_game_time").size()==1,"Ghost is a timed entry, not ordinary city interaction")
	var first := text(content.dialogue("QST_SIDE_003_001",{"stage":"available"}))
	check("第一次" in first and "第二次" not in first and "第三次" not in first,"First sacrifice does not leak future requirements")
	var second := text(content.dialogue("QST_SIDE_003_001",{"stage":"stage_2"}))
	check("第二次" in second and "第一次" not in second and "第三次" not in second,"Second sacrifice exposes only its own requirement")
	check("我的好兄弟，可算把你找回来了" in text(content.dialogue("QST_GRASS_007",{"stage":"return_dialogue","entry":"donkey"})),"Both donkey entrances select shared return text")
	check("城墙修缮费" in text(content.dialogue("QST_SIDE_002_001",{"stage":"active","defense_won":false})),"Active commission uses revisit text")
	check("不愧是王国" in text(content.dialogue("QST_SIDE_002_001",{"stage":"active","defense_won":true})),"Victory commission uses hand-in text")
	check("不许笑" in text(content.dialogue("QST_GRASS_015",{"stage":"teach","route":"funny"})),"Reopened ghost dialogue restores chosen answer")
	for e: Dictionary in content.events.values():
		for sequence: Array in e.dialogues.values():
			for paragraph: Dictionary in sequence:
				check("待绑定" not in paragraph.text and "（获得" not in paragraph.text and "**" not in paragraph.text,"Authoring notes do not become dialogue: "+e.id)
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.enable_hex_map = false
	app.save_path = "res://Tests/.runtime/story_events/content_%d.json" % Time.get_ticks_usec()
	app.display_settings_path = app.save_path+".cfg"
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	app.start_new_game()
	for frame: int in 600:
		if app.phase=="world": break
		await physics_frame
	app.ui._close_all()
	var presenter := PRESENTER.new()
	app.add_child(presenter)
	presenter.setup(app)
	presenter.open("QST_GRASS_005","shepherd")
	check(app.ui.overlay.visible and app.ui.find_child("StoryChoice_talk",true,false)==null,"First dialogue page has no premature completion button")
	presenter._leave()
	check(not app.session.story_event_view("QST_GRASS_005").completed,"Closing incomplete dialogue preserves event")
	presenter.open("QST_GRASS_005","shepherd")
	presenter.page_index = presenter.pages.size()-1
	presenter._replace()
	check(app.ui.find_child("StoryChoice_talk",true,false)!=null,"Final page displays actual branch")
	presenter._choose("talk")
	check(app.session.story_event_view("QST_GRASS_005").completed and not app.ui.overlay.visible,"Actual final dialogue confirmation completes rumor event")
	app.session.story_events.config.bindings.rewards.stars=null
	presenter.open("QST_GRASS_013","well")
	presenter.page_index = presenter.pages.size()-1
	presenter._replace()
	var record := app.ui.find_child("StoryChoice_record",true,false) as Button
	check(record!=null and record.disabled and "待配置" in record.tooltip_text,"Missing reward disables only affected choice with reason")
	presenter._leave()
	app.queue_free()
	await process_frame
	print("STORY_EVENT_CONTENT_", "FAILED" if failed else "PASSED", " checks=",checks)
	quit(1 if failed else 0)
