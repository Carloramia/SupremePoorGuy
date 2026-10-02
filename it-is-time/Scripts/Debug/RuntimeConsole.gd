extends CanvasLayer

@export var toggle_action: StringName = &"CallConsole"
@export_range(10, 1000, 1) var maximum_output_lines: int = 100
@export_range(0.05, 10.0, 0.05, "or_greater") var motion_tracking_interval: float = 0.1

@onready var _output: RichTextLabel = $ConsoleRoot/Panel/Margin/VBox/Output
@onready var _command_input: LineEdit = $ConsoleRoot/Panel/Margin/VBox/CommandRow/CommandInput

var _output_lines: Array[String] = []
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _motion_tracking_enabled: bool = false
var _motion_tracking_elapsed: float = 0.0

func _ready() -> void:
	visible = false
	_command_input.text_submitted.connect(_on_command_submitted)
	_append_output("Runtime console ready. Available commands: getlogs, trackmotion")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(toggle_action):
		get_viewport().set_input_as_handled()
		set_console_open(not visible)

func _process(delta: float) -> void:
	if not _motion_tracking_enabled:
		return
	_motion_tracking_elapsed += delta
	if _motion_tracking_elapsed < motion_tracking_interval:
		return
	_motion_tracking_elapsed = 0.0
	_emit_motion_snapshot()

func set_console_open(open: bool) -> void:
	if visible == open:
		return
	visible = open
	if open:
		_previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_command_input.clear()
		_command_input.grab_focus()
	else:
		_command_input.release_focus()
		Input.mouse_mode = _previous_mouse_mode

func is_console_open() -> bool:
	return visible

func execute_command(command: String) -> String:
	var normalized := command.strip_edges().to_lower()
	match normalized:
		"getlogs":
			var archive_path := create_logs_archive()
			if archive_path.is_empty():
				return "Failed to create runtime log archive."
			return "Runtime logs archived to: %s" % archive_path
		"trackmotion":
			_motion_tracking_enabled = not _motion_tracking_enabled
			_motion_tracking_elapsed = 0.0
			if _motion_tracking_enabled:
				_emit_motion_snapshot()
				return "Character_Test_2 Leg motion tracking enabled."
			return "Character_Test_2 Leg motion tracking disabled."
		"":
			return ""
		_:
			return "Unknown command: %s" % command.strip_edges()

## Packs user://logs into a ZIP. Tests may pass different writable source and output directories.
func create_logs_archive(output_directory: String = "", log_directory: String = "user://logs") -> String:
	var destination_directory := output_directory
	if destination_directory.is_empty():
		destination_directory = get_archive_output_directory()
	else:
		destination_directory = ProjectSettings.globalize_path(destination_directory)
	if not DirAccess.dir_exists_absolute(destination_directory):
		var make_error := DirAccess.make_dir_recursive_absolute(destination_directory)
		if make_error != OK:
			push_error("Cannot create runtime log output directory: %s" % destination_directory)
			return ""

	var timestamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var archive_path := destination_directory.path_join("runtime_logs_%s.zip" % timestamp)
	var writer := ZIPPacker.new()
	var open_error := writer.open(archive_path)
	if open_error != OK:
		push_error("Cannot open runtime log archive: %s (error %s)" % [archive_path, open_error])
		return ""

	var log_root := log_directory
	var log_files: Array[String] = []
	_collect_files_recursive(log_root, log_files)
	for log_path: String in log_files:
		var relative_path := log_path.trim_prefix(log_root).trim_prefix("/").replace("\\", "/")
		if relative_path.is_empty():
			continue
		if writer.start_file("logs/%s" % relative_path) != OK:
			continue
		writer.write_file(FileAccess.get_file_as_bytes(log_path))
		writer.close_file()

	var manifest := (
		"Project: %s\nCreated: %s\nLog source: %s\nFiles: %d\n"
		% [ProjectSettings.get_setting("application/config/name", ""), timestamp, ProjectSettings.globalize_path(log_root), log_files.size()]
	)
	if writer.start_file("archive_manifest.txt") == OK:
		writer.write_file(manifest.to_utf8_buffer())
		writer.close_file()
	writer.close()
	print("Runtime logs archived to: %s" % archive_path)
	return archive_path

func get_archive_output_directory() -> String:
	# globalized res:// is the project root in editor runs and the executable resource root in exports.
	return ProjectSettings.globalize_path("res://").trim_suffix("/").trim_suffix("\\")

func is_motion_tracking_enabled() -> bool:
	return _motion_tracking_enabled

func get_runtime_log_directory() -> String:
	return ProjectSettings.globalize_path("user://logs")

