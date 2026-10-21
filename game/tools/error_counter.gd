extends Logger
## Counts engine errors/warnings (script errors, failed loads, push_error) so tool scripts can fail
## loudly. Usage: var counter := ErrorCounter.new(); OS.add_logger(counter) ... counter.errors

var errors: int = 0
var warnings: int = 0
var first_errors: PackedStringArray = []


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		warnings += 1
		return
	errors += 1
	if first_errors.size() < 20:
		var what := rationale if rationale != "" else code
		first_errors.append("%s:%d %s(): %s" % [file, line, function, what])


func _log_message(_message: String, _error: bool) -> void:
	pass
