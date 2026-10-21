extends RefCounted
## Builds the city inside the world node: the terrain and the water, the road and block tiles
## (or the fallback city from city.json), the landmarks, the pooled lights, the street furniture,
## the traffic signals, the reflection probes, the gameplay sites and the sky lanes.
##
## The builder owns the systems it creates so the world can query them (the signal controller for
## `signal_state()`, the light pool, the probe placer and the gameplay sites).

const CityData := preload("res://world/loader/city_data.gd")
const AssetLibrary := preload("res://world/loader/asset_library.gd")
const LandmarkManifest := preload("res://world/loader/landmark_manifest.gd")
const TerrainBuilder := preload("res://world/build/terrain_builder.gd")
const GroundBuilder := preload("res://world/build/ground_builder.gd")
const RoadBuilder := preload("res://world/build/road_builder.gd")
const BlockBuilder := preload("res://world/build/block_builder.gd")
const FurnitureBuilder := preload("res://world/build/furniture_builder.gd")
const FurnitureData := preload("res://world/build/furniture_data.gd")
const ShopAtlas := preload("res://world/build/shop_atlas.gd")
const WorldCache := preload("res://world/loader/world_cache.gd")
const RouteBuilder := preload("res://world/api/route_builder.gd")
const StreetDresser := preload("res://world/build/street_dresser.gd")
const SignalController := preload("res://world/build/signal_controller.gd")
const SignFactory := preload("res://world/build/sign_factory.gd")
const LightPool := preload("res://world/build/light_pool.gd")
const ProbePlacer := preload("res://world/build/probe_placer.gd")
const GameplaySites := preload("res://world/build/gameplay_sites.gd")
const SkyLaneBuilder := preload("res://world/build/sky_lane_builder.gd")
const LaneGraphBuilder := preload("res://world/api/lane_graph.gd")
const LaneLinks := preload("res://world/api/lane_links.gd")
const LaneSpatial := preload("res://world/api/lane_spatial.gd")
const FurnitureFilter := preload("res://world/build/furniture_filter.gd")
const Heading := preload("res://world/api/heading.gd")

## The floods of the Bund and of the landmarks get their own pool: twelve spots that reach
## across the river (the street lamps keep the 60 m rule of the dossier).
const FLOOD_SPOTS := 12
const FLOOD_FADE_BEGIN := 500.0
const FLOOD_FADE_LENGTH := 400.0
const FLOOD_DECAL_DISTANCE := 100000.0
const FLOOD_SEARCH_RADIUS := 1200.0

var data: CityData
var signals: SignalController
var lights: LightPool
## The pool of the floods of the Bund and of the landmarks (a second pool, so the street lamps
## keep their 60 m rule and the floods still reach the far side of the river).
var floods: LightPool
var probes: ProbePlacer
var sites: GameplaySites
var signs: SignFactory
var roadblock_sites: Array[Transform3D] = []
## The lane graph (built before the furniture, so the furniture can avoid the carriageway).
var lanes: Array[LanePath] = []
## The spatial index of the lanes: the furniture, the route builder and the lane links use it.
var lane_grid: LaneSpatial
## The drivable graph of the lanes.
var _graph: LaneGraphBuilder
## The positions of the street furniture that was placed.
var furniture_positions: Array[Vector3] = []
## The boxes of the buildings of the city (the gameplay sites step out of them).
var building_boxes: Array[AABB] = []
## The kind of every prop that was placed (the same order as the positions).
var furniture_kinds: Array[String] = []

var _world: Node3D
## The clock of the phases (the duration of the phase that is running).
var _started := 0
var _traffic_lights: Array[Dictionary] = []
## The floods of the landmarks, collected while the landmarks are built and registered with the
## flood pool when the pool exists.
var _pending_floods: Array[Dictionary] = []
## The groups of the world: the world node has a handful of children, not one per prop (the
## performance probe of the core walks them one by one).
var _groups: Dictionary = {}
## The cache of the city: the lane graph, the routes and the furniture placements.
var _cache: WorldCache
## What the cache holds for this build (empty when there is no cache).
var _cached: Dictionary = {}
## The furniture placements of this build (they are written to the cache).
var _furniture_entries: Array[Dictionary] = []
## The routes of the city (the racing lines and the start grids).
var routes: Dictionary = {}


