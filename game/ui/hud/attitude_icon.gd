extends Control
## Car-attitude indicator (Roadster reveal livestream, dossier §6.4): a dark disc with a white
## line-art side silhouette of the Roadster, rotated by the current pitch about the car's centre,
## plus plume ticks at the four corner thrusters when they fire.
##
## The silhouette is built from the real proportions in ref/roadster/DOSSIER.md §4.1 (side-profile
## polylines) and §2 (wheel positions), so it reads as the Roadster and not as a scribble.

const Palette := preload("res://ui/theme/skyrush_palette.gd")

const ICON_SIZE := Vector2(156, 156)
const CAR_LENGTH := 4.38          ## metres, nose Y +2.29 to tail Y -2.09
const LENGTH_FRACTION := 0.80     ## of the disc diameter
const BODY_STROKE := 1.75
const WHEEL_STROKE := 1.5
const RIM_WIDTH := 1.5
const PLUME_LEN_FRACTION := 0.25
const PLUME_WIDTH := 2.0
## The car rotates about its bounding-box centre (Y 0.10, Z 0.63), not about the ground.
const PIVOT_Y := 0.10
const PIVOT_Z := 0.63
## The pitch ticks on the rim.
const TICK_STEP_DEG := 30.0
const TICK_LENGTH := 7.0

## Side profile, (Y forward, Z up) in metres — roadster dossier §4.1 centreline top.
static var CENTRELINE := PackedVector2Array([
	Vector2(2.29, 0.485), Vector2(2.17, 0.525), Vector2(2.10, 0.545), Vector2(1.97, 0.59),
	Vector2(1.85, 0.635), Vector2(1.80, 0.645), Vector2(1.65, 0.69), Vector2(1.61, 0.70),
	Vector2(1.41, 0.77), Vector2(1.19, 0.842), Vector2(1.02, 0.905), Vector2(0.85, 0.962),
	Vector2(0.68, 1.017), Vector2(0.51, 1.067), Vector2(0.38, 1.10), Vector2(0.17, 1.138),
	Vector2(0.00, 1.147), Vector2(-0.17, 1.147), Vector2(-0.34, 1.14), Vector2(-0.46, 1.13),
	Vector2(-0.68, 1.112), Vector2(-0.85, 1.093), Vector2(-1.02, 1.067), Vector2(-1.19, 1.005),
	Vector2(-1.36, 0.952), Vector2(-1.53, 0.93), Vector2(-1.745, 0.915), Vector2(-1.90, 0.90),
	Vector2(-2.04, 0.883), Vector2(-2.09, 0.875)])
## The closed side outline: the centreline, the tail face down to the sill, the sill forward and
## the nose face (dossier §4.1).
static var OUTLINE_EXTRA := PackedVector2Array([
	Vector2(-2.09, 0.12), Vector2(2.29, 0.12), Vector2(2.29, 0.485)])
## DLO top (the side-glass upper edge) — dossier §4.1.
static var DLO_TOP := PackedVector2Array([
	Vector2(0.90, 0.91), Vector2(0.68, 0.985), Vector2(0.54, 1.022), Vector2(0.34, 1.056),
	Vector2(0.07, 1.097), Vector2(-0.14, 1.097), Vector2(-0.41, 1.083), Vector2(-0.61, 1.063),
	Vector2(-0.82, 1.035), Vector2(-0.97, 1.015)])
## DLO bottom = the beltline — dossier §4.1.
static var BELTLINE := PackedVector2Array([
	Vector2(0.90, 0.91), Vector2(0.70, 0.845), Vector2(0.54, 0.805), Vector2(0.34, 0.80),
	Vector2(0.07, 0.828), Vector2(-0.14, 0.856), Vector2(-0.41, 0.889), Vector2(-0.61, 0.917),
	Vector2(-0.82, 0.964), Vector2(-0.97, 1.015)])
## The canopy: the glass area between the DLO top and the beltline.
static var CANOPY := PackedVector2Array([
	Vector2(0.90, 0.91), Vector2(0.07, 1.097), Vector2(-0.97, 1.015), Vector2(-0.82, 0.964),
	Vector2(-0.41, 0.889), Vector2(0.07, 0.828), Vector2(0.54, 0.805), Vector2(0.90, 0.91)])
