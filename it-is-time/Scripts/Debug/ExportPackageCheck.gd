extends RefCounted
## Opt-in release-package smoke check; run the game with -- --verify-export.
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const CATALOG = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
var failed := false
var _tree: SceneTree

func check(ok: bool, message: String) -> void:
	print("EXPORT_CHECK ",ok," ",message)
	if not ok: failed = true; push_error(message)

func capture(label: String) -> void:
	if DisplayServer.get_name()=="headless": return
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--capture-dir="): continue
		var directory := argument.trim_prefix("--capture-dir=")
		DirAccess.make_dir_recursive_absolute(directory)
		await _tree.process_frame
		await RenderingServer.frame_post_draw
		check(_tree.root.get_texture().get_image().save_png(directory.path_join(label+".png"))==OK,"Screenshot: "+label)

func run(app: Node) -> void:
	_tree = app.get_tree()
	_tree.root.size = Vector2i(1280,720)
	check(OS.has_feature("template") and not OS.has_feature("editor"),"Running the standalone template, not the editor")
	check(not OS.has_feature("C#"),"No .NET runtime dependency")
	check(not ResourceLoader.exists("res://Tests/ValidateRuntimeConsole.gd"),"Development tests excluded from PCK")
	check(not ResourceLoader.exists("res://Deliveries/NewPlayerTasks_20261018/source/it-is-time/Scripts/Application/NewPlayerTasks.gd"),"Delivery sources excluded from PCK")
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Localization/config.json"))
	for locale: Dictionary in config.locales.values():
		for path: String in locale.files:
			check(JSON.parse_string(FileAccess.get_file_as_string("res://Localization/"+path)) is Dictionary,"Localization JSON: "+path)
	check(not CATALOG.world().is_empty(),"World-map JSON loaded from PCK")
	for id: String in CATALOG.index().maps:
		check(not CATALOG.map_data(id).is_empty(),"Map JSON: "+id)
	for id: String in FACTORY.DEFINITIONS:
		var record: Dictionary = FACTORY.template(id)
		check(not record.is_empty() and str(record.get("template_hash","")).length()==64 and FACTORY.valid_record(record),"Dynamic creature scene and saved-pose hash: "+id)
	var test_root := "user://export_smoke/"+str(Time.get_ticks_usec())
	app.save_path = test_root+"/slot.json"
	app.display_settings_path = test_root+"/display.cfg"
	app.session.save_path = app.save_path
	app.ui.animate_panels = false
	app.ui.board_motion.enabled = false
	check(app.phase=="main","Main menu initializes")
	await capture("main_menu")
	app.start_new_game()
	for frame: int in 900:
		if app.phase=="world": break
		await _tree.physics_frame
	check(app.phase=="world" and app.delivery_map!=null,"New game opens the actual delivery map")
	check(app.session.delivery_version()=="20261019" and CATALOG.index().maps.size()==42,"New hex-world runtime is included in the package")
	check(FileAccess.file_exists(app.save_path),"Save writes outside the installed game directory")
	await capture("world_map")
	app.ui._close_all()
	var unit: Dictionary = FACTORY.template("wolf")
	unit.merge({"id":"export_wolf","position":"team","traits":[]},true)
	app.session.data.monsters.append(unit)
	check(app.session.save(),"Exported creature hashes allow saving the roster")
	var camp := {}
	for object: Dictionary in CATALOG.world().objects:
		if object.type=="camp" and "wolf" in str(object.get("enemy_config_id","")) and app.get_delivery_battle_settings().availability_error(str(object.enemy_config_id)).is_empty(): camp=object; break
	check(not camp.is_empty(),"Battle configuration available")
	if not camp.is_empty():
		app.delivery_map.runtime.data.player = camp.position.duplicate()
		app.delivery_map.runtime.data.discovered.append(camp.id)
		check(app.delivery_map.begin_battle(camp.id,"clear"),"Battle request accepted")
		for frame: int in 1200:
			if app.phase=="deployment": break
			await _tree.physics_frame
		var expected := 1+app.get_delivery_battle_settings().enemy_rosters[str(camp.enemy_config_id)].definitions.size()
		check(app.phase=="deployment" and app.battle!=null and app.battle.actors.size()==expected,"3D map, navigation and configured physical creatures deploy")
		await capture("deployment")
		if app.phase=="deployment":
			app.start_battle()
			check(app.phase=="battle","Battle starts from deployment")
			for frame: int in 30: await _tree.physics_frame
	var console := _tree.root.get_node("RuntimeConsole")
	check(console.get_archive_output_directory()==ProjectSettings.globalize_path("user://log_archives"),"Release getlogs uses a writable user directory")
	var log_root := test_root+"/logs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(log_root))
	var log_file := FileAccess.open(log_root+"/probe.log",FileAccess.WRITE)
	log_file.store_string("export smoke test")
	log_file.close()
	var archive: String = console.create_logs_archive("",log_root)
	var reader := ZIPReader.new()
	check(reader.open(archive)==OK and "logs/probe.log" in reader.get_files(),"getlogs creates a valid ZIP from the standalone game")
	reader.close()
	if not archive.is_empty(): DirAccess.remove_absolute(archive)
	for path: String in ["/slot.json","/slot.json.bak","/display.cfg","/logs/probe.log"]:
		if FileAccess.file_exists(test_root+path): DirAccess.remove_absolute(ProjectSettings.globalize_path(test_root+path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(log_root))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_root))
	print("EXPORTED_PACKAGE_","FAILED" if failed else "PASSED")
	_tree.quit(1 if failed else 0)
