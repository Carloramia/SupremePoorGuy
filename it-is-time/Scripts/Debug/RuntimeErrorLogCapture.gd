extends Logger
## Logger callbacks can run on worker threads; pass only data to the console.
var _mutex := Mutex.new()
var _pending: Dictionary = {}

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING: return
	_mutex.lock()
	if _pending.is_empty():
		var traces: Array[String] = []
		for trace: ScriptBacktrace in script_backtraces: traces.append(trace.format())
		_pending = {"trigger":"runtime_error","function":function,"file":file,"line":line,"code":code,"message":rationale,"error_type":error_type,"backtraces":traces,"time_ms":Time.get_ticks_msec()}
	_mutex.unlock()

func take_error() -> Dictionary:
	_mutex.lock()
	var result := _pending
	_pending = {}
	_mutex.unlock()
	return result
