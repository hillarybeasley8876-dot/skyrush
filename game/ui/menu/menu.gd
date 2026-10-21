extends CanvasLayer
## SKYRUSH front end: loading → title → main menu, plus the pause and the results overlays.
##
## Owns `res://ui/menu/**` only. Other units are never edited: the modes, environment, camera and
## audio units are reached through `bridge.gd` and `results_router.gd`, which duck-type a method
## name.
##
## Two stacks: the *front* stack is the front end (main menu, race setup, settings, ...), the
## *overlay* stack sits on top of the game (pause, results). The overlay stack wins when both are
## present, so a screen pushed from the pause menu lands on the overlay.
##
## While the front end is up the menu owns the camera (the title stage), the car is parked and
## the HUD is hidden.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const Layout := preload("res://ui/menu/widgets/layout.gd")
const MenuInput := preload("res://ui/menu/menu_input.gd")
const Bridge := preload("res://ui/menu/bridge.gd")
const Prefs := preload("res://ui/menu/prefs.gd")
const MenuScreen := preload("res://ui/menu/screens/menu_screen.gd")
const MenuStacks := preload("res://ui/menu/menu_stacks.gd")
const MenuScreens := preload("res://ui/menu/menu_screens.gd")
const MenuDebug := preload("res://ui/menu/menu_debug.gd")
const ResultsRouter := preload("res://ui/menu/results_router.gd")
const FrontEnd := preload("res://ui/menu/front_end.gd")
const LoadingScreen := preload("res://ui/menu/screens/loading_screen.gd")

var root: Control
var front_layer: Control
var overlay_layer: Control
var prefs: Prefs
var router: ResultsRouter
var front_end: FrontEnd

## Set by the demo / tests to open a specific screen instead of the loading screen.
var demo_screen: StringName = &""
## The file the preferences are read from and written to ("" = the player's file).
var prefs_path: String = ""

var _stacks: MenuStacks
var _debug: MenuDebug
var _input_state: MenuInput
var _skip_menu: bool = false
var _await_release: bool = false
var _current_options: Dictionary = {}
var _paused_by_menu: bool = false


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	MenuInput.register()
	_input_state = MenuInput.new()
	prefs = Prefs.new(prefs_path)
	prefs.load_from_disk()
	router = ResultsRouter.new()
	router.results_ready.connect(_on_results_ready)
	front_end = FrontEnd.new()
	_skip_menu = Game.has_option("skip-menu")
	_build()
	_connect_events()
	_apply_saved_preferences()
	if _skip_menu:
		return
	_push_front(demo_screen if demo_screen != &"" else &"loading")


func _build() -> void:
	root = Control.new()
	Layout.fill(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.build()
	add_child(root)

	front_layer = Control.new()
	Layout.fill(front_layer)
	front_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(front_layer)

	overlay_layer = Control.new()
	Layout.fill(overlay_layer)
	overlay_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay_layer)

	_stacks = MenuStacks.new(front_layer, overlay_layer)
	_stacks.prepare = _prepare_screen
	_debug = MenuDebug.new(_stacks, get_tree())
	_stacks.request_screen.connect(_on_request_screen)
	_stacks.request_mode.connect(_on_request_mode)
	_stacks.request_back.connect(_on_request_back)
	_stacks.request_quit.connect(_on_request_quit)
	_stacks.request_main_menu.connect(_on_request_main_menu)
	_stacks.request_resume.connect(_on_request_resume)
	_stacks.front_changed.connect(_on_front_changed)
	_stacks.changed.connect(_on_stack_changed)


func _exit_tree() -> void:
	if front_end != null and front_end.stage != null and is_instance_valid(front_end.stage):
		# The stage gives the camera back before it goes.
		front_end.stage.deactivate()
		front_end.stage.queue_free()


func _connect_events() -> void:
	Events.race_finished.connect(_on_race_finished)


## The screen gets the prefs, the router and the root before it is attached.
func _prepare_screen(base: MenuScreen) -> void:
	base.menu = self
	base.router = router
	base.front_end = front_end
	base.prefs = prefs


