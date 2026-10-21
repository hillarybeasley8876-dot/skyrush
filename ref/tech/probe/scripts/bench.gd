extends SceneTree
# Feature-cost benchmark. Usage (windowed, vsync off):
#   ./run.sh 200 --path . --resolution 1920x1080 --script res://scripts/bench.gd -- --configs=base,glow,ssr --shots=base,glow
# Prints one RESULT line per config: fps (wall clock), gpu ms (RenderingServer measured), draw calls.
const World := preload("res://scripts/bench_world.gd")
var features_path := "res://scripts/bench_features.gd"   # --features=res://scripts/inst_features.gd
const WARM_MS := 1200
const MEASURE_MS := 2000

var w
var fx
var configs: PackedStringArray = ["base"]
var shots: PackedStringArray = []
var idx := -1
var warm := true
var t0 := 0
var frames := 0
var gpu_sum := 0.0
var cpu_sum := 0.0
var vp_rid: RID
var drawn0 := 0        # Engine.get_frames_drawn() at measure start: detects frames macOS did not draw
var minimal := false   # --minimal: world without the 400 benchmark buildings / 50 omnis
var extra_views := 0   # --views=K renders the same camera K more times per frame (GPU amplification)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--configs="): configs = a.substr(10).split(",")
		if a.begins_with("--shots="): shots = a.substr(8).split(",")
		if a.begins_with("--views="): extra_views = a.substr(8).to_int()
		if a.begins_with("--features="): features_path = a.substr(11)
		if a == "--minimal": minimal = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	w = World.new()
	w.minimal = minimal
	w.build(get_root())
	var evps: Array[Viewport] = []
	var ecams: Array[Camera3D] = []
	for i in extra_views:
		var sv := SubViewport.new()
		sv.size = Vector2i(1920, 1080)
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		get_root().add_child(sv)          # own_world_3d=false -> shares the root World3D + WorldEnvironment
		var c := Camera3D.new()
		c.fov = w.camera.fov
		c.far = w.camera.far
		c.transform = w.camera.transform
		sv.add_child(c)
		c.current = true
		evps.append(sv)
		ecams.append(c)
	fx = load(features_path).new(w, get_root(), evps, ecams)
	vp_rid = get_root().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	print("WINDOW ", DisplayServer.window_get_size(), " VIEWPORT ", get_root().get_visible_rect().size, " vsync=", DisplayServer.window_get_vsync_mode())
	_next()

func _next() -> bool:
	idx += 1
	if idx >= configs.size():
		quit()
		return true
	fx.apply(configs[idx])
	warm = true
	t0 = Time.get_ticks_msec()
	return false

func _process(_d: float) -> bool:
	var now := Time.get_ticks_msec()
	if warm:
		if now - t0 >= WARM_MS:
			warm = false
			t0 = now
			frames = 0
			drawn0 = Engine.get_frames_drawn()
			gpu_sum = 0.0
			cpu_sum = 0.0
		return false
	frames += 1
	gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
	cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + RenderingServer.get_frame_setup_time_cpu()
	if now - t0 < MEASURE_MS:
		return false
	var secs := (now - t0) / 1000.0
	var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var objs := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var vram := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0
	print("RESULT views=%d %-22s ms=%6.2f fps=%6.1f gpu_ms=%6.2f cpu_ms=%5.2f draws=%5d objs=%5d prims=%8d vram_mb=%6.0f bake_ms=%d can_draw=%s focused=%s drawn=%.2f" % [
		extra_views + 1, configs[idx], secs * 1000.0 / frames, frames / secs, gpu_sum / frames, cpu_sum / frames, dc, objs, prims, vram, fx.last_bake_ms, DisplayServer.window_can_draw(), DisplayServer.window_is_focused(), float(Engine.get_frames_drawn() - drawn0) / frames])
	fx.last_bake_ms = -1
	if configs[idx] in shots:
		var img := get_root().get_texture().get_image()
		img.save_png("res://out/bench_%s.png" % configs[idx].replace("+", "_"))
	return _next()
