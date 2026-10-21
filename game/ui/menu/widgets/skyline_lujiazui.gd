extends RefCounted
## The Lujiazui skyline of the loading screen: the four landmarks with their LED signatures
## (ART §11) and a row of generic towers with clustered lit windows, crown lines and beacons.
##
## The masses stay dark (#0B1024–#141A2E); the landmarks carry the colour and are the brightest
## thing on the screen after the logo.

## The masses of the buildings.
const MASS_DARK := Color("0b1024")
const MASS_LIGHT := Color("141a2e")
## The lit windows and the crown lines.
const WINDOW_WARM := Color("ffcf87")
const WINDOW_COOL := Color("cfe8ff")
const CROWN_COOL := Color("cfe8ff")
## The aviation beacon on the roofs over 100 m.
const BEACON_RED := Color("ff2a3a")
## The LED signatures of the landmarks.
const PEARL_LOWER := Color("ff2bd6")
const PEARL_UPPER := Color("9b5cff")
const TOWER_LED := Color("7fd4ff")
const SWFC_EDGE := Color("cfe8ff")
const JINMAO_GOLD := Color("ffcf87")

## The heights of the landmarks, as a fraction of the skyline.
const PEARL_HEIGHT := 0.40
const TOWER_HEIGHT := 0.44
const SWFC_HEIGHT := 0.40
const JINMAO_HEIGHT := 0.34
## Where the landmarks stand, as a fraction of the width.
const PEARL_X := 0.12
const JINMAO_X := 0.30
const TOWER_X := 0.47
const SWFC_X := 0.64
## The number of tiers of Jin Mao.
const JINMAO_TIERS := 13
## The beacon blinks once a second.
const BEACON_HZ := 1.0
## The share of the floors that are lit.
const LIT_SHARE := 0.24
## The height of one floor of windows.
const FLOOR_HEIGHT := 7.0
## The width of one window and the gap to the next one.
const WINDOW_WIDTH := 4.0
const WINDOW_GAP := 4.0
## The generic towers: x, width and height, all as a fraction of the skyline.
const GENERIC: Array[Dictionary] = [
	{"x": 0.02, "w": 0.055, "h": 0.15},
	{"x": 0.075, "w": 0.040, "h": 0.10},
	{"x": 0.19, "w": 0.050, "h": 0.19},
	{"x": 0.245, "w": 0.035, "h": 0.13},
	{"x": 0.35, "w": 0.050, "h": 0.23},
	{"x": 0.40, "w": 0.040, "h": 0.16},
	{"x": 0.55, "w": 0.050, "h": 0.21},
	{"x": 0.60, "w": 0.045, "h": 0.14},
	{"x": 0.72, "w": 0.050, "h": 0.18},
	{"x": 0.775, "w": 0.060, "h": 0.25},
	{"x": 0.86, "w": 0.050, "h": 0.12},
	{"x": 0.92, "w": 0.055, "h": 0.20},
]


## Draws the skyline. `rect` is the area above the horizon; the buildings stand on its bottom.
func draw(canvas: CanvasItem, rect: Rect2, time: float, sky: Color) -> void:
	var base := rect.position.y + rect.size.y
	for tower: Dictionary in GENERIC:
		_draw_generic(canvas, rect, base, tower, time)
	_draw_pearl(canvas, rect, base, time)
	_draw_jinmao(canvas, rect, base)
	_draw_tower(canvas, rect, base, time)
	_draw_swfc(canvas, rect, base, sky)


## A generic tower: a dark mass, clustered lit floors, a crown line and a beacon.
func _draw_generic(canvas: CanvasItem, rect: Rect2, base: float, tower: Dictionary,
		time: float) -> void:
	var x := rect.position.x + rect.size.x * float(tower["x"])
	var width := rect.size.x * float(tower["w"])
	var height := rect.size.y * float(tower["h"])
	var box := Rect2(x, base - height, width, height)
	canvas.draw_rect(box, MASS_DARK)
	_draw_floors(canvas, box, LIT_SHARE, int(x))
	# Half of the towers wear a cool white crown line.
	if _hash(int(x), 7) > 0.5:
		canvas.draw_rect(Rect2(box.position.x, box.position.y, box.size.x, 2.0), CROWN_COOL)
	# Every roof over 100 m carries a red beacon that blinks once a second.
	if height > rect.size.y * 0.28:
		_draw_beacon(canvas, Vector2(box.position.x + box.size.x * 0.5, box.position.y), time)