func _emit_motion_snapshot() -> void:
	var controllers := get_tree().get_nodes_in_group(&"leg_step_movement_controllers")
	if controllers.is_empty():
		_append_log_output("[trackmotion] No Character_Test_2 movement controller found.")
		return
	for controller: Node in controllers:
		if not (
			controller.has_method("get_leg_parts")
			and controller.has_method("get_active_leg")
			and controller.has_method("get_leg_adhesion_surface_normal")
		):
			continue
		var character := controller.get_parent()
		var character_name := character.name if character != null else &"UnknownCharacter"
		var active_leg: RigidBody3D = controller.call("get_active_leg") as RigidBody3D
		var release_time: float = float(controller.call("get_adhesion_release_time_remaining"))
		var input_direction: Vector3 = controller.call("get_last_input_direction")
		var step_state: String = controller.call("get_step_state_name")
		var step_target: Vector3 = controller.call("get_step_target")
		var step_target_normal: Vector3 = controller.call("get_step_target_normal")
		var target_distance: float = float(controller.call("get_active_leg_horizontal_target_distance"))
		var timeout_remaining: float = float(controller.call("get_landing_timeout_remaining"))
		var speed_preset: String = controller.call("get_current_speed_preset_name")
		var step_sequence: int = int(controller.call("get_step_sequence"))
		var last_touchdown_leg: StringName = controller.call("get_last_touchdown_leg")
		var touchdown_interval: float = float(controller.call("get_last_touchdown_interval"))
		var lift_remaining: float = float(controller.call("get_fast_lift_time_remaining"))
		var lift_force: float = float(controller.call("get_current_fast_lift_force"))
		var landing_force: Vector3 = controller.call("get_current_fast_landing_force")
		var desired_fast_velocity: Vector3 = controller.call("get_desired_fast_velocity")
		var fast_step_frequency: float = float(controller.call("get_fast_step_frequency"))
		var fast_step_interval: float = float(controller.call("get_fast_step_interval"))
		var torso := character.get_node_or_null("Torso") as RigidBody3D
		var torso_height := torso.global_position.y if torso != null else 0.0
		var torso_vertical_velocity := torso.linear_velocity.y if torso != null else 0.0
		var torso_horizontal_speed := Vector2(torso.linear_velocity.x, torso.linear_velocity.z).length() if torso != null else 0.0
		for leg: RigidBody3D in controller.call("get_leg_parts"):
			var normal: Vector3 = controller.call("get_leg_adhesion_surface_normal", leg)
			var is_moving := leg == active_leg
			var is_attached := not is_moving and release_time <= 0.0 and not normal.is_zero_approx()
			var is_grounded: bool = bool(controller.call("is_leg_grounded", leg))
			var message := (
				"[trackmotion] character=%s leg=%s attached=%s moving=%s grounded=%s state=%s speed=%s input=%s position=%s velocity=%s normal=%s target=%s target_normal=%s target_distance=%.3f landing_timeout=%.3f adhesion_release=%.3f step_sequence=%d last_touchdown=%s touchdown_interval=%.3f torso_y=%.3f torso_vy=%.3f torso_horizontal_speed=%.3f desired_velocity=%s fast_step_frequency=%.3f fast_step_interval=%.3f lift_remaining=%.3f lift_force=%.3f landing_force=%s landing_force_magnitude=%.3f"
				% [
					character_name,
					leg.name,
					is_attached,
					is_moving,
					is_grounded,
					step_state,
					speed_preset,
					_format_vector3(input_direction),
					_format_vector3(leg.global_position),
					_format_vector3(leg.linear_velocity),
					_format_vector3(normal),
					_format_vector3(step_target),
					_format_vector3(step_target_normal),
					target_distance,
					timeout_remaining,
					release_time,
					step_sequence,
					last_touchdown_leg,
					touchdown_interval,
					torso_height,
					torso_vertical_velocity,
					torso_horizontal_speed,
					_format_vector3(desired_fast_velocity),
					fast_step_frequency,
					fast_step_interval,
					lift_remaining,
					lift_force,
					_format_vector3(landing_force),
					landing_force.length(),
				]
			)
			_append_log_output(message)

func _format_vector3(value: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [value.x, value.y, value.z]

func _append_log_output(message: String) -> void:
	_append_output(message)
	print(message)

func _collect_files_recursive(directory_path: String, result: Array[String]) -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory_path)):
		return
	for file_name: String in DirAccess.get_files_at(directory_path):
		result.append(directory_path.path_join(file_name))
	for child_directory: String in DirAccess.get_directories_at(directory_path):
		_collect_files_recursive(directory_path.path_join(child_directory), result)

func _on_command_submitted(command: String) -> void:
	var trimmed := command.strip_edges()
	if not trimmed.is_empty():
		_append_output("> %s" % trimmed)
	var result := execute_command(command)
	if not result.is_empty():
		_append_output(result)
	_command_input.clear()
	_command_input.grab_focus()

func _append_output(message: String) -> void:
	_output_lines.append(message)
	while _output_lines.size() > maximum_output_lines:
		_output_lines.pop_front()
	if is_instance_valid(_output):
		_output.text = "\n".join(_output_lines)
		_output.scroll_to_line(maxi(_output.get_line_count() - 1, 0))
