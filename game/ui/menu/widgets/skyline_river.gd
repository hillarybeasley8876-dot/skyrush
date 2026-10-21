extends RefCounted
## The Huangpu of the loading screen: the dark water with the reflection of the skyline.
##
## The reflection is a set of vertical streaks in the colour of each landmark, jittered, over
## 40–60 % of the band. The water is never a flat plate: the streaks break it up.

## The water.
const WATER := Color("060a16")
## The colour of the sky at the horizon (the water catches it).
const HORIZON_GLOW := Color("2a1440")
## The share of the band that carries a streak.
const COVER_SHARE := 0.5
## The number of streaks of one landmark.
const STREAKS := 9
## The width of a streak.
const STREAK_WIDTH := 3.0
## How far the streaks wander from the landmark.
const JITTER := 9.0


## Draws the river. `rect` is the band of the water; `sources` are the reflections:
## each entry is {"x": a fraction of the width, "colour": a Color}.
func draw(canvas: CanvasItem, rect: Rect2, sources: Array, time: float) -> void:
	canvas.draw_rect(rect, WATER)
	# The glow of the far bank on the water.
	canvas.draw_rect(Rect2(rect.position.x, rect.position.y, rect.size.x, rect.size.y * 0.35),
			Color(HORIZON_GLOW.r, HORIZON_GLOW.g, HORIZON_GLOW.b, 0.30))
	for source: Dictionary in sources:
		_draw_reflection(canvas, rect, source, time)


## The reflection of one landmark: vertical streaks that jitter with the water.
func _draw_reflection(canvas: CanvasItem, rect: Rect2, source: Dictionary, time: float) -> void:
	var colour: Color = source["colour"]
	var x := rect.position.x + rect.size.x * float(source["x"])
	for i in STREAKS:
		var t := float(i) / float(STREAKS)
		var y := rect.position.y + rect.size.y * t
		var wobble := sin(time * 1.4 + float(i) * 1.7) * JITTER
		var length := rect.size.y * (0.12 + 0.10 * _hash(i, int(x)))
		# The streak is broken: only the upper part of each step is bright.
		var alpha := (0.30 - 0.22 * t) * COVER_SHARE * 2.0
		canvas.draw_rect(Rect2(x - STREAK_WIDTH * 0.5 + wobble, y, STREAK_WIDTH, length),
				Color(colour.r, colour.g, colour.b, maxf(alpha, 0.0)))


## A stable number between 0 and 1 for a grid cell.
static func _hash(a: int, b: int) -> float:
	var value := (a * 73856093) ^ (b * 19349663)
	value = (value ^ (value >> 13)) * 1274126177
	return float(absi(value) % 10007) / 10007.0