## Wheels: (Y, Z centre, radius) — dossier §2.
static var WHEELS := PackedVector3Array([
	Vector3(1.4125, 0.3425, 0.3425), Vector3(-1.4125, 0.367, 0.367)])
## Corner thruster positions in car space (Y, Z) — P1 front, P2 front, P3 side, P4 rear.
static var PLUME_POINTS := PackedVector2Array([
	Vector2(1.9, 0.12), Vector2(1.9, 0.12), Vector2(0.3, 0.12), Vector2(-1.8, 0.12)])
## P1 and P2 share a point in the side view, so they are offset along the car (screen pixels).
const PLUME_OFFSET_X: Array[float] = [-2.0, 2.0, 0.0, 0.0]

var pitch_deg: float = 0.0
var _plumes: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _last_pitch: float = -1.0
var _last_plumes: PackedFloat32Array = PackedFloat32Array([-1.0, -1.0, -1.0, -1.0])
var _disc: GradientTexture2D = null
## The car geometry, pre-scaled to screen pixels on every resize, so a redraw never measures or
## transforms a point.
var _scale: float = 1.0
var _pivot: Vector2 = Vector2.ZERO
var _body: PackedVector2Array = PackedVector2Array()
## The body outline, closed: the array is built once, not duplicated every draw.
var _body_closed: PackedVector2Array = PackedVector2Array()
var _dlo: PackedVector2Array = PackedVector2Array()
var _belt: PackedVector2Array = PackedVector2Array()
var _canopy: PackedVector2Array = PackedVector2Array()
var _wheels: PackedVector2Array = PackedVector2Array()
var _wheel_r: PackedFloat32Array = PackedFloat32Array()
var _plume_anchor: PackedVector2Array = PackedVector2Array()
## The colours of the plume quads, reused so a redraw allocates nothing.
var _plume_cols: PackedColorArray = PackedColorArray()
## The quad of one plume tick, reused.
var _quad: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = ICON_SIZE
	_disc = _make_disc()
	resized.connect(_on_resized)
	_on_resized()


## Pre-scale the car geometry to screen pixels (the rotation is applied by the draw transform).
func _on_resized() -> void:
	var disc := minf(size.x, size.y)
	if disc <= 8.0:
		return
	_scale = disc * LENGTH_FRACTION / CAR_LENGTH
	_pivot = Vector2(PIVOT_Y * _scale, -PIVOT_Z * _scale)
	_body = _scaled(CENTRELINE) + _scaled(OUTLINE_EXTRA)
	_body_closed = _body.duplicate()
	_body_closed.append(_body[0])
	_dlo = _scaled(DLO_TOP)
	_belt = _scaled(BELTLINE)
	_canopy = _scaled(CANOPY)
	_wheels = PackedVector2Array()
	_wheel_r = PackedFloat32Array()
	for w in WHEELS:
		_wheels.append(Vector2(w.x * _scale, -w.y * _scale))
		_wheel_r.append(w.z * _scale)
	_plume_anchor = PackedVector2Array()
	for i in PLUME_POINTS.size():
		var p := PLUME_POINTS[i]
		# P1 and P2 sit on the same point in the side view, so they are offset across the car.
		var off := PLUME_OFFSET_X[i] if i < PLUME_OFFSET_X.size() else 0.0
		_plume_anchor.append(Vector2(p.x * _scale + off, -p.y * _scale))
	queue_redraw()


