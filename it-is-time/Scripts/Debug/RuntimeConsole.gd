extends CanvasLayer

const MOTION_PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")

const COMMAND_HELP: Array[Dictionary] = [
	{&"name": "help", &"description": "List all available console commands."},
	{&"name": "getlogs", &"description": "Pack runtime logs into a ZIP in the project root."},
	{&"name": "trackgenerated", &"description": "Toggle generated creature foot, limb-chain and gait diagnostics."},
	{&"name": "trackmotion", &"description": "Toggle all BodyPart motion tracking for the currently controlled character."},
	{&"name": "trackcontrolperf", &"description": "Toggle Controller, cursor, arc and generation timings (inclusive) and frame spikes."},
	{&"name": "trackperformance", &"description": "Toggle runtime performance summaries."},
	{&"name": "tracknpc", &"description": "Toggle NPC navigation and gait diagnostics."},
	{&"name": "trackcollision", &"description": "Toggle BodyPart contact enter/exit and collision configuration logs."},
	{&"name": "trackdamage", &"description": "Toggle weapon impact, HP, break, and joint-removal logs."},
	{&"name": "trackturn", &"description": "Toggle facing decisions, combined walking/turning targets and Leg traction logs."},
	{&"name": "trackswing", &"description": "Toggle Arm swing direction, load, and Joint diagnostics."},
]

# Enable before starting the game to capture first-frame creature generation.
@export var control_performance_on_start: bool = false
@export var toggle_action: StringName = &"CallConsole"
@export_range(10, 1000, 1) var maximum_output_lines: int = 100
@export_range(0.05, 10.0, 0.05, "or_greater") var motion_tracking_interval: float = 0.1
@export_range(0.25, 10.0, 0.25, "or_greater") var performance_tracking_interval: float = 1.0

@onready var _output: RichTextLabel = $ConsoleRoot/Panel/Margin/VBox/Output
@onready var _command_input: LineEdit = $ConsoleRoot/Panel/Margin/VBox/CommandRow/CommandInput

var _control_performance_tracking_enabled: bool = false
var _control_perf_elapsed: float = 0.0
var _control_perf_frames: int = 0
var _control_perf_max_delta: float = 0.0
var _control_perf_slow_frames: int = 0

var _output_lines: Array[String] = []
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _generated_motion_tracking_enabled: bool = false
var _motion_tracking_enabled: bool = false
var _motion_tracking_elapsed: float = 0.0
var _motion_snapshot_sequence: int = 0
var _performance_tracking_enabled: bool = false
var _performance_tracking_elapsed: float = 0.0
var _npc_diagnostic_tracking_enabled: bool = false
var _collision_tracking_enabled: bool = false
var _damage_tracking_enabled: bool = false
var _swing_tracking_enabled: bool = false
var _turn_tracking_enabled: bool = true

func _ready() -> void:
	_control_performance_tracking_enabled = control_performance_on_start
	visible = false
	_command_input.text_submitted.connect(_on_command_submitted)
	_append_output("Runtime console ready. Type 'help' to list available commands.")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(toggle_action):
		get_viewport().set_input_as_handled()
		set_console_open(not visible)

