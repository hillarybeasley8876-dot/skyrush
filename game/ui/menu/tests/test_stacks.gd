extends "res://ui/menu/tests/menu_test_base.gd"
## Test of the menu stacks: a covered screen is hidden, a fast confirm → back does not leave the
## front end blank, the overlays do not stack, and the settings screen does not connect its
## signal twice.
##
## Run: tools/godot.sh test res://ui/menu/tests/test_stacks.gd


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true

	_menu = _make_menu(&"main")
	await get_tree().process_frame

	await _test_covered_screen_is_hidden()
	await _test_fast_confirm_and_back()
	await _test_fast_confirm_and_back_late()
	await _test_overlay_does_not_stack()
	await _test_settings_connects_once()
	await _test_camera_is_handed_back()
	await _test_skip_menu_keeps_the_camera()

	print("STACKS TEST %s (%d failures)" % ["FAIL" if _failure_count() > 0 else "PASS",
		_failure_count()])
	get_tree().quit(1 if _failure_count() > 0 else 0)


## A screen that is covered by another one fades out and is hidden.
func _test_covered_screen_is_hidden() -> void:
	_menu.call("open_screen", &"main")
	await get_tree().process_frame
	await _move_to(1)
	await _key(KEY_ENTER)
	await get_tree().create_timer(0.35).timeout
	var main_screen: Node = _menu.call("debug_screen", "main")
	_expect(main_screen != null, "the main menu is still on the stack")
	if main_screen != null:
		_expect(not main_screen.is_visible_in_tree(), "the covered screen is hidden")
	_expect(_visible_hint_bars(_menu.get("front_layer")) == 1, "only one hint bar is visible")
	await _key(KEY_BACKSPACE)
	await get_tree().create_timer(0.35).timeout
	_expect(_visible_hint_bars(_menu.get("front_layer")) == 1, "the main menu is back with one hint bar")


## A confirm and a back one frame apart must not leave the front end blank.
func _test_fast_confirm_and_back() -> void:
	_menu.call("open_screen", &"main")
	await get_tree().process_frame
	await _move_to(1)
	# The confirm opens the race setup, the back closes it again — in the same frame.
	await _key(KEY_ENTER)
	await _key(KEY_BACKSPACE)
	await get_tree().create_timer(0.5).timeout
	var main_screen: Node = _menu.call("debug_screen", "main")
	_expect(main_screen != null, "the main menu is on the stack after a fast confirm and back")
	if main_screen != null:
		_expect(main_screen.is_visible_in_tree(), "the main menu is visible after a fast confirm and back")
		_expect(is_equal_approx(main_screen.modulate.a, 1.0),
				"the main menu is fully opaque after a fast confirm and back")
		_expect(main_screen.process_mode == Node.PROCESS_MODE_INHERIT,
				"the main menu processes again after a fast confirm and back")
	_expect(_visible_hint_bars(_menu.get("front_layer")) == 1,
			"one hint bar is visible after a fast confirm and back")


## The same, but the pop comes a few frames later (the cover tween is still running).
func _test_fast_confirm_and_back_late() -> void:
	_menu.call("open_screen", &"main")
	await get_tree().process_frame
	await _move_to(1)
	await _key(KEY_ENTER)
	await _frames(3)
	await _key(KEY_BACKSPACE)
	await get_tree().create_timer(0.5).timeout
	var main_screen: Node = _menu.call("debug_screen", "main")
	_expect(main_screen != null and main_screen.is_visible_in_tree(),
			"the main menu is visible after a confirm and a late back")
	_expect(_visible_hint_bars(_menu.get("front_layer")) == 1,
			"one hint bar is visible after a confirm and a late back")