## The group node of a part of the world.
func _group(name: String) -> Node3D:
	if _groups.has(name):
		return _groups[name]
	var node := Node3D.new()
	node.name = name
	_world.add_child(node)
	_groups[name] = node
	return node


## Builds the city in phases. Every phase yields a frame and reports its progress, so the
## loading screen moves and the game stays responsive while the city is built.
func build(world: Node3D, city_data: CityData) -> void:
	_world = world
	data = city_data
	_started = Time.get_ticks_msec()
	_cache = WorldCache.new()
	_cached = _cache.load_cache(data)
	if _cached.is_empty():
		print("[world] cache: none, the city is built from the data")
	else:
		print("[world] cache: %d lanes, %d routes, %d props" % [
			(_cached["lanes"] as Array).size(), (_cached["routes"] as Dictionary).size(),
			(_cached["furniture"] as Array).size()])
	_build_terrain()
	await _phase("terrain", 0.05)
	_build_roads()
	await _phase("roads", 0.25)
	_build_blocks()
	_build_landmarks()
	await _phase("blocks", 0.40)
	_build_lights()
	_build_lanes()
	await _phase("lanes", 0.55)
	await _build_furniture()
	await _phase("furniture", 0.70)
	_build_signals()
	await _phase("signals", 0.80)
	_build_probes()
	_build_gameplay()
	_build_sky_lanes()
	await _phase("sites", 0.95)
	_build_routes()
	await _phase("routes", 0.98)
	_store_cache()


## The routes of the city: the racing lines and the start grids of every route.
func _build_routes() -> void:
	if not _cached.is_empty():
		routes = _cached["routes"]
		return
	routes = RouteBuilder.new().build(data.routes(), lanes, lane_grid)


## Writes the cache of the city (the lane graph, the routes and the furniture placements).
func _store_cache() -> void:
	if not _cached.is_empty():
		return
	if lanes.is_empty():
		return
	_cache.store_cache(data, {"lanes": lanes, "routes": routes, "furniture": _furniture_entries,
		"traffic_lights": _traffic_lights})


## Prints the time the phase took, reports the progress and yields a frame.
func _phase(label: String, fraction: float) -> void:
	var now := Time.get_ticks_msec()
	print("[world] %s: %.2f s" % [label, float(now - _started) / 1000.0])
	_started = now
	Events.loading_progress.emit(fraction, label)
	var loop := Engine.get_main_loop() as SceneTree
	if loop != null:
		await loop.process_frame


# --- terrain, tiles and landmarks ------------------------------------------------------------------

func _build_terrain() -> void:
	var terrain := TerrainBuilder.new()
	var window := data.window_rect()
	var bodies := terrain.parse_water(data.water())
	var ground := _group("Terrain")
	GroundBuilder.new().build(ground, window, terrain.water_polygons())
	terrain.build_water(ground, bodies)
	terrain.build_kill_floor(ground, window)


func _build_roads() -> void:
	var lib := AssetLibrary.new()
	var root := _group("Roads")
	var near := lib.instantiate_dir(AssetLibrary.ROADS_DIR, "roads_", false)
	var far := lib.instantiate_dir(AssetLibrary.ROADS_DIR, "roads_", true)
	var total := lib.find_glbs(AssetLibrary.ROADS_DIR, "roads_").size()
	if near.is_empty() and far.is_empty():
		print("[world] roads: 0 of %d tiles loaded, the fallback city is used" % total)
		RoadBuilder.new().build(root, data.roads())
		return
	print("[world] roads: %d of %d tiles loaded" % [near.size() + far.size(), total])
	for node in near:
		root.add_child(node)
	for node in far:
		root.add_child(node)


func _build_blocks() -> void:
	var lib := AssetLibrary.new()
	var root := _group("Blocks")
	var near := lib.instantiate_dir(AssetLibrary.BLOCKS_DIR, "blocks_", false)
	var far := lib.instantiate_dir(AssetLibrary.BLOCKS_DIR, "blocks_", true)
	var total := lib.find_glbs(AssetLibrary.BLOCKS_DIR, "blocks_").size()
	if near.is_empty() and far.is_empty():
		print("[world] blocks: 0 of %d tiles loaded, the fallback city is used" % total)
		BlockBuilder.new().build(root, data.blocks())
		return
	var occluders := 0
	var shapes := 0
	var clock := Time.get_ticks_msec()
	for node in near:
		occluders += lib.apply_occluders(node, str(node.get_meta("source_path", "")))
		building_boxes.append_array(lib.collect_boxes(node, str(node.get_meta("source_path", ""))))
		shapes += lib.merge_collision(node)
		root.add_child(node)
	print("[world] blocks: the near tiles take %.2f s" % (float(Time.get_ticks_msec() - clock) / 1000.0))
	clock = Time.get_ticks_msec()
	for node in far:
		root.add_child(node)
	print("[world] blocks: the far tiles take %.2f s" % (float(Time.get_ticks_msec() - clock) / 1000.0))
	print("[world] blocks: %d of %d tiles loaded, %d occlusion boxes, %d collision shapes" % [
		near.size() + far.size(), total, occluders, shapes])


