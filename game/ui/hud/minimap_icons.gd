extends RefCounted
## The icons of the minimap: the points of interest, the police and rival blips, the player arrow
## with its view cone and the north tick on the rim.
##
## They live in their own file so the panel stays small and the drawing can be reused. Every icon
## is drawn from a CONSTANT array (the arrow and the cone are drawn under a transform), so a
## redraw of the overlay allocates nothing.

const Palette := preload("res://ui/theme/skyrush_palette.gd")
const Fonts := preload("res://ui/theme/skyrush_fonts.gd")

const CONE_ALPHA := 0.12
const PLAYER_OUTLINE := Color(0.020, 0.024, 0.059, 1.0)
## The north tick: a bold N on a dark disc.
const NORTH_SIZE := 13
const NORTH_DISC := 9.0
const NORTH_COLOR := Color(0.020, 0.024, 0.059, 0.9)

## The view cone, relative to the player arrow: the apex and 8 points of the 40 degree arc.
static var CONE_POINTS := PackedVector2Array([
	Vector2(0.0, 0.0), Vector2(-14.36, -39.47), Vector2(-10.87, -40.57), Vector2(-7.29, -41.36),
	Vector2(-3.66, -41.84), Vector2(0.0, -42.0), Vector2(3.66, -41.84), Vector2(7.29, -41.36),
	Vector2(10.87, -40.57), Vector2(14.36, -39.47)])
## The player arrow: a dark outline and a white core.
static var ARROW_OUTLINE := PackedVector2Array([
	Vector2(0.0, -8.0), Vector2(6.0, 7.0), Vector2(0.0, 3.0), Vector2(-6.0, 7.0)])
static var ARROW_CORE := PackedVector2Array([
	Vector2(0.0, -6.5), Vector2(4.8, 5.6), Vector2(0.0, 2.4), Vector2(-4.8, 5.6)])
## The police chevron.
static var POLICE_CHEVRON := PackedVector2Array([
	Vector2(0.0, -4.0), Vector2(3.5, 3.0), Vector2(-3.5, 3.0)])

## The one array that is reused for the blips (no allocation per frame).
var _blip: PackedVector2Array = PackedVector2Array()


## The points of interest, culled to the visible area.
## project: a Callable that maps a world XZ point to the screen.
## visible: a Callable that tells whether a screen point is inside the map.
func draw_pois(item: CanvasItem, pois: Array[Dictionary], project: Callable,
		visible: Callable) -> void:
	for poi in pois:
		var kind := StringName(str(poi.get("kind", "")))
		var pos: Vector3 = poi.get("position", Vector3.ZERO)
		var sp: Vector2 = project.call(Vector2(pos.x, pos.z))
		if not visible.call(sp):
			continue
		match kind:
			&"charge":
				_draw_bolt(item, sp, Palette.CYAN)
			&"gas":
				item.draw_circle(sp, 4.0, Palette.AMBER)
			&"toll":
				_draw_gate(item, sp)
			&"sky_lane":
				item.draw_dashed_line(sp - Vector2(7, 0), sp + Vector2(7, 0), Palette.CYAN, 2.0, 4.0)
			&"police_station":
				item.draw_rect(Rect2(sp - Vector2(4, 4), Vector2(8, 8)), Palette.RED, false, 1.5)
			_:
				_draw_diamond(item, sp)


## A toll gate: two posts and a bar.
func _draw_gate(item: CanvasItem, sp: Vector2) -> void:
	item.draw_line(sp + Vector2(-5, 5), sp + Vector2(-5, -4), Color(1, 1, 1, 0.9), 1.5, true)
	item.draw_line(sp + Vector2(5, 5), sp + Vector2(5, -4), Color(1, 1, 1, 0.9), 1.5, true)
	item.draw_line(sp + Vector2(-6, -4), sp + Vector2(6, -4), Color(1, 1, 1, 0.9), 1.5, true)


