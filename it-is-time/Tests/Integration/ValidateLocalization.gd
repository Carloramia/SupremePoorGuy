extends SceneTree
const TEXT = preload("res://Scripts/Localization/GameText.gd")
var failed := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var service: Node = root.get_node("GameLocalization")
	var original_path: String = service.settings_path
	service.settings_path = "res://Tests/.runtime/localization/language.cfg"
	check(service.set_locale("zh_CN",false),"Chinese initializes")
	check(TEXT.text("ui.main.start_game")=="开始游戏","Stable keys resolve to the Chinese source")
	check(not service.set_locale("invalid_locale",false),"An unsupported locale is rejected")
	var label := Label.new()
	root.add_child(label)
	var values := {"count":3,"capacity":6}
	TEXT.bind(label,&"text",func(): return TEXT.text("party.count",values))
	check(label.text=="当前出战：3 / 6","Named placeholders are formatted")
	var before_count: int = TEXT._bindings.size()
	check(service.set_locale("en",false),"English is available with fallback")
	check(label.text=="Party: 3 / 6","An existing dynamic label updates without reconstruction")
	values.count = 4
	TEXT.refresh_bindings()
	check(label.text=="Party: 4 / 6","Bindings retain the original parameters")
	check(TEXT.text("此地点暂无已接入的事件。")=="此地点暂无已接入的事件。","Missing English entries use Chinese")
	check(TEXT.creature_name({"definition_id":"wolf","name":"灰狼"})=="Gray Wolf","Default creature names use their stable species ID")
	check(TEXT.creature_name({"definition_id":"wolf","name":"灰狼","custom_name":true})=="灰狼","A custom name matching a source message stays literal")
	label.free()
	check(TEXT._bindings.size()==before_count-1,"Freeing a control unregisters its binding")
	service.set_locale("zh_CN",false)
	root.size = Vector2i(1280,720)
	var app := preload("res://Scenes/Application/GameRoot.tscn").instantiate()
	app.save_path = "res://Tests/.runtime/localization/save_"+str(Time.get_ticks_usec())+".json"
	root.add_child(app)
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	app.ui._settings()
	await process_frame
	var language: OptionButton = app.ui.modal_box.find_child("Language",true,false)
	var fullscreen: CheckButton = app.ui.modal_box.find_child("Fullscreen",true,false)
	var resolution: OptionButton = app.ui.modal_box.find_child("Resolution",true,false)
	var resolution_before := resolution.selected
	var settings_id: int = app.ui.modal_box.get_instance_id()
	language.select(1)
	language.item_selected.emit(1)
	await process_frame
	check(service.current_locale()=="en" and fullscreen.text=="Fullscreen","The real settings selector changes the visible interface")
	check(app.ui.modal_stack.size()==1 and app.ui.modal_box.get_instance_id()==settings_id and resolution.selected==resolution_before,"Language switching preserves the open page and resolution selection")
	var preferences := ConfigFile.new()
	check(preferences.load(service.settings_path)==OK and preferences.get_value("language","locale","")=="en","Language preference is saved independently of the game save")
	check(root.get_node("RuntimeConsole").execute_command("help").begins_with("Available commands:"),"Console help resolves the selected language while keeping commands stable")
	app.ui._close_all()
	app.phase = "world"
	app.ui._show("world")
	var wolf: Dictionary = app.session.FACTORY.template("wolf")
	wolf.merge({"id":"localized_wolf","position":"warehouse","traits":[]},true)
	app.session.data.monsters.append(wolf)
	app.ui._warehouse()
	app.ui.form_filters.assign(["兽形"])
	app.ui._refresh_warehouse_filters(false)
	service.set_locale("zh_CN",false)
	check(app.ui.form_filters==["兽形"],"Language changes do not translate internal form filters")
	check(app.session.rename_monster("localized_wolf","灰狼"),"The existing rename transaction remains valid")
	app.ui._render_modal()
	service.set_locale("en",false)
	check(app.ui.warehouse_page.get_node("%DetailBody").get_child(0).get_node("%Name").text=="灰狼","A player-authored name stays literal in the real detail view")
	app.ui._close_all()
	app.ui._open_ritual()
	await process_frame
	var board_id: int = app.ui.board.get_instance_id()
	var draft: Array = app.ui.rules.draft.duplicate()
	service.set_locale("zh_CN",false)
	check(app.ui.board.get_instance_id()==board_id and app.ui.rules.draft==draft,"An open ritual board and its draft survive language switching")
	app.ui._close_all()
	app.ui._tasks()
	service.set_locale("en",false)
	await process_frame
	app.ui._close_all()
	var bindings_before_free: int = TEXT._bindings.size()
	app.free()
	await process_frame
	check(TEXT._bindings.size()<bindings_before_free,"Closing the application releases its live UI bindings")
	service.settings_path = original_path
	service.set_locale("zh_CN",false)
	print("LOCALIZATION_INTEGRATION_FAILED" if failed else "LOCALIZATION_INTEGRATION_PASSED")
	quit(1 if failed else 0)
