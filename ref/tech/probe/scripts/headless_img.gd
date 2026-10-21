extends SceneTree
func _initialize() -> void:
	_go.call_deferred()
func _go() -> void:
	print("DISPLAY ", DisplayServer.get_name(), " RENDER ", RenderingServer.get_current_rendering_driver_name())
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	print("HEADLESS_IMG ", "null" if img == null else "%dx%d empty=%s" % [img.get_width(), img.get_height(), img.is_empty()])
	quit()
