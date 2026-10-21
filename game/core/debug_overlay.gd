extends CanvasLayer
## F3 debug overlay (core-owned): fps, frame time, draw calls, units real/stub, player telemetry.
## Shown at start with --debug. Tests and critics use it to read state from screenshots.

var _label: Label


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_label = Label.new()
	_label.position = Vector2(12.0, 12.0)
	_label.add_theme_font_size_override(&"font_size", 15)
	_label.add_theme_color_override(&"font_color", Color(0.75, 1.0, 0.85))
	_label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_label.add_theme_constant_override(&"outline_size", 4)
	add_child(_label)
	visible = Game.has_option("debug")


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		visible = not visible


func _process(_delta: float) -> void:
	if not visible:
		return
	var lines: PackedStringArray = []
	lines.append("fps %d  (%.1f ms)  draw %d  objs %d" % [Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	var stubs: PackedStringArray = []
	for unit: StringName in Modules.loaded:
		if Modules.loaded[unit] == "stub":
			stubs.append(String(unit))
	lines.append("stubs: " + (", ".join(stubs) if not stubs.is_empty() else "none"))
	var car := Game.player
	if car != null:
		var t := car.telemetry
		lines.append("pos %s  %.0f km/h  air %s  n2 %.0f (+%.0f)  bat %.2f" % [
			str(car.global_position.snapped(Vector3.ONE * 0.1)), t.speed_kmh, str(t.airborne),
			t.n2, t.n2_pending, t.battery])
		lines.append("drift %s  boost %s  fly %s  alt %.1f m  hp %.0f" % [String(t.drift_state),
			String(t.boost_kind), str(t.flying), t.altitude_m, car.health])
	_label.text = "\n".join(lines)
