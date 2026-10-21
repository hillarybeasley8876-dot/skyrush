extends RefCounted
## The Bund roofline of the loading screen: the historic façades in front of the river, their
## domes and the clock tower of 江海关, floodlit in warm gold (ART §3).
##
## The Bund is the nearest band of the picture, so it is the darkest and the warmest: the stone
## catches the floodlights, the windows are warm.

## The masses of the façades.
const MASS_DARK := Color("0a0d1c")
const MASS_LIGHT := Color("141a2e")
## The floodlight on the stone and the warm windows.
const FLOOD := Color("e9c98f")
const WINDOW_WARM := Color("ffcf87")
## The colour of the clock face.
const CLOCK_FACE := Color("ffe9c0")

## The row of façades: x, width, height and the kind (0 = plain, 1 = dome, 2 = pediment).
const FACADES: Array[Dictionary] = [
	{"x": 0.01, "w": 0.075, "h": 0.42, "kind": 0},
	{"x": 0.09, "w": 0.060, "h": 0.55, "kind": 1},
	{"x": 0.155, "w": 0.070, "h": 0.36, "kind": 0},
	{"x": 0.23, "w": 0.055, "h": 0.48, "kind": 2},
	{"x": 0.29, "w": 0.065, "h": 0.34, "kind": 0},
	{"x": 0.36, "w": 0.050, "h": 0.30, "kind": 0},
	{"x": 0.42, "w": 0.045, "h": 0.62, "kind": 3},
	{"x": 0.47, "w": 0.060, "h": 0.38, "kind": 1},
	{"x": 0.54, "w": 0.070, "h": 0.44, "kind": 0},
	{"x": 0.62, "w": 0.055, "h": 0.33, "kind": 2},
	{"x": 0.685, "w": 0.065, "h": 0.51, "kind": 0},
	{"x": 0.76, "w": 0.070, "h": 0.40, "kind": 1},
	{"x": 0.84, "w": 0.055, "h": 0.47, "kind": 0},
	{"x": 0.905, "w": 0.085, "h": 0.36, "kind": 0},
]
## The kind of the clock tower of 江海关.
const KIND_CLOCK_TOWER := 3
## The width of the clock tower.
const TOWER_WIDTH := 0.045
## The height of the tower above the roof line.
const TOWER_EXTRA := 0.14
## The height of one floor of windows.
const FLOOR_HEIGHT := 6.0
## The width of one window and the gap to the next one.
const WINDOW_WIDTH := 3.5
const WINDOW_GAP := 4.5


## Draws the roofline. `rect` is the band of the Bund; the façades stand on its bottom.
func draw(canvas: CanvasItem, rect: Rect2) -> void:
	var base := rect.position.y + rect.size.y
	for facade: Dictionary in FACADES:
		_draw_facade(canvas, rect, base, facade)


## One façade: the mass, the floodlit cornice, the windows and the roof.
func _draw_facade(canvas: CanvasItem, rect: Rect2, base: float, facade: Dictionary) -> void:
	var x := rect.position.x + rect.size.x * float(facade["x"])
	var width := rect.size.x * float(facade["w"])
	var height := rect.size.y * float(facade["h"])
	var top := base - height
	canvas.draw_rect(Rect2(x, top, width, height), MASS_DARK)
	# The floodlit cornice along the top of the stone.
	canvas.draw_rect(Rect2(x - 1.0, top, width + 2.0, 2.4),
			Color(FLOOD.r, FLOOD.g, FLOOD.b, 0.55))
	_draw_windows(canvas, Rect2(x, top + 4.0, width, height - 4.0), int(x))
	match int(facade["kind"]):
		1:
			_draw_dome(canvas, Vector2(x + width * 0.5, top), width * 0.42)
		2:
			_draw_pediment(canvas, Vector2(x + width * 0.5, top), width)
		3:
			_draw_clock_tower(canvas, rect, Vector2(x + width * 0.5, top), width)


