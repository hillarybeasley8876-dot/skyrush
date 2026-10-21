extends "res://ui/menu/tests/menu_test_base.gd"
## Scripted navigation test for the SKYRUSH menu.
##
## Covers the acceptance items: the front end is navigable with the keyboard alone and with the
## gamepad alone, a confirmed press is answered within one frame, the title takes any key, the
## info panel follows the selection, the UI sounds play and the mouse works.
##
## Run: tools/godot.sh test res://ui/menu/tests/test_menu.gd

const MainMenuScript := preload("res://ui/menu/screens/main_menu.gd")
const Logo := preload("res://ui/menu/widgets/logo.gd")

## A stand-in for the audio unit: it counts the sounds the menu asks for.
class FakeAudio extends Node:
	var played: Array[StringName] = []

	func _ready() -> void:
		add_to_group(&"audio")

	func play_sfx(id: StringName, _volume_db: float = 0.0, _pitch: float = 1.0) -> void:
		played.append(id)


var _audio: FakeAudio = null


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_audio = FakeAudio.new()
	add_child(_audio)

	var camera := Camera3D.new()
	add_child(camera)
	camera.current = true

	_menu = _make_menu(&"main")
	await get_tree().process_frame

	_check_actions()
	await _test_keyboard()
	await _test_gamepad()
	await _test_stick_does_not_flood()
	await _test_info_panel_follows()
	await _test_pursuit_setup()
	await _test_title_takes_any_key()
	await _test_sounds()
	await _test_mouse_click()
	await _test_stick_directions()
	await _test_stick_repeat()
	await _test_logo_spacing()

	print("MENU TEST %s (%d failures)" % ["FAIL" if _failure_count() > 0 else "PASS",
		_failure_count()])
	get_tree().quit(1 if _failure_count() > 0 else 0)


func _check_actions() -> void:
	for action: StringName in [&"menu_up", &"menu_down", &"menu_left", &"menu_right",
			&"menu_accept", &"menu_cancel"]:
		_expect(InputMap.has_action(action), "action %s registered" % action)
	_expect(InputMap.has_action(&"pause"), "core pause action registered")


func _test_keyboard() -> void:
	_expect(_front() == ["ScreenMain"], "menu opens on the main screen")
	_expect(_selection() == 0, "the first row is selected")
	await _key(KEY_DOWN)
	_expect(_selection() == 1, "keyboard: down moves the selection")
	await _key(KEY_UP)
	_expect(_selection() == 0, "keyboard: up moves the selection back")
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	_expect(_selection() == 3, "keyboard: down x3 reaches the settings row")
	await _key(KEY_ENTER)
	_expect(_front() == ["ScreenMain", "ScreenSettings"], "keyboard: enter opens the settings")
	await _key(KEY_BACKSPACE)
	_expect(_front() == ["ScreenMain"], "keyboard: back returns to the main menu")


func _test_gamepad() -> void:
	await _button(JOY_BUTTON_DPAD_UP)
	await _button(JOY_BUTTON_DPAD_UP)
	_expect(_selection() == 1, "gamepad: d-pad up moves the selection")
	await _button(JOY_BUTTON_A)
	_expect(_front() == ["ScreenMain", "ScreenRaceSetup"], "gamepad: A opens the race setup")
	await _button(JOY_BUTTON_B)
	_expect(_front() == ["ScreenMain"], "gamepad: B returns to the main menu")


## One push of the stick is one move, not one per motion event.
func _test_stick_does_not_flood() -> void:
	var start := _selection()
	for i in 8:
		await _axis(JOY_AXIS_LEFT_Y, 0.3 + 0.1 * float(i))
	await get_tree().process_frame
	_expect(_selection() == start + 1, "gamepad: one stick push moves the selection by one")
	await _axis(JOY_AXIS_LEFT_Y, 0.0)
	await get_tree().process_frame


## The info panel of the main menu follows the highlighted row.
func _test_info_panel_follows() -> void:
	var before := _selection()
	await _key(KEY_DOWN)
	var after := _selection()
	_expect(after == before + 1, "the selection moved down")
	_expect(_panel_title().contains(_item_title(after)), "the info panel follows the selection")
	await _key(KEY_UP)
	_expect(_panel_title().contains(_item_title(before)), "the info panel follows the selection back")


## The pursuit opens its setup (the goal, the number of police cars, the heat).
func _test_pursuit_setup() -> void:
	await _move_to(2)
	await _key(KEY_ENTER)
	_expect(_front() == ["ScreenMain", "ScreenPursuitSetup"], "the pursuit opens its setup")
	if _front().size() < 2:
		return
	# The cursor starts on 开始追捕.
	await _key(KEY_ENTER)
	var options: Dictionary = _menu.get("_current_options")
	_expect(String(options.get("goal", "")) != "", "the pursuit carries its goal")
	_expect(int(options.get("count", 0)) > 0, "the pursuit carries the number of units")
	_expect(int(options.get("heat", 0)) > 0, "the pursuit carries the starting heat")
	# The pursuit started, so the front end is closed: open the main menu again.
	_menu.call("open_screen", &"main")
	await get_tree().process_frame


## The title takes any key, any button and any click.
func _test_title_takes_any_key() -> void:
	var title_menu := _make_menu(&"title")
	await get_tree().process_frame
	_expect(_state_of(title_menu)["front"] == ["ScreenTitle"], "the title screen is open")
	await _key(KEY_X)
	_expect(_state_of(title_menu)["front"] == ["ScreenMain"], "title: an ordinary key starts the game")
	title_menu.queue_free()
	await get_tree().process_frame

	var start_menu := _make_menu(&"title")
	await get_tree().process_frame
	await _button(JOY_BUTTON_START)
	_expect(_state_of(start_menu)["front"] == ["ScreenMain"], "title: the start button starts the game")
	start_menu.queue_free()
	await get_tree().process_frame

	var pad_menu := _make_menu(&"title")
	await get_tree().process_frame
	await _button(JOY_BUTTON_Y)
	_expect(_state_of(pad_menu)["front"] == ["ScreenMain"], "title: any pad button starts the game")
	pad_menu.queue_free()
	await get_tree().process_frame