## The rain and the motion blur of the last session are applied once, when the menu starts.
func _apply_saved_preferences() -> void:
	if prefs.rain != Bridge.is_raining():
		Bridge.set_rain(prefs.rain)
	if prefs.motion_blur != Bridge.motion_blur_enabled():
		Bridge.set_motion_blur(prefs.motion_blur)


## --- input ----------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	MenuInput.note_device(event)
	# The stick axes are polled by the input state (one move per push, not per motion event).
	if event is InputEventJoypadMotion:
		return
	var action := MenuInput.action_of(event)
	if action != &"":
		if event.is_action_pressed(action):
			_input_state.note_press(action)
			_dispatch(action, event)
		else:
			_input_state.note_release(action)
		return
	# A screen may want a raw event (the title takes any key).
	var base := _stacks.active() as MenuScreen
	if base != null and base.handle_raw_event(event):
		get_viewport().set_input_as_handled()
		return
	# The core pause action (Esc / P / Start) means "back" in the front end.
	if InputMap.has_action(&"pause") and event.is_action_pressed(&"pause"):
		if _handle_pause():
			get_viewport().set_input_as_handled()


## Sends an action to the active screen and plays the sound of it.
func _dispatch(action: StringName, event: InputEvent) -> void:
	if action == &"menu_cancel":
		if _handle_back():
			get_viewport().set_input_as_handled()
		return
	if action == &"menu_accept" and _await_release:
		return
	var base := _stacks.active() as MenuScreen
	if base == null:
		return
	if base.handle_action(action, event):
		Bridge.ui_sound_for(action)
		get_viewport().set_input_as_handled()


## Esc / Start: back in the front end, close an overlay, or open the pause menu.
func _handle_pause() -> bool:
	if not _stacks.overlay.is_empty() or not _stacks.front.is_empty():
		return _handle_back()
	return _open_pause()


## B / Backspace: always "back", never "pause".
func _handle_back() -> bool:
	var base := _stacks.active() as MenuScreen
	if base != null and base.handle_back():
		return true
	if _pop_overlay():
		return true
	return _stacks.pop_front()


func _open_pause() -> bool:
	var screen := MenuScreens.make(&"pause")
	if screen == null:
		return false
	_stacks.push_overlay(screen, {"mode": Game.mode, "options": _current_options})
	Game.set_paused(true)
	_paused_by_menu = true
	Bridge.ui_sound(&"ui_whoosh")
	return true


## --- screen requests ------------------------------------------------------------------------------

func _on_request_screen(name: StringName, data: Dictionary) -> void:
	if name == &"main":
		_push_front(&"main")
		return
	var screen := MenuScreens.make(name)
	if screen == null:
		return
	if not _stacks.overlay.is_empty():
		# The results replace the pause menu: the two dim plates must not stack.
		_stacks.push_overlay(screen, data, name == &"results")
	else:
		_stacks.push_front(screen, data)
	Bridge.ui_sound(&"ui_whoosh")


func _on_request_mode(mode: StringName, options: Dictionary) -> void:
	_start_mode(mode, options)


func _on_request_back() -> void:
	Bridge.ui_sound(&"ui_back")
	if not _stacks.overlay.is_empty():
		_pop_overlay()
	else:
		_stacks.pop_front()


func _on_request_quit() -> void:
	get_tree().quit()


## Closes every overlay and resumes the game.
func _on_request_resume() -> void:
	_clear_overlays()
	Game.set_paused(false)
	_paused_by_menu = false


func _on_request_main_menu() -> void:
	_clear_overlays()
	_stacks.clear_front()
	Game.set_paused(false)
	_paused_by_menu = false
	Game.mode = &"menu"
	router.park_session()
	# The car goes back to the spot of the title stage (it stopped where the player quit).
	front_end.repark()
	_push_front(&"main")


## Opens a screen of the front end directly (demo / tests).
func open_screen(name: StringName) -> void:
	_push_front(name)


