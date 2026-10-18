@tool
extends EditorExportPlugin

func _get_name() -> String: return "JSONLocalization"

static func files_to_include() -> PackedStringArray:
	var root := "res://Localization/"
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(root+"config.json"))
	var files: Array = ["config.json","catalog.json"]
	for locale: Dictionary in config.locales.values(): files.append_array(locale.files)
	var result := PackedStringArray()
	for file: String in files: result.append(root+file)
	return result

func _export_begin(_features: PackedStringArray, _debug: bool, _path: String, _flags: int) -> void:
	for path: String in files_to_include(): add_file(path,FileAccess.get_file_as_bytes(path),false)