func _build_landmarks() -> void:
	var lib := AssetLibrary.new()
	var root := _group("Landmarks")
	# The Bund and the landmarks are seen from the other side of the river: no visibility range.
	for node in lib.instantiate_dir(AssetLibrary.BUND_DIR, "", false, false):
		building_boxes.append_array(lib.collect_boxes(node))
		root.add_child(node)
	var manifest := LandmarkManifest.new()
	manifest.build(root)
	_pending_floods = manifest.floods
	for poi in data.pois():
		if not poi is Dictionary:
			continue
		var entry := poi as Dictionary
		if str(entry.get("kind", "")) != "landmark":
			continue
		var asset := str(entry.get("asset", ""))
		if asset == "":
			continue
		var path := "res://assets/landmarks/%s.glb" % asset
		if not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var landmark := packed.instantiate() as Node3D
		if landmark == null:
			continue
		MaterialLibrary.apply(landmark)
		landmark.position = Vector3(float(entry.get("x", 0.0)), float(entry.get("y", 0.0)),
			float(entry.get("z", 0.0)))
		landmark.rotation.y = Heading.yaw_from_heading(float(entry.get("heading_deg", 0.0)))
		root.add_child(landmark)


## The counts of the furniture per type, as a short string.
static func _str(counts: Dictionary) -> String:
	var parts: Array[String] = []
	for key in counts.keys():
		parts.append("%s %d" % [key, int(counts[key])])
	return ", ".join(parts)


# --- lights, furniture and signals ------------------------------------------------------------------

func _build_lights() -> void:
	lights = LightPool.new()
	lights.name = "LightPool"
	_group("Lighting").add_child(lights)
	floods = LightPool.new()
	floods.name = "FloodPool"
	floods.max_omni = 0
	floods.max_spot = FLOOD_SPOTS
	floods.max_decals = 0
	floods.fade_begin = FLOOD_FADE_BEGIN
	floods.fade_length = FLOOD_FADE_LENGTH
	floods.decal_distance = FLOOD_DECAL_DISTANCE
	floods.search_radius = FLOOD_SEARCH_RADIUS
	_group("Lighting").add_child(floods)
	for entry in data.bund_lights:
		if entry is Dictionary:
			_add_bund_light(entry as Dictionary)
	for flood in _pending_floods:
		floods.add_source(flood["position"], flood["color"], flood["energy"], flood["range"],
			"spot", 0.0, 0.0, flood["direction"], flood["position"], flood["angle"])


## The bund sidecar stores a light as {"position": [x, y, z], "direction": [x, y, z],
## "color": [r, g, b], "energy", "range", "angle"} in Godot axes.
func _add_bund_light(entry: Dictionary) -> void:
	var raw_position: Variant = entry.get("position", null)
	if not raw_position is Array or (raw_position as Array).size() < 3:
		return
	var p := raw_position as Array
	var position := Vector3(float(p[0]), float(p[1]), float(p[2]))
	var color := Color("ffcf87")
	if entry.get("color", null) is Array:
		var c := entry["color"] as Array
		color = Color(float(c[0]), float(c[1]), float(c[2]))
	var energy := float(entry.get("energy", data.bund_crown.get("energy", 25.0)))
	var light_range := float(entry.get("range", data.bund_crown.get("range", 30.0)))
	var angle := float(entry.get("angle", data.bund_crown.get("angle", 55.0)))
	var direction := Vector3.ZERO
	var raw_direction: Variant = entry.get("direction", null)
	if raw_direction is Array and (raw_direction as Array).size() >= 3:
		var d := raw_direction as Array
		direction = Vector3(float(d[0]), float(d[1]), float(d[2]))
	floods.add_source(position, color, energy, light_range, "spot", 80.0, 0.0, direction,
		position, angle)


