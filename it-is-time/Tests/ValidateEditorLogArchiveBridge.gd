@tool
extends SceneTree

class BreakObserver extends EditorDebuggerPlugin:
	var breaks := 0
	var paused_session: EditorDebuggerSession
	func _setup_session(session_id: int) -> void:
		var session := get_session(session_id)
		session.breaked.connect(_on_break.bind(session_id))
	func _on_break(_can_debug: bool, session_id: int) -> void:
		breaks += 1
		paused_session = get_session(session_id)

var failed := false
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	print("EDITOR_ARCHIVE_CHECK ",ok," ",message)
	failed = failed or not ok

func run() -> void:
	if not Engine.is_editor_hint(): print("Run this test with --editor --headless."); quit(1); return
	for frame: int in 30: await process_frame
	while EditorInterface.get_resource_filesystem().is_scanning(): await process_frame
	var observer := BreakObserver.new()
	var host := EditorPlugin.new()
	root.add_child(host)
	host.add_debugger_plugin(observer)
	var status_path := ProjectSettings.globalize_path("user://logs/editor_archive_fixture_%d.json" % OS.get_process_id())
	OS.set_environment("ITISTIME_EDITOR_ARCHIVE_STATUS",status_path)
	ProjectSettings.set_setting("editor/run/main_run_args","--headless --log-file "+ProjectSettings.globalize_path("user://logs/editor_archive_fixture.log"))
	EditorInterface.get_editor_settings().set_setting("run/auto_save/save_before_running",false)
	EditorInterface.play_custom_scene("res://Tests/Fixtures/AutomaticLogArchiveBreak.tscn")
	var deadline := Time.get_ticks_msec()+30000
	var pid := 0
	var archives: Array[String] = []
	var project_root := ProjectSettings.globalize_path("res://")
	while Time.get_ticks_msec()<deadline and archives.size()<2:
		if pid==0 and FileAccess.file_exists(status_path):
			var status: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(status_path))
			pid = status.pid
			check(status.bridge_connected,"Actual project editor plugin completes the runtime handshake")
		if pid>0 and observer.breaks>archives.size():
			for file: String in DirAccess.get_files_at(project_root):
				if not file.begins_with("runtime_logs_") or not file.ends_with(".zip") or not ("_%d_" % pid) in file: continue
				var path := project_root.path_join(file)
				if path in archives: continue
				var reader := ZIPReader.new()
				if reader.open(path)!=OK: continue
				var context: Dictionary = JSON.parse_string(reader.read_file("archive_trigger.json").get_string_from_utf8())
				reader.close()
				check(observer.paused_session.is_breaked(),"ZIP is complete while actual editor session is still paused")
				check(context.trigger=="debugger_break" and ("run" if archives.is_empty() else "freed_reference_error") in str(context.paused_backtraces),"Manual/error breakpoint stack is archived")
				archives.append(path)
				# The observer never requests archives; the installed project plugin must do that.
				await create_timer(0.3).timeout
				observer.paused_session.send_message("continue",[])
				break
		await process_frame
	check(archives.size()==2 and observer.breaks==2,"Real editor plugin exports both manual and runtime-error breakpoints")
	await create_timer(0.3).timeout
	EditorInterface.stop_playing_scene()
	observer.paused_session = null
	host.remove_debugger_plugin(observer)
	host.free()
	OS.unset_environment("ITISTIME_EDITOR_ARCHIVE_STATUS")
	for path: String in archives: DirAccess.remove_absolute(path)
	if FileAccess.file_exists(status_path): DirAccess.remove_absolute(status_path)
	print("EDITOR_LOG_ARCHIVE_BRIDGE_","FAILED" if failed else "PASSED")
	for node: Node in root.get_children(): node.queue_free()
	await process_frame; await process_frame
	quit(1 if failed else 0)
