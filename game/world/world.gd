extends WorldBase
## The playable Shanghai. Loads the city (city.json + the roads unit's lane and furniture data),
## instantiates the road, block, bund and landmark tiles, places the street furniture, the pooled
## lights, the traffic signals and the gameplay sites, and answers the WorldBase API for the AI,
## the modes, the HUD and the player.
##
## Every input is optional: a missing tile, a missing data file or a missing glb degrades the
## world instead of failing the load (a warning is printed once per file).

const CityData := preload("res://world/loader/city_data.gd")
const WorldBuilder := preload("res://world/build/world_builder.gd")
const Heading := preload("res://world/api/heading.gd")
const LaneIndex := preload("res://world/api/lane_index.gd")
const SpawnPlacer := preload("res://world/api/spawn_placer.gd")

var data: CityData
var loading_fraction := 0.0
var _builder: WorldBuilder
var _lanes: Array[LanePath] = []
var _routes: Dictionary = {}
var _minimap: Array[PackedVector2Array] = []
var _pois: Array[Dictionary] = []
var _roadblocks: Array[Transform3D] = []
var _build_seconds := 0.0
var _announced := false
## True when the API was asked for something before the city was built.
var _warned_not_ready := false
var _index: LaneIndex
## The spawn points of the world (on a lane, facing the traffic, with a clear road ahead).
var _placer: SpawnPlacer

## The height decides between the elevated deck and the road below it.
## The cars sit this far above the lane surface.
## How far ahead the lane tangent is sampled for the facing.
## The layer of the road surfaces (the world).
## How far above and below the lane the road surface is looked for.
## The road ahead of a spawn must be clear over this distance.
## The world layer and the trigger layer (the props and the sites).
## Another lane closer than this blocks the spawn.
## The distance between two traffic cars on a lane.
const TRAFFIC_SPACING := 37.0
## How many steps the spawn walks along the lane until the road ahead is clear.


func _ready() -> void:
	Game.world = self
	_build.call_deferred()


## Builds the city. The builder works in phases and yields a frame between them, so the
## loading screen shows the progress.
func _build() -> void:
	var started := Time.get_ticks_msec()
	data = CityData.new()
	data.load_all()
	_progress(0.02, "读取城市数据")
	_builder = WorldBuilder.new()
	await _builder.build(self, data)
	_build_api()
	_build_seconds = float(Time.get_ticks_msec() - started) / 1000.0
	print("[world] built in %.2f s (%d lanes, %d routes)" % [_build_seconds, _lanes.size(),
		_routes.size()])
	_progress(1.0, "就绪")
	for warning in data.warnings:
		push_warning("[world] %s" % warning)


## The world is built while the other units are still being created, so the loading screen
## misses the progress events. The state is repeated on the first frame, when the menu exists.
func _process(_delta: float) -> void:
	if _announced:
		return
	_announced = true
	_progress(loading_fraction, "就绪")


func _progress(fraction: float, label: String) -> void:
	loading_fraction = fraction
	Events.loading_progress.emit(fraction, label)


## The lane graph, the routes, the minimap and the points of interest.
func _build_api() -> void:
	_lanes = _builder.lanes
	_routes = _builder.routes
	_index = LaneIndex.new()
	_index.build(_lanes)
	_placer = SpawnPlacer.new()
	_placer.setup(_lanes, _index)
	_minimap = CityData.build_minimap(data.minimap_roads, data.road_ids().keys(), data.roads())
	_pois = CityData.build_pois(data.pois(), data.sky_lanes())
	_roadblocks = _builder.roadblock_sites


# --- WorldBase API ----------------------------------------------------------------------------------

## True when the city is built. The API answers with the documented fallbacks until then.
func is_ready() -> bool:
	return data != null and _builder != null and not _routes.is_empty()


## A warning that the API was used before the city was built (once).
func _not_ready() -> void:
	if _warned_not_ready:
		return
	_warned_not_ready = true
	push_warning("[world] the API was used before the city was built")


