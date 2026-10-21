extends Logger
## The engine errors of the POLICE code (the errors of the other units are not ours).
##
## The police tests fail when a script of `res://ai/police/` raises an engine error: a test that
## runs on a crashing script is not a test. The errors of the units that are edited in parallel
## (their scripts are dependencies of the police) are counted by res://tools/error_counter.gd
## and printed, but they do not fail the police suite.

## The path prefix of the code of this unit.
const OWN_PATH := "res://ai/police/"

## The number of engine errors of the police code.
var errors: int = 0
## The first errors of the police code.
var first_errors: PackedStringArray = []


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	if not file.begins_with(OWN_PATH):
		return
	errors += 1
	if first_errors.size() < 20:
		var what := rationale if rationale != "" else code
		first_errors.append("%s:%d %s(): %s" % [file, line, function, what])
