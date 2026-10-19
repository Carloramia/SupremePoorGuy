extends CanvasLayer
const L10N = preload("res://Scripts/Localization/GameText.gd")

const MOTION_PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")
const PERF = preload("res://Scripts/Debug/ControlPerformanceStats.gd")
var _performance_mode: Resource = preload("res://Resources/Settings/PerformanceOptimization.tres")
const JOINT_DIAGNOSTICS = preload("res://Scripts/Debug/JointMotionDiagnostics3D.gd")
const STEP_TARGET_DISPLAY = preload("res://Scripts/Debug/StepTargetDisplay3D.gd")
var _step_target_display: Node3D
const SNAKE_PATH_DISPLAY = preload("res://Scripts/Debug/SnakePathDisplay3D.gd")
var _snake_path_display: Node3D
const ATTACK_COLLISION_DISPLAY = preload("res://Scripts/Debug/AttackCollisionDisplay3D.gd")
var _attack_collision_display: Node

const COMMAND_HELP: Array[Dictionary] = [
	{&"name":"trackmap [on|off|status]",&"description":"Track map clicks, travel, interaction refusals, encounter rolls, events and battle returns; event-based, off by default."},
	{&"name":"mapstate [location_id]",&"description":"Print current map/input/pending state; optionally inspect a location's visibility, conditions and interaction refusal."},
	{&"name":"trackintegration [on|off|status]",&"description":"Track application routes, transactions, save failures and battle lifecycle."},
	{&"name": "perfmode [on|off|status]", &"description": "Switch shared NPC performance optimizations; independent of diagnostic tracking."},
	{&"name": "trackjoints [on|off] [filter]", &"description": "Track joint reference rotations, limits and anchor gaps; filter by character name, path or ID."},
	{&"name": "jointstates [filter]", &"description": "Print joint snapshots reconstructed from activation frames (not private solver angles)."},
	{&"name": "showsteptargets [on|off]", &"description": "Toggle world-space planned landing rings; each foot has a fixed color."},
	{&"name": "showattackboxes [on|off|status]", &"description": "Draw all temporary attack volumes and active weapon colliders; red=damage enabled, orange=inactive temporary volume."},
	{&"name": "showsnakepath [on|off] [filter]", &"description": "Draw Snake routes on terrain: cyan history, orange preview; filter by character name, path or ID."},
	{&"name": "motiondetail [summary|full]", &"description": "Choose compact gait summaries (default) or full BodyPart snapshots for motion tracking."},
	{&"name": "trackcharge", &"description": "Toggle charge phases, torso speeds/forces, support foot locks/steps and stuck timers every 0.1s."},
	{&"name": "help", &"description": "List all available console commands."},
	{&"name": "getlogs", &"description": "Pack runtime logs into a ZIP and print its output path."},
	{&"name": "autogetlogs [on|off|status]", &"description": "Automatically archive logs on debugger breaks or runtime errors; on rearms immediately; warnings are ignored."},
	{&"name": "trackgenerated", &"description": "Toggle generated creature foot, limb-chain and gait diagnostics."},
	{&"name": "trackflight [on|off]", &"description": "Track controlled bird flight, dive attacks, landing, wing torques and feather errors every 0.1s."},
	{&"name": "trackmotion", &"description": "Toggle controlled character motion tracking; use motiondetail to choose summary/full."},
	{&"name": "trackcontrolperf", &"description": "Toggle Controller, cursor, arc and generation timings (inclusive) and frame spikes."},
	{&"name": "trackperformance", &"description": "Toggle runtime performance summaries."},
	{&"name": "tracknpc", &"description": "Toggle NPC navigation and gait diagnostics."},
	{&"name": "tracknpcmotion [on|off] [filter]", &"description": "Track NPC gait every 0.1s; filter by name, path or ID; motiondetail full adds all BodyParts."},
	{&"name": "tracknpcstate [on|off] [filter]", &"description": "Track FSM changes and snapshots; filter by NPC name, full path or instance ID."},
	{&"name": "npcstates [filter]", &"description": "Print a one-time NPC state-machine snapshot."},
	{&"name": "trackcollision", &"description": "Toggle BodyPart contact enter/exit and collision configuration logs."},
	{&"name": "trackdamage", &"description": "Toggle weapon/shockwave/dive impact, HP, break, and joint-removal logs."},
	{&"name": "trackwolfattacks [on|off] [filter]", &"description": "Track Wolf attacks and Rat static-target bites (preparation, locked point, arrival and jaw closure)."},
	{&"name": "tracksnakeattacks [on|off] [filter]", &"description": "Track Snake preparation, lunge, jaw motion, hits and cancellation every 0.1s."},
	{&"name": "trackturn", &"description": "Toggle facing decisions, combined walking/turning targets and Leg traction logs."},
	{&"name": "trackswing", &"description": "Toggle Arm swing direction, load, and Joint diagnostics."},
	{&"name": "trackgrip [on|off] [filter]", &"description": "Track equipment/grip changes and binding alignment every 0.1s; filter by character name, path or ID."},
	{&"name": "trackbow [on|off|status] [filter]", &"description": "Track Bow pose, joint torques, string/draw reactions every 0.1s and exact phase/shot events; off by default."},
	{&"name": "gripstates [filter]", &"description": "Print a one-time equipment/grip snapshot, including empty inventories."},
]

