extends SceneTree
## Parse/compile-check EVERY .gd under res:// in one headless run (verified Godot 4.7.2).
##   godot --headless --path <project> --script res://tools/check_scripts.gd [-- --root=res://src]
## Output: one "SCRIPT_FAIL <path>" per broken script (the engine also prints the exact
## "SCRIPT ERROR: Parse Error: ... at: GDScript::reload (res://x.gd:LINE)" lines on stderr),
## then "CHECKED <n> scripts, <k> failed". Exit code = min(failed, 125) -> 0 means clean.
## Run `godot --headless --path <project> --import` first after adding/renaming class_name
## scripts, otherwise the global class cache is stale and valid references fail.
## Skips: .godot/, addons/, any folder containing a .gdignore file.

var root_dir := "res://"
var checked := 0
var failed: PackedStringArray = []

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--root="):
			root_dir = a.substr(7)
	_scan(root_dir)
	for f in failed:
		print("SCRIPT_FAIL ", f)
	print("CHECKED %d scripts, %d failed" % [checked, failed.size()])
	quit(mini(failed.size(), 125))

func _scan(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		printerr("CHECK_FAIL cannot open ", dir_path)
		failed.append(dir_path)
		return
	if d.file_exists(".gdignore"):
		return
	for sub in d.get_directories():
		if sub.begins_with(".") or sub == "addons":
			continue
		_scan(dir_path.path_join(sub))
	for f in d.get_files():
		if f.get_extension() == "gd":
			_check(dir_path.path_join(f))

func _check(path: String) -> void:
	if path == (get_script() as Script).resource_path:
		return      # re-loading the running script with CACHE_MODE_IGNORE hangs the engine
	checked += 1
	var s := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	if s == null or not s.can_instantiate():
		failed.append(path)
