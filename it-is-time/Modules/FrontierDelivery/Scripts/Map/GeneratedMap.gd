@tool
extends Node2D
@export var map_id := ""
@export_file("*.json") var data_path := ""

func definition() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(data_path))
