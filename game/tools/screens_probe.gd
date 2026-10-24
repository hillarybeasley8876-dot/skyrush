extends SceneTree
## Prints the screens that Godot sees: the size, the refresh rate, which one is the primary and which one the window is on.
##   Godot --path game -s res://tools/screens_probe.gd


func _initialize() -> void:
	var count := DisplayServer.get_screen_count()
	print("SCREENS %d, primary %d, the window on %d, vsync mode %d" % [count, DisplayServer.get_primary_screen(),
		DisplayServer.window_get_current_screen(), DisplayServer.window_get_vsync_mode()])
	for i in count:
		print("SCREEN %d: size %s at %s, refresh %.2f Hz, dpi %d, scale %.2f" % [i, str(DisplayServer.screen_get_size(i)),
			str(DisplayServer.screen_get_position(i)), DisplayServer.screen_get_refresh_rate(i), DisplayServer.screen_get_dpi(i),
			DisplayServer.screen_get_scale(i)])
	quit(0)
