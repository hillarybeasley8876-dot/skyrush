extends RefCounted
## All map data the world needs, in one place.
##   city.json          — data/city/city.json (city_layout unit, OUTSIDE the Godot project)
##   lanes.json         — res://world/data/lanes.json (roads unit)
##   minimap.json       — res://world/data/minimap.json (roads unit)
##   road_furniture.json— res://world/data/road_furniture.json (roads unit)
## Every file is optional. A missing file downgrades the world (derived lanes, no furniture,
## no minimap) and records a warning; it never fails the load.

const LANES_PATH := "res://world/data/lanes.json"
const MINIMAP_PATH := "res://world/data/minimap.json"
const FURNITURE_PATH := "res://world/data/road_furniture.json"
const BUND_LIGHTS_PATH := "res://assets/bund/bund_lights.json"

var city: Dictionary = {}
var lanes: Array[Dictionary] = []
## Explicit lane-to-lane links of the roads unit ({"from", "to", "turn"}).
var lane_links: Array[Dictionary] = []
## The statistics per road of lanes.json ({road id: {"length", "covered", "trimmed", "buildings"?}}): "buildings" is the length of
## lane that the buildings of the Bund took from the road (the roads unit ended the street at the building).
var lane_stats: Dictionary = {}
var minimap_roads: Array[Dictionary] = []
var furniture: Array[Dictionary] = []
var bund_lights: Array[Dictionary] = []
## The shared "crown" light spec of the bund sidecar (colour, energy, range).
var bund_crown: Dictionary = {}
var warnings: PackedStringArray = []
var city_path: String = ""
var used_test_city: bool = false

## When set, this path is used instead of the candidate list (used by the tests to load
## test_city.json and then the real city.json).
static var forced_city_path: String = ""


func load_all() -> void:
	if forced_city_path != "":
		var forced: Variant = _read_json(forced_city_path)
		if forced is Dictionary and not (forced as Dictionary).is_empty():
			city = forced
			city_path = forced_city_path
			used_test_city = forced_city_path.ends_with("test_city.json")
		else:
			warnings.append("forced city file %s could not be read" % forced_city_path)
	else:
		_load_city()
	lanes = _read_lane_dicts(LANES_PATH)
	lane_links = _read_lane_links(LANES_PATH)
	lane_stats = _read_lane_stats(LANES_PATH)
	minimap_roads = _read_minimap_roads(MINIMAP_PATH)
	furniture = _read_furniture(FURNITURE_PATH)
	bund_lights = _read_bund_lights(BUND_LIGHTS_PATH)


## --- city.json ---------------------------------------------------------------------------------

func _load_city() -> void:
	for candidate in _city_candidates():
		var data: Variant = _read_json(candidate)
		if data is Dictionary and not (data as Dictionary).is_empty():
			city = data
			city_path = candidate
			used_test_city = candidate.ends_with("test_city.json")
			return
	warnings.append("city.json not found (looked at %s)" % ", ".join(_city_candidates()))


func _city_candidates() -> PackedStringArray:
	var out := PackedStringArray(["res://world/data/city.json"])
	var repo := repo_root()
	if repo != "":
		out.append(repo.path_join("data/city/city.json"))
		out.append(repo.path_join("data/city/test_city.json"))
	return out


## Absolute path of the repository root (the folder that holds `game/` and `data/`), or "".
static func repo_root() -> String:
	var game_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	if game_dir == "":
		return ""
	return game_dir.get_base_dir()


## --- typed accessors --------------------------------------------------------------------------

func roads() -> Array:
	return _list(city, "roads")


func junctions() -> Array:
	return _list(city, "junctions")


func water() -> Array:
	return _list(city, "water")


func blocks() -> Array:
	return _list(city, "blocks")


func pois() -> Array:
	return _list(city, "pois")


func sky_lanes() -> Array:
	return _list(city, "sky_lanes")


func routes() -> Array:
	return _list(city, "routes")


func spawns() -> Dictionary:
	var s: Variant = city.get("spawns", {})
	return s if s is Dictionary else {}


## The ids of the roads of this city; the roads unit's data files are only used for the roads
## they know, so a file generated for another map cannot leak into the world.
func road_ids() -> Dictionary:
	var out: Dictionary = {}
	for road in roads():
		if road is Dictionary:
			out[str((road as Dictionary).get("id", ""))] = true
	return out


func window_rect() -> Rect2:
	var w: Variant = city.get("window", {})
	if w is Dictionary:
		var d := w as Dictionary
		var x0 := float(d.get("x_min", -2200.0))
		var x1 := float(d.get("x_max", 1800.0))
		var z0 := float(d.get("z_min", -1200.0))
		var z1 := float(d.get("z_max", 1800.0))
		return Rect2(Vector2(x0, z0), Vector2(x1 - x0, z1 - z0))
	return Rect2(Vector2(-2200.0, -1200.0), Vector2(4000.0, 3000.0))


# --- roads unit data files ----------------------------------------------------------------------

func _read_lane_dicts(path: String) -> Array[Dictionary]:
	var data: Variant = _read_json(path)
	if data == null:
		warnings.append("%s missing" % path)
		return [] as Array[Dictionary]
	var list: Array = []
	if data is Array:
		list = data
	elif data is Dictionary:
		var raw: Variant = (data as Dictionary).get("lanes", [])
		if raw is Array:
			list = raw
	var out: Array[Dictionary] = []
	for entry in list:
		if entry is Dictionary:
			out.append(entry)
	if out.is_empty():
		warnings.append("%s has no lanes" % path)
	return out


