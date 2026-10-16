@tool
extends EditorPlugin

class LogArchiveDebugger extends EditorDebuggerPlugin:
	func _has_capture(capture: String) -> bool:
		return capture == "runtime_console"

	func _capture(message: String, data: Array, session_id: int) -> bool:
		if message == "runtime_console:ready":
			get_session(session_id).send_message("runtime_console:bridge_ready",[])
			return true
		if message == "runtime_console:archive_result":
			print("[auto_getlogs] editor received archive result: ",data)
			return true
		return false

	func _setup_session(session_id: int) -> void:
		var session := get_session(session_id)
		session.breaked.connect(_on_break.bind(session_id))

	func _on_break(can_debug: bool, session_id: int) -> void:
		var session := get_session(session_id)
		if session.is_active(): session.send_message("runtime_console:archive_on_break",[can_debug])

var _debugger := LogArchiveDebugger.new()

func _enter_tree() -> void:
	add_debugger_plugin(_debugger)
	print("[auto_getlogs] editor breakpoint bridge loaded")

func _exit_tree() -> void:
	remove_debugger_plugin(_debugger)
