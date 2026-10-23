extends "res://ui/menu/screens/menu_screen.gd"
## Title screen: the SKYRUSH logo over the live 3D stage — the menu's camera frames the player's
## Roadster parked on the Bund promenade, in three authored beats.
##
## The prompt sits at 80 % of the height on a dark band, clear of the car in the middle of the
## frame, and any key / button / click starts the game. When the camera changes beat, the frame of
## the old shot is snapshotted and faded out over 1.2 s (the cross-fade).

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")
const Logo := preload("res://ui/menu/widgets/logo.gd")
const Layout := preload("res://ui/menu/widgets/layout.gd")
const TitleStage := preload("res://ui/menu/widgets/title_stage.gd")

## The height of the band the prompt sits on (the bottom of the screen).
const BAND_TOP := 0.76
const BAND_BOTTOM := 1.0
## The size of the logo on the title screen.
const LOGO_SIZE := 150
## The top of the logo.
const LOGO_TOP := 24.0
## How long the cross-fade over a beat change lasts.
const CROSSFADE_SECONDS := 1.2
## How fast the prompt breathes.
const PROMPT_SPEED := 2.6

var logo: Logo
var prompt: Label
var subtitle: Label

var _snapshot: TextureRect
var _pulse: float = 0.0


func _ready() -> void:
	Layout.fill(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	logo = Logo.new()
	logo.font_size = LOGO_SIZE
	# The logo reports the height it needs (the word, the gap and the Chinese name).
	UI.place(logo, 0, 0, 1, 0, 0, LOGO_TOP, 0, LOGO_TOP + logo.content_height())
	add_child(logo)

	var band := TextureRect.new()
	band.texture = _band_texture()
	band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	band.stretch_mode = TextureRect.STRETCH_SCALE
	UI.place(band, 0, BAND_TOP, 1, BAND_BOTTOM, 0, 0, 0, 0)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)

	prompt = UI.display_label("按任意键开始   PRESS ANY KEY", 36, Palette.WHITE,
			HORIZONTAL_ALIGNMENT_CENTER)
	UI.place(prompt, 0, BAND_TOP, 1, BAND_TOP, 0, 96, 0, 158)
	add_child(prompt)

	subtitle = UI.label("飞驰申城  ·  NEON SHANGHAI  ·  2026", 20, Palette.TEXT_DIM, Fonts.text(),
			HORIZONTAL_ALIGNMENT_CENTER)
	UI.place(subtitle, 0, BAND_TOP, 1, BAND_TOP, 0, 166, 0, 200)
	add_child(subtitle)

	var build := UI.label("演示版 DEMO BUILD  v0.1", 16, Palette.TEXT_DIM, Fonts.text())
	UI.place(build, 0, 1, 0, 1, 36, -52, 300, -28)
	add_child(build)

	var credit := UI.label("夜雨  外滩  申城", 16, Palette.TEXT_DIM, Fonts.text(),
			HORIZONTAL_ALIGNMENT_RIGHT)
	UI.place(credit, 1, 1, 1, 1, -300, -52, -36, -28)
	add_child(credit)

	# CC BY 4.0 asks for the credit where the player can see it (CREDITS.md has the full text).
	var model_credit := UI.label("车模 Car Concept © Eric Chadwick / Darmstadt Graphics Group · CC BY 4.0", 13,
			Palette.TEXT_DIM, Fonts.text(), HORIZONTAL_ALIGNMENT_RIGHT)
	UI.place(model_credit, 1, 1, 1, 1, -700, -26, -36, -6)
	add_child(model_credit)

	_snapshot = TextureRect.new()
	_snapshot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_snapshot.stretch_mode = TextureRect.STRETCH_SCALE
	Layout.fill(_snapshot)
	_snapshot.visible = false
	_snapshot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_snapshot)


func on_enter() -> void:
	var stage := _stage()
	if stage != null and not stage.beat_changed.is_connected(_on_beat_changed):
		stage.beat_changed.connect(_on_beat_changed)


func on_exit() -> void:
	var stage := _stage()
	if stage != null and stage.beat_changed.is_connected(_on_beat_changed):
		stage.beat_changed.disconnect(_on_beat_changed)


## Any key starts the game: the title forwards to the main menu.
func handle_action(action: StringName, _event: InputEvent) -> bool:
	if action == &"menu_cancel":
		return false
	_start()
	return true


## Any key, any button and any click starts the game (the title is the "press any key" screen).
func handle_raw_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			_start()
			return true
		return false
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if button.pressed:
			_start()
			return true
		return false
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			_start()
			return true
	return false


func _process(delta: float) -> void:
	super._process(delta)
	_pulse += delta
	prompt.modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_pulse * PROMPT_SPEED))


func _start() -> void:
	request_screen.emit(&"main", {})


## The cross-fade over a beat change: the frame of the old shot is frozen and faded out.
func _on_beat_changed(_index: int) -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var image := viewport.get_texture().get_image()
	if image == null:
		return
	_snapshot.texture = ImageTexture.create_from_image(image)
	_snapshot.visible = true
	_snapshot.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_property(_snapshot, "modulate:a", 0.0, CROSSFADE_SECONDS)
	tween.tween_callback(func() -> void: _snapshot.visible = false)


## The title stage (the camera of the menu).
func _stage() -> TitleStage:
	if front_end == null:
		return null
	return front_end.stage


func _band_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(0.01, 0.012, 0.03, 0.0))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(0.01, 0.012, 0.03, 0.86))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 4
	texture.height = 256
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	return texture
