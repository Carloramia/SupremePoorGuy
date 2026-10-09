class_name WorldMapSaveService
extends RefCounted

const DEFAULT_PATH := "user://world_map_save.json"
var last_error: String = ""

func save_state(state: WorldMapRuntimeState, path: String = DEFAULT_PATH) -> bool:
	last_error = ""
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "Cannot write save: %s" % FileAccess.get_open_error()
		push_warning(last_error)
		return false
	file.store_string(JSON.stringify(state.to_dict(), "\t"))
	file.close()
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))
	if error != OK:
		last_error = "Cannot replace save: %s" % error
		push_warning(last_error)
	return error == OK

func load_state(path: String = DEFAULT_PATH) -> WorldMapRuntimeState:
	last_error = ""
	if not FileAccess.file_exists(path):
		last_error = "No save file yet"
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "Cannot read save"
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		last_error = "Invalid JSON save"
		push_warning(last_error)
		return null
	var data: Dictionary = migrate_save_data(json.data)
	if data.is_empty() or not validate_save_data(data):
		last_error = "Unsupported or malformed save"
		push_warning(last_error)
		return null
	return WorldMapRuntimeState.from_dict(data)

func migrate_save_data(data: Dictionary) -> Dictionary:
	return data if _number(data.get("save_version")) and int(data.save_version) == 1 else {}

func validate_save_data(data: Dictionary) -> bool:
	if migrate_save_data(data).is_empty():
		return false
	if not data.get("map_id") is String or not data.get("player_position") is Dictionary:
		return false
	if not _valid_point(data.player_position):
		return false
	if not data.get("active_spawn_id", "") is String or not _number(data.get("procedural_seed", 2026)):
		return false
	if not data.get("exploration_samples", []) is Array or not data.get("location_runtime_states", {}) is Dictionary:
		return false
	for sample in data.get("exploration_samples", []):
		if not sample is Dictionary or not sample.get("position") is Dictionary:
			return false
		if not _valid_point(sample.position) or not _number(sample.get("radius")) or float(sample.radius) <= 0:
			return false
		if sample.has("from") and (not sample.from is Dictionary or not _valid_point(sample.from)):
			return false
	for state in data.get("location_runtime_states", {}).values():
		if not state is Dictionary or not _number(state.get("lifecycle", 0)) or not _number(state.get("visits", 0)) or not state.get("discovered", false) is bool or not state.get("custom_data", {}) is Dictionary:
			return false
	if not data.get("procedural_results", {}) is Dictionary or not data.get("pending_battle", {}) is Dictionary:
		return false
	var generated: Dictionary = data.get("procedural_results", {})
	if not generated.get("locations", []) is Array:
		return false
	for descriptor in generated.get("locations", []):
		if not descriptor is Dictionary or not descriptor.get("id") is String or not descriptor.get("definition") is String:
			return false
		for field: String in ["x", "y", "interaction_x", "interaction_y", "discovery_radius", "interaction_radius", "completion_behavior_override"]:
			if descriptor.has(field) and not _number(descriptor[field]):
				return false
	var pending: Dictionary = data.get("pending_battle", {})
	return pending.is_empty() or (pending.get("map_id") is String and pending.get("location_id") is String and pending.get("encounter_data", {}) is Dictionary)

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _valid_point(data: Dictionary) -> bool:
	return (data.get("x") is float or data.get("x") is int) and (data.get("y") is float or data.get("y") is int) and is_finite(float(data.x)) and is_finite(float(data.y))
