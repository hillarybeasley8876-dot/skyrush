extends SceneTree
## Loads every script, scene and shader under res:// (or --only=res://a/,res://b/) and reports
## failures. Exit code 1 if anything failed or any engine error was logged.
##   tools/godot.sh check [--only=res://vehicle/]

const ErrorCounter := preload("res://tools/error_counter.gd")
const EXTS: PackedStringArray = ["gd", "tscn", "tres", "gdshader"]
const SKIP_DIRS: PackedStringArray = ["res://.godot", "res://addons"]

var _failed: PackedStringArray = []


func _initialize() -> void:
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var roots: PackedStringArray = ["res://"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			roots = arg.trim_prefix("--only=").split(",", false)
	var files: PackedStringArray = []
	for r in roots:
		_collect(r, files)
	for path in files:
		_check(path)
	for line in counter.first_errors:
		print("CHECK ERROR ", line)
	print("CHECK %d files, %d failed, %d engine errors, %d warnings" % [files.size(), _failed.size(),
			counter.errors, counter.warnings])
	for path in _failed:
		print("CHECK FAIL ", path)
	quit(1 if (_failed.size() > 0 or counter.errors > 0) else 0)


func _collect(dir_path: String, out: PackedStringArray) -> void:
	if SKIP_DIRS.has(dir_path.trim_suffix("/")):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), out)
	for file in dir.get_files():
		if EXTS.has(file.get_extension()):
			out.append(dir_path.path_join(file))


func _check(path: String) -> void:
	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res == null:
		_failed.append(path)
		return
	if res is GDScript and not (res as GDScript).can_instantiate() and not _is_abstract_tool(path):
		_failed.append(path + " (script does not compile)")
	elif res is PackedScene:
		var node := (res as PackedScene).instantiate()
		if node == null:
			_failed.append(path + " (scene does not instantiate)")
		else:
			node.free()


func _is_abstract_tool(path: String) -> bool:
	return path.begins_with("res://tools/")