## A landmark: a small diamond.
func _draw_diamond(item: CanvasItem, sp: Vector2) -> void:
	_blip.resize(4)
	_blip[0] = sp + Vector2(0, -3.5)
	_blip[1] = sp + Vector2(3.5, 0)
	_blip[2] = sp + Vector2(0, 3.5)
	_blip[3] = sp + Vector2(-3.5, 0)
	item.draw_colored_polygon(_blip, Color(1, 1, 1, 0.4))


## A charging station: a bolt.
func _draw_bolt(item: CanvasItem, p: Vector2, col: Color) -> void:
	_blip.resize(6)
	_blip[0] = p + Vector2(1, -6)
	_blip[1] = p + Vector2(-3, 1)
	_blip[2] = p + Vector2(0, 1)
	_blip[3] = p + Vector2(-1, 6)
	_blip[4] = p + Vector2(3, -1)
	_blip[5] = p + Vector2(0, -1)
	item.draw_colored_polygon(_blip, col)


## The police blips are chevrons (dossier §8.3), the rival blips are dots.
func draw_blips(item: CanvasItem, blips: PackedVector3Array, project: Callable,
		visible: Callable, police: bool) -> void:
	var blink := fmod(float(Time.get_ticks_msec()) * 0.004, 1.0) < 0.5
	for b in blips:
		var sp: Vector2 = project.call(Vector2(b.x, b.z))
		if not visible.call(sp):
			continue
		if police:
			var c := Palette.RED if blink else Palette.POLICE_BLUE
			item.draw_circle(sp, 5.0, Color(c.r, c.g, c.b, 0.3))
			_blip.resize(3)
			_blip[0] = sp + POLICE_CHEVRON[0]
			_blip[1] = sp + POLICE_CHEVRON[1]
			_blip[2] = sp + POLICE_CHEVRON[2]
			item.draw_colored_polygon(_blip, c)
		else:
			item.draw_circle(sp, 3.0, Palette.AMBER)


## The next gate of the race: a pulsing amber diamond at the gate.
func draw_gate(item: CanvasItem, sp: Vector2) -> void:
	var pulse := fmod(float(Time.get_ticks_msec()) * 0.004, 1.0)
	var r := 5.0 + 2.0 * pulse
	# A dark rim, so the marker reads over the bright line of the route.
	_diamond(item, sp, r + 1.5, PLAYER_OUTLINE)
	_diamond(item, sp, r, Color(Palette.AMBER.r, Palette.AMBER.g, Palette.AMBER.b, 0.6 + 0.4 * pulse))


## A diamond of the radius r at the point.
func _diamond(item: CanvasItem, sp: Vector2, r: float, color: Color) -> void:
	_blip.resize(4)
	_blip[0] = sp + Vector2(0.0, -r)
	_blip[1] = sp + Vector2(r, 0.0)
	_blip[2] = sp + Vector2(0.0, r)
	_blip[3] = sp + Vector2(-r, 0.0)
	item.draw_colored_polygon(_blip, color)


## The player: an arrow with a dark outline and a 40 degree view cone. Both are drawn from the
## constant arrays under a transform, so nothing is allocated.
func draw_player(item: CanvasItem, centre: Vector2) -> void:
	item.draw_set_transform(centre, 0.0, Vector2.ONE)
	item.draw_colored_polygon(CONE_POINTS, Color(1, 1, 1, CONE_ALPHA))
	item.draw_colored_polygon(ARROW_OUTLINE, PLAYER_OUTLINE)
	item.draw_colored_polygon(ARROW_CORE, Palette.WHITE)
	item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A tick on the rim that points north: a bold N on a dark disc, so it reads over the map.
func draw_north(item: CanvasItem, centre: Vector2, radius: float, angle: float) -> void:
	var dir := Vector2(cos(angle), sin(angle))
	var p := centre + dir * (radius - 7.0)
	item.draw_line(centre + dir * (radius - 12.0), p, Color(1, 1, 1, 0.7), 2.0, true)
	item.draw_circle(p, NORTH_DISC, NORTH_COLOR)
	var font := Fonts.text_bold()
	var w := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, NORTH_SIZE).x
	item.draw_string(font, p - Vector2(w * 0.5, -NORTH_SIZE * 0.35), "N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, NORTH_SIZE, Color(1, 1, 1, 0.9))
