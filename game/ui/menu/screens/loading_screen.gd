extends "res://ui/menu/screens/menu_screen.gd"
## The loading screen: the SKYRUSH logo drawing itself in over the Lujiazui skyline, a segmented
## progress bar, the loading label and a rotating gameplay tip.
##
## The progress comes from `Events.loading_progress` and from `Game.world.loading_fraction` (the
## world is built before the menu exists, so the signal alone is not enough).
##
## The screen is opaque from its first frame: the world must never show through it while the
## city is still being built.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")
const Logo := preload("res://ui/menu/widgets/logo.gd")
const Skyline := preload("res://ui/menu/widgets/skyline.gd")
const Segments := preload("res://ui/menu/widgets/progress_bar.gd")
const Layout := preload("res://ui/menu/widgets/layout.gd")

const TIPS: PackedStringArray = [
	"氮气 N2 是唯一资源：加速、跳跃、悬停、翻滚和飞行航道都要花它。",
	"漂移三秒攒满一个氮气槽，小喷要在出弯的瞬间按。",
	"擦肩而过 +5 分，撞废一辆警车 +50 分，撞毁车辆 -25 分。",
	"申城闪充 0.45 秒补满电，路上别错过。",
	"120 km/h 以上加 25 氮气，就能冲上飞行航道。",
	"被警察盯上后，甩开视线热度就会下降。",
]

## The Chinese label of every phase of the build (the world reports its own ids).
const PHASE_LABELS: Dictionary = {
	"terrain": "正在铺设地形  TERRAIN",
	"roads": "正在铺设道路  ROADS",
	"blocks": "正在生成街区  BLOCKS",
	"lanes": "正在规划车道  LANES",
	"furniture": "正在摆放街道设施  STREET FURNITURE",
	"signals": "正在点亮信号灯  SIGNALS",
	"sites": "正在布置地标  LANDMARKS",
	"读取城市数据": "读取城市数据  CITY DATA",
	"就绪": "就绪  READY",
}
## The label of a phase nobody knows.
const DEFAULT_LABEL := "正在载入世界…  LOADING WORLD"

## The loading screen stays up for at least this long (the world is built before the menu).
const MIN_SECONDS := 1.5
## ... and for at least this many rendered frames.
const MIN_FRAMES := 60
## The size of the logo and the top of it.
const LOGO_SIZE := 100
const LOGO_TOP := 90.0
## The band of the progress bar and the status label.
const PROGRESS_TOP := 600.0
const PROGRESS_BOTTOM := 700.0
## The tip at the bottom of the screen and the label above it.
const TIP_BOTTOM := -150.0
const TIP_TOP := -112.0
const HINT_BOTTOM := -188.0
const HINT_TOP := -160.0
## The delta of one frame is clamped to this, so a long first frame cannot skip the screen.
const MAX_DELTA := 0.1
## After this long without any progress the screen gives way to the title.
const GRACE_SECONDS := 4.0
## How long a tip stays on the screen.
const TIP_SECONDS := 4.5
## How fast the tip breathes.
const TIP_SPEED := 2.0

var progress_bar: Segments
var percent_label: Label
var status_label: Label
var tip_label: Label
var logo: Logo

## The capture rig holds the screen open (it never gives way to the title).
var hold: bool = false

var _fraction: float = 0.0
var _shown: float = 0.0
var _frames: int = 0
var _started_ms: int = 0
var _last_progress_ms: int = 0
var _tip_index: int = 0
var _tip_shown_at: float = 0.0
var _clock_us: int = 0
var _raw_label: String = ""