## Car space (Y, Z metres) -> screen pixels, relative to the car's pivot.
func _scaled(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = Vector2(points[i].x * _scale, -points[i].y * _scale) - _pivot
	return out


## pitch: nose-up angle in degrees. plumes: four values 0..1 for the corner thrusters P1..P4.
func set_values(pitch: float, plumes: PackedFloat32Array) -> void:
	pitch_deg = pitch
	var changed := not is_equal_approx(pitch, _last_pitch)
	for i in mini(plumes.size(), 4):
		if i < _last_plumes.size() and not is_equal_approx(plumes[i], _last_plumes[i]):
			changed = true
	if not changed:
		return
	_last_pitch = pitch
	# The arrays are REUSED: a new one every frame would be a per-frame allocation.
	_plumes.resize(4)
	_last_plumes.resize(4)
	for i in mini(plumes.size(), 4):
		_plumes[i] = plumes[i]
		_last_plumes[i] = plumes[i]
	queue_redraw()


## The disc: a radial gradient #1A2236 at alpha 0.85 in the centre, fading out to nothing.
func _make_disc() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.0)
	gradient.set_color(0, Color(0.102, 0.133, 0.212, 0.85))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(0.102, 0.133, 0.212, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


func _draw() -> void:
	var centre := size * 0.5
	var disc := minf(size.x, size.y)
	var r := disc * 0.5 - 3.0
	if r <= 4.0:
		return
	draw_circle(centre, r, Color(0.020, 0.027, 0.051, 0.8))
	draw_texture_rect(_disc, Rect2(centre - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false)
	draw_arc(centre, r, 0.0, TAU, 48, Color(1, 1, 1, 0.35), RIM_WIDTH, true)
	# The top-left highlight arc.
	draw_arc(centre, r - 2.0, PI * 1.05, PI * 1.55, 24, Color(1, 1, 1, 0.15), 2.0, true)
	_draw_pitch_ticks(centre, r)

	var rot := -deg_to_rad(pitch_deg)
	var pivot_screen := centre + _pivot
	# The horizon line: where the car would sit level.
	var horizon := Vector2(cos(rot), sin(rot)) * (r - 12.0)
	draw_line(centre - horizon, centre + horizon, Color(1, 1, 1, 0.12), 1.0, true)
	# Everything that belongs to the car is drawn under one transform: the rotation about the
	# car's pivot, with the geometry already scaled to pixels.
	draw_set_transform(pivot_screen, rot, Vector2.ONE)
	_draw_plumes(r)
	# The body fill (photo 30 shows a solid white car), then the outline.
	draw_colored_polygon(_canopy, Color(1, 1, 1, 0.12))
	draw_colored_polygon(_body, Color(1, 1, 1, 0.18))
	draw_polyline(_body_closed, Palette.WHITE, BODY_STROKE, true)
	draw_polyline(_dlo, Color(1, 1, 1, 0.85), BODY_STROKE * 0.8, true)
	draw_polyline(_belt, Color(1, 1, 1, 0.85), BODY_STROKE * 0.8, true)
	for i in _wheels.size():
		draw_arc(_wheels[i], _wheel_r[i], 0.0, TAU, 20, Palette.WHITE, WHEEL_STROKE, true)
		draw_circle(_wheels[i], _wheel_r[i] * 0.45, Color(1, 1, 1, 0.55))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The pitch ticks on the rim: one every 30 degrees.
func _draw_pitch_ticks(centre: Vector2, r: float) -> void:
	for deg in range(-180, 180, int(TICK_STEP_DEG)):
		var a := deg_to_rad(float(deg) - 90.0)
		var dir := Vector2(cos(a), sin(a))
		draw_line(centre + dir * (r - TICK_LENGTH), centre + dir * (r - 1.0),
			Color(1, 1, 1, 0.18), 1.0, true)


## Plume ticks at the P1..P4 positions, pointing along the car-local -Z, so they rotate with the
## car. The transform is already set, so the ticks are drawn in the car's own space.
func _draw_plumes(r: float) -> void:
	for i in mini(_plumes.size(), 4):
		var out := _plumes[i]
		if out <= 0.02:
			continue
		var base := _plume_anchor[i]
		var length := r * PLUME_LEN_FRACTION * clampf(out, 0.0, 1.0)
		# The car-local -Z, which is +Y in the scaled space.
		var dir := Vector2(0.0, 1.0)
		var tip := base + dir * length
		var side := Vector2(-dir.y, dir.x) * (PLUME_WIDTH * 0.5)
		_quad.resize(4)
		_quad[0] = base - side
		_quad[1] = base + side
		_quad[2] = tip + side * 0.25
		_quad[3] = tip - side * 0.25
		_plume_cols.resize(4)
		_plume_cols[0] = Color(1, 1, 1, 0.9)
		_plume_cols[1] = Color(1, 1, 1, 0.9)
		_plume_cols[2] = Color(1, 1, 1, 0.0)
		_plume_cols[3] = Color(1, 1, 1, 0.0)
		draw_polygon(_quad, _plume_cols)
