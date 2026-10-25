extends Node
## Pooled street lighting (ref/art/DOSSIER.md §3.4): a fixed set of real omni/spot lights that is
## re-assigned to the lamp positions nearest the camera every 0.25 s, plus a pool of light-pool
## decals that stand in for the lamps that are too far away to afford a real light.
## All real lights are shadowless and fade out at 60 m.
##
## The sources are kept in a spatial hash, so the re-assignment only looks at the lamps around
## the camera (3,678 sources cost 22.9 ms when the whole list was sorted every time).

## The defaults of the street pool; a second pool (the floods of the Bund and of the landmarks)
## overrides them before the node enters the tree.
const DEFAULT_MAX_OMNI := 32
const DEFAULT_MAX_SPOT := 12
const DEFAULT_MAX_DECALS := 48
const REASSIGN := 0.25
const DEFAULT_FADE_BEGIN := 60.0
const DEFAULT_FADE_LENGTH := 20.0
const DECAL_FADE_BEGIN := 200.0
const DECAL_FADE_LENGTH := 50.0
const DECAL_SIZE := Vector3(10.0, 6.0, 10.0)
## The size of the cells of the spatial hash.
const GRID_CELL := 64.0
## Only the sources this close to the camera are looked at.
const DEFAULT_SEARCH_RADIUS := 130.0
## Beyond this distance a lamp gets a decal instead of a real light.
const DEFAULT_DECAL_DISTANCE := 60.0
const DEFAULT_SPOT_ANGLE := 45.0

## The number of real lights of the pool.
var max_omni := DEFAULT_MAX_OMNI
var max_spot := DEFAULT_MAX_SPOT
var max_decals := DEFAULT_MAX_DECALS
## The distance at which the real lights start to fade.
var fade_begin := DEFAULT_FADE_BEGIN
var fade_length := DEFAULT_FADE_LENGTH
## Beyond this distance a source gets a decal instead of a real light.
var decal_distance := DEFAULT_DECAL_DISTANCE
## How far from the camera the sources are looked at.
var search_radius := DEFAULT_SEARCH_RADIUS

var _sources: Array[Dictionary] = []
var _grid: Dictionary = {}  # "x_z" -> Array[int] of source indices
var _omni: Array[OmniLight3D] = []
var _spot: Array[SpotLight3D] = []
var _decals: Array[Decal] = []
var _timer := 0.0
var _decal_texture: Texture2D
## The time the last re-assignment took (ms), for the performance test.
var last_reassign_ms := 0.0


func _ready() -> void:
	# The pool moves its nodes to new places now and then: no physics interpolation (a moved node
	# would slide there over a tick).
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_decal_texture = _make_radial_texture()
	for i in max_omni:
		var light := OmniLight3D.new()
		light.name = "Omni_%d" % i
		light.shadow_enabled = false
		light.light_energy = 0.0
		light.distance_fade_enabled = true
		light.distance_fade_begin = fade_begin
		light.distance_fade_length = fade_length
		light.distance_fade_shadow = fade_length
		light.omni_range = 18.0
		add_child(light)
		_omni.append(light)
	for i in max_spot:
		var spot := SpotLight3D.new()
		spot.name = "Spot_%d" % i
		spot.shadow_enabled = false
		spot.light_energy = 0.0
		spot.spot_range = 30.0
		spot.spot_angle = DEFAULT_SPOT_ANGLE
		spot.distance_fade_enabled = true
		spot.distance_fade_begin = fade_begin
		spot.distance_fade_length = fade_length
		add_child(spot)
		_spot.append(spot)
	for i in max_decals:
		_add_decal(i)


## Registers a light source. kind: "omni" or "spot". pitch is the elevation in degrees and yaw
## the compass bearing; `direction` (world space) overrides both for spots. `ground` is the
## point on the floor under the lamp (the light pools are drawn there).
func add_source(position: Vector3, color: Color, energy: float, light_range: float,
		kind: String = "omni", pitch: float = 0.0, yaw: float = 0.0,
		direction: Vector3 = Vector3.ZERO, ground: Vector3 = Vector3.INF,
		angle: float = DEFAULT_SPOT_ANGLE) -> int:
	var index := _sources.size()
	_sources.append({
		"position": position, "color": color, "energy": energy, "range": light_range,
		"kind": kind, "pitch": pitch, "yaw": yaw, "direction": direction,
		"ground": position if ground == Vector3.INF else ground, "angle": angle,
		"assigned": false, "off": false,
	})
	_insert(position, index)
	return index


## Switches a source off (the lamp was knocked down) or on again. The lights are given out again at once.
func set_source_enabled(index: int, enabled: bool) -> void:
	if index < 0 or index >= _sources.size():
		return
	_sources[index]["off"] = not enabled
	_timer = REASSIGN
