extends Logger
## Counts the engine errors of the world unit only (the other units have their own assets and
## their own errors, which are reported to the lead, not to this test).
##
## An error counts when the file it comes from is under res://world/ or when one of the frames
## of its backtrace is (an error inside a world script that is called from elsewhere).

var errors: int = 0
var first_errors: PackedStringArray = []


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	if not _is_ours(file, script_backtraces):
		return
	errors += 1
	if first_errors.size() < 20:
		var what := rationale if rationale != "" else code
		first_errors.append("%s:%d %s(): %s" % [file, line, function, what])


## True when the error comes from the world unit.
func _is_ours(file: String, script_backtraces: Array[ScriptBacktrace]) -> bool:
	if file.begins_with("res://world/"):
		return true
	for trace in script_backtraces:
		for frame in range(trace.get_frame_count()):
			if str(trace.get_frame_file(frame)).begins_with("res://world/"):
				return true
	return false
