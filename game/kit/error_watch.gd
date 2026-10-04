class_name ErrorWatch
extends Logger
## Counts every engine/script error while the game runs. Harness runs (screenshots, --strict) fail when it
## is not zero, because a runtime error that only prints to a console nobody reads is a bug nobody fixes.

var errors: PackedStringArray = []
var _mutex := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == Logger.ERROR_TYPE_WARNING:
		return
	_mutex.lock()
	errors.append("%s (%s:%d in %s)" % [rationale if rationale != "" else code, file, line, function])
	_mutex.unlock()


func count() -> int:
	_mutex.lock()
	var n := errors.size()
	_mutex.unlock()
	return n