## A click on a row moves the selection (and must not raise an error).
func _test_mouse_click() -> void:
	var list := _list_of(_menu)
	_expect(list != null, "the main menu has a list")
	if list == null:
		return
	var item: Node = list.call("get_item", 1)
	_expect(item != null, "the list has a second row")
	if item == null:
		return
	item.emit_signal("activated")
	await get_tree().process_frame
	_expect(_menu.call("debug_screen", "race_setup") != null, "mouse: clicking a row opens it")
	await _key(KEY_BACKSPACE)
	await get_tree().process_frame


## The menu asks the audio unit for the UI sounds.
func _test_sounds() -> void:
	# A row that opens a screen (not a mode): the main menu stays open.
	await _move_to(1)
	_audio.played.clear()
	await _key(KEY_DOWN)
	await get_tree().process_frame
	_expect(_audio.played.has(&"ui_hover"), "a move plays the hover sound")
	_audio.played.clear()
	await _key(KEY_ENTER)
	await get_tree().process_frame
	_expect(_audio.played.has(&"ui_confirm"), "a confirm plays the confirm sound")
	_audio.played.clear()
	await _key(KEY_BACKSPACE)
	await get_tree().process_frame
	_expect(_audio.played.has(&"ui_back"), "going back plays the back sound")


## The stick moves the selection one row per push, in every direction.
func _test_stick_directions() -> void:
	_menu.call("open_screen", &"main")
	await get_tree().process_frame
	await _move_to(0)
	var start := _selection()
	await _axis(JOY_AXIS_LEFT_Y, 1.0)
	await get_tree().process_frame
	_expect(_selection() == start + 1, "stick: down moves the selection down")
	await _axis(JOY_AXIS_LEFT_Y, 0.0)
	await _axis(JOY_AXIS_LEFT_Y, -1.0)
	await get_tree().process_frame
	_expect(_selection() == start, "stick: up moves the selection up")
	await _axis(JOY_AXIS_LEFT_Y, 0.0)
	await get_tree().process_frame
	# Left and right change a value (the quality row of the settings).
	_menu.call("open_screen", &"settings")
	await get_tree().process_frame
	var settings: Node = _menu.call("debug_screen", "settings")
	if settings != null:
		var list: Variant = settings.get("list")
		var row: Variant = list.call("get_item", 0)
		var before := String(row.get("value_label").text)
		await _axis(JOY_AXIS_LEFT_X, 1.0)
		await get_tree().process_frame
		var after := String(row.get("value_label").text)
		_expect(before != after, "stick: right changes the value of a row")
		await _axis(JOY_AXIS_LEFT_X, 0.0)
		await get_tree().process_frame
		# And to the left again.
		await _axis(JOY_AXIS_LEFT_X, -1.0)
		await get_tree().process_frame
		var back := String(row.get("value_label").text)
		_expect(back != after, "stick: left changes the value of a row")
		await _axis(JOY_AXIS_LEFT_X, 0.0)
	await get_tree().process_frame


## A held stick gives one move and then repeats.
func _test_stick_repeat() -> void:
	# The settings screen has enough rows below the cursor to see every repeat.
	_menu.call("open_screen", &"settings")
	await get_tree().process_frame
	await _move_to(0)
	var start := _selection()
	await _axis(JOY_AXIS_LEFT_Y, 1.0)
	var moves := 0
	# The test runs at a fixed 120 fps, so 120 frames are one second of game time.
	for i in 120:
		await get_tree().process_frame
		moves = _selection() - start
	await _axis(JOY_AXIS_LEFT_Y, 0.0)
	await get_tree().process_frame
	_expect(moves >= 6 and moves <= 8, "a 1 s stick hold gives one move and the repeats (%d)" % moves)


## The letters of the logo follow each other (the spacing bug of round 1).
func _test_logo_spacing() -> void:
	var logo := Logo.new()
	logo.font_size = 104
	add_child(logo)
	await get_tree().process_frame
	var positions := logo.glyph_positions()
	_expect(positions.size() == 7, "the logo has seven letters")
	var monotonic := true
	var sane := true
	for i in range(1, positions.size()):
		var gap := positions[i] - positions[i - 1]
		monotonic = monotonic and gap > 0.0
		sane = sane and gap < 200.0
	_expect(monotonic, "the letters of the logo follow each other")
	_expect(sane, "the letters of the logo do not jump")
	logo.queue_free()
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


## The title of a row of the main menu.
func _item_title(index: int) -> String:
	var items: Array = MainMenuScript.ITEMS
	if index < 0 or index >= items.size():
		return ""
	return String((items[index] as Dictionary)["title"])


## The title of the info panel of the main menu.
func _panel_title() -> String:
	var screen := _front_screen()
	if screen == null:
		return ""
	var label := screen.get("title_label") as Label
	return label.text if label != null else ""


## The list of the main menu.
func _list_of(menu: Node) -> Node:
	var screen := _front_screen_of(menu)
	if screen == null:
		return null
	return screen.get("list")


func _front_screen() -> Node:
	return _front_screen_of(_menu)


func _front_screen_of(menu: Node) -> Node:
	return menu.call("debug_screen", "main")