## The lit floors of a building: whole bands, not a polka-dot grid (ART §11).
func _draw_floors(canvas: CanvasItem, box: Rect2, share: float, seed_value: int) -> void:
	var floors := int(box.size.y / FLOOR_HEIGHT)
	if floors <= 0:
		return
	for floor in floors:
		if _hash(floor, seed_value) > share:
			continue
		var y := box.position.y + float(floor) * FLOOR_HEIGHT
		var x := box.position.x + 3.0
		while x < box.position.x + box.size.x - 4.0:
			if _hash(floor * 31 + int(x), seed_value) > 0.32:
				var warm := _hash(floor, seed_value + 3) > 0.55
				var colour := WINDOW_WARM if warm else WINDOW_COOL
				canvas.draw_rect(Rect2(x, y + 1.5, WINDOW_WIDTH, 3.0), colour)
			x += WINDOW_WIDTH + WINDOW_GAP


## The red aviation beacon on a roof (it blinks once a second).
func _draw_beacon(canvas: CanvasItem, position: Vector2, time: float) -> void:
	var phase := fmod(time * BEACON_HZ, 1.0)
	var alpha := 1.0 if phase < 0.45 else 0.15
	canvas.draw_circle(position, 2.4, Color(BEACON_RED.r, BEACON_RED.g, BEACON_RED.b, alpha))


## 东方明珠: three legs, a magenta lower sphere, a violet upper sphere and a spire.
func _draw_pearl(canvas: CanvasItem, rect: Rect2, base: float, time: float) -> void:
	var x := rect.position.x + rect.size.x * PEARL_X
	var height := rect.size.y * PEARL_HEIGHT
	var unit := rect.size.x / 42.0
	# The three legs, splayed.
	for leg in 3:
		var angle := -0.45 + 0.45 * float(leg)
		var foot := Vector2(x + sin(angle) * unit * 1.5, base)
		var top := Vector2(x, base - height * 0.52)
		canvas.draw_line(foot, top, MASS_DARK, unit * 0.28)
	# The column between the two spheres.
	canvas.draw_rect(Rect2(x - unit * 0.16, base - height * 0.52, unit * 0.32, height * 0.52),
			MASS_DARK)
	# The lower sphere (magenta) and the upper one (violet).
	var lower := Vector2(x, base - height * 0.52)
	var upper := Vector2(x, base - height * 0.80)
	_draw_sphere(canvas, lower, unit * 0.62, PEARL_LOWER, time, 0)
	_draw_sphere(canvas, upper, unit * 0.40, PEARL_UPPER, time, 1)
	# The spire.
	canvas.draw_rect(Rect2(x - unit * 0.06, base - height * 1.06, unit * 0.12, height * 0.26),
			MASS_DARK)
	canvas.draw_line(Vector2(x, base - height * 1.06), Vector2(x, base - height * 1.16),
			Color(PEARL_UPPER.r, PEARL_UPPER.g, PEARL_UPPER.b, 0.9), 1.6)


## A sphere of the Pearl: a dark ball with LED dots that chase around it.
func _draw_sphere(canvas: CanvasItem, centre: Vector2, radius: float, colour: Color,
		time: float, phase: int) -> void:
	canvas.draw_circle(centre, radius, MASS_LIGHT)
	for i in 10:
		var angle := TAU * float(i) / 10.0 + time * 0.6 + float(phase)
		var point := centre + Vector2(cos(angle), sin(angle) * 0.7) * radius * 0.82
		var chase := fmod(time * 1.6 + float(i) * 0.1, 1.0)
		var alpha := 0.25 + 0.75 * clampf(1.0 - absf(chase - 0.5) * 2.0, 0.0, 1.0)
		canvas.draw_circle(point, 1.5, Color(colour.r, colour.g, colour.b, alpha))