func _process(delta: float) -> void:
	if _control_performance_tracking_enabled:
		_control_perf_elapsed += delta
		_control_perf_frames += 1
		_control_perf_max_delta = maxf(_control_perf_max_delta, delta)
		if delta > 1.0 / 30.0: _control_perf_slow_frames += 1
		if _control_perf_elapsed >= performance_tracking_interval:
			_emit_control_performance_snapshot()
	if _motion_tracking_enabled:
		_motion_tracking_elapsed += delta
		if _motion_tracking_elapsed >= motion_tracking_interval:
			_motion_tracking_elapsed = 0.0
			_emit_motion_snapshot()
	if _performance_tracking_enabled:
		_performance_tracking_elapsed += delta
		if _performance_tracking_elapsed >= performance_tracking_interval:
			_performance_tracking_elapsed = 0.0
			_emit_performance_snapshot()

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
		"help":
			return _get_help_text()
		"getlogs":
			var archive_path := create_logs_archive()
			if archive_path.is_empty():
				return "Failed to create runtime log archive."
			return "Runtime logs archived to: %s" % archive_path
		"trackgenerated":
			_generated_motion_tracking_enabled = not _generated_motion_tracking_enabled
			for controller: Node in get_tree().get_nodes_in_group(&"leg_step_movement_controllers"):
				if controller.has_method("get_generated_movement_diagnostics"):
					controller.call("set_diagnostic_logging_enabled", _generated_motion_tracking_enabled)
					if _generated_motion_tracking_enabled:
						_append_log_output("[generated_gait] %s" % [controller.call("get_generated_movement_diagnostics")])
			return "Generated creature movement tracking %s." % ("enabled" if _generated_motion_tracking_enabled else "disabled")
		"trackmotion":
			_motion_tracking_enabled = not _motion_tracking_enabled
			_motion_tracking_elapsed = 0.0
			if _motion_tracking_enabled:
				_emit_motion_snapshot()
				return "Controlled character BodyPart motion tracking enabled."
			return "Controlled character BodyPart motion tracking disabled."
		"trackcontrolperf":
			_control_performance_tracking_enabled = not _control_performance_tracking_enabled
			_reset_control_performance_window()
			for component: Node in get_tree().get_nodes_in_group(&"control_performance_components"):
				component.set_control_performance_tracking_enabled(_control_performance_tracking_enabled)
			return "Control performance tracking %s. Timings are inclusive; summaries every %.2f seconds." % ["enabled" if _control_performance_tracking_enabled else "disabled", performance_tracking_interval]
		"trackperformance":
			_performance_tracking_enabled = not _performance_tracking_enabled
			_performance_tracking_elapsed = 0.0
			_set_component_performance_tracking(_performance_tracking_enabled)
			if _performance_tracking_enabled:
				_emit_performance_snapshot()
				return "Performance tracking enabled. A summary is logged every %.2f seconds." % performance_tracking_interval
			return "Performance tracking disabled."
		"tracknpc":
			_npc_diagnostic_tracking_enabled = not _npc_diagnostic_tracking_enabled
			_set_npc_diagnostic_tracking(_npc_diagnostic_tracking_enabled)
			if _npc_diagnostic_tracking_enabled:
				return "NPC navigation and gait diagnostics enabled."
			return "NPC navigation and gait diagnostics disabled."
		"trackcollision":
			_collision_tracking_enabled = not _collision_tracking_enabled
			for part: Node in get_tree().get_nodes_in_group(&"physical_body_parts"):
				part.call("set_collision_logging_enabled", _collision_tracking_enabled)
			if _collision_tracking_enabled:
				for actor: Node in get_tree().get_nodes_in_group(&"physical_characters_3d"):
					if actor.has_method("get_internal_collision_diagnostics"):
						_append_log_output("[internal_collision] character=%s audit=%s" % [actor.name, actor.call("get_internal_collision_diagnostics")])
			return "BodyPart collision tracking %s." % ("enabled" if _collision_tracking_enabled else "disabled")
		"trackdamage":
			_damage_tracking_enabled = not _damage_tracking_enabled
			_set_damage_tracking(_damage_tracking_enabled)
			return "Damage tracking %s." % ("enabled" if _damage_tracking_enabled else "disabled")
		"trackturn":
			_turn_tracking_enabled = not _turn_tracking_enabled
			for controller: Node in get_tree().get_nodes_in_group(&"physical_facing_controllers_3d"):
				controller.call("set_diagnostic_logging_enabled", _turn_tracking_enabled)
			return "Turning tracking %s." % ("enabled" if _turn_tracking_enabled else "disabled")
		"trackswing":
			_swing_tracking_enabled = not _swing_tracking_enabled
			_set_swing_tracking(_swing_tracking_enabled)
			return "Arm swing tracking %s." % ("enabled" if _swing_tracking_enabled else "disabled")
		"":
			return ""
		_:
			return "Unknown command: %s" % command.strip_edges()

func _get_help_text() -> String:
	var lines: Array[String] = ["Available commands:"]
	for entry: Dictionary in COMMAND_HELP:
		lines.append("  %-16s %s" % [entry.name, entry.description])
	return "\n".join(lines)

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

func is_generated_motion_tracking_enabled() -> bool:
	return _generated_motion_tracking_enabled

func is_motion_tracking_enabled() -> bool:
	return _motion_tracking_enabled

func is_performance_tracking_enabled() -> bool:
	return _performance_tracking_enabled

func is_npc_diagnostic_tracking_enabled() -> bool:
	return _npc_diagnostic_tracking_enabled

