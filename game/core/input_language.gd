extends Node
## The keyboard of the game window (core-owned, a child of the Game autoload). On Windows an input
## method (Sogou, Microsoft Pinyin) takes the keys of the game: Ctrl+Space (the nitro and the hop
## together) turns it on, Shift (the drift) switches it between Chinese and English, and then W, A,
## S, D go into its candidate box instead of the car. While the game window has the focus it uses an
## English keyboard layout and no input method; it gives the player's layout back when it loses the
## focus and when it quits. --keep-layout leaves the layout alone.

## The layout of the player before the game took the focus (-1: none taken).
var _player_layout: int = -1
## The English layout of the machine (-1: there is none).
var _english: int = -1
var _active: bool = false


func _ready() -> void:
	_active = OS.has_feature("windows") and DisplayServer.get_name() != "headless" \
			and not Game.has_option("keep-layout")
	if not _active:
		return
	_english = english_layout()
	_take()


func _notification(what: int) -> void:
	if not _active:
		return
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_take()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE:
			_give_back()


## The index of the English (US first) keyboard layout, or -1.
static func english_layout() -> int:
	var found: int = -1
	for i in DisplayServer.keyboard_get_layout_count():
		if DisplayServer.keyboard_get_layout_language(i).to_lower().begins_with("en"):
			if found < 0 or DisplayServer.keyboard_get_layout_name(i).contains("US"):
				found = i
	return found


## The game window takes the keyboard: no input method, the English layout.
func _take() -> void:
	DisplayServer.window_set_ime_active(false)
	if _english < 0:
		return
	var current: int = DisplayServer.keyboard_get_current_layout()
	if current != _english:
		_player_layout = current
		DisplayServer.keyboard_set_current_layout(_english)


## The player's layout comes back when the game leaves the focus.
func _give_back() -> void:
	if _player_layout >= 0 and _player_layout < DisplayServer.keyboard_get_layout_count():
		DisplayServer.keyboard_set_current_layout(_player_layout)
	_player_layout = -1
