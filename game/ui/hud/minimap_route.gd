extends RefCounted
## The racing line of the race on the minimap: a bright line above the roads and the sky lanes.
##
## The world points are projected into a cached array every frame, so a redraw of the map does
## not allocate anything. The line is thinned by the caller (one point every 10 m), so the
## polyline stays short.

## The line of the route: brighter than the roads and in the cyan of the HUD.
const ROUTE_COLOR := Color(0.0, 0.898, 1.0, 0.95)
## The line is thicker than the roads, so it reads over them.
const ROUTE_WIDTH := 3.2

## The world XZ of the points of the route.
var _points: PackedVector2Array = PackedVector2Array()
## The points on the screen (the projection of the world points), reused every frame.
var _screen: PackedVector2Array = PackedVector2Array()


## The racing line on the map (world XZ metres).
func set_route(points: PackedVector2Array) -> void:
	_points = points
	_screen.resize(points.size())


## The racing line is gone.
func clear_route() -> void:
	_points = PackedVector2Array()
	_screen = PackedVector2Array()


## The line on the map. project: a Callable that maps a world XZ point to the screen.
func draw(item: CanvasItem, project: Callable) -> void:
	if _points.size() < 2:
		return
	for i in _points.size():
		var p: Vector2 = project.call(_points[i])
		_screen[i] = p
	item.draw_polyline(_screen, ROUTE_COLOR, ROUTE_WIDTH, true)