func is_collision_tracking_enabled() -> bool:
	return _collision_tracking_enabled

func is_damage_tracking_enabled() -> bool:
	return _damage_tracking_enabled

func is_turn_tracking_enabled() -> bool:
	return _turn_tracking_enabled

func is_swing_tracking_enabled() -> bool:
	return _swing_tracking_enabled

func _set_damage_tracking(enabled: bool) -> void:
	for component: Node in get_tree().get_nodes_in_group(&"damage_components"):
		if component.has_method("set_damage_logging_enabled"):
			component.call("set_damage_logging_enabled", enabled)

func _set_swing_tracking(enabled: bool) -> void:
	for controller: Node in get_tree().get_nodes_in_group(&"limb_swing_controllers"):
		if controller.has_method("set_diagnostic_logging_enabled"):
			controller.call("set_diagnostic_logging_enabled", enabled)

func _set_npc_diagnostic_tracking(enabled: bool) -> void:
	for state_machine: Node in get_tree().get_nodes_in_group(&"npc_state_machines"):
		if state_machine.has_method("set_diagnostic_logging_enabled"):
			state_machine.call("set_diagnostic_logging_enabled", enabled)
	for controller: Node in get_tree().get_nodes_in_group(&"leg_step_movement_controllers"):
		var character := controller.get_parent()
		if character == null or not character.has_node("NPCStateMachine3D"):
			continue
		if controller.has_method("set_diagnostic_logging_enabled"):
			controller.call("set_diagnostic_logging_enabled", enabled)

func get_runtime_log_directory() -> String:
	return ProjectSettings.globalize_path("user://logs")

func _emit_motion_snapshot() -> void:
	var messages := _collect_motion_snapshot()
	# Refresh the visible log once per snapshot rather than once per body.
	_output_lines.append_array(messages)
	while _output_lines.size() > maximum_output_lines: _output_lines.pop_front()
	if is_instance_valid(_output): _output.text = "\n".join(_output_lines)
	print("\n".join(messages))

func _collect_motion_snapshot() -> Array[String]:
	var messages: Array[String] = []
	var character := MOTION_PLAYER_CONTEXT.controlled_character(self)
	if not is_instance_valid(character):
		messages.append("[trackmotion] No controlled character (Controller detached or no target).")
		return messages
	_motion_snapshot_sequence += 1
	var parts: Array[PhysicalBodyPart3D] = []
	for node: Node in character.find_children("*", "RigidBody3D", true, false):
		if node is PhysicalBodyPart3D and not node.is_queued_for_deletion(): parts.append(node)
	var recovery := character.get_node_or_null("CreatureRecoveryStateMachine3D")
	messages.append("[trackmotion] snapshot=%d physics_frame=%d time_ms=%d character=%s character_path=%s parts=%d recovery=%s" % [
		_motion_snapshot_sequence, Engine.get_physics_frames(), Time.get_ticks_msec(), character.name, character.get_path(), parts.size(),
		recovery.get_recovery_diagnostics() if recovery != null else {}])
	for part: PhysicalBodyPart3D in parts:
		var tags := PackedStringArray()
		for tag: int in part.tags: tags.append(PhysicalBodyPart3D.BodyPartTag.keys()[tag])
		messages.append("[trackmotion] character=%s part=%s path=%s id=%d tags=%s role=%s segment=%d position=%s local_position=%s rotation_degrees=%s velocity=%s linear_speed=%.3f angular_velocity=%s angular_speed=%.3f moving=%s sleeping=%s frozen=%s mass=%.3f gravity_scale=%.3f hp=%.3f max_hp=%.3f broken=%s" % [
			character.name, part.name, character.get_path_to(part), part.get_instance_id(), tags,
			part.get_meta(&"generated_role", "BodyPart"), int(part.get_meta(&"body_segment_id", -1)), _format_vector3(part.global_position), _format_vector3(part.position),
			_format_vector3(part.global_rotation * (180.0 / PI)), _format_vector3(part.linear_velocity), part.linear_velocity.length(),
			_format_vector3(part.angular_velocity), part.angular_velocity.length(),
			part.linear_velocity.length_squared() > 0.0001 or part.angular_velocity.length_squared() > 0.0001,
			part.sleeping, part.freeze, part.mass, part.gravity_scale, part.current_hp, part.max_hp, part.is_broken])
	# Preserve the detailed gait fields, limited to the selected actor's controllers.
	for controller: Node in get_tree().get_nodes_in_group(&"leg_step_movement_controllers"):
		if controller.get_parent() == character:
			messages.append_array(_collect_leg_motion_lines(controller))
			if controller.has_method("get_automatic_motion_diagnostics"):
				messages.append("[trackmotion] character=%s automatic_motion=%s" % [character.name, controller.call("get_automatic_motion_diagnostics")])
			if controller.has_method("get_contact_drive_diagnostics"):
				messages.append("[trackmotion] character=%s contact_drive=%s" % [character.name, controller.call("get_contact_drive_diagnostics")])
			if controller.has_method("get_stance_support_diagnostics"):
				var support: Dictionary = controller.call("get_stance_support_diagnostics")
				for foot: RigidBody3D in controller.call("get_leg_parts"):
					messages.append("[trackmotion] character=%s foot=%s rotation_lock_x=%s rotation_lock_y=%s rotation_lock_z=%s slipping=%s ground_pin=%s anchor_drift=%.4f angular_velocity=%s" % [character.name, foot.name, foot.axis_lock_angular_x, foot.axis_lock_angular_y, foot.axis_lock_angular_z, controller.call("is_leg_slipping", foot), controller.call("get_support_foot_diagnostics", foot).locked, controller.call("get_support_foot_diagnostics", foot).drift, foot.angular_velocity])
				var constraints: Array = support.get("segment_rotation_constraints", [])
				support.erase("segment_rotation_constraints")
				for constraint: Dictionary in constraints:
					messages.append("[trackmotion] character=%s segment_constraint=%s" % [character.name, constraint])
				var joints: Array = support.get("joints", [])
				support.erase("joints")
				messages.append("[trackmotion] character=%s stance_support=%s" % [character.name, support])
				for joint: Dictionary in joints:
					messages.append("[trackmotion] character=%s stance_joint=%s" % [character.name, joint])
	var head_support := character.get_node_or_null("HeadPositionSupport3D")
	if head_support != null:
		for row: Dictionary in head_support.get_head_support_diagnostics():
			messages.append("[trackmotion] character=%s head_support=%s" % [character.name,row])

	return messages

