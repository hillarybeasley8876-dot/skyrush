extends Node
## The looping beds of the player car: the road roll, the wind, the boost roar, the tyre
## squeal and the two scrape loops (the player and the nearest other car).
##
## Child of the AudioDirector. The beds are quiet until something happens: the road follows
## the speed, the squeal follows the slip, the scrape loop only runs during a contact (an
## idle loop is a bed of its own).

const SfxLibrary := preload("res://audio/sfx_library.gd")
const Tuning := preload("res://audio/audio_tuning.gd")

var _road: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _boost_roar: AudioStreamPlayer
var _squeal: AudioStreamPlayer
var _scrape: AudioStreamPlayer
var _scrape_3d: AudioStreamPlayer3D
## The level of the scrape loop of the player car (dB).
var _scrape_db := Tuning.SILENT_DB
var _scrape_3d_db := Tuning.SILENT_DB
var _scrape_fading := false
var _scrape_3d_fading := false
var _scrape_fade_step := 0.0
var _scrape_3d_fade_step := 0.0
## True while the game is paused (the players are stream-paused then).
var _paused := false


func _ready() -> void:
	_build()


## Creates the players (the beds loop, the scrape loop waits for a contact).
func _build() -> void:
	_road = _make_loop(&"road", SfxLibrary.stream(Tuning.ROAD_BED_ID), true)
	_wind = _make_loop(&"wind", SfxLibrary.stream(Tuning.WIND_BED_ID), true)
	_boost_roar = _make_loop(&"roar", SfxLibrary.stream(&"boost_roar_loop"), true)
	_squeal = _make_loop(&"squeal", SfxLibrary.stream(&"tyre_squeal"), true)
	# the scrape loop of the player car and the one of the nearest other car
	_scrape = _make_loop(&"scrape", SfxLibrary.stream(&"scrape_loop"), false)
	_scrape_3d = AudioStreamPlayer3D.new()
	_scrape_3d.name = "Scrape3D"
	_scrape_3d.bus = &"SFX"
	_scrape_3d.stream = SfxLibrary.stream(&"scrape_loop")
	_scrape_3d.volume_db = Tuning.SILENT_DB
	_scrape_3d.max_distance = Tuning.POOL_MAX_DISTANCE_M
	_scrape_3d.unit_size = Tuning.POOL_UNIT_SIZE
	_scrape_3d.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	add_child(_scrape_3d)


## A bed that loops from the start (the scrape loop is silent until a contact).
func _make_loop(node_name: StringName, stream: AudioStream, start: bool) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = &"SFX"
	player.stream = stream
	player.volume_db = Tuning.SILENT_DB
	add_child(player)
	if start:
		player.play()
	return player


# --- scrape --------------------------------------------------------------------------------------------
## The scrape loop of the player car (a sustained contact against a wall or a car).
func set_scrape(level_db: float, pitch: float) -> void:
	if _scrape == null:
		return
	_scrape.pitch_scale = pitch
	_scrape_db = level_db
	_scrape.volume_db = level_db
	_scrape_fading = false
	if not _scrape.playing:
		_scrape.play()
		if _paused:
			_scrape.stream_paused = true


## Lets the scrape loop of the player car fade out.
func release_scrape() -> void:
	if _scrape == null:
		return
	_scrape_fade_step = maxf(0.0, _scrape_db - Tuning.SILENT_DB) / Tuning.SCRAPE_FADE_S
	_scrape_fading = true


## The scrape loop of the nearest other car (a 3D one, it sits at the contact point).
func set_scrape_3d(position: Vector3, level_db: float, pitch: float) -> void:
	if _scrape_3d == null:
		return
	_scrape_3d.global_position = position
	_scrape_3d.pitch_scale = pitch
	_scrape_3d_db = level_db
	_scrape_3d.volume_db = level_db
	_scrape_3d_fading = false
	if not _scrape_3d.playing:
		_scrape_3d.play()
		if _paused:
			_scrape_3d.stream_paused = true


## Lets the scrape loop of the other car fade out.
func release_scrape_3d() -> void:
	if _scrape_3d == null:
		return
	_scrape_3d_fade_step = maxf(0.0, _scrape_3d_db - Tuning.SILENT_DB) / Tuning.SCRAPE_FADE_S
	_scrape_3d_fading = true


## True when the scrape loop of the player car is playing.
func scrape_playing() -> bool:
	return _scrape != null and _scrape.playing


## The level of the scrape loop of the player car (dB).
func scrape_level_db() -> float:
	return _scrape_db


# --- per frame -----------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	_update_scrape_fade(delta)