# Enable before starting the game to capture first-frame creature generation.
@export var control_performance_on_start: bool = false
@export var toggle_action: StringName = &"CallConsole"
@export var auto_getlogs_enabled: bool = true
@export_range(1.0,300.0,1.0,"or_greater") var auto_getlogs_cooldown: float = 30.0
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
var _map_tracking_enabled := false
var _map_event_sequence := 0
var _output_dirty := false
var _output_refresh_elapsed := 0.0
var _full_motion_details := false
var _logger_perf := PERF.new()
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _generated_motion_tracking_enabled: bool = false
var _charge_tracking_enabled := false
var _flight_tracking_enabled := false
var _flight_tracking_elapsed := 0.0
var _motion_tracking_enabled: bool = false
var _motion_tracking_elapsed: float = 0.0
var _motion_snapshot_sequence: int = 0
var _performance_tracking_enabled: bool = false
var _performance_tracking_elapsed: float = 0.0
var _npc_diagnostic_tracking_enabled: bool = false
var _npc_motion_tracking_enabled: bool = false
var _npc_motion_filter: String = ""
var _npc_motion_elapsed: float = 0.0
var _npc_state_tracking_enabled := false
var _npc_state_filter := ""
var _npc_state_elapsed := 0.0
var _joint_tracking_enabled := false
var _joint_tracking_filter := ""
var _joint_tracking_elapsed := 0.0
var _joint_last_physics_frame := -1
@export_range(0.1,10.0,0.1) var npc_state_tracking_interval: float = 0.5
var _collision_tracking_enabled: bool = false
var _damage_tracking_enabled: bool = false
var _wolf_attack_tracking_enabled := false
var _wolf_attack_filter := ""
var _snake_attack_tracking_enabled := false
var _snake_attack_filter := ""
var _swing_tracking_enabled: bool = false
var _grip_tracking_enabled := false
var _grip_tracking_filter := ""
var _grip_tracking_elapsed := 0.0
var _bow_tracking_enabled := false
var _bow_tracking_filter := ""
var _bow_tracking_elapsed := 0.0
var _turn_tracking_enabled: bool = true
var _error_capture := preload("res://Scripts/Debug/RuntimeErrorLogCapture.gd").new()
var _archive_mutex := Mutex.new()
var _auto_archiving := false
var _last_auto_archive_time: int = -1
var _last_auto_archive_path := ""
var _archive_bridge_connected := false

func _enter_tree() -> void:
	OS.add_logger(_error_capture)
	if EngineDebugger.is_active(): EngineDebugger.register_message_capture("runtime_console",_capture_debugger_message)

func _exit_tree() -> void:
	OS.remove_logger(_error_capture)
	if EngineDebugger.has_capture("runtime_console"): EngineDebugger.unregister_message_capture("runtime_console")

func _capture_debugger_message(message: String, _data: Array) -> bool:
	if message == "bridge_ready":
		_archive_bridge_connected = true
		print("[auto_getlogs] editor breakpoint bridge connected")
		return true
	if message != "archive_on_break": return false
	print("[auto_getlogs] debugger break received")
	var context := _error_capture.take_error()
	context["trigger"] = "debugger_break"
	var traces: Array[String] = []
	for trace: ScriptBacktrace in Engine.capture_script_backtraces(): traces.append(trace.format())
	context["paused_backtraces"] = traces
	var path := _try_auto_archive(context)
	if path.is_empty(): print("[auto_getlogs] archive skipped; enabled=%s cooldown=%.1fs last=%s" % [auto_getlogs_enabled,auto_getlogs_cooldown,_last_auto_archive_path])
	if EngineDebugger.is_active(): EngineDebugger.send_message("runtime_console:archive_result",[path])
	return true

func _try_auto_archive(context: Dictionary) -> String:
	_archive_mutex.lock()
	var now := Time.get_ticks_msec()
	if not auto_getlogs_enabled or _auto_archiving or (_last_auto_archive_time >= 0 and now-_last_auto_archive_time < auto_getlogs_cooldown*1000.0):
		_archive_mutex.unlock()
		return ""
	_auto_archiving = true
	_last_auto_archive_time = now
	_archive_mutex.unlock()
	var path := create_logs_archive("","user://logs",context)
	_archive_mutex.lock()
	_last_auto_archive_path = path
	_auto_archiving = false
	_archive_mutex.unlock()
	_append_output.call_deferred("[auto_getlogs] "+("Archive failed; check output for the reason." if path.is_empty() else path))
	return path

func _ready() -> void:
	_control_performance_tracking_enabled = control_performance_on_start
	_logger_perf.register(self)
	_logger_perf.set_enabled(_control_performance_tracking_enabled)
	visible = false
	_command_input.text_submitted.connect(_on_command_submitted)
	_append_output("Runtime console ready. Type 'help' to list available commands.")
	print("[auto_getlogs] enabled=%s cooldown=%.1fs debugger_attached=%s" % [auto_getlogs_enabled,auto_getlogs_cooldown,EngineDebugger.is_active()])
	if EngineDebugger.is_active():
		EngineDebugger.send_message("runtime_console:ready",[])
		get_tree().create_timer(3.0).timeout.connect(_check_archive_bridge)

func _check_archive_bridge() -> void:
	if auto_getlogs_enabled and not _archive_bridge_connected:
		print("[auto_getlogs] editor breakpoint bridge is not connected; enable Runtime Log Archive in Project Settings > Plugins, or reopen the Godot project. Runtime error archives will wait until execution resumes.")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(toggle_action):
		get_viewport().set_input_as_handled()
		set_console_open(not visible)

