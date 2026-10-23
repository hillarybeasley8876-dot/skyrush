extends "res://ui/hud/glass_panel.gd"
## Top-right minimap: heading-up (the player always points up) road outline, points of interest and
## police / rival blips.
##
## The roads are rendered ONCE into a SubViewport texture in world metres, at a fixed resolution
## (0.5 px/m, capped at 2048 px). Every frame the overlay only moves, rotates and scales that one
## texture, so the per-frame cost is a transform plus a handful of blips. The polylines are
## simplified with Douglas-Peucker (3 m) when the world is loaded.

const Icons := preload("res://ui/hud/minimap_icons.gd")
const Simplify := preload("res://ui/hud/minimap_simplify.gd")
const Route := preload("res://ui/hud/minimap_route.gd")

const PANEL_SIZE := Vector2(252, 252)
const CLIP_INSET := 12.0
const ROAD_COLOR := Color(0.604, 0.651, 0.769, 0.68)
const ROAD_WIDTH := 2.4
## The grid of the map, in metres.
const GRID_SPACING := 100.0
const SKY_COLOR := Color(0.0, 0.898, 1.0, 0.9)
## The zoom of the map, in px/m.
const ZOOM_FAST := 0.45             ## below 80 km/h (about 560 m across)
const ZOOM_FAST_SPEED := 80.0
const ZOOM_SLOW := 0.25             ## at 250 km/h
const ZOOM_SLOW_SPEED := 250.0
## The map texture is rendered at this resolution and only SCALED in the overlay, so a change of
## the zoom never re-renders the roads.
const TEXTURE_ZOOM := 0.5
## The map texture never grows beyond this many pixels on its longest side.
const MAX_TEXTURE := 2048
## A police unit further away than this is not shown (dossier §3.4: 220 m of sight).
const BLIP_RANGE := 260.0
## The map heading is taken from the velocity below this horizontal length.
const HEADING_EPSILON := 0.5
## The dark base under the map, so the scene never shows through between the roads.
const MAP_BASE := Color(0.020, 0.027, 0.051, 0.85)
const MAP_BASE_INSET := 2.0

var _clip: Control
var _overlay: Control
## The roads are rendered once into this viewport; every frame the map is a single textured quad
## that is moved and rotated (re-rasterising 5000 road points every frame is far too slow).
var _viewport: SubViewport
var _vp_layer: Control
var _vignette: GradientTexture2D
var _world_min: Vector2 = Vector2.ZERO
var _world_size: Vector2 = Vector2(1, 1)
var _tex_zoom: float = TEXTURE_ZOOM

var _roads: Array[PackedVector2Array] = []
var _road_bounds: Array[Rect2] = []
var _sky_lanes: Array[PackedVector2Array] = []
var _pois: Array[Dictionary] = []
var _police: PackedVector3Array = PackedVector3Array()
var _rivals: PackedVector3Array = PackedVector3Array()

var _player_pos: Vector2 = Vector2.ZERO
var _rot: float = 0.0
var _zoom: float = ZOOM_FAST
## The icons draw with these; they are created once, not every frame.
var _icons: Icons
var _project: Callable
var _inside_callable: Callable

## The racing line of the race on the map: the world XZ of the line, thinned by the caller.
var route_points: PackedVector2Array = PackedVector2Array()
## The world XZ of the next gate of the race.
var next_gate_world: Vector2 = Vector2.ZERO
## True when there is a next gate on the map.
var has_next_gate: bool = false
## The helper that draws the line of the route.
var _route: Route = Route.new()


func _ready() -> void:
	super._ready()
	cut = 18.0
	header = "地图 MAP"
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	_icons = Icons.new()
	_project = Callable(self, "project_point")
	_inside_callable = Callable(self, "_inside")
	_build()


func _build() -> void:
	_clip = Control.new()
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(_clip, 0, 0, 1, 1, CLIP_INSET, CLIP_INSET, -CLIP_INSET, -CLIP_INSET)
	add_child(_clip)

	_vignette = _make_vignette()
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	add_child(_viewport)

	_vp_layer = Control.new()
	_vp_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp_layer.draw.connect(_draw_layer)
	_viewport.add_child(_vp_layer)

	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	_clip.add_child(_overlay)


## world_polylines: Array[PackedVector2Array] in world XZ metres; pois: Array of
## {kind, position, label}; sky_lanes: Array[PackedVector2Array] of the flight corridors.
func set_world(world_polylines: Array[PackedVector2Array], pois: Array[Dictionary],
		sky_lanes: Array[PackedVector2Array] = []) -> void:
	_roads = []
	_road_bounds = []
	for l in world_polylines:
		var simplified := Simplify.simplify(l as PackedVector2Array)
		_roads.append(simplified)
		_road_bounds.append(Simplify.bounds_of(simplified))
	_sky_lanes = []
	for s in sky_lanes:
		_sky_lanes.append(Simplify.simplify(s as PackedVector2Array))
	_pois = pois
	_rebuild_texture()


