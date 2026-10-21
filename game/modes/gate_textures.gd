class_name GateTextures
extends RefCounted
## The textures of a race gate: the LED sign panel, the hazard stripes of the plinths, the
## chevrons of the ground decal and the checker band of a start/finish line.
##
## The textures are generated once, offline, by `game/modes/tools/gen_gate_textures.py` and
## committed: the game never writes into `res://` (a packaged game has a read-only project
## folder) and the headless tests see the same art as the windowed run.

const DIR := "res://modes/textures/"
const BOARD := "gate_board_%s_%d_%d.png"
const GROUND := "gate_ground_chevrons.png"
const HAZARD := "gate_plinth_hazard.png"
const CHECKER := "gate_checker_band.png"

static var _cache: Dictionary = {}


## The LED sign panel of a gate: the text of the gate as a matrix of LEDs.
##
## kind: &"checkpoint", &"start", &"finish" or &"start_finish".
static func board_texture(kind: StringName, index: int, total: int) -> Texture2D:
	var key := "board_%s_%d_%d" % [kind, index, total]
	if _cache.has(key):
		return _cache[key] as Texture2D
	var path := DIR + (BOARD % [kind, index, total])
	var texture := _load(path)
	if texture == null:
		push_error("[modes] the sign panel of gate %d/%d is missing: %s" % [index + 1, total, path])
		return null
	_cache[key] = texture
	return texture


## The chevrons of the tarmac under a gate.
static func ground_texture() -> Texture2D:
	return _once("ground", GROUND)


## The hazard stripes of the plinth of a pylon.
static func hazard_texture() -> Texture2D:
	return _once("hazard", HAZARD)


## The black/white band of a start/finish line.
static func checker_texture() -> Texture2D:
	return _once("checker", CHECKER)


## Loads a texture of the directory once.
static func _once(key: String, file: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key] as Texture2D
	var path := DIR + file
	var texture := _load(path)
	if texture == null:
		push_error("[modes] the gate texture is missing: %s" % path)
		return null
	_cache[key] = texture
	return texture


## Loads a texture of the project (null when it is missing).
static func _load(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D
