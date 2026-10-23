extends Control
## The HOP prompt (dossier §5.7): 150 m before a roadblock or a toll plaza the HUD flashes
## "跳！HOP ▲" in amber, when the player has at least 50 N2 (the price of the Big Hop).
##
## The sites of the world (the roadblock sites and the toll plazas) are handed in once and cached;
## the scan over the cached list runs five times a second, not every frame. The gates of the
## prompt (the N2 of the player, the car on the ground) are checked every frame, so the prompt
## disappears the moment the car leaves the road.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const UI := preload("res://ui/theme/skyrush_theme.gd")
const HopSites := preload("res://ui/hud/hop_sites.gd")

## The text of the prompt.
const TEXT := "跳！HOP ▲"
## The prompt appears 150 m before the obstacle.
const MAX_DISTANCE := 150.0
## The obstacle must be on the same deck as the car (the map has several levels).
const MAX_LEVEL := 4.0
## The angle between the obstacle and the forward axis of the car.
const MAX_ANGLE := 35.0
## The Big Hop costs 50 N2.
const N2_MIN := 50.0
## The scan over the sites runs five times a second.
const SCAN_PERIOD := 0.2
## The pulse of the prompt (Hz).
const PULSE_HZ := 1.5
const MAIN_SIZE := 48
const DIST_SIZE := 24
const SIZE := Vector2(360.0, 96.0)

var _main: Label
var _distance: Label
## The sites of the world (the roadblock sites and the toll plazas), in world metres.
var _sites: Array[Vector3] = []
## The sites are read from the world once it is ready.
var _sites_loaded: bool = false
var _scan_timer: float = 0.0
var _phase: float = 0.0
var _shown_m: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = SIZE
	size = SIZE
	visible = false
	_main = UI.outlined_label(TEXT, MAIN_SIZE, Palette.AMBER, null, HORIZONTAL_ALIGNMENT_CENTER)
	UI.place(_main, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 60.0)
	add_child(_main)
	_distance = UI.outlined_label("", DIST_SIZE, Palette.AMBER, null, HORIZONTAL_ALIGNMENT_CENTER)
	UI.place(_distance, 0.0, 0.0, 1.0, 0.0, 0.0, 60.0, 0.0, 92.0)
	add_child(_distance)


## The sites of the world: the roadblock sites and the toll plazas.
func set_sites(sites: Array[Vector3]) -> void:
	_sites = sites


## The sites are read from the world once it is ready (the world builds them asynchronously) and
## then cached: the scan never walks the world again.
func sync_world() -> void:
	if _sites_loaded:
		return
	var world := Game.world
	if not HopSites.world_ready(world):
		return
	_sites_loaded = true
	set_sites(HopSites.read(world))


## The state of the car: the gates are checked every frame, the scan five times a second.
func update_state(telemetry: CarTelemetry, car_pos: Vector3, forward: Vector3,
		delta: float) -> void:
	_pulse(delta)
	if telemetry == null or telemetry.n2 < N2_MIN or telemetry.airborne or telemetry.flying:
		hide_hint()
		return
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = SCAN_PERIOD
	_scan(car_pos, forward)


## No car, or nothing to show: the prompt is gone and the next scan runs at once.
func hide_hint() -> void:
	_hide()
	_scan_timer = 0.0


## The prompt pulses slowly (a sine on the alpha, 1.5 Hz).
func _pulse(delta: float) -> void:
	if not visible:
		return
	_phase += delta
	modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(TAU * PULSE_HZ * _phase))


## The nearest site that is ahead of the car, on its level and close enough.
func _scan(car_pos: Vector3, forward: Vector3) -> void:
	var flat_forward := Vector3(forward.x, 0.0, forward.z)
	if flat_forward.length_squared() < 0.001:
		_hide()
		return
	flat_forward = flat_forward.normalized()
	var best := -1.0
	for site in _sites:
		var offset := site - car_pos
		var flat := Vector3(offset.x, 0.0, offset.z)
		var distance := flat.length()
		if distance > MAX_DISTANCE or distance < 0.001:
			continue
		# Another deck (the Yan'an street under the elevated road) is not a hop.
		if absf(offset.y) > MAX_LEVEL:
			continue
		# Behind the car.
		if flat.dot(flat_forward) <= 0.0:
			continue
		var angle := rad_to_deg(acos(clampf(flat.normalized().dot(flat_forward), -1.0, 1.0)))
		if angle > MAX_ANGLE:
			continue
		if best < 0.0 or distance < best:
			best = distance
	if best < 0.0:
		_hide()
		return
	_show(best)


## The prompt shows the distance of the site (written only when it changes).
func _show(distance: float) -> void:
	visible = true
	var metres := int(round(distance))
	if metres == _shown_m:
		return
	_shown_m = metres
	_distance.text = "%d m" % metres


## The prompt is gone.
func _hide() -> void:
	visible = false
	_shown_m = -1