## The racing line of the race on the map (world XZ metres, thinned by the caller).
func set_route(points: PackedVector2Array) -> void:
	route_points = points
	_route.set_route(points)
	_redraw_map()


## The route of the race is gone (and the gate of the player with it).
func clear_route() -> void:
	route_points = PackedVector2Array()
	next_gate_world = Vector2.ZERO
	has_next_gate = false
	_route.clear_route()
	_redraw_map()


## The next gate of the race on the map (world XZ metres).
func set_next_gate(pos: Vector2) -> void:
	next_gate_world = pos
	has_next_gate = true
	_redraw_map()


## The player is home: there is no next gate on the map.
func clear_next_gate() -> void:
	next_gate_world = Vector2.ZERO
	has_next_gate = false
	_redraw_map()


## The map has to be redrawn (the route or the gate changed).
func _redraw_map() -> void:
	if _overlay != null:
		_overlay.queue_redraw()


## The sky lanes of the world, collected once (a SkyLane is a Path3D whose curve points are world
## positions).
func collect_sky_lanes(world: WorldBase) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if world == null:
		return out
	for node in world.find_children("SkyLane_*", "Path3D", true, false):
		var lane := node as Path3D
		if lane == null or lane.curve == null:
			continue
		var flat := PackedVector2Array()
		for p in lane.curve.get_baked_points():
			flat.append(Vector2(p.x, p.z))
		if flat.size() >= 2:
			out.append(flat)
	return out


## The police and rival blips, refreshed a few times a second so they do not step across the map.
func refresh_blips(player_pos: Vector3) -> void:
	_police.clear()
	_rivals.clear()
	for n in get_tree().get_nodes_in_group("police"):
		var v := n as VehicleBase
		if v == null or v.is_wrecked:
			continue
		if player_pos.distance_to(v.global_position) > BLIP_RANGE:
			continue
		_police.append(v.global_position)
	for n in get_tree().get_nodes_in_group("rivals"):
		var v2 := n as VehicleBase
		if v2 != null:
			_rivals.append(v2.global_position)


## The heading the map uses: the car's forward axis, or its horizontal velocity when the car points
## straight up (at +-90 degrees of pitch the map would spin).
static func heading_for(player: VehicleBase) -> Vector3:
	var forward := -player.global_transform.basis.z
	if Vector2(forward.x, forward.z).length() >= HEADING_EPSILON:
		return forward
	var velocity := player.linear_velocity
	if Vector2(velocity.x, velocity.z).length() >= HEADING_EPSILON:
		return velocity
	return forward


## The world XZ of a point -> the minimap screen position.
func project_point(p: Vector2) -> Vector2:
	var centre := _clip.size * 0.5
	var d := p - _player_pos
	var c := cos(_rot)
	var s := sin(_rot)
	return centre + Vector2((d.x * c - d.y * s) * _zoom, (d.x * s + d.y * c) * _zoom)


## The police blips on the map (the HUD also counts them for the busted meter).
func police_positions() -> PackedVector3Array:
	return _police


## player_pos: the player's world position; forward: the player's forward axis; speed_kmh: the
## current speed (it drives the zoom).
func update_map(player_pos: Vector3, forward: Vector3, speed_kmh: float) -> void:
	_player_pos = Vector2(player_pos.x, player_pos.z)
	_rot = -PI * 0.5 - atan2(forward.z, forward.x)
	_zoom = _zoom_for(speed_kmh)
	_overlay.queue_redraw()


## The zoom: 0.45 px/m below 80 km/h, easing down to 0.25 px/m at 250 km/h.
func _zoom_for(speed_kmh: float) -> float:
	var t := clampf((speed_kmh - ZOOM_FAST_SPEED) / (ZOOM_SLOW_SPEED - ZOOM_FAST_SPEED), 0.0, 1.0)
	return lerpf(ZOOM_FAST, ZOOM_SLOW, t)


## Render the roads into the map texture. This happens ONCE per world: the overlay only scales the
## texture, so a change of the zoom costs nothing.
func _rebuild_texture() -> void:
	if _roads.is_empty():
		return
	var bounds := _road_bounds[0]
	for b in _road_bounds:
		bounds = bounds.merge(b)
	_world_min = bounds.position
	_world_size = bounds.size
	# Keep the texture inside a sane size; the zoom above that is only a blur.
	var tex_zoom := minf(TEXTURE_ZOOM, MAX_TEXTURE / maxf(_world_size.x, _world_size.y))
	_tex_zoom = tex_zoom
	var px := maxi(int(_world_size.x * tex_zoom), 16)
	var py := maxi(int(_world_size.y * tex_zoom), 16)
	_viewport.size = Vector2i(px, py)
	_vp_layer.size = Vector2(px, py)
	_vp_layer.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## The roads and the sky lanes, drawn in world metres (the layer's transform does the rest).
