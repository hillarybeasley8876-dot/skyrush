extends RefCounted
## The cache of the city: the lane graph with its links, the routes and the placements of the
## street furniture are written to a binary .res in user://world_cache/. The name of the file
## is the SHA-256 of the three data files (city.json, lanes.json and road_furniture.json), so
## the cache is rebuilt when one of them changes and reused when they do not.
##
## The build of the city takes more than a minute without the cache (the routes alone walk the
## lane network of the whole city); with it the world is playable in a few seconds.

const CacheData := preload("res://world/loader/cache_data.gd")
const CityData := preload("res://world/loader/city_data.gd")

## The folder of the cache.
const CACHE_DIR := "user://world_cache"
## The version of the cache: it is bumped when the shape of the payload changes.
const VERSION := 14


## The key of the cache: the hash of the three data files.
func key_for(data: CityData) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for path in _data_files(data):
		context.update(_bytes_of(path))
		context.update(path.to_utf8_buffer())
	return "%d_%s" % [VERSION, context.finish().hex_encode()]


## The files the cache depends on.
func _data_files(data: CityData) -> PackedStringArray:
	return PackedStringArray([data.city_path, CityData.LANES_PATH, CityData.FURNITURE_PATH])


## The bytes of a file (an empty array when it cannot be read).
func _bytes_of(path: String) -> PackedByteArray:
	if path == "" or not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


## The path of the cache file of a key.
func path_for(key: String) -> String:
	return "%s/%s.res" % [CACHE_DIR, key]


## Reads the cache. Returns an empty dictionary when there is no cache for the key.
func load_cache(data: CityData) -> Dictionary:
	var key := key_for(data)
	var path := path_for(key)
	if not FileAccess.file_exists(path):
		return {}
	var cache := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as CacheData
	if cache == null:
		return {}
	var routes: Dictionary = cache.routes
	if routes.is_empty():
		# A cache without the routes is not usable: the routes are built from the data again.
		return {}
	return {"lanes": cache.lanes, "routes": routes, "furniture": cache.furniture,
		"traffic_lights": cache.traffic_lights}


## Writes the cache. The failures are not fatal: the world is built from the data instead.
func store_cache(data: CityData, payload: Dictionary) -> void:
	var key := key_for(data)
	if not DirAccess.dir_exists_absolute(CACHE_DIR):
		DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var cache := CacheData.new()
	cache.lanes = payload.get("lanes", [] as Array[LanePath])
	cache.routes = payload.get("routes", {})
	cache.furniture = payload.get("furniture", [])
	cache.traffic_lights = payload.get("traffic_lights", [])
	var path := path_for(key)
	if ResourceSaver.save(cache, path) != OK:
		push_warning("[world] the cache could not be written (%s)" % path)
		return
	# Only the newest cache is kept: the files are large.
	for file in DirAccess.get_files_at(CACHE_DIR):
		if file != path.get_file():
			DirAccess.remove_absolute("%s/%s" % [CACHE_DIR, file])
	print("[world] cache: %s" % path)
