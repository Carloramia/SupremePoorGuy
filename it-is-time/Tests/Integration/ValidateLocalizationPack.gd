extends SceneTree
const EXPORTER = preload("res://addons/localization_export/exporter.gd")
const DIRECTORY := "res://Tests/.runtime/localization_pack/"

func _initialize() -> void: call_deferred("run")

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	DirAccess.make_dir_recursive_absolute(DIRECTORY)
	var fixtures := {
		"project.godot": '[application]\nconfig/name="LocalizationPackProbe"\nrun/main_scene="res://Probe.tscn"\n[autoload]\nGameLocalization="*res://Scripts/Localization/GameText.gd"\n',
		"Probe.tscn": '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://Probe.gd" id="1"]\n[node name="Probe" type="Node"]\nscript = ExtResource("1")\n',
		"Probe.gd": 'extends Node\nfunc _ready() -> void:\n\tvar service := get_node("/root/GameLocalization")\n\tassert(service.set_locale("en",false))\n\tassert(service.text("ui.main.start_game")=="New Game")\n\tassert(service.text("party.count",{"count":2,"capacity":6})=="Party: 2 / 6")\n\tassert(service.text("此地点暂无已接入的事件。")=="此地点暂无已接入的事件。")\n\tprint("LOCALIZATION_PACK_BOOT_PASSED")\n\tget_tree().quit()\n'
	}
	var packer := PCKPacker.new()
	assert(packer.pck_start(DIRECTORY+"localization.pck")==OK)
	for name: String in fixtures:
		var file := FileAccess.open(DIRECTORY+name,FileAccess.WRITE)
		file.store_string(fixtures[name])
		file.close()
		assert(packer.add_file("res://"+name,DIRECTORY+name)==OK)
	assert(packer.add_file("res://Scripts/Localization/GameText.gd","res://Scripts/Localization/GameText.gd")==OK)
	for path: String in EXPORTER.files_to_include():
		assert(FileAccess.file_exists(path))
		assert(packer.add_file(path,path)==OK)
	assert(packer.flush()==OK)
	print("LOCALIZATION_PACK_CREATED ",ProjectSettings.globalize_path(DIRECTORY+"localization.pck"))
	quit()