## The "links" array of lanes.json (lane id -> lane id).
func _read_lane_links(path: String) -> Array[Dictionary]:
	var data: Variant = _read_json(path)
	if not data is Dictionary:
		return [] as Array[Dictionary]
	var raw: Variant = (data as Dictionary).get("links", [])
	if not raw is Array:
		return [] as Array[Dictionary]
	var out: Array[Dictionary] = []
	for entry in raw as Array:
		if entry is Dictionary:
			out.append(entry)
	return out


## The "roads" statistics of lanes.json (road id -> record).
func _read_lane_stats(path: String) -> Dictionary:
	var data: Variant = _read_json(path)
	if not data is Dictionary:
		return {}
	var raw: Variant = (data as Dictionary).get("roads", {})
	return raw as Dictionary if raw is Dictionary else {}


func _read_minimap_roads(path: String) -> Array[Dictionary]:
	var data: Variant = _read_json(path)
	if data == null:
		warnings.append("%s missing" % path)
		return [] as Array[Dictionary]
	var list: Array = []
	if data is Array:
		list = data
	elif data is Dictionary:
		var raw: Variant = (data as Dictionary).get("roads", [])
		if raw is Array:
			list = raw
	var out: Array[Dictionary] = []
	for entry in list:
		if entry is Dictionary:
			out.append(entry)
	return out


func _read_furniture(path: String) -> Array[Dictionary]:
	var data: Variant = _read_json(path)
	if data == null:
		warnings.append("%s missing" % path)
		return [] as Array[Dictionary]
	var list: Array = []
	if data is Array:
		list = data
	elif data is Dictionary:
		var raw: Variant = (data as Dictionary).get("props", [])
		if raw is Array:
			list = raw
	var out: Array[Dictionary] = []
	for entry in list:
		if entry is Dictionary:
			out.append(entry)
	return out


func _read_bund_lights(path: String) -> Array[Dictionary]:
	var data: Variant = _read_json(path)
	if data == null:
		return [] as Array[Dictionary]
	var list: Array = []
	if data is Array:
		list = data
	elif data is Dictionary:
		var crown: Variant = (data as Dictionary).get("crown", {})
		if crown is Dictionary:
			bund_crown = crown
		var raw: Variant = (data as Dictionary).get("lights", [])
		if raw is Array:
			list = raw
	var out: Array[Dictionary] = []
	for entry in list:
		if entry is Dictionary:
			out.append(entry)
	return out


# --- helpers -------------------------------------------------------------------------------------

static func _list(source: Dictionary, key: String) -> Array:
	var raw: Variant = source.get(key, [])
	return raw if raw is Array else []


## Reads JSON from a res:// path or an absolute OS path. Returns null when unreadable.
static func _read_json(path: String) -> Variant:
	if path.begins_with("res://"):
		if FileAccess.file_exists(path):
			var text: String = FileAccess.get_file_as_string(path)
			return JSON.parse_string(text)
		return null
	if FileAccess.file_exists(path):
		var text2: String = FileAccess.get_file_as_string(path)
		return JSON.parse_string(text2)
	return null


## The road outlines for the HUD minimap, in world XZ metres.
static func build_minimap(minimap_roads: Array, road_ids: Array,
		roads: Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for road in minimap_roads:
		if not road_ids.has(str(road.get("id", ""))):
			continue  # the minimap file was generated for another map
		var line := PackedVector2Array()
		for point in _points2(road.get("points", [])):
			line.append(point)
		if line.size() >= 2:
			out.append(line)
	if not out.is_empty():
		return out
	for road in roads:
		if not road is Dictionary:
			continue
		var line2 := PackedVector2Array()
		for point in _points2((road as Dictionary).get("points", [])):
			line2.append(point)
		if line2.size() >= 2:
			out.append(line2)
	return out


## The points of interest for the HUD and the minimap icons.
static func build_pois(pois: Array, sky_lanes: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for poi in pois:
		if not poi is Dictionary:
			continue
		var d := poi as Dictionary
		out.append({
			"kind": StringName(str(d.get("kind", "landmark"))),
			"position": Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)),
				float(d.get("z", 0.0))),
			"label": str(d.get("label", "")),
		})
	for lane in sky_lanes:
		if not lane is Dictionary:
			continue
		var d2 := lane as Dictionary
		var points := _points3(d2.get("points", []))
		if points.is_empty():
			continue
		out.append({
			"kind": &"sky_lane",
			"position": points[0],
			"label": str(d2.get("label", "飞行航道")),
		})
	return out


## The points of an array of pairs.
static func _points2(raw: Variant) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not raw is Array:
		return out
	for entry in raw as Array:
		if entry is Array and (entry as Array).size() >= 2:
			out.append(Vector2(float(entry[0]), float(entry[1])))
	return out


## The points of an array of triples.
static func _points3(raw: Variant) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if not raw is Array:
		return out
	for entry in raw as Array:
		if entry is Array and (entry as Array).size() >= 3:
			out.append(Vector3(float(entry[0]), float(entry[1]), float(entry[2])))
	return out
