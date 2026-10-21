extends Control
## Base class for every menu screen.
##
## Screens never talk to each other: they emit a request signal and the menu root decides what to
## do with it (push another screen, start a mode, go back, quit). That keeps the front end free of
## references to other units' code.
##
## Every screen fades and slides in (0.22 s, 24 px) and out again, and it never blocks the input.

const ResultsRouter := preload("res://ui/menu/results_router.gd")
const FrontEnd := preload("res://ui/menu/front_end.gd")

signal request_screen(screen: StringName, data: Dictionary)
signal request_mode(mode: StringName, options: Dictionary)
signal request_back()
signal request_quit()
signal request_main_menu()
## Close every overlay and resume the game.
signal request_resume()

## Which screen this is ("race_setup", "pause", ...); the menu sets it.
var kind: StringName = &""

## The menu root (the screens reach the title stage through it).
var menu: Node = null

## The front end (the title stage lives there).
var front_end: FrontEnd = null

## The menu's side of the modes unit (the records and the results).
var router: ResultsRouter = null

## The menu root hands the screen the shared preferences before pushing it.
var prefs: RefCounted = null

## Extra data for the screen (the results payload, the pause reason, ...).
var payload: Dictionary = {}

const TRANSITION_TIME := 0.22
const TRANSITION_SLIDE := 24.0
## How long a screen takes to fade out when another screen covers it.
const COVER_FADE := 0.18

var _transition: float = 1.0
var _cover: float = 1.0
var _exiting: bool = false
var _slide_dir: float = 1.0
## The running cover tween (the screen owns it, so a pop can kill it).
var _cover_tween: Tween = null
## True while another screen is on top of this one.
var _covered: bool = false


func _ready() -> void:
	set_process(true)


## Called by the root when the screen becomes the active one.
func on_enter() -> void:
	pass


## Called by the root when the screen is popped or replaced.
func on_exit() -> void:
	pass


## Handles a menu action. Return true when the screen consumed it.
func handle_action(_action: StringName, _event: InputEvent) -> bool:
	return false


## Handles a back request (Esc / B). Return true when the screen consumed it.
func handle_back() -> bool:
	return false


## Handles an event that is not a menu action (a raw key, a mouse click). The title takes any.
func handle_raw_event(_event: InputEvent) -> bool:
	return false


## Index of the highlighted row (-1 when the screen has no list). Used by the tests.
func debug_selection() -> int:
	return -1


## The alpha of the screen (1 = shown, 0 = covered by another screen).
func cover_alpha() -> float:
	return _cover


## Sets the alpha of the screen (1 = shown, 0 = covered by another screen).
func set_cover(value: float) -> void:
	_cover = value
	_apply_transition()


## Hides the screen at once: another screen is on top of it.
func cover() -> void:
	_covered = true
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	set_cover(0.0)


## Shows the screen again (it was covered by another one).
func uncover() -> void:
	_covered = false
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	set_cover(0.0)


## Fades the screen out: another screen is coming on top of it.
##
## The screen owns the tween, so a pop can kill it: a fast confirm → back must not leave the
## screen hidden by a tween that was started before the pop.
func begin_cover() -> void:
	_kill_cover_tween()
	_covered = true
	_cover_tween = create_tween()
	_cover_tween.tween_method(set_cover, cover_alpha(), 0.0, COVER_FADE)
	_cover_tween.tween_callback(_hide_if_covered)


## Fades the screen back in: the screen on top of it is gone.
##
## The screen is made visible and processable *before* the tween is created, or the tween would
## be bound to a disabled node and would never run.
func begin_uncover() -> void:
	_kill_cover_tween()
	_covered = false
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	set_cover(0.0)
	_cover_tween = create_tween()
	_cover_tween.tween_method(set_cover, 0.0, 1.0, COVER_FADE)


## Kills the running cover tween (a new one takes over).
func _kill_cover_tween() -> void:
	if _cover_tween != null and _cover_tween.is_valid():
		_cover_tween.kill()
	_cover_tween = null


## Hides the screen — but only when it is still covered (a pop may have uncovered it).
func _hide_if_covered() -> void:
	if not _covered:
		return
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	set_cover(0.0)


## Fades and slides the screen in.
func play_enter() -> void:
	_exiting = false
	_slide_dir = 1.0
	_transition = 0.0
	_apply_transition()


## Shows the screen at once, without the fade (the loading screen must never show the world
## through it while it fades in).
func appear_now() -> void:
	_transition = 1.0
	_apply_transition()


## Fades and slides the screen out; the screen frees itself when the transition is done.
func play_exit() -> void:
	_exiting = true
	_slide_dir = -1.0


func _process(delta: float) -> void:
	if _exiting:
		_transition = maxf(0.0, _transition - delta / TRANSITION_TIME)
		_apply_transition()
		if _transition <= 0.0:
			queue_free()
		return
	if _transition < 1.0:
		_transition = minf(1.0, _transition + delta / TRANSITION_TIME)
		_apply_transition()


func _apply_transition() -> void:
	modulate.a = _transition * _cover
	position.x = (1.0 - _transition) * TRANSITION_SLIDE * _slide_dir