## 上海中心: a twisting taper with spiral LED lines and a lit crown.
func _draw_tower(canvas: CanvasItem, rect: Rect2, base: float, time: float) -> void:
	var x := rect.position.x + rect.size.x * TOWER_X
	var height := rect.size.y * TOWER_HEIGHT
	var half := rect.size.x * 0.026
	var lean := rect.size.x * 0.008
	var steps := 24
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in steps + 1:
		var t := float(i) / float(steps)
		var y := base - height * t
		var width := half * (1.0 - 0.52 * t)
		var shift := sin(t * TAU) * lean
		left.append(Vector2(x - width + shift, y))
		right.append(Vector2(x + width + shift, y))
	var body := PackedVector2Array()
	body.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		body.append(right[i])
	canvas.draw_colored_polygon(body, MASS_DARK)
	# The spiral LED lines up the facade.
	for line in 3:
		var points := PackedVector2Array()
		for i in steps + 1:
			var t := float(i) / float(steps)
			var width := half * (1.0 - 0.52 * t)
			var phase := t * TAU * 1.5 + float(line) * TAU / 3.0
			points.append(Vector2(x + sin(t * TAU) * lean + cos(phase) * width * 0.72,
					base - height * t))
		canvas.draw_polyline(points, Color(TOWER_LED.r, TOWER_LED.g, TOWER_LED.b, 0.75), 1.4, true)
	# The lit crown.
	var crown := Rect2(x - half * 0.5, base - height - 3.0, half, 3.0)
	canvas.draw_rect(crown, Color(CROWN_COOL.r, CROWN_COOL.g, CROWN_COOL.b, 0.9))


## 环球金融中心: the trapezoid aperture cut out of the top, outlined in blue white.
func _draw_swfc(canvas: CanvasItem, rect: Rect2, base: float, sky: Color) -> void:
	var x := rect.position.x + rect.size.x * SWFC_X
	var height := rect.size.y * SWFC_HEIGHT
	var half := rect.size.x * 0.030
	var top := base - height
	canvas.draw_rect(Rect2(x - half, top, half * 2.0, height), MASS_DARK)
	# The aperture: a trapezoid of sky, outlined.
	var aperture := PackedVector2Array([
		Vector2(x - half * 0.55, top),
		Vector2(x + half * 0.55, top),
		Vector2(x + half * 0.30, top - height * 0.16),
		Vector2(x - half * 0.30, top - height * 0.16)])
	canvas.draw_colored_polygon(aperture, sky)
	var outline := PackedVector2Array([
		Vector2(x - half * 0.55, top),
		Vector2(x + half * 0.55, top),
		Vector2(x + half * 0.30, top - height * 0.16),
		Vector2(x - half * 0.30, top - height * 0.16)])
	canvas.draw_polyline(outline, SWFC_EDGE, 2.0, true)
	# The vertical edge lines.
	canvas.draw_line(Vector2(x - half, top), Vector2(x - half, base), Color(SWFC_EDGE.r,
			SWFC_EDGE.g, SWFC_EDGE.b, 0.5), 1.2)
	canvas.draw_line(Vector2(x + half, top), Vector2(x + half, base), Color(SWFC_EDGE.r,
			SWFC_EDGE.g, SWFC_EDGE.b, 0.5), 1.2)
	_draw_floors(canvas, Rect2(x - half, top + height * 0.2, half * 2.0, height * 0.8),
			LIT_SHARE, int(x))


## 金茂: thirteen tiers with warm gold bands and a spire.
func _draw_jinmao(canvas: CanvasItem, rect: Rect2, base: float) -> void:
	var x := rect.position.x + rect.size.x * JINMAO_X
	var height := rect.size.y * JINMAO_HEIGHT
	var half := rect.size.x * 0.024
	for tier in JINMAO_TIERS:
		var t := float(tier) / float(JINMAO_TIERS)
		var width := half * (1.0 - 0.78 * t * t)
		var y := base - height * (t + 1.0 / float(JINMAO_TIERS))
		var band := height / float(JINMAO_TIERS)
		canvas.draw_rect(Rect2(x - width, y, width * 2.0, band), MASS_DARK)
		# The warm gold band that rings every tier.
		canvas.draw_rect(Rect2(x - width, y, width * 2.0, 1.6),
				Color(JINMAO_GOLD.r, JINMAO_GOLD.g, JINMAO_GOLD.b, 0.55))
	# The spire.
	canvas.draw_line(Vector2(x, base - height), Vector2(x, base - height * 1.14), JINMAO_GOLD, 1.8)


## A stable number between 0 and 1 for a grid cell.
static func _hash(a: int, b: int) -> float:
	var value := (a * 73856093) ^ (b * 19349663)
	value = (value ^ (value >> 13)) * 1274126177
	return float(absi(value) % 10007) / 10007.0