func _process(delta: float) -> void:
	if _bow_tracking_enabled:
		_bow_tracking_elapsed += delta
		if _bow_tracking_elapsed>=motion_tracking_interval:
			_bow_tracking_elapsed = 0.0
			_emit_bow_snapshot()
	var error := _error_capture.take_error()
	if not error.is_empty(): _try_auto_archive(error)
	_output_refresh_elapsed += delta
	if _grip_tracking_enabled:
		_grip_tracking_elapsed += delta
		if _grip_tracking_elapsed >= motion_tracking_interval:
			_grip_tracking_elapsed = 0.0
			_emit_weapon_grip_snapshot(_grip_tracking_filter)
	if _joint_tracking_enabled:
		_joint_tracking_elapsed += delta
		if _joint_tracking_elapsed >= motion_tracking_interval and _joint_last_physics_frame != Engine.get_physics_frames():
			_joint_tracking_elapsed = 0.0
			_emit_joint_snapshot(_joint_tracking_filter)
	if _flight_tracking_enabled and not _motion_tracking_enabled:
		_flight_tracking_elapsed += delta
		if _flight_tracking_elapsed >= motion_tracking_interval:
			_flight_tracking_elapsed = 0.0
			_emit_flight_snapshot()
	if _npc_motion_tracking_enabled:
		_npc_motion_elapsed += delta
		if _npc_motion_elapsed >= motion_tracking_interval:
			_npc_motion_elapsed = 0.0
			_emit_npc_motion_snapshot()
	if _npc_state_tracking_enabled:
		_npc_state_elapsed += delta
		if _npc_state_elapsed >= npc_state_tracking_interval:
			_npc_state_elapsed = 0.0
			_emit_npc_state_snapshot(_npc_state_filter)
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
	if visible and _output_dirty and _output_refresh_elapsed >= 0.1:
		_refresh_output_text()

