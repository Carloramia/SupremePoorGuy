extends SceneTree
var failed := false
var archives: Array[String] = []

func _initialize() -> void:
	call_deferred("_break_fixture" if "--break-fixture" in OS.get_cmdline_user_args() else "_validate")

func check(ok: bool, message: String) -> void:
	print("AUTO_ARCHIVE_CHECK ",ok," ",message)
	failed = failed or not ok

func inspect_archive(path: String, trigger: String) -> Dictionary:
	if path.is_empty(): check(false,"Archive exists"); return {}
	archives.append(path)
	var reader := ZIPReader.new()
	if reader.open(path)!=OK: check(false,"Archive opens"); return {}
	check("archive_manifest.txt" in reader.get_files(),"Existing getlogs manifest retained")
	var context: Dictionary = JSON.parse_string(reader.read_file("archive_trigger.json").get_string_from_utf8())
	check(context.get("trigger")==trigger,"Archive records its trigger")
	reader.close()
	return context

func _freed_reference_error() -> void:
	var node := Node.new()
	var cache := {"node":node}
	node.free()
	var _invalid: Node = cache.node

func _validate() -> void:
	var console := root.get_node("RuntimeConsole")
	check(console.auto_getlogs_enabled,"Automatic logging defaults to enabled")
	check("autogetlogs" in console.execute_command("help"),"Help lists automatic logging")
	push_warning("AUTO_ARCHIVE_WARNING_FIXTURE")
	await process_frame; await process_frame
	check(console._last_auto_archive_path.is_empty(),"Warnings do not create archives")
	_freed_reference_error()
	await process_frame; await process_frame
	var first: String = console._last_auto_archive_path
	var context := inspect_archive(first,"runtime_error")
	check("freed" in str(context).to_lower() and not context.get("backtraces",[]).is_empty(),"Real freed-reference error and stack are captured")
	push_error("AUTO_ARCHIVE_REPEATED_ERROR_FIXTURE")
	await process_frame; await process_frame
	check(console._last_auto_archive_path==first,"Cooldown suppresses consecutive errors")
	check(console.execute_command("autogetlogs off").begins_with("Automatic log archives disabled"),"Console can disable automatic logging")
	push_error("AUTO_ARCHIVE_DISABLED_FIXTURE")
	await process_frame; await process_frame
	check(console._last_auto_archive_path==first,"Disabled mode ignores runtime errors")
	console.execute_command("autogetlogs on")
	var worker := Thread.new()
	check(worker.start(func():push_error("AUTO_ARCHIVE_WORKER_FIXTURE"))==OK,"Worker error fixture starts")
	worker.wait_to_finish()
	await process_frame; await process_frame
	context = inspect_archive(console._last_auto_archive_path,"runtime_error")
	check("AUTO_ARCHIVE_WORKER_FIXTURE" in str(context),"Errors from worker threads are captured safely")
	check(console._last_auto_archive_path!=first,"Immediate rearming never overwrites the earlier ZIP")
	console.execute_command("autogetlogs off")
	await _validate_remote_break()
	for path: String in archives:
		check(path.begins_with(console.get_archive_output_directory()+"/runtime_logs_"),"Only this test's project ZIP is removed")
		if path.begins_with(console.get_archive_output_directory()+"/runtime_logs_"): DirAccess.remove_absolute(path)
	print("AUTOMATIC_LOG_ARCHIVES_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)

func _break_fixture() -> void:
	print("AUTO_ARCHIVE_BREAK_FIXTURE_READY active=",EngineDebugger.is_active())
	breakpoint
	root.get_node("RuntimeConsole").execute_command("autogetlogs on")
	_freed_reference_error()
	print("AUTO_ARCHIVE_BREAK_FIXTURE_RESUMED")
	quit()

func _validate_remote_break() -> void:
	var server := TCPServer.new()
	check(server.listen(0,"127.0.0.1")==OK,"Remote debugger test listens on loopback")
	var port := server.get_local_port()
	var fixture_log := ProjectSettings.globalize_path("user://logs/automatic_break_fixture.log")
	var pid := OS.create_process(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--remote-debug","tcp://127.0.0.1:%d" % port,"--script","res://Tests/ValidateAutomaticLogArchives.gd","--log-file",fixture_log,"--","--break-fixture"]))
	check(pid>0,"Launch real breakpoint fixture")
	var deadline := Time.get_ticks_msec()+15000
	while not server.is_connection_available() and Time.get_ticks_msec()<deadline: await process_frame
	if not server.is_connection_available():
		check(false,"Debugger fixture connects")
		if OS.is_process_running(pid): OS.kill(pid)
		server.stop()
		return
	var stream := server.take_connection()
	var peer := PacketPeerStream.new()
	peer.stream_peer = stream
	var break_count := 0
	var archive_count := 0
	var continued_count := 0
	while Time.get_ticks_msec()<deadline:
		stream.poll()
		while peer.get_available_packet_count()>0:
			var message: Array = peer.get_var()
			if message[0]=="debug_enter":
				break_count += 1
				peer.put_var(["runtime_console:archive_on_break",message[1],[]])
			elif message[0]=="runtime_console:archive_result":
				var path: String = message[2][0]
				var context := inspect_archive(path,"debugger_break")
				if not path.is_empty() and continued_count<break_count: archive_count += 1
				check(("_break_fixture" if break_count==1 else "_freed_reference_error") in str(context.get("paused_backtraces",[])),"Paused archive preserves the breakpoint/error stack")
				peer.put_var(["continue",message[1],[]])
			elif message[0]=="debug_exit": continued_count += 1
		if continued_count==2: break
		await process_frame
	check(break_count==2 and archive_count==2 and continued_count==2,"getlogs completes before both manual and error breakpoints resume")
	stream.disconnect_from_host()
	server.stop()
	for frame: int in 120:
		if not OS.is_process_running(pid): break
		await process_frame
	if OS.is_process_running(pid): OS.kill(pid)