func _collect_leg_motion_lines(controller: Node) -> Array[String]:
	var messages: Array[String] = []
	var character := controller.get_parent()
	var character_name := character.name if character != null else &"UnknownCharacter"
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
	var fast_mode_active: bool = bool(controller.call("is_fast_speed_active"))
	var torso_force_support_legs: Array = controller.call(
		"get_torso_movement_force_legs",
		fast_mode_active
	)
	var torso_force_grace: float = float(controller.call("get_fast_airborne_force_grace_remaining"))
	var torso := controller.get_node_or_null(controller.get("torso_path")) as RigidBody3D
	var torso_height := torso.global_position.y if torso != null else 0.0
	var torso_vertical_velocity := torso.linear_velocity.y if torso != null else 0.0
	var torso_horizontal_speed := Vector2(torso.linear_velocity.x, torso.linear_velocity.z).length() if torso != null else 0.0
	for leg: RigidBody3D in controller.call("get_leg_parts"):
		var normal: Vector3 = controller.call("get_leg_adhesion_surface_normal", leg)
		var is_moving: bool = controller.call("is_leg_stepping", leg)
		var leg_step: Dictionary = controller.call("get_leg_step_diagnostics", leg)
		step_sequence = leg_step.sequence
		step_state = leg_step.state
		step_target = leg_step.target
		step_target_normal = leg_step.normal
		target_distance = leg_step.distance
		timeout_remaining = leg_step.timeout
		var is_attached := not is_moving and release_time <= 0.0 and not normal.is_zero_approx()
		var is_grounded: bool = bool(controller.call("is_leg_grounded", leg))
		var message := (
			"[trackmotion] character=%s leg=%s attached=%s moving=%s grounded=%s state=%s speed=%s input=%s position=%s velocity=%s normal=%s target=%s target_normal=%s target_distance=%.3f landing_timeout=%.3f adhesion_release=%.3f torso_force_support_count=%d torso_force_grace=%.3f step_sequence=%d last_touchdown=%s touchdown_interval=%.3f torso_y=%.3f torso_vy=%.3f torso_horizontal_speed=%.3f desired_velocity=%s fast_step_frequency=%.3f fast_step_interval=%.3f lift_remaining=%.3f lift_force=%.3f landing_force=%s landing_force_magnitude=%.3f"
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
				torso_force_support_legs.size(),
				torso_force_grace,
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
		if controller.has_method("get_support_foot_diagnostics"):
			var support: Dictionary = controller.call("get_support_foot_diagnostics", leg)
			message += " foot_locked=%s foot_anchor=%s foot_drift=%.3f foot_speed=%.3f support_force=%s brake_force=%s expected_speed=%.3f" % [
				support.locked, _format_vector3(support.anchor), support.drift,
				support.speed, _format_vector3(support.force), _format_vector3(support.brake_force), support.expected_speed]
			if support.has("foot_heading"):
				message += " foot_yaw_locked=%s foot_heading=%s" % [support.get("foot_yaw_locked", false), support.foot_heading]
			message += " adhesion_force=%s ground_gap=%.3f alignment_torque=%s" % [
				_format_vector3(support.get("adhesion_force", Vector3.ZERO)),
				float(support.get("ground_gap", -1.0)),
				_format_vector3(support.get("alignment_torque", Vector3.ZERO))]
			if support.has("step_tracking_force"):
				message += " step_force=%s gravity_feedforward=%s drive_mass=%.3f drive_cap=%.3f drive_limited=%s drive_error=%s lifted=%s failed_steps=%d last_failure=%s" % [
					_format_vector3(support.step_tracking_force), _format_vector3(support.step_gravity_force),
					support.step_effective_mass, support.step_force_limit, support.step_force_limited,
					_format_vector3(support.step_position_error), support.step_has_lifted,
					support.failed_steps, support.last_step_failure]
		if controller.has_method("get_support_foot_diagnostics"):
			var gallop: Dictionary = controller.call("get_support_foot_diagnostics",leg).get("gallop",{})
			if not gallop.is_empty(): message += " gallop=%s" % [gallop]
		message += " stepping_limit=%d planned_frequency=%.3f" % [controller.call("get_maximum_stepping_feet"), controller.call("get_planned_step_frequency")]
		messages.append(message)

	return messages

func _set_component_performance_tracking(enabled: bool) -> void:
	for group_name: StringName in [
		&"leg_step_movement_controllers",
		&"auto_outline_components",
		&"npc_state_machines",
	]:
		for component: Node in get_tree().get_nodes_in_group(group_name):
			if component.has_method("set_performance_tracking_enabled"):
				if (
					component.has_method("is_performance_tracking_enabled")
					and bool(component.call("is_performance_tracking_enabled")) == enabled
				):
					continue
				component.call("set_performance_tracking_enabled", enabled)

func _emit_performance_snapshot() -> void:
	# Newly spawned components join tracking before their first aggregate is consumed.
	_set_component_performance_tracking(true)
	var controller_stats := _consume_group_performance(&"leg_step_movement_controllers")
	var outline_stats := _consume_group_performance(&"auto_outline_components")
	var navigation_stats := _consume_group_performance(&"npc_state_machines")
	var global_message := (
		"[trackperformance] fps=%.1f process_ms=%.3f physics_ms=%.3f navigation_ms=%.3f nodes=%d "
		+ "draw_calls=%d primitives=%d active_3d_bodies=%d collision_pairs_3d=%d islands_3d=%d static_memory_mb=%.2f"
	) % [
		Performance.get_monitor(Performance.TIME_FPS),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0),
	]
	_append_log_output(global_message)
	_append_log_output(
		("[trackperformance] controllers=%d controller_total_ms=%.3f controller_max_ms=%.3f "
		+ "controller_frames=%d ray_queries=%d shape_queries=%d") % [
			controller_stats.components,
			float(controller_stats.total_usec) / 1000.0,
			float(controller_stats.max_usec) / 1000.0,
			controller_stats.physics_frames,
			controller_stats.ray_queries,
			controller_stats.shape_queries,
		]
	)
	_append_log_output(
		("[trackperformance] outlines=%d enabled_outlines=%d outline_total_ms=%.3f outline_max_ms=%.3f "
		+ "outline_frames=%d outline_target_visits=%d mesh_rebuilds=%d outline_entries=%d") % [
			outline_stats.components,
			outline_stats.enabled,
			float(outline_stats.total_usec) / 1000.0,
			float(outline_stats.max_usec) / 1000.0,
			outline_stats.process_calls,
			outline_stats.target_visits,
			outline_stats.mesh_rebuilds,
			outline_stats.entries,
		]
	)
	_append_log_output(
		("[trackperformance] navigation_agents=%d navigation_total_ms=%.3f navigation_max_ms=%.3f "
		+ "navigation_frames=%d target_refreshes=%d repaths=%d map_projections=%d") % [
			navigation_stats.components,
			float(navigation_stats.total_usec) / 1000.0,
			float(navigation_stats.max_usec) / 1000.0,
			navigation_stats.physics_frames,
			navigation_stats.target_refreshes,
			navigation_stats.repaths,
			navigation_stats.map_projections,
		]
	)

