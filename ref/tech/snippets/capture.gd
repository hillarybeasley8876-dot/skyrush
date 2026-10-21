extends SceneTree
## Screenshot capture (verified Godot 4.7.2 / macOS Metal, 2026-10-19). Must run WINDOWED:
## with --headless the dummy renderer returns no image (script exits with code 2).
##   godot --path <project> --resolution 1920x1080 --always-on-top \
##     --script res://tools/capture.gd -- --scene=res://scenes/x.tscn --frames=30 \
##     --out=res://captures/x.png [--camera=Path/To/Camera3D] [--shots=3 --interval=20]
## --frames   frames to wait before the first shot (shader compile + TAA/SSR/GI history settle: >= 30)
## --shots/--interval  extra shots every N frames: x_0.png, x_1.png ... (for motion checks)
## Prints CAPTURE_OK <abs path> <w>x<h> per image; exit code 0 = all written.

var scene_path := ""
var out_path := "res://captures/capture.png"
var wait_frames := 30
var shots := 1
var interval := 20
var camera_path := ""

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv.size() != 2: continue
		match kv[0]:
			"scene": scene_path = kv[1]
			"out": out_path = kv[1]
			"frames": wait_frames = maxi(kv[1].to_int(), 1)
			"shots": shots = maxi(kv[1].to_int(), 1)
			"interval": interval = maxi(kv[1].to_int(), 1)
			"camera": camera_path = kv[1]
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("CAPTURE_FAIL headless display has no framebuffer; run without --headless")
		quit(2)
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		printerr("CAPTURE_FAIL cannot load scene ", scene_path)
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	if camera_path != "":
		var cam := scene.get_node_or_null(camera_path) as Camera3D
		if cam == null:
			printerr("CAPTURE_FAIL camera not found ", camera_path)
			quit(1)
			return
		cam.make_current()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path).get_base_dir())
	for i in wait_frames:
		await process_frame
	for s in shots:
		await RenderingServer.frame_post_draw          # image of a fully drawn frame
		var img := root.get_texture().get_image()
		if img == null or img.is_empty():
			printerr("CAPTURE_FAIL empty framebuffer")
			quit(1)
			return
		var target := out_path if shots == 1 else out_path.get_basename() + "_%d.png" % s
		var abs_path := ProjectSettings.globalize_path(target)
		var err := img.save_png(abs_path)
		if err != OK:
			printerr("CAPTURE_FAIL save error ", err, " ", abs_path)
			quit(1)
			return
		print("CAPTURE_OK ", abs_path, " ", img.get_width(), "x", img.get_height())
		for f in interval:
			await process_frame
	quit(0)