## The overlay stack: a screen opened from the pause menu covers it.
func _test_overlay_does_not_stack() -> void:
	_menu.call("open_screen", &"main")
	await get_tree().process_frame
	# the first overlay asked the empty overlay stack for the screen below it: "Can't take value from empty array" every time the
	# pause menu opened in a game
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	_menu.call("open_overlay", &"pause", {"mode": &"free", "options": {}})
	await get_tree().create_timer(0.35).timeout
	OS.remove_logger(counter)
	_expect(counter.errors == 0, "opening the pause menu raises no engine error (%d)" % counter.errors)
	for line in counter.first:
		print("  error: ", line)
	_expect(_overlay() == ["ScreenPause"], "the pause menu is on the overlay stack")
	_expect(_visible_hint_bars(_menu.get("overlay_layer")) == 1, "the pause menu has one hint bar")

	# The settings screen opens on the overlay: the pause menu is covered, not stacked.
	_menu.call("_on_request_screen", &"settings", {})
	await get_tree().create_timer(0.35).timeout
	var pause_screen: Node = _menu.call("debug_screen", "pause")
	_expect(pause_screen != null and not pause_screen.is_visible_in_tree(),
			"the covered pause menu is hidden")
	_expect(_visible_hint_bars(_menu.get("overlay_layer")) == 1,
			"only one hint bar is visible on the overlay stack")
	await _key(KEY_BACKSPACE)
	await get_tree().create_timer(0.35).timeout
	var back: Node = _menu.call("debug_screen", "pause")
	_expect(back != null and back.is_visible_in_tree(), "the pause menu is back")
	_expect(_visible_hint_bars(_menu.get("overlay_layer")) == 1,
			"the pause menu has one hint bar again")


## The results replace the pause menu (their dim plates must not stack).
func _test_results_replace_the_pause() -> void:
	_menu.call("open_overlay", &"pause", {"mode": &"free", "options": {}})
	await get_tree().create_timer(0.2).timeout
	_menu.call("_on_request_screen", &"results", {"kind": "free", "score": 10})
	await get_tree().create_timer(0.35).timeout
	_expect(_overlay() == ["ScreenResults"], "the results replace the pause menu")
	_expect(_visible_hint_bars(_menu.get("overlay_layer")) == 1, "the results have one hint bar")
	await _key(KEY_BACKSPACE)
	await get_tree().process_frame


## The settings screen connects its selection once, not once per visit.
func _test_settings_connects_once() -> void:
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	_menu.call("open_screen", &"settings")
	await get_tree().process_frame
	for i in 3:
		# The controls page and back again.
		_menu.call("_on_request_screen", &"controls", {})
		await get_tree().process_frame
		await _key(KEY_BACKSPACE)
		await get_tree().process_frame
	OS.remove_logger(counter)
	_expect(counter.errors == 0, "settings → controls → back x3 raises no engine error (%d)" % [
		counter.errors])
	if counter.errors > 0:
		for line in counter.first:
			print("  error: ", line)
	var settings: Node = _menu.call("debug_screen", "settings")
	if settings != null:
		var list: Variant = settings.get("list")
		var connections: Array = list.selection_changed.get_connections()
		var own := 0
		for connection: Dictionary in connections:
			var callable := connection["callable"] as Callable
			if callable.get_object() == settings:
				own += 1
		_expect(own == 1, "the settings screen connects its selection once (%d)" % own)


## The menu hands the camera back to the game when a mode starts.
func _test_camera_is_handed_back() -> void:
	var camera := _game_camera()
	_expect(camera != null, "the game camera is rendering")
	_menu.call("_start_mode", &"free", {})
	await get_tree().process_frame
	_expect(_front().is_empty(), "starting a mode closes the front end")
	_expect(get_viewport().get_camera_3d() == camera, "the game camera is current again")


## With --skip-menu the menu never takes the camera.
func _test_skip_menu_keeps_the_camera() -> void:
	Game.options["skip-menu"] = "true"
	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true
	var menu := _make_menu(&"main")
	await get_tree().process_frame
	_expect((_state_of(menu)["front"] as Array).is_empty(), "--skip-menu opens no screen")
	_expect(get_viewport().get_camera_3d() == camera, "--skip-menu keeps the game camera")
	var front: Variant = menu.get("front_end")
	_expect(front != null and front.get("stage") == null, "--skip-menu creates no title stage")
	menu.queue_free()
	camera.queue_free()
	Game.options.erase("skip-menu")
	await get_tree().process_frame


## --- helpers --------------------------------------------------------------------------------------

## Moves the selection to a row (the cursor only moves one row per press).
func _move_to(index: int) -> void:
	for i in 8:
		if _selection() == index:
			return
		if _selection() < index:
			await _key(KEY_DOWN)
		else:
			await _key(KEY_UP)


## The camera of the game (the one the test made current).
func _game_camera() -> Camera3D:
	for child in get_children():
		if child is Camera3D:
			return child as Camera3D
	return null
