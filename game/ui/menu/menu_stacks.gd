extends RefCounted
## The menu's screen stacks.
##
## * front  — the front end: loading, title, main menu, race setup, settings, controls.
## * overlay — on top of the game: pause, results.
##
## The overlay wins when both are present, so a screen opened from the pause menu lands on the
## overlay. The stack attaches the screens' request signals and plays their transitions; the
## menu root decides what a request means.

signal request_screen(screen: StringName, data: Dictionary)
signal request_mode(mode: StringName, options: Dictionary)
signal request_back()
signal request_quit()
signal request_main_menu()
signal request_resume()
## The front stack changed: `open` is false when the front end was closed.
signal front_changed(open: bool)
## A screen was pushed or popped.
signal changed()

const MenuScreen := preload("res://ui/menu/screens/menu_screen.gd")

## How long a screen takes to fade out when another screen covers it.
const COVER_FADE := 0.18

var front: Array[Control] = []
var overlay: Array[Control] = []
## Called with the screen before it is attached (the root fills in the prefs and the router).
var prepare: Callable = Callable()

var _front_layer: Control
var _overlay_layer: Control


func _init(front_layer: Control, overlay_layer: Control) -> void:
	_front_layer = front_layer
	_overlay_layer = overlay_layer


func push_front(screen: Control, payload: Dictionary = {}, replace: bool = false) -> void:
	if screen == null:
		return
	_attach(screen, payload)
	if replace and not front.is_empty():
		_remove(front.pop_back())
	if not front.is_empty():
		# The screen below fades out: only one screen is visible at a time.
		_cover(front.back())
	screen.name = _unique_name(_front_layer, String(screen.name))
	_front_layer.add_child(screen)
	front.append(screen)
	_enter(screen)
	changed.emit()
	front_changed.emit(true)


## Pops the front stack, but never below the main menu (the floor of the front end).
func pop_front() -> bool:
	if front.size() <= 1:
		return false
	_remove(front.pop_back())
	_enter(front.back())
	_uncover(front.back())
	changed.emit()
	front_changed.emit(true)
	return true


func push_overlay(screen: Control, payload: Dictionary = {}, replace: bool = false) -> void:
	if screen == null:
		return
	if replace:
		# The results replace the pause menu: the two dim plates must not stack.
		_clear_overlay_now()
	_attach(screen, payload)
	screen.name = _unique_name(_overlay_layer, String(screen.name))
	_overlay_layer.add_child(screen)
	var below: Control = overlay.back()
	overlay.append(screen)
	if below != null:
		# The screen below fades out: only one screen is visible at a time.
		_cover(below)
	_enter(screen)
	changed.emit()


## Replaces the whole overlay stack with one screen (the results replace the pause menu).
func replace_overlay(screen: Control, payload: Dictionary = {}) -> void:
	if screen == null:
		return
	_clear_overlay_now()
	push_overlay(screen, payload)


## Hides and frees the overlay screens at once (no fade: something covers them).
func _clear_overlay_now() -> void:
	for screen in overlay:
		var base := screen as MenuScreen
		if base != null:
			base.cover()
		if is_instance_valid(screen):
			screen.queue_free()
	overlay.clear()


func pop_overlay() -> bool:
	if overlay.is_empty():
		return false
	_remove(overlay.pop_back())
	if not overlay.is_empty():
		_uncover(overlay.back())
	changed.emit()
	return true


func clear_overlay() -> void:
	while not overlay.is_empty():
		_remove(overlay.pop_back())
	changed.emit()


func clear_front() -> void:
	while not front.is_empty():
		_remove(front.pop_back())
	changed.emit()
	front_changed.emit(false)


## The screen that receives the input: the overlay wins over the front end.
func active() -> Control:
	if not overlay.is_empty():
		return overlay.back()
	if not front.is_empty():
		return front.back()
	return null


func names(stack: Array) -> Array:
	var out: Array = []
	for screen in stack:
		out.append(String(screen.name))
	return out


## A name that is not used by another screen of the layer yet.
func _unique_name(layer: Control, wanted: String) -> String:
	if wanted.is_empty():
		return wanted
	var candidate := wanted
	var index := 2
	while layer.get_node_or_null(NodePath(candidate)) != null:
		candidate = "%s%d" % [wanted, index]
		index += 1
	return candidate


func _attach(screen: Control, payload: Dictionary) -> void:
	var base := screen as MenuScreen
	if base == null:
		return
	base.payload = payload
	if prepare.is_valid():
		prepare.call(base)
	base.request_screen.connect(_on_request_screen)
	base.request_mode.connect(_on_request_mode)
	base.request_back.connect(_on_request_back)
	base.request_quit.connect(_on_request_quit)
	base.request_main_menu.connect(_on_request_main_menu)
	base.request_resume.connect(_on_request_resume)


## Fades the screen out: another screen is on top of it.
func _cover(screen: Control) -> void:
	var base := screen as MenuScreen
	if base == null:
		return
	base.begin_cover()


## Fades the screen back in: the screen on top of it is gone.
func _uncover(screen: Control) -> void:
	var base := screen as MenuScreen
	if base == null:
		return
	base.begin_uncover()


func _enter(screen: Control) -> void:
	var base := screen as MenuScreen
	if base == null:
		return
	base.on_enter()
	base.play_enter()


## The screen fades out and frees itself when its transition is done.
func _remove(screen: Control) -> void:
	var base := screen as MenuScreen
	if base != null:
		base.on_exit()
		base.play_exit()
		return
	if is_instance_valid(screen):
		screen.queue_free()


func _on_request_screen(screen: StringName, data: Dictionary) -> void:
	request_screen.emit(screen, data)


func _on_request_mode(mode: StringName, options: Dictionary) -> void:
	request_mode.emit(mode, options)


func _on_request_back() -> void:
	request_back.emit()


func _on_request_quit() -> void:
	request_quit.emit()


func _on_request_main_menu() -> void:
	request_main_menu.emit()


func _on_request_resume() -> void:
	request_resume.emit()