## Spawn transforms for the player, the police, the traffic and the rivals. Every spawn sits on
## a lane centre, faces the lane and has a clear road ahead.
func get_spawn_transform(kind: StringName, index: int) -> Transform3D:
	if not is_ready():
		_not_ready()
		return Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	var spawns := data.spawns()
	if kind == &"player":
		var spec: Variant = spawns.get("player", null)
		if spec is Array and (spec as Array).size() >= 3:
			return _placer.spawn_transform(self, _transform(spec as Array).origin)
	if kind == &"police":
		var list: Variant = spawns.get("police", [])
		if list is Array and not (list as Array).is_empty():
			var entries := list as Array
			var entry: Variant = entries[index % entries.size()]
			if entry is Array and (entry as Array).size() >= 3:
				return _placer.spawn_transform(self, _transform(entry as Array).origin)
	if kind == &"rival":
		for route in _routes.values():
			var race := route as RaceRoute
			if race.grid.size() > 0:
				return _placer.spawn_transform(self, race.grid[index % race.grid.size()].origin)
	if _lanes.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))
	var lane := _lanes[index % _lanes.size()]
	return _placer.spawn_on_lane(self, lane, float(index) * TRAFFIC_SPACING)


## Closest safe on-road transform (lane centre, -Z along traffic direction).
func nearest_road_transform(pos: Vector3) -> Transform3D:
	if not is_ready():
		_not_ready()
		return Transform3D(Basis.IDENTITY, Vector3(pos.x, 1.0, pos.z))
	var found := _placer.closest_lane(pos)
	if found.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(pos.x, 1.0, pos.z))
	var lane: LanePath = found["lane"]
	var offset: float = found["offset"]
	return _placer.lane_transform(self, lane, offset)


## The player back on the road after a wreck or a reset: the closest lane, driven along `direction`, at a place with a clear
## road ahead (world/api/spawn_placer.gd respawn_on_lane).
func respawn_transform(pos: Vector3, direction: Vector3) -> Transform3D:
	if not is_ready():
		_not_ready()
		return Transform3D(Basis.IDENTITY, Vector3(pos.x, 1.0, pos.z))
	var found := _placer.closest_lane(pos)
	if found.is_empty():
		return Transform3D(Basis.IDENTITY, Vector3(pos.x, 1.0, pos.z))
	return _placer.respawn_on_lane(self, found["lane"], found["offset"], direction)


func get_lane_paths() -> Array[LanePath]:
	return _lanes


func get_route_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in _routes.keys():
		out.append(String(id))
	out.sort()
	return out


func get_route(id: StringName) -> RaceRoute:
	return _routes.get(String(id)) as RaceRoute


func get_minimap_polylines() -> Array[PackedVector2Array]:
	return _minimap


func get_points_of_interest() -> Array[Dictionary]:
	return _pois


func get_roadblock_sites() -> Array[Transform3D]:
	if _builder == null:
		_not_ready()
		return []
	return _roadblocks


## The positions of the street furniture that was placed (the HUD and the tests use them).
func get_furniture_positions() -> Array[Vector3]:
	if _builder == null:
		_not_ready()
		return []
	return _builder.furniture_positions


## Traffic-light state for the approach of `road_id` into `junction_id`: 0 red, 1 amber, 2 green.
func signal_state(junction_id: StringName, road_id: StringName) -> int:
	if _builder == null or _builder.signals == null:
		_not_ready()
		return 2
	return _builder.signals.signal_state(junction_id, road_id)


# --- helpers -----------------------------------------------------------------------------------------

func _transform(entry: Array) -> Transform3D:
	var heading := 0.0
	if entry.size() >= 4:
		heading = Heading.yaw_from_heading(float(entry[3]))
	return Transform3D(Basis(Vector3.UP, heading),
		Vector3(float(entry[0]), float(entry[1]), float(entry[2])))


static func _points2(raw: Variant) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not raw is Array:
		return out
	for entry in raw as Array:
		if entry is Array and (entry as Array).size() >= 2:
			out.append(Vector2(float(entry[0]), float(entry[1])))
	return out


static func _points3(raw: Variant) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not raw is Array:
		return out
	for entry in raw as Array:
		if entry is Array and (entry as Array).size() >= 3:
			out.append(Vector3(float(entry[0]), float(entry[1]), float(entry[2])))
	return out