## The warm windows of a façade, in bands.
func _draw_windows(canvas: CanvasItem, box: Rect2, seed_value: int) -> void:
	var floors := int(box.size.y / FLOOR_HEIGHT)
	if floors <= 0:
		return
	for floor in floors:
		if _hash(floor, seed_value) > 0.5:
			continue
		var y := box.position.y + float(floor) * FLOOR_HEIGHT
		var x := box.position.x + 3.0
		while x < box.position.x + box.size.x - 4.0:
			if _hash(floor * 17 + int(x), seed_value) > 0.3:
				canvas.draw_rect(Rect2(x, y + 1.0, WINDOW_WIDTH, 2.6),
						Color(WINDOW_WARM.r, WINDOW_WARM.g, WINDOW_WARM.b, 0.75))
			x += WINDOW_WIDTH + WINDOW_GAP


## The dome of one of the historic bank buildings.
func _draw_dome(canvas: CanvasItem, top: Vector2, radius: float) -> void:
	var points := PackedVector2Array()
	var steps := 12
	for i in steps + 1:
		var angle := PI + PI * float(i) / float(steps)
		points.append(top + Vector2(cos(angle) * radius, sin(angle) * radius * 0.8))
	points.append(top + Vector2(radius, 0.0))
	points.append(top + Vector2(-radius, 0.0))
	canvas.draw_colored_polygon(points, MASS_LIGHT)
	canvas.draw_polyline(points, Color(FLOOD.r, FLOOD.g, FLOOD.b, 0.6), 1.4, true)


## The triangular pediment of a façade.
func _draw_pediment(canvas: CanvasItem, top: Vector2, width: float) -> void:
	var points := PackedVector2Array([
		top + Vector2(-width * 0.5, 0.0),
		top + Vector2(0.0, -width * 0.22),
		top + Vector2(width * 0.5, 0.0)])
	canvas.draw_colored_polygon(points, MASS_LIGHT)
	canvas.draw_polyline(points, Color(FLOOD.r, FLOOD.g, FLOOD.b, 0.6), 1.4, true)


## The clock tower of 江海关: a square tower, a lit clock face and a spire.
func _draw_clock_tower(canvas: CanvasItem, rect: Rect2, top: Vector2, width: float) -> void:
	var tower_width := rect.size.x * TOWER_WIDTH
	var tower_height := rect.size.y * TOWER_EXTRA
	var tower_top := top.y - tower_height
	canvas.draw_rect(Rect2(top.x - tower_width * 0.5, tower_top, tower_width, tower_height),
			MASS_LIGHT)
	# The lit clock face.
	var face := Vector2(top.x, tower_top + tower_height * 0.34)
	var radius := tower_width * 0.17
	canvas.draw_circle(face, radius, Color(CLOCK_FACE.r, CLOCK_FACE.g, CLOCK_FACE.b, 0.8))
	canvas.draw_arc(face, radius, 0.0, TAU, 20, Color(FLOOD.r, FLOOD.g, FLOOD.b, 0.9), 1.4)
	# The hands of the clock.
	canvas.draw_line(face, face + Vector2(0.0, -radius * 0.6), CLOCK_FACE, 1.2)
	canvas.draw_line(face, face + Vector2(radius * 0.45, radius * 0.2), CLOCK_FACE, 1.2)
	# The roof of the tower and its spire.
	canvas.draw_line(Vector2(top.x - tower_width * 0.5, tower_top),
			Vector2(top.x + tower_width * 0.5, tower_top),
			Color(FLOOD.r, FLOOD.g, FLOOD.b, 0.6), 1.6)
	canvas.draw_line(Vector2(top.x, tower_top), Vector2(top.x, tower_top - tower_height * 0.30),
			Color(FLOOD.r, FLOOD.g, FLOOD.b, 0.8), 1.4)


## A stable number between 0 and 1 for a grid cell.
static func _hash(a: int, b: int) -> float:
	var value := (a * 73856093) ^ (b * 19349663)
	value = (value ^ (value >> 13)) * 1274126177
	return float(absi(value) % 10007) / 10007.0