func _process(delta: float) -> void:
	_timer += delta
	if _timer < REASSIGN:
		return
	_timer = 0.0
	_reassign()


func _reassign() -> void:
	var started := Time.get_ticks_usec()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var origin := camera.global_position
	var near := _gather(origin)
	near.sort_custom(func(a: int, b: int) -> bool:
		return origin.distance_squared_to(_sources[a]["position"]) \
			< origin.distance_squared_to(_sources[b]["position"]))
	var omni_index := 0
	var spot_index := 0
	var decal_index := 0
	for index in near:
		var source := _sources[index]
		source["assigned"] = false
		if bool(source.get("off", false)):
			continue
		var distance := origin.distance_to(source["position"])
		if distance <= decal_distance:
			var kind := String(source["kind"])
			if kind == "spot" and spot_index < _spot.size():
				_apply_spot(_spot[spot_index], source)
				spot_index += 1
				source["assigned"] = true
				continue
			if kind == "omni" and omni_index < _omni.size():
				_apply_omni(_omni[omni_index], source)
				omni_index += 1
				source["assigned"] = true
				continue
		if decal_index < _decals.size():
			_apply_decal(_decals[decal_index], source)
			decal_index += 1
			source["assigned"] = true
	for i in range(omni_index, _omni.size()):
		_omni[i].light_energy = 0.0
	for i in range(spot_index, _spot.size()):
		_spot[i].light_energy = 0.0
	for i in range(decal_index, _decals.size()):
		_decals[i].emission_energy = 0.0
	last_reassign_ms = float(Time.get_ticks_usec() - started) / 1000.0


## The sources around a point (the cells of the spatial hash).
func _gather(origin: Vector3) -> Array[int]:
	var out: Array[int] = []
	var span := maxi(int(ceil(search_radius / GRID_CELL)), 1)
	var cx := int(floor(origin.x / GRID_CELL))
	var cz := int(floor(origin.z / GRID_CELL))
	for dx in range(-span, span + 1):
		for dz in range(-span, span + 1):
			var key := "%d_%d" % [cx + dx, cz + dz]
			if not _grid.has(key):
				continue
			for index in _grid[key] as Array:
				if not out.has(index):
					out.append(index)
	return out


func _insert(position: Vector3, index: int) -> void:
	var key := "%d_%d" % [int(floor(position.x / GRID_CELL)), int(floor(position.z / GRID_CELL))]
	if not _grid.has(key):
		_grid[key] = []
	var list: Array = _grid[key]
	if not list.has(index):
		list.append(index)


func _apply_omni(light: OmniLight3D, source: Dictionary) -> void:
	light.global_position = source["position"]
	light.light_color = source["color"]
	light.light_energy = source["energy"]
	light.omni_range = source["range"]


func _apply_spot(light: SpotLight3D, source: Dictionary) -> void:
	light.global_position = source["position"]
	light.light_color = source["color"]
	light.light_energy = source["energy"]
	light.spot_range = source["range"]
	light.spot_angle = float(source.get("angle", DEFAULT_SPOT_ANGLE))
	var direction: Vector3 = source.get("direction", Vector3.ZERO)
	if direction.length_squared() < 0.0001:
		var pitch := deg_to_rad(float(source.get("pitch", 0.0)))
		var yaw := deg_to_rad(float(source.get("yaw", 0.0)))
		direction = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	direction = direction.normalized()
	light.look_at(light.global_position + direction,
		Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD)


## The light pool on the ground under a lamp that has no real light.
func _apply_decal(decal: Decal, source: Dictionary) -> void:
	decal.global_position = source["ground"]
	decal.modulate = source["color"]
	decal.emission_energy = 0.6


func _add_decal(index: int) -> void:
	var decal := Decal.new()
	decal.name = "LightPool_%d" % index
	decal.size = DECAL_SIZE
	decal.upper_fade = 0.3
	decal.lower_fade = 0.3
	decal.modulate = Color(1, 1, 1, 1)
	decal.texture_albedo = _decal_texture
	decal.texture_emission = _decal_texture
	decal.emission_energy = 0.0
	decal.distance_fade_enabled = true
	decal.distance_fade_begin = DECAL_FADE_BEGIN
	decal.distance_fade_length = DECAL_FADE_LENGTH
	decal.cull_mask = 1048575
	add_child(decal)
	_decals.append(decal)


static func _make_radial_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.set_color(1, Color(0, 0, 0, 0))
	gradient.add_point(0.42, Color(0.34, 0.34, 0.34, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	return tex