func set_console_open(open: bool) -> void:
	if visible == open:
		return
	visible = open
	if open:
		_refresh_output_text()
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
	var args := command.strip_edges().split(" ",false)
	if not args.is_empty() and args[0].to_lower()=="autogetlogs":
		if args.size()!=2 or args[1].to_lower() not in ["on","off","status"]: return "Usage: autogetlogs [on|off|status]"
		_archive_mutex.lock()
		if args[1].to_lower()!="status":
			auto_getlogs_enabled = args[1].to_lower()=="on"
			if auto_getlogs_enabled: _last_auto_archive_time = -1
		var result := "Automatic log archives %s; cooldown=%.1fs; bridge=%s; last=%s" % ["enabled" if auto_getlogs_enabled else "disabled",auto_getlogs_cooldown,"connected" if _archive_bridge_connected else "not_connected",_last_auto_archive_path]
		_archive_mutex.unlock()
		return result
	if not args.is_empty() and args[0].to_lower()=="trackmap":
		if args.size()>2 or (args.size()==2 and args[1].to_lower() not in ["on","off","status"]): return "Usage: trackmap [on|off|status]"
		if args.size()==1: _map_tracking_enabled = not _map_tracking_enabled
		elif args[1].to_lower()!="status": _map_tracking_enabled = args[1].to_lower()=="on"
		var host := MOTION_PLAYER_CONTEXT.application(self)
		if host!=null and is_instance_valid(host.delivery_map): host.delivery_map.set_map_diagnostic_logging(_map_tracking_enabled)
		if _map_tracking_enabled and (args.size()==1 or args[1].to_lower()=="on") and host!=null:
			log_map_event("snapshot",host.get_map_diagnostics())
		return "Map tracking: %s; event-based; %s" % ["enabled" if _map_tracking_enabled else "disabled","phase="+host.phase if host!=null else "waiting for GameRoot"]
	if not args.is_empty() and args[0].to_lower()=="mapstate":
		if args.size()>2: return "Usage: mapstate [location_id]"
		var host := MOTION_PLAYER_CONTEXT.application(self)
		if host==null: return "Application host is not active (open GameRoot)."
		log_map_event("snapshot",host.get_map_diagnostics(args[1] if args.size()==2 else ""),true)
		return "Map snapshot printed with [map_event]."
	if not args.is_empty() and args[0].to_lower()=="trackintegration":
		var host := MOTION_PLAYER_CONTEXT.application(self)
		if host == null: return "Application host is not active (open GameRoot)."
		if args.size()>2 or (args.size()==2 and args[1] not in ["on","off","status"]): return "Usage: trackintegration [on|off|status]"
		if args.size()==1: host.session.integration_logging = not host.session.integration_logging
		elif args[1]!="status": host.session.integration_logging = args[1]=="on"
		return "Integration tracking: %s; phase=%s" % [host.session.integration_logging,host.phase]
	if not args.is_empty() and args[0].to_lower() == "gripstates":
		return "Weapon grip snapshots: %d" % _emit_weapon_grip_snapshot(" ".join(args.slice(1)))
	if not args.is_empty() and args[0].to_lower()=="trackbow":
		if args.size()==1: _bow_tracking_enabled = not _bow_tracking_enabled
		elif args[1].to_lower() in ["on","off","status"]:
			if args[1].to_lower()!="status":
				_bow_tracking_enabled = args[1].to_lower()=="on"
				_bow_tracking_filter = " ".join(args.slice(2))
		else: return "Usage: trackbow [on|off|status] [character name, path or instance ID]"
		return "Bow tracking %s; matched=%d; interval=%.2fs" % ["enabled" if _bow_tracking_enabled else "disabled",_emit_bow_snapshot() if _bow_tracking_enabled else 0,motion_tracking_interval]
	if not args.is_empty() and args[0].to_lower() == "trackgrip":
		if args.size() == 1:
			_grip_tracking_enabled = not _grip_tracking_enabled
			_grip_tracking_filter = ""
		elif args[1].to_lower() in ["on", "off"]:
			_grip_tracking_enabled = args[1].to_lower() == "on"
			_grip_tracking_filter = " ".join(args.slice(2))
		else: return "Usage: trackgrip [on|off] [character name, path or instance ID]"
		_grip_tracking_elapsed = 0.0
		var count := _emit_weapon_grip_snapshot(_grip_tracking_filter) if _grip_tracking_enabled else 0
		return "Weapon grip tracking %s; filter=%s; matched=%d; interval=%.2fs" % ["enabled" if _grip_tracking_enabled else "disabled", _grip_tracking_filter if not _grip_tracking_filter.is_empty() else "all", count, motion_tracking_interval]
	if not args.is_empty() and args[0].to_lower() == "perfmode":
		if args.size() > 2 or (args.size() == 2 and args[1].to_lower() not in ["on", "off", "status"]): return "Usage: perfmode [on|off|status]"
		if args.size() == 1: _performance_mode.set(&"enabled", not _performance_mode.enabled)
		elif args[1].to_lower() != "status": _performance_mode.set(&"enabled", args[1].to_lower() == "on")
		var message := "Performance optimization: %s; AI planning interval: %.3fs; physics updates unchanged." % ["ON" if _performance_mode.enabled else "OFF", _performance_mode.ai_decision_interval]
		_append_log_output("[perfmode] " + message)
		return message
	if not args.is_empty() and args[0].to_lower() == "tracksnakeattacks":
		if args.size() == 1: _snake_attack_tracking_enabled = not _snake_attack_tracking_enabled
		elif args[1].to_lower() in ["on","off"]:
			_snake_attack_tracking_enabled = args[1].to_lower() == "on"
			_snake_attack_filter = " ".join(args.slice(2))
		else: return "Usage: tracksnakeattacks [on|off] [character name, path or instance ID]"
		for controller: Node in get_tree().get_nodes_in_group(&"snake_attack_controllers"):
			controller.diagnostic_logging = is_snake_attack_tracking_enabled(controller.get_parent())
		return "Snake attack tracking %s; filter=%s." % ["enabled" if _snake_attack_tracking_enabled else "disabled",_snake_attack_filter if not _snake_attack_filter.is_empty() else "all"]
	if not args.is_empty() and args[0].to_lower() == "trackwolfattacks":
		if args.size() == 1: _wolf_attack_tracking_enabled = not _wolf_attack_tracking_enabled
		elif args[1].to_lower() in ["on","off"]:
			_wolf_attack_tracking_enabled = args[1].to_lower() == "on"
			_wolf_attack_filter = " ".join(args.slice(2))
		else: return "Usage: trackwolfattacks [on|off] [character name, path or instance ID]"
		for controller: Node in get_tree().get_nodes_in_group(&"wolf_attack_controllers"):
			controller.diagnostic_logging = is_wolf_attack_tracking_enabled(controller.get_parent())
		return "Wolf attack tracking %s; filter=%s." % ["enabled" if _wolf_attack_tracking_enabled else "disabled",_wolf_attack_filter if not _wolf_attack_filter.is_empty() else "all"]
	if not args.is_empty() and args[0].to_lower() == "jointstates":
		return "Joint snapshots: %d" % _emit_joint_snapshot(" ".join(args.slice(1)))
	if not args.is_empty() and args[0].to_lower() == "trackjoints":
		if args.size() == 1:
			_joint_tracking_enabled = not _joint_tracking_enabled
		elif args[1].to_lower() in ["on", "off"]:
			_joint_tracking_enabled = args[1].to_lower() == "on"
			_joint_tracking_filter = " ".join(args.slice(2))
		else:
			return "Usage: trackjoints [on|off] [character name, path or instance ID]"
		_joint_tracking_elapsed = 0.0
		var count := _emit_joint_snapshot(_joint_tracking_filter) if _joint_tracking_enabled else 0
		return "Joint tracking %s; filter=%s; joints=%d; interval=%.2fs" % ["enabled" if _joint_tracking_enabled else "disabled", _joint_tracking_filter if not _joint_tracking_filter.is_empty() else "all", count, motion_tracking_interval]
	if not args.is_empty() and args[0].to_lower() == "showsnakepath":
		if args.size() > 1 and args[1].to_lower() not in ["on","off"]:
			return "Usage: showsnakepath [on|off] [character name, path or instance ID]"
		if not is_instance_valid(_snake_path_display):
			_snake_path_display = SNAKE_PATH_DISPLAY.new()
			_snake_path_display.name = "SnakePathDisplay3D"
			MOTION_PLAYER_CONTEXT.level(self).add_child(_snake_path_display)
		var value: bool = not _snake_path_display.enabled if args.size() == 1 else args[1].to_lower() == "on"
		var actor_filter := " ".join(args.slice(2))
		_snake_path_display.set_enabled(value,actor_filter)
		var message := "Snake ground path display %s; filter=%s; cyan=history; orange=preview." % ["enabled" if value else "disabled",actor_filter if not actor_filter.is_empty() else "all"]
		_append_log_output("[snake_path_display] "+message)
		return message
	if not args.is_empty() and args[0].to_lower() == "showattackboxes":
		if args.size() > 2 or (args.size() == 2 and args[1].to_lower() not in ["on","off","status"]):
			return "Usage: showattackboxes [on|off|status]"
		var value: bool = is_instance_valid(_attack_collision_display) and _attack_collision_display.enabled
		if args.size() == 1: value = not value
		elif args[1].to_lower() != "status": value = args[1].to_lower() == "on"
		if value and not is_instance_valid(_attack_collision_display):
			_attack_collision_display = ATTACK_COLLISION_DISPLAY.new()
			_attack_collision_display.name = "AttackCollisionDisplay3D"
			add_child(_attack_collision_display)
		if is_instance_valid(_attack_collision_display) and (args.size() == 1 or args[1].to_lower() != "status"):
			_attack_collision_display.set_enabled(value)
		return "Attack collision display %s; shapes=%d; red=damage enabled; orange=inactive temporary volume." % ["enabled" if value else "disabled",_attack_collision_display._meshes.size() if is_instance_valid(_attack_collision_display) else 0]
	if not args.is_empty() and args[0].to_lower() == "showsteptargets":
		if args.size() > 2 or (args.size() == 2 and args[1].to_lower() not in ["on", "off"]):
			return "Usage: showsteptargets [on|off]"
		if not is_instance_valid(_step_target_display):
			_step_target_display = STEP_TARGET_DISPLAY.new()
			_step_target_display.name = "StepTargetDisplay3D"
			MOTION_PLAYER_CONTEXT.level(self).add_child(_step_target_display)
		var value: bool = not _step_target_display.enabled if args.size() == 1 else args[1].to_lower() == "on"
		_step_target_display.set_enabled(value)
		return "Step target rings %s." % ("enabled" if value else "disabled")
	if not args.is_empty() and args[0].to_lower() == "motiondetail":
		if args.size() != 2 or args[1].to_lower() not in ["summary", "full"]: return "Usage: motiondetail [summary|full]"
		_full_motion_details = args[1].to_lower() == "full"
		return "Motion detail: %s" % args[1].to_lower()
	if not args.is_empty() and args[0].to_lower() == "trackflight":
		if args.size() == 1: _flight_tracking_enabled = not _flight_tracking_enabled
		elif args.size() == 2 and args[1].to_lower() in ["on","off"]: _flight_tracking_enabled = args[1].to_lower() == "on"
		else: return "Usage: trackflight [on|off]"
		_flight_tracking_elapsed = 0.0
		_sync_bird_diagnostic_tracking()
		if _flight_tracking_enabled: _emit_flight_snapshot()
		return "Bird flight tracking %s; interval=%.2fs" % ["enabled" if _flight_tracking_enabled else "disabled",motion_tracking_interval]
	if not args.is_empty() and args[0].to_lower() == "tracknpcmotion":
		if args.size() == 1:
			_npc_motion_tracking_enabled = not _npc_motion_tracking_enabled
			_npc_motion_filter = ""
		elif args[1].to_lower() in ["on", "off"]:
			_npc_motion_tracking_enabled = args[1].to_lower() == "on"
			_npc_motion_filter = " ".join(args.slice(2))
		else:
			return "Usage: tracknpcmotion [on|off] [NPC name, path or instance ID]"
		_npc_motion_elapsed = 0.0
		var count := _emit_npc_motion_snapshot() if _npc_motion_tracking_enabled else 0
		return "NPC motion tracking %s; filter=%s; matched=%d; interval=%.2fs" % ["enabled" if _npc_motion_tracking_enabled else "disabled", _npc_motion_filter if not _npc_motion_filter.is_empty() else "all", count, motion_tracking_interval]
	if not args.is_empty() and args[0].to_lower() == "npcstates":
		return "NPC state snapshots: %d" % _emit_npc_state_snapshot(" ".join(args.slice(1)))
	if not args.is_empty() and args[0].to_lower() == "tracknpcstate":
		if args.size() == 1:
			_npc_state_tracking_enabled = not _npc_state_tracking_enabled
			_npc_state_filter = ""
		elif args[1].to_lower() in ["on","off"]:
			_npc_state_tracking_enabled = args[1].to_lower() == "on"
			_npc_state_filter = " ".join(args.slice(2))
		else: return "Usage: tracknpcstate [on|off] [NPC name, path or instance ID]"
		_npc_state_elapsed = 0.0
		if _npc_state_tracking_enabled: _emit_npc_state_snapshot(_npc_state_filter)
		return "NPC FSM tracking %s; filter=%s; interval=%.2fs" % ["enabled" if _npc_state_tracking_enabled else "disabled",_npc_state_filter if not _npc_state_filter.is_empty() else "all",npc_state_tracking_interval]
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
			_sync_bird_diagnostic_tracking()
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
		"trackcharge":
			_charge_tracking_enabled = not _charge_tracking_enabled
			for component: Node in get_tree().get_nodes_in_group(&"charge_attack_controllers"):
				component.set_diagnostic_tracking_enabled(_charge_tracking_enabled)
			return "Charge tracking %s." % ("enabled" if _charge_tracking_enabled else "disabled")
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
	var lines: Array[String] = [L10N.text("Available commands:")]
	for entry: Dictionary in COMMAND_HELP:
		lines.append("  %-16s %s" % [entry.name, L10N.text(entry.description)])
	return "\n".join(lines)