func _consume_group_performance(group_name: StringName) -> Dictionary:
	var total := {
		&"components": 0,
		&"enabled": 0,
		&"physics_frames": 0,
		&"process_calls": 0,
		&"ray_queries": 0,
		&"shape_queries": 0,
		&"target_visits": 0,
		&"mesh_rebuilds": 0,
		&"entries": 0,
		&"target_refreshes": 0,
		&"repaths": 0,
		&"map_projections": 0,
		&"total_usec": 0,
		&"max_usec": 0,
	}
	for component: Node in get_tree().get_nodes_in_group(group_name):
		if not component.has_method("consume_performance_stats"):
			continue
		var stats: Dictionary = component.call("consume_performance_stats")
		if group_name == &"leg_step_movement_controllers":
			var frames: int = stats.get(&"physics_frames", 0)
			_append_log_output("[trackperformance] movement_component=%s frames=%d total_ms=%.3f avg_ms=%.3f max_ms=%.3f ray_queries=%d shape_queries=%d" % [component.get_path(), frames,
				float(stats.get(&"total_usec", 0)) / 1000.0, float(stats.get(&"total_usec", 0)) / maxi(frames, 1) / 1000.0,
				float(stats.get(&"max_usec", 0)) / 1000.0, stats.get(&"ray_queries", 0), stats.get(&"shape_queries", 0)])
		total.components += 1
		for key: StringName in stats:
			if key == &"enabled":
				total.enabled += 1 if stats[key] else 0
			elif key == &"max_usec":
				total.max_usec = maxi(total.max_usec, int(stats[key]))
			elif total.has(key):
				total[key] += int(stats[key])
	return total

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