func _ready() -> void:
	Layout.fill(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sky := Skyline.new()
	Layout.fill(sky)
	add_child(sky)

	logo = Logo.new()
	logo.font_size = LOGO_SIZE
	logo.reveal = 0.0
	# The logo reports the height it needs (the word, the gap and the Chinese name).
	UI.place(logo, 0, 0, 1, 0, 0, LOGO_TOP, 0, LOGO_TOP + logo.content_height())
	add_child(logo)

	var box := UI.v_box(BoxContainer.ALIGNMENT_CENTER, 12)
	UI.place(box, 0.5, 0, 0.5, 0, -430, PROGRESS_TOP, 430, PROGRESS_BOTTOM)
	add_child(box)

	progress_bar = Segments.new()
	box.add_child(progress_bar)

	var row := UI.h_box(BoxContainer.ALIGNMENT_BEGIN, 18)
	box.add_child(row)

	percent_label = UI.display_label("0%", 28, Palette.CYAN)
	row.add_child(percent_label)

	status_label = UI.label(DEFAULT_LABEL, 19, Palette.TEXT, Fonts.text())
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(status_label)

	tip_label = UI.label(TIPS[0], 21, Palette.TEXT, Fonts.text(), HORIZONTAL_ALIGNMENT_CENTER)
	UI.place(tip_label, 0, 1, 1, 1, 120, TIP_TOP, -120, TIP_BOTTOM)
	add_child(tip_label)

	var hint := UI.label("提示 TIP", 16, Palette.TEXT_DIM, Fonts.text(), HORIZONTAL_ALIGNMENT_CENTER)
	UI.place(hint, 0, 1, 1, 1, 120, HINT_TOP, -120, HINT_BOTTOM)
	add_child(hint)


func on_enter() -> void:
	_started_ms = Time.get_ticks_msec()
	_last_progress_ms = _started_ms
	if not Events.loading_progress.is_connected(_on_loading_progress):
		Events.loading_progress.connect(_on_loading_progress)


func on_exit() -> void:
	if Events.loading_progress.is_connected(_on_loading_progress):
		Events.loading_progress.disconnect(_on_loading_progress)


## The loading screen does not fade in: the world must not show through it.
func play_enter() -> void:
	super.play_enter()
	appear_now()


## Feeds the bar; the root switches to the title when the fraction reaches 1.
func set_progress(fraction: float, label: String) -> void:
	_fraction = clampf(fraction, 0.0, 1.0)
	progress_bar.set_value(_fraction)
	percent_label.text = "%d%%" % int(round(_fraction * 100.0))
	if not label.is_empty():
		_raw_label = label
		status_label.text = phase_label(label)


func current_fraction() -> float:
	return _fraction


## The Chinese label of a build phase.
static func phase_label(raw: String) -> String:
	return String(PHASE_LABELS.get(raw, DEFAULT_LABEL))


func _on_loading_progress(fraction: float, label: String) -> void:
	_last_progress_ms = Time.get_ticks_msec()
	set_progress(fraction, label)


## The loading is done: the world reports 100 % (or nothing at all for long enough) and the screen
## has been up for at least MIN_SECONDS.
func is_done() -> bool:
	if hold:
		return false
	var now := Time.get_ticks_msec()
	var ready := _fraction >= 1.0
	var stalled := now - _last_progress_ms > int(GRACE_SECONDS * 1000.0)
	# The screen stays up for at least MIN_SECONDS of clamped time and MIN_FRAMES frames.
	return (ready or stalled) and _shown >= MIN_SECONDS and _frames >= MIN_FRAMES


func _process(delta: float) -> void:
	super._process(delta)
	_shown += minf(delta, MAX_DELTA)
	_frames += 1
	# The wall clock: the world is built at a few frames per second, so a delta driven tip
	# timer would crawl.
	_clock_us = Time.get_ticks_usec()
	var elapsed := float(_clock_us) * 0.000001
	tip_label.modulate.a = 0.72 + 0.28 * sin(elapsed * TIP_SPEED)
	if elapsed - _tip_shown_at >= TIP_SECONDS:
		_tip_shown_at = elapsed
		_tip_index = (_tip_index + 1) % TIPS.size()
		tip_label.text = TIPS[_tip_index]
	# The world reports its own progress (it is built before the menu exists).
	var world := Game.world
	if world != null:
		var fraction := float(world.get("loading_fraction"))
		if fraction > _fraction:
			set_progress(fraction, _raw_label)