func is_map_tracking_enabled() -> bool:
	return _map_tracking_enabled

func log_map_event(event: String, detail: Dictionary, force: bool = false) -> void:
	if not _map_tracking_enabled and not force: return
	_map_event_sequence += 1
	var row := detail.duplicate()
	row.event = event
	row.sequence = _map_event_sequence
	row.time_ms = Time.get_ticks_msec()
	_append_log_output("[map_event] "+JSON.stringify(row))

func _npc_matches(machine: Node, filter: String) -> bool:
	var actor := machine.get_parent()
	return filter.is_empty() or filter.to_lower() == "all" or str(actor.name).to_lower() == filter.to_lower() or str(actor.get_path()) == filter or str(actor.get_instance_id()) == filter or str(machine.get_path()) == filter

func _emit_bow_snapshot() -> int:
	var count := 0
	for controller: Node in get_tree().get_nodes_in_group(&"bow_attack_controllers"):
		if not _npc_matches(controller,_bow_tracking_filter): continue
		_append_log_output("[bow_attack] "+JSON.stringify(controller.get_attack_diagnostics()))
		count += 1
	return count

func is_bow_tracking_enabled(controller: Node) -> bool:
	return _bow_tracking_enabled and _npc_matches(controller,_bow_tracking_filter)

func log_bow_event(controller: Node, event: StringName, detail: Dictionary) -> void:
	if not is_bow_tracking_enabled(controller): return
	var row: Dictionary = controller.get_attack_diagnostics()
	row.event = event
	row.details = detail
	_append_log_output("[bow_event] "+JSON.stringify(row))

func is_npc_state_tracking_enabled(machine: Node) -> bool:
	return _npc_state_tracking_enabled and _npc_matches(machine,_npc_state_filter)

func _emit_npc_state_snapshot(filter: String) -> int:
	var messages: Array[String] = []
	var count := 0
	for machine: Node in get_tree().get_nodes_in_group(&"npc_state_machines"):
		if not _npc_matches(machine,filter): continue
		count += 1
		messages.append("[npc_state] event=snapshot data=%s" % machine.get_state_diagnostics())
		messages.append("[npc_state] event=friendly_avoidance data=%s" % machine.get_friendly_avoidance_diagnostics())
		messages.append("[npc_state] event=attack_ranges data=%s" % machine.get_attack_range_diagnostics())
	_emit_motion_lines(messages)
	return count

