@tool
extends EditorPlugin
const EXPORTER = preload("res://addons/localization_export/exporter.gd")
var exporter: EditorExportPlugin

func _enter_tree() -> void:
	exporter = EXPORTER.new()
	add_export_plugin(exporter)

func _exit_tree() -> void:
	remove_export_plugin(exporter)