## The lane graph of the city: the lanes of the roads unit, the rest derived from city.json.
func _build_lanes() -> void:
	if not _cached.is_empty():
		lanes = _cached["lanes"]
		lane_grid = LaneSpatial.new()
		lane_grid.build(lanes)
		return
	_graph = LaneGraphBuilder.new()
	lanes = _graph.build(data.lanes, data.roads(), data.lane_links)
	lane_grid = LaneSpatial.new()
	lane_grid.build(lanes)
	LaneLinks.new().link(lanes, _graph, data.junctions(), lane_grid)

func _build_furniture() -> void:
	var furniture := FurnitureBuilder.new()
	var filter := FurnitureFilter.new()
	filter.setup(lanes, data.junctions(), data.pois(), data.roads(), lane_grid)
	var styles := _road_styles()
	var data_reader := FurnitureData.new()
	data_reader.set_road_styles(styles)
	# The atlas of the shop name boards: the name of a board is a cell of one texture, so the
	# 1,187 boards of the city stay one MultiMesh per tile.
	var atlas := ShopAtlas.new()
	atlas.name = "ShopAtlas"
	_group("Signs").add_child(atlas)
	await atlas.generate()
	furniture.setup(lights, filter, atlas)
	furniture.set_road_styles(styles)
	var rest: Array[Dictionary] = []
	if not _cached.is_empty():
		rest = _cached["furniture"]
		_traffic_lights = _cached["traffic_lights"]
	else:
		var entries := data_reader.normalise(data.furniture)
		var road_ids := data.road_ids()
		for entry in entries:
			var road := str(entry.get("road", ""))
			if road != "" and not road_ids.has(road):
				continue  # the furniture file was generated for another map
			if str(entry.get("kind", "")) == "traffic_light":
				_traffic_lights.append(entry)
			else:
				rest.append(entry)
		if rest.is_empty() and _traffic_lights.is_empty():
			rest = data_reader.derive_from_roads(data.roads())
		var dresser := StreetDresser.new()
		var half_widths: Dictionary = {}
		for road_id in filter.half_widths():
			half_widths[road_id] = filter.half_width(road_id)
		var dressed := dresser.build(data.roads(), data.junctions(), data.pois(), half_widths, lane_grid)
		for entry in dressed:
			rest.append(entry)
		print("[world] street dressing: %s" % _str(dresser.counts()))
	var sign_props := furniture.build(_group("Furniture"), rest)
	furniture_positions = furniture.placed
	furniture_kinds = furniture.placed_kinds
	_furniture_entries = furniture.placed_entries
	for key in filter.rejected().keys():
		print("[world] furniture rejected: %s x%d" % [key, filter.rejected()[key]])
	print("[world] furniture placed: %s (moved %d off the carriageway)" % [
		_str(furniture.counts), filter.relocated()])
	signs = SignFactory.new()
	signs.name = "SignFactory"
	_group("Signs").add_child(signs)
	signs.apply_signs(sign_props)


## The style of every road: the lamps follow it and the sign panels follow the kind.
func _road_styles() -> Dictionary:
	var out: Dictionary = {}
	for road in data.roads():
		if not road is Dictionary:
			continue
		var d := road as Dictionary
		var style: Dictionary = d.get("style", {})
		out[str(d.get("id", ""))] = {
			"kind": str(d.get("kind", "surface")),
			"lamps": str(style.get("lamps", "side")),
			"trees": str(style.get("trees", "none")),
		}
	return out


func _build_signals() -> void:
	signals = SignalController.new()
	signals.name = "Signals"
	var group := _group("TrafficSignals")
	group.add_child(signals)
	signals.setup(data.junctions(), data.roads(), group, _traffic_lights, lanes, lane_grid)


func _build_probes() -> void:
	probes = ProbePlacer.new()
	probes.name = "Probes"
	_group("Probes").add_child(probes)
	probes.build(data.roads())


func _build_gameplay() -> void:
	sites = GameplaySites.new()
	sites.signs = signs
	sites.build(_group("Sites"), data.pois(), data.roads(), lanes, lane_grid, building_boxes)
	roadblock_sites = sites.roadblock_sites
	if signs != null:
		signs.apply_signs(sites.sign_texts())


func _build_sky_lanes() -> void:
	SkyLaneBuilder.new().build(_group("SkyLanes"), data.sky_lanes())