## Packs user://logs into a ZIP. Tests may pass different writable source and output directories.
func create_logs_archive(output_directory: String = "", log_directory: String = "user://logs", trigger: Dictionary = {}) -> String:
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
	var archive_path := destination_directory.path_join("runtime_logs_%s_%d_%d.zip" % [timestamp,OS.get_process_id(),Time.get_ticks_usec()])
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

	# Include this process's buffered console output even when --log-file redirects the
	# engine log outside user://logs. It also captures the event immediately before getlogs.
	if writer.start_file("logs/runtime_console_snapshot.log") == OK:
		writer.write_file(("\n".join(_output_lines)+"\n").to_utf8_buffer())
		writer.close_file()

	var manifest := (
		"Project: %s\nCreated: %s\nLog source: %s\nFiles: %d\n"
		% [ProjectSettings.get_setting("application/config/name", ""), timestamp, ProjectSettings.globalize_path(log_root), log_files.size()]
	)
	if writer.start_file("archive_manifest.txt") == OK:
		writer.write_file(manifest.to_utf8_buffer())
		writer.close_file()
	if not trigger.is_empty() and writer.start_file("archive_trigger.json") == OK:
		writer.write_file(JSON.stringify(trigger,"\t").to_utf8_buffer())
		writer.close_file()
	writer.close()
	print("Runtime logs archived to: %s" % archive_path)
	return archive_path

func get_archive_output_directory() -> String:
	# Installed games may live in a read-only directory; keep editor behavior unchanged.
	var directory := "res://" if OS.has_feature("editor") else "user://log_archives"
	return ProjectSettings.globalize_path(directory).trim_suffix("/").trim_suffix("\\")

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

func is_wolf_attack_tracking_enabled(character: Node) -> bool:
	return _wolf_attack_tracking_enabled and (_wolf_attack_filter.is_empty() or str(character.get_path()).to_lower().contains(_wolf_attack_filter.to_lower()) or str(character.get_instance_id()) == _wolf_attack_filter)

func is_snake_attack_tracking_enabled(character: Node) -> bool:
	return _snake_attack_tracking_enabled and (_snake_attack_filter.is_empty() or str(character.get_path()).to_lower().contains(_snake_attack_filter.to_lower()) or str(character.get_instance_id()) == _snake_attack_filter)

func is_turn_tracking_enabled() -> bool:
	return _turn_tracking_enabled

func is_swing_tracking_enabled() -> bool:
	return _swing_tracking_enabled

func log_weapon_grip_event(inventory: Node, event: String) -> void:
	if _grip_tracking_enabled and _weapon_grip_matches(inventory, _grip_tracking_filter):
		_append_weapon_grip_snapshot(inventory, event)

func _weapon_grip_matches(inventory: Node, filter: String) -> bool:
	return is_instance_valid(inventory) and inventory.is_inside_tree() and not inventory.is_queued_for_deletion() and is_instance_valid(inventory.get_parent()) and not inventory.get_parent().is_queued_for_deletion() and _npc_matches(inventory, filter)

func _emit_weapon_grip_snapshot(filter: String) -> int:
	var count := 0
	for inventory: Node in get_tree().get_nodes_in_group(&"weapon_grip_inventories"):
		if not _weapon_grip_matches(inventory, filter): continue
		_append_weapon_grip_snapshot(inventory, "snapshot")
		count += 1
	return count

func _append_weapon_grip_snapshot(inventory: Node, event: String) -> void:
	var actor := inventory.get_parent()
	_append_log_output("[weapon_grip] character_path=%s character_id=%d event=%s data=%s" % [actor.get_path(), actor.get_instance_id(), event, inventory.get_weapon_grip_diagnostics()])

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
	var started := _logger_perf.start()
	var messages := _collect_motion_snapshot()
	_logger_perf.finish(&"motion_snapshot_build", started)
	_emit_motion_lines(messages)

func _emit_motion_lines(messages: Array[String]) -> void:
	if messages.is_empty(): return
	_output_lines.append_array(messages)
	while _output_lines.size() > maximum_output_lines: _output_lines.pop_front()
	_output_dirty = true
	_print_log("\n".join(messages))

func _collect_npc_motion_snapshot() -> Array[String]:
	var messages: Array[String] = []
	var visited: Dictionary = {}
	for machine: Node in get_tree().get_nodes_in_group(&"npc_state_machines"):
		var actor := machine.get_parent() as Node3D
		if not is_instance_valid(actor) or actor.is_queued_for_deletion() or visited.has(actor) or not _npc_matches(machine, _npc_motion_filter): continue
		visited[actor] = true
		var identity := "[npc_motion] npc_path=%s npc_id=%d" % [actor.get_path(), actor.get_instance_id()]
		if _full_motion_details:
			messages.append("%s state=%s" % [identity, machine.get_state_diagnostics()])
			messages.append("%s attack_ranges=%s" % [identity, machine.get_attack_range_diagnostics()])
			messages.append("%s navigation=%s" % [identity, machine.get_navigation_motion_diagnostics()])
			for controller: Node in get_tree().get_nodes_in_group(&"leg_step_movement_controllers"):
				if controller.get_parent() == actor and controller.has_method("get_npc_motion_execution_diagnostics"):
					messages.append("%s execution=%s" % [identity, controller.get_npc_motion_execution_diagnostics()])
		for line: String in _collect_motion_snapshot(actor):
			messages.append(line.replace("[trackmotion]", identity))
	return messages

func _emit_npc_motion_snapshot() -> int:
	var started := _logger_perf.start()
	var messages := _collect_npc_motion_snapshot()
	_logger_perf.finish(&"npc_motion_snapshot_build", started)
	var count := 0
	for line: String in messages:
		if " snapshot=" in line: count += 1
	_emit_motion_lines(messages)
	return count