## All the roads go into ONE draw_multiline call: a draw call per road would cost more than the
## whole HUD budget with the real city network.
## The roads are drawn into the map texture in TEXTURE space: the texel of a world point p is
## (p - _world_min) * _tex_zoom, with no offset. The overlay maps the texture back with the
## heading rotation, so the two must agree exactly.
func _draw_layer() -> void:
	# draw_multiline takes segment pairs, so every road becomes (p0, p1), (p1, p2), ...
	var pts := PackedVector2Array()
	for line in _roads:
		if line.size() < 2:
			continue
		for i in range(line.size() - 1):
			pts.append((line[i] - _world_min) * _tex_zoom)
			pts.append((line[i + 1] - _world_min) * _tex_zoom)
	_draw_grid()
	if pts.size() >= 4:
		_vp_layer.draw_multiline(pts, ROAD_COLOR, ROAD_WIDTH, true)
	for line in _sky_lanes:
		if line.size() < 2:
			continue
		_draw_dashed_polyline(line, SKY_COLOR, ROAD_WIDTH * 1.4, ROAD_WIDTH * 2.5)


## The radial edge vignette: transparent in the middle, dark at the rim.
func _make_vignette() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_offset(0, 0.55)
	gradient.set_color(0, Color(0.02, 0.024, 0.059, 0.0))
	gradient.set_offset(1, 1.0)
	gradient.set_color(1, Color(0.02, 0.024, 0.059, 0.75))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 128
	tex.height = 128
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


## A 100 m grid over the whole map (white alpha 0.05).
func _draw_grid() -> void:
	var step := GRID_SPACING * _tex_zoom
	if step < 4.0:
		return
	var w := _vp_layer.size.x
	var h := _vp_layer.size.y
	var col := Color(1, 1, 1, 0.05)
	var x := fmod(-_world_min.x * _tex_zoom, step)
	while x < w:
		_vp_layer.draw_line(Vector2(x, 0.0), Vector2(x, h), col, 1.0, true)
		x += step
	var y := fmod(-_world_min.y * _tex_zoom, step)
	while y < h:
		_vp_layer.draw_line(Vector2(0.0, y), Vector2(w, y), col, 1.0, true)
		y += step


## A dashed polyline (draw_dashed_line only draws a single segment).
func _draw_dashed_polyline(points: PackedVector2Array, color: Color, width: float, dash: float) -> void:
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var seg := b - a
		var len := seg.length()
		if len < 0.01:
			continue
		var dir := seg / len
		var d := 0.0
		while d < len:
			var d2 := minf(d + dash, len)
			_vp_layer.draw_line((a + dir * d - _world_min) * _tex_zoom,
				(a + dir * d2 - _world_min) * _tex_zoom, color, width, true)
			d = d2 + dash


## The moving parts: POIs, blips, the player arrow and the north tick.
func _draw_overlay() -> void:
	# The dark base: the scene must never show through between the roads.
	_overlay.draw_rect(Rect2(Vector2(MAP_BASE_INSET, MAP_BASE_INSET),
		_clip.size - Vector2(MAP_BASE_INSET, MAP_BASE_INSET) * 2.0), MAP_BASE)
	_draw_map_texture()
	_draw_vignette()
	_route.draw(_overlay, _project)
	_icons.draw_pois(_overlay, _pois, _project, _inside_callable)
	_icons.draw_blips(_overlay, _rivals, _project, _inside_callable, false)
	_icons.draw_blips(_overlay, _police, _project, _inside_callable, true)
	_draw_next_gate()
	_icons.draw_player(_overlay, _clip.size * 0.5)
	_icons.draw_north(_overlay, _clip.size * 0.5, minf(_clip.size.x, _clip.size.y) * 0.5,
		-PI * 0.5 - _rot)


## The next gate of the race: a pulsing amber diamond at the gate (clipped like the icons).
func _draw_next_gate() -> void:
	if not has_next_gate:
		return
	var sp := project_point(next_gate_world)
	if not _inside(sp):
		return
	_icons.draw_gate(_overlay, sp)


## A soft dark edge inside the clip, so the map fades into the panel.
func _draw_vignette() -> void:
	var r := _clip.size * 0.5
	_overlay.draw_texture_rect(_vignette, Rect2(_clip.size * 0.5 - r, r * 2.0), false)


## The map itself: one textured quad, moved and rotated to the player's heading.
func _draw_map_texture() -> void:
	if _viewport.size.x <= 1:
		return
	var tex := _viewport.get_texture()
	if tex == null:
		return
	var centre := _clip.size * 0.5
	var c := cos(_rot)
	var s := sin(_rot)
	# The texture was rendered at _tex_zoom; the map is shown at _zoom, so it is scaled by k.
	var k := _zoom / maxf(_tex_zoom, 0.0001)
	var rel := (_world_min - _player_pos) * _zoom
	var translation := centre + Vector2(rel.x * c - rel.y * s, rel.x * s + rel.y * c)
	_overlay.draw_set_transform(translation, _rot, Vector2(k, k))
	_overlay.draw_texture_rect(tex, Rect2(Vector2.ZERO, Vector2(_viewport.size)), false)
	_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _inside(sp: Vector2) -> bool:
	return sp.x >= 0.0 and sp.y >= 0.0 and sp.x <= _clip.size.x and sp.y <= _clip.size.y
