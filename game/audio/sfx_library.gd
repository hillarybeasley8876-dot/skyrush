extends RefCounted
## Loads and caches the generated audio streams.
##
## The OGG importer's default is `loop=false`, so the looping files (siren, hum, squeal, ambience,
## music) get their loop flag set here when they are loaded. The loops themselves are
## sample-periodic, so repeating them is click-free.
##
## The cache is static on purpose (the streams are shared by every player), so clear_cache() has to
## be called when the audio unit shuts down — otherwise the engine reports leaked resources.

const Tuning := preload("res://audio/audio_tuning.gd")

const SFX_DIR := "res://audio/sfx/"
const MUSIC_DIR := "res://audio/music/"

static var _cache: Dictionary = {}


## Returns the stream for `id` (file name without extension) or null when it is missing.
static func stream(id: StringName, folder: String = SFX_DIR, looping: bool = false) -> AudioStream:
	var key := folder + String(id)
	if _cache.has(key):
		return _cache[key] as AudioStream
	var path := key + ".ogg"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		# CACHE_MODE_IGNORE: the library has its own cache, and the ResourceLoader cache would
		# keep the streams alive until the engine exits (a "resource still in use" error)
		s = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
		if s is AudioStreamOggVorbis and (looping or is_looping(id)):
			# the loop region itself comes from the LOOPSTART/LOOPEND vorbis comments that
			# tools/audio/common.py :: to_ogg writes; the flag lives in the .import file
			(s as AudioStreamOggVorbis).loop = true
	_cache[key] = s
	return s


## Loads a stream by its full res:// path (the voice lines) and caches it under that path.
static func stream_path(path: String) -> AudioStream:
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path] as AudioStream
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AudioStream
	_cache[path] = s
	return s


## Drops the cached streams (called when the audio unit shuts down).
static func clear_cache() -> void:
	_cache.clear()


## True when `id` is one of the seamless loops.
static func is_looping(id: StringName) -> bool:
	return Tuning.LOOP_IDS.has(id)


## Every sfx id present in the project, sorted alphabetically.
static func sfx_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for f in ResourceLoader.list_directory(SFX_DIR):
		if f.ends_with(".ogg"):
			out.append(StringName(f.get_basename()))
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out