func _emit_joint_snapshot(filter: String) -> int:
	var started := _logger_perf.start()
	var messages: Array[String] = []
	var visited: Dictionary = {}
	for controller: Node in get_tree().get_nodes_in_group(&"leg_step_movement_controllers"):
		var actor := controller.get_parent() as Node3D
		if not is_instance_valid(actor) or actor.is_queued_for_deletion() or visited.has(actor) or not _npc_matches(controller, filter): continue
		visited[actor] = true
		for joint: Generic6DOFJoint3D in actor.find_children("*", "Generic6DOFJoint3D", true, false):
			messages.append("[joint_motion] character=%s character_path=%s character_id=%d data=%s" % [actor.name, actor.get_path(), actor.get_instance_id(), JOINT_DIAGNOSTICS.collect(joint)])
	_joint_last_physics_frame = Engine.get_physics_frames()
	_logger_perf.finish(&"joint_snapshot_build", started)
	_emit_motion_lines(messages)
	return messages.size()

func _character_components(character: Node3D) -> Array[Node]:
	return character.get_control_components() if character.has_method("get_control_components") else character.get_children()

func _collect_motion_summary(character: Node3D) -> Array[String]:
	var messages: Array[String] = []
	messages.append("[trackmotion] snapshot=%d physics_frame=%d time_ms=%d character=%s detail=summary" % [
		_motion_snapshot_sequence, Engine.get_physics_frames(), Time.get_ticks_msec(), character.name])
	for controller: Node in _character_components(character):
		if controller.has_method("get_snake_motion_diagnostics"):
			var snake: Dictionary = controller.get_snake_motion_diagnostics(false)
			snake.erase("parts")
			messages.append("[trackmotion] character=%s snake_motion=%s" % [character.name, snake])
		if not controller.is_in_group(&"leg_step_movement_controllers"): continue
		var automatic: Dictionary = controller.get_automatic_motion_diagnostics()
		var legs: Array[Dictionary] = []
		for profile: Dictionary in automatic.legs:
			var row := {"foot": profile.foot}
			for key: String in ["stride", "reachable_speed", "observed_step_duration", "occupied_step_duration", "usable_stance_stride_limit", "required_stance_stride", "cycle", "frequency", "average_slot_usage"]:
				if profile.has(key): row[key] = profile[key]
			legs.append(row)
		var torsos: Array[Dictionary] = []
		var feet: Array[Dictionary] = []
		for foot: RigidBody3D in controller.get_leg_parts():
			feet.append({"foot": foot.name, "grounded": controller.is_leg_grounded(foot),
				"stepping": controller.is_leg_stepping(foot), "slipping": controller.is_leg_slipping(foot)})
		for torso: RigidBody3D in controller.get_torso_parts():
			torsos.append({"body": torso.name, "position": torso.global_position, "velocity": torso.linear_velocity})
		messages.append("[trackmotion] character=%s requested_speed=%.3f planned_speed=%.3f stepping=%d torso_motion=%s leg_profiles=%s feet=%s" % [
			character.name, automatic.requested_speed, automatic.target_speed, controller._active_steps.size(), torsos, legs, feet])
		if automatic.has("wolf_auto_gallop"):
			messages.append("[trackmotion] character=%s wolf_auto_gallop=%s" % [character.name, automatic.wolf_auto_gallop])
		if automatic.has("spider_motion_budget"):
			messages.append("[trackmotion] character=%s spider_motion_budget=%s" % [character.name, automatic.spider_motion_budget])
	return messages