## Fades the scrape loops out when the contact is over.
func _update_scrape_fade(delta: float) -> void:
	if _scrape_fading and _scrape != null:
		_scrape_db = maxf(Tuning.SILENT_DB, _scrape_db - _scrape_fade_step * delta)
		_scrape.volume_db = _scrape_db
		if _scrape_db <= Tuning.SILENT_DB + Tuning.SCRAPE_FADE_EPSILON_DB:
			_scrape_db = Tuning.SILENT_DB
			_scrape.volume_db = Tuning.SILENT_DB
			_scrape_fading = false
	if _scrape_3d_fading and _scrape_3d != null:
		_scrape_3d_db = maxf(Tuning.SILENT_DB, _scrape_3d_db - _scrape_3d_fade_step * delta)
		_scrape_3d.volume_db = _scrape_3d_db
		if _scrape_3d_db <= Tuning.SILENT_DB + Tuning.SCRAPE_FADE_EPSILON_DB:
			_scrape_3d_db = Tuning.SILENT_DB
			_scrape_3d.volume_db = Tuning.SILENT_DB
			_scrape_3d_fading = false


## The beds follow the car: the road roll follows the speed, the wind follows the speed
## squared, the squeal follows the slip of the rear axle and the roar follows the nozzles.
func update(speed_kmh: float, rear_slip: float, rear_level: float, delta: float) -> void:
	var norm := clampf(speed_kmh / Tuning.SPEED_MAX_KMH, 0.0, 1.0)
	_road.volume_db = linear_to_db(maxf(norm, Tuning.ROAD_MIN_NORM)) + Tuning.ROAD_MIX_OFFSET_DB
	_road.pitch_scale = Tuning.ROAD_PITCH_MIN + Tuning.ROAD_PITCH_SPAN * norm
	_wind.volume_db = linear_to_db(maxf(norm * norm, Tuning.WIND_MIN_NORM)) + Tuning.WIND_MIX_OFFSET_DB
	_wind.pitch_scale = Tuning.WIND_PITCH_MIN + (Tuning.WIND_PITCH_MAX - Tuning.WIND_PITCH_MIN) * norm
	# the tyre squeal while the rear axle is sliding
	var slip := clampf(rear_slip, 0.0, 1.0)
	var squeal_db := Tuning.SILENT_DB
	if slip >= Tuning.SQUEAK_SLIP_MIN:
		squeal_db = linear_to_db(slip) + Tuning.SQUEAK_TRIM_DB
	_squeal.volume_db = lerpf(_squeal.volume_db, squeal_db, clampf(delta * Tuning.SQUEAK_FADE_RATE, 0.0, 1.0))
	_squeal.pitch_scale = Tuning.SQUEAK_PITCH_MIN + Tuning.SQUEAK_PITCH_SPAN * slip
	# the boost roar follows the rear nozzles, not the boost flag (the flag can stay on with no N2)
	var roar_db := Tuning.SILENT_DB
	if rear_level > Tuning.BOOST_ROAR_REAR_MIN:
		roar_db = Tuning.BOOST_ROAR_MIX_OFFSET_DB - Tuning.BOOST_ROAR_SPAN \
				+ Tuning.BOOST_ROAR_SPAN * clampf(rear_level, 0.0, 1.0)
	_boost_roar.volume_db = lerpf(_boost_roar.volume_db, roar_db,
			clampf(delta * Tuning.BOOST_ROAR_FADE_RATE, 0.0, 1.0))
	_boost_roar.pitch_scale = Tuning.BOOST_ROAR_PITCH_MIN \
			+ Tuning.BOOST_ROAR_PITCH_SPAN * clampf(speed_kmh / Tuning.SPEED_MAX_KMH, 0.0, 1.0)


## Falls silent (the car is gone).
func silence() -> void:
	for p in [_road, _wind, _boost_roar, _squeal]:
		if p != null:
			(p as AudioStreamPlayer).volume_db = Tuning.SILENT_DB


## Pauses or resumes the beds (the game pause).
func set_paused(paused: bool) -> void:
	_paused = paused
	_apply_pause()


## The flag is set again every frame while the game is paused: stopping a player clears it, and
## the scrape loop can stop while the game is paused.
func _apply_pause() -> void:
	for p in [_road, _wind, _boost_roar, _squeal, _scrape]:
		if p != null:
			(p as AudioStreamPlayer).stream_paused = _paused
	if _scrape_3d != null:
		_scrape_3d.stream_paused = _paused


## True when every playing bed is paused.
func gameplay_paused() -> bool:
	var players: Array[Node] = [_road, _wind, _boost_roar, _squeal, _scrape]
	for p in players:
		if p == null:
			continue
		# a player that is not playing is silent anyway
		if not (p as AudioStreamPlayer).playing:
			continue
		if not (p as AudioStreamPlayer).stream_paused:
			return false
	if _scrape_3d != null and _scrape_3d.playing and not _scrape_3d.stream_paused:
		return false
	return true


## Stops every bed (the scene is torn down).
func stop_all() -> void:
	for p in [_road, _wind, _boost_roar, _squeal, _scrape]:
		if p != null:
			(p as AudioStreamPlayer).stop()
	if _scrape_3d != null:
		_scrape_3d.stop()