## Opens a screen on top of the game (demo / tests).
func open_overlay(name: StringName, data: Dictionary = {}) -> void:
	_stacks.push_overlay(MenuScreens.make(name), data)
	Game.set_paused(true)
	_paused_by_menu = true


## Opens a screen of the front end.
func _push_front(name: StringName) -> void:
	var screen := MenuScreens.make(name)
	if screen == null:
		return
	_stacks.push_front(screen, {}, true)
	Bridge.ui_sound(&"ui_whoosh")


## --- game events ----------------------------------------------------------------------------------

## The race results of the modes unit (the session reports them as well; this is the fallback).
func _on_race_finished(results: Array) -> void:
	if _skip_menu or has_screen("results"):
		return
	_show_results(router.build_payload(results))


## The modes unit reported the results of a session.
func _on_results_ready(payload: Dictionary) -> void:
	_show_results(payload)


func _show_results(payload: Dictionary) -> void:
	if _skip_menu or payload.is_empty():
		return
	if has_screen("results"):
		return
	_stacks.push_overlay(MenuScreens.make(&"results"), payload)
	Game.set_paused(true)
	_paused_by_menu = true
	Bridge.ui_sound(&"ui_whoosh")


## --- frame ----------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _await_release and not Input.is_action_pressed(&"menu_accept"):
		_await_release = false
	# The stick and the held keys repeat here (one move per push, then every 0.12 s).
	for action in _input_state.poll(delta):
		_dispatch(action, null)
	_update_loading()


## The loading screen gives way to the title when it is done.
func _update_loading() -> void:
	if _stacks.front.is_empty():
		return
	var screen := _stacks.front.back() as LoadingScreen
	if screen != null and screen.is_done():
		_push_front(&"title")


## Starts a mode: the front end closes, the modes unit runs the session.
func _start_mode(mode: StringName, options: Dictionary) -> void:
	_current_options = options
	_clear_overlays()
	_stacks.clear_front()
	Game.set_paused(false)
	_paused_by_menu = false
	Game.mode = mode
	if not router.start(mode, options):
		push_warning("[menu] no modes unit with start_mode(); only Game.mode was set")
	front_end.close(get_tree())


## Closes the top overlay (and unpauses the game when the menu was the one that paused it).
func _pop_overlay() -> bool:
	if not _stacks.pop_overlay():
		return false
	if _stacks.overlay.is_empty() and _paused_by_menu:
		_paused_by_menu = false
		Game.set_paused(false)
	return true


func _clear_overlays() -> void:
	_stacks.clear_overlay()
	if _paused_by_menu:
		_paused_by_menu = false
		Game.set_paused(false)


## The front end owns the screen while it is up: the car is parked and the HUD is hidden.
func _on_front_changed(open: bool) -> void:
	if open:
		front_end.open(get_tree())
	else:
		front_end.close(get_tree())
	front_layer.visible = open
	_sync_stage_camera()


## The stage takes the camera when the front end is up and the loading screen is not on top of
## it (the loading screen shows the world, not the city).
func _sync_stage_camera() -> void:
	if _stacks.front.is_empty():
		return
	var top := _stacks.front.back() as MenuScreen
	var loading := top != null and top.kind == &"loading"
	front_end.set_stage_active(not loading)


## Closes the front end (the demo and the tests).
func close_front_end() -> void:
	_stacks.clear_front()


## A screen was pushed or popped: wait for the confirm key to be released before accepting it
## again, so a press that opened a screen cannot also confirm the next one.
func _on_stack_changed() -> void:
	_await_release = true
	_sync_stage_camera()


## The screen of that kind on either stack (the tests).
func debug_screen(kind: String) -> Control:
	return _debug.screen(kind)


## True when a screen of that kind is on the overlay stack.
func has_screen(kind: String) -> bool:
	return _debug.has(kind)


## What is on the stacks right now (demo / tests).
func debug_state() -> Dictionary:
	return _debug.state()