func _collect_motion_snapshot(character: Node3D = null) -> Array[String]:
	var messages: Array[String] = []
	if character == null: character = MOTION_PLAYER_CONTEXT.controlled_character(self)
	if not is_instance_valid(character):
		messages.append("[trackmotion] No controlled character (Controller detached or no target).")
		return messages
	_motion_snapshot_sequence += 1
	if not _full_motion_details: return _collect_motion_summary(character)
	var parts: Array[PhysicalBodyPart3D] = []
	var bodies: Array = character._get_physical_body_parts() if character.has_method("_get_physical_body_parts") else character.find_children("*", "RigidBody3D", true, false)
	for node: Node in bodies:
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
	if character.has_method("get_standing_pose_diagnostics"):
		messages.append("[trackmotion] character=%s grounded_standing_pose=%s" % [character.name, character.get_standing_pose_diagnostics()])
	for controller: Node in _character_components(character):
		if controller.has_method("get_snake_motion_diagnostics"):
			messages.append("[trackmotion] character=%s snake_motion=%s" % [character.name, controller.get_snake_motion_diagnostics()])
		if controller.is_in_group(&"leg_step_movement_controllers"):
			if controller.has_method("get_creature_action_controller"):
				var action: Node = controller.get_creature_action_controller()
				if action != null: messages.append("[trackmotion] character=%s creature_action=%s" % [character.name,action.get_action_diagnostics()])
			messages.append_array(_collect_leg_motion_lines(controller))
			if controller.has_method("get_walk_start_stagger_diagnostics"):
				messages.append("[trackmotion] character=%s walk_start_stagger=%s" % [character.name,controller.get_walk_start_stagger_diagnostics()])
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

	messages.append_array(_collect_bird_motion_lines(character,"[trackmotion]"))
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
		if not leg_step.get("plan",{}).is_empty(): message += " step_plan=%s" % leg_step.plan
		if controller.has_method("get_support_foot_diagnostics"):
			var support: Dictionary = controller.call("get_support_foot_diagnostics", leg)
			message += " foot_locked=%s foot_anchor=%s foot_drift=%.3f foot_speed=%.3f support_force=%s brake_force=%s expected_speed=%.3f" % [
				support.locked, _format_vector3(support.anchor), support.drift,
				support.speed, _format_vector3(support.force), _format_vector3(support.brake_force), support.expected_speed]
			if support.has("contact_point"):
				message += " pin_kind=%s contact_point=%s contact_velocity=%s body_center=%s turn_released=%s spider_touchdown=%s" % [support.get("pin_kind", "none"), _format_vector3(support.contact_point), _format_vector3(support.get("contact_velocity", Vector3.ZERO)), _format_vector3(support.get("body_center", leg.global_position)), support.get("turn_released", false), support.get("spider_touchdown", {})]
			if support.has("spider_support_selection"):
				message += " spider_support_selection=%s spider_liftoff=%s spider_joint_springs=%s" % [support.spider_support_selection, support.get("spider_liftoff", {}), support.get("spider_joint_springs", [])]
				message += " spider_landing=%s spider_last_touchdown=%s" % [support.get("spider_landing", {}), support.get("spider_last_touchdown", {})]
				message += " spider_pose_guide=%s spider_contact_trajectory=%s spider_attempts=%s" % [support.get("spider_pose_guide", {}), support.get("spider_contact_trajectory", {}), support.get("spider_attempts", {})]
				message += " spider_catch_up=%s spider_recovery_attempts=%s" % [support.get("spider_catch_up", {}), support.get("spider_recovery_attempts", 0)]
				message += " spider_constraint_guard=%s spider_live_reach=%s" % [support.get("spider_constraint_guard", {}), support.get("spider_live_reach", {})]
				message += " spider_leg_rotation_balance=%s" % support.get("spider_leg_rotation_balance", {})
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
		+ "navigation_frames=%d target_refreshes=%d repaths=%d map_projections=%d planning_decisions=%d") % [
			navigation_stats.components,
			float(navigation_stats.total_usec) / 1000.0,
			float(navigation_stats.max_usec) / 1000.0,
			navigation_stats.physics_frames,
			navigation_stats.target_refreshes,
			navigation_stats.repaths,
			navigation_stats.map_projections,
			navigation_stats.planning_decisions,
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
		&"planning_decisions": 0,
		&"total_usec": 0,
		&"max_usec": 0,
	}
	for component: Node in get_tree().get_nodes_in_group(group_name):
		if not component.has_method("consume_performance_stats"):
			continue
		var stats: Dictionary = component.call("consume_performance_stats")
		if group_name == &"leg_step_movement_controllers":
			var frames: int = stats.get(&"physics_frames", 0)
			_append_log_output("[trackperformance] movement_component=%s frames=%d total_ms=%.3f avg_ms=%.3f max_ms=%.3f ray_queries=%d shape_queries=%d tracking_enabled=%s physics_processing=%s can_process=%s" % [component.get_path(), frames,
				float(stats.get(&"total_usec", 0)) / 1000.0, float(stats.get(&"total_usec", 0)) / maxi(frames, 1) / 1000.0,
				float(stats.get(&"max_usec", 0)) / 1000.0, stats.get(&"ray_queries", 0), stats.get(&"shape_queries", 0),
				component.is_performance_tracking_enabled(), component.is_physics_processing(), component.can_process()])
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
	_print_log(message)

func _print_log(message: String) -> void:
	var started := _logger_perf.start()
	print(message)
	_logger_perf.finish(&"log_print", started)
	_logger_perf.count(&"log_characters", message.length())

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
	_output_dirty = true

func _refresh_output_text() -> void:
	if not visible or not is_instance_valid(_output): return
	var started := _logger_perf.start()
	_output.text = "\n".join(_output_lines)
	_output.scroll_to_line(maxi(_output.get_line_count() - 1, 0))
	_output_dirty = false
	_output_refresh_elapsed = 0.0
	_logger_perf.finish(&"console_text_refresh", started)

func set_control_performance_tracking_enabled(enabled: bool) -> void:
	_logger_perf.set_enabled(enabled)

func consume_control_performance_stats() -> Dictionary:
	return _logger_perf.consume()

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

func is_bird_physics_tracking_enabled() -> bool:
	return _flight_tracking_enabled or _motion_tracking_enabled

func _sync_bird_diagnostic_tracking() -> void:
	for component: Node in get_tree().get_nodes_in_group(&"bird_physics_diagnostics"):
		component.set_diagnostic_tracking_enabled(is_bird_physics_tracking_enabled())

func _emit_flight_snapshot() -> void:
	var character := MOTION_PLAYER_CONTEXT.controlled_character(self)
	_emit_motion_lines(_collect_bird_motion_lines(character,"[trackflight]"))

func _collect_bird_motion_lines(character: Node3D, prefix: String) -> Array[String]:
	var lines: Array[String] = []
	if not is_instance_valid(character):
		lines.append("%s No controlled character." % prefix)
		return lines
	for component: Node in _character_components(character):
		var method := "get_flight_diagnostics" if component.has_method("get_flight_diagnostics") else "get_wing_diagnostics"
		if component.has_method("get_dive_diagnostics"): method = "get_dive_diagnostics"
		if not component.has_method(method): continue
		var data: Dictionary = component.call(method)
		var legs: Array = data.get("legs",[])
		var joints: Array = data.get("joints",[])
		var wings: Array = data.get("wings",[])
		data.erase("legs"); data.erase("joints"); data.erase("wings")
		var header := "%s physics_frame=%d time_ms=%d character=%s component=%s" % [prefix,Engine.get_physics_frames(),Time.get_ticks_msec(),character.get_path(),component.name]
		lines.append("%s summary=%s" % [header,data])
		for row: Dictionary in legs: lines.append("%s flight_leg=%s" % [header,row])
		for row: Dictionary in joints: lines.append("%s flight_joint=%s" % [header,row])
		for row: Dictionary in wings: lines.append("%s wing_pose=%s" % [header,row])
	return lines

func is_charge_tracking_enabled() -> bool:
	return _charge_tracking_enabled