func is_control_performance_tracking_enabled() -> bool:
	return _control_performance_tracking_enabled

func _reset_control_performance_window() -> void:
	_control_perf_elapsed = 0.0
	_control_perf_frames = 0
	_control_perf_max_delta = 0.0
	_control_perf_slow_frames = 0

func _emit_control_performance_snapshot() -> void:
	var window := _control_perf_elapsed
	_append_log_output("[trackcontrolperf] window_s=%.3f frames=%d frame_avg_ms=%.3f frame_max_ms=%.3f frames_over_33ms=%d process_ms=%.3f physics_ms=%.3f active_bodies=%d collision_pairs=%d timings=inclusive" % [
		window, _control_perf_frames, window * 1000.0 / maxi(_control_perf_frames, 1),
		_control_perf_max_delta * 1000.0, _control_perf_slow_frames,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))])
	for component: Node in get_tree().get_nodes_in_group(&"control_performance_components"):
		var stats: Dictionary = component.consume_control_performance_stats()
		if stats.timings.is_empty() and stats.counters.is_empty(): continue
		var phases: PackedStringArray = []
		for phase: StringName in stats.timings:
			var entry: Dictionary = stats.timings[phase]
			phases.append("%s{calls=%d,total_ms=%.3f,avg_ms=%.3f,max_ms=%.3f}" % [phase, entry.calls,
				float(entry.total_usec) / 1000.0, float(entry.total_usec) / maxi(int(entry.calls), 1) / 1000.0, float(entry.max_usec) / 1000.0])
		var target := ""
		if component.has_method("get_controlled_character"):
			var character: Node = component.get_controlled_character()
			target = " attached=%s target=%s wheel_open=%s" % [character != null, character.name if character != null else &"none", component.wheel.visible]
		elif component.has_method("get_selected_character"):
			var selected: Node = component.get_selected_character()
			target = " selected=%s" % [selected.name if selected != null else &"none"]
		_append_log_output("[trackcontrolperf] component=%s%s phases=[%s] counters=%s" % [component.get_path(), target, "; ".join(phases), stats.counters])
	_reset_control_performance_window()
