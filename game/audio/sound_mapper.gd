extends "res://audio/event_mapper.gd"
## Maps the vehicle events of the core event bus to sounds. Child of the AudioDirector.
##
## The race and pursuit events are mapped by race_mapper.gd. The voice lines go through the
## priority queue, so a line is never cut off and repeating lines are throttled.

## stunt kind -> voice line id
const STUNT_VOICES: Dictionary = {
	&"fly_over_gas": &"fly_gas_station",
	&"fly_over_toll": &"fly_toll",
	&"fly_over_traffic": &"fly_traffic",
	&"fly_over_barrier": &"fly_barrier",
	&"drift": &"drift_start",
	&"drift_chain": &"drift_chain",
	&"barrel_roll": &"barrel_roll",
	&"airtime": &"airtime",
	&"near_miss": &"near_miss",
	&"takedown": &"takedown",
	&"speed": &"speed_record",
}

## boost kind -> voice line id
const BOOST_VOICES: Dictionary = {
	&"nitro": &"boost_nitro",
	&"mini": &"mini_boost",
	&"air_mini": &"mini_boost",
	&"landing": &"mini_boost",
	&"launch": &"launch_perfect",
	&"charge": &"charge_done",
}

## Impulse (N.s) above which a collision also breaks glass.
const GLASS_IMPULSE := 9000.0

var _last_n2_tier := 0
## True once the N2 tier has been read from the telemetry.
var _n2_initialised := false
## The last impact of every vehicle (its instance id) — the cooldown per car.
var _impact_times: Dictionary = {}
## The last contact of every vehicle — the scrape needs a repeated contact.
var _contact_times: Dictionary = {}
## The instance id of the car the player is currently scraping against (0 = none).
var _scrape_vehicle := 0
## The instance id of the other car that is scraping (0 = none).
var _scrape_3d_id := 0
## The seconds since the last contact of the scrape.
var _scrape_age := 0.0
## The seconds since the last contact of the other car's scrape.
var _scrape_3d_age := 0.0
## The distance of the other car's contact point to the player.
var _scrape_3d_dist := 0.0
## The strongest impulse of the current contact (the scrape level follows it).
var _scrape_impulse := 0.0
## The strongest impulse of the other car's contact.
var _scrape_3d_impulse := 0.0
## The battery warning is edge triggered.
var _battery_low := false
var _battery_beep_timer := 0.0
## The game clock of the mapper (s). The cooldowns follow it and not the wall clock, so they
## behave the same in a fast test run and they stop while the game is paused.
var _clock := 0.0


func _connect_all() -> void:
	Events.vehicle_collided.connect(_on_vehicle_collided)
	Events.vehicle_wrecked.connect(_on_vehicle_wrecked)
	Events.boost_started.connect(_on_boost_started)
	Events.drift_started.connect(_on_drift_started)
	Events.drift_ended.connect(_on_drift_ended)
	Events.hop.connect(_on_hop)
	Events.landed.connect(_on_landed)
	Events.barrel_roll.connect(_on_barrel_roll)
	Events.near_miss.connect(_on_near_miss)
	Events.stunt.connect(_on_stunt)
	Events.sky_lane_launch.connect(_on_sky_lane_launch)
	Events.flight_changed.connect(_on_flight_changed)
	Events.n2_ring.connect(_on_n2_ring)
	Events.charge_started.connect(_on_charge_started)
	Events.charge_finished.connect(_on_charge_finished)
	Events.takedown.connect(_on_takedown)


# --- vehicle -------------------------------------------------------------------------------------------
func _on_vehicle_collided(vehicle: VehicleBase, _other: Node3D, impulse: float, point: Vector3, _normal: Vector3) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	# a light touch is not a hit
	if impulse < Tuning.IMPACT_MIN_IMPULSE_NS:
		return
	var is_player := _is_player(vehicle)
	# the traffic cars report a contact on every physics tick, so the impacts are rate limited
	if not _impact_allowed(vehicle.get_instance_id()):
		if _contact_repeated(vehicle.get_instance_id()):
			_scrape_contact(vehicle, impulse, point, is_player)
		return
	var severity := &"impact_light"
	if impulse > Tuning.IMPULSE_HEAVY:
		severity = &"impact_heavy"
	elif impulse > Tuning.IMPULSE_MEDIUM:
		severity = &"impact_medium"
	var level := clampf(impulse / Tuning.IMPULSE_SCALE, 0.0, 1.0) * Tuning.IMPULSE_LEVEL_DB
	if is_player:
		_sfx(severity, Tuning.IMPACT_MIX_DB + level)
	else:
		_sfx_3d(severity, point, Tuning.IMPACT_MIX_DB + level)
	if impulse > GLASS_IMPULSE:
		_sfx_3d(&"glass_break", point, Tuning.GLASS_MIX_DB)
	# the scrape loop needs a repeated contact: a single hit is an impact, not a scrape
	if _contact_repeated(vehicle.get_instance_id()):
		_scrape_contact(vehicle, impulse, point, is_player)


## True when this vehicle may play an impact again (one impact per cooldown).
func _impact_allowed(vehicle_id: int) -> bool:
	var now := _clock
	var last := float(_impact_times.get(vehicle_id, Tuning.VOICE_NO_PREVIOUS))
	if now - last < Tuning.IMPACT_COOLDOWN_S:
		return false
	_impact_times[vehicle_id] = now
	return true


## True when the same car hit again within the repeat window (a single hit is not a scrape).
func _contact_repeated(vehicle_id: int) -> bool:
	var now := _clock
	var last := float(_contact_times.get(vehicle_id, Tuning.VOICE_NO_PREVIOUS))
	_contact_times[vehicle_id] = now
	return now - last <= Tuning.SCRAPE_REPEAT_S


## A sustained contact becomes a scrape loop (the player only, the nearest other car).
func _scrape_contact(vehicle: VehicleBase, impulse: float, point: Vector3, is_player: bool) -> void:
	if _audio == null:
		return
	if is_player:
		_scrape_vehicle = vehicle.get_instance_id()
		_scrape_age = 0.0
		_scrape_impulse = maxf(_scrape_impulse, impulse)
		_audio.set_scrape(_scrape_level(_scrape_impulse, Tuning.SCRAPE_PLAYER_DB), _scrape_pitch(vehicle))
		return
	var vehicle_id := vehicle.get_instance_id()
	if _scrape_3d_id == vehicle_id:
		# the same car keeps scraping: the loop follows it
		_scrape_3d_age = 0.0
		_scrape_3d_impulse = maxf(_scrape_3d_impulse, impulse)
		_audio.set_scrape_3d(point, _scrape_level(_scrape_3d_impulse, Tuning.SCRAPE_MAX_DB),
				_scrape_pitch(vehicle))
		return
	var distance := _distance_to_player(point)
	if _scrape_3d_id != 0 and distance >= _scrape_3d_dist:
		# another car is already scraping and it is the nearer one
		return
	_scrape_3d_id = vehicle_id
	_scrape_3d_age = 0.0
	_scrape_3d_dist = distance
	_scrape_3d_impulse = impulse
	_audio.set_scrape_3d(point, _scrape_level(impulse, Tuning.SCRAPE_MAX_DB), _scrape_pitch(vehicle))


## The distance of a point to the player car.
func _distance_to_player(point: Vector3) -> float:
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return Tuning.EMITTER_FAR_DISTANCE_M
	return player.global_position.distance_to(point)


## The level of the scrape loop (dB), it follows the impulse of the contact.
func _scrape_level(impulse: float, base_db: float) -> float:
	return base_db + linear_to_db(clampf(impulse / Tuning.IMPULSE_SCALE, Tuning.SCRAPE_MIN_NORM, 1.0))


## The pitch of the scrape loop, it follows the speed of the car.
func _scrape_pitch(vehicle: VehicleBase) -> float:
	var speed := 0.0
	if vehicle != null and is_instance_valid(vehicle):
		speed = absf(vehicle.telemetry.speed_kmh)
	var norm := clampf(speed / Tuning.SPEED_MAX_KMH, 0.0, 1.0)
	return Tuning.SCRAPE_PITCH_MIN + Tuning.SCRAPE_PITCH_SPAN * norm


func _on_vehicle_wrecked(vehicle: VehicleBase, _source: Node3D) -> void:
	if vehicle == null or not is_instance_valid(vehicle):
		return
	if _is_player(vehicle):
		_sfx(&"impact_heavy", 0.0)
		_voice(&"crashed", Tuning.VOICE_PRIORITY_NEVER_CUT)
	else:
		_sfx_3d(&"impact_heavy", vehicle.global_position, 0.0)


func _on_boost_started(vehicle: VehicleBase, kind: StringName) -> void:
	if not _is_player(vehicle):
		return
	if kind == &"nitro":
		_sfx(&"boost_ignite", Tuning.BOOST_IGNITE_MIX_DB)
	else:
		_sfx(&"mini_pssh", Tuning.MINI_BOOST_MIX_DB)
	_voice(BOOST_VOICES.get(kind, &""))


func _on_drift_started(vehicle: VehicleBase, _direction: int) -> void:
	if _is_player(vehicle):
		_voice(&"drift_start", Tuning.VOICE_PRIORITY_DROP)


func _on_drift_ended(vehicle: VehicleBase, duration: float, clean: bool, _n2_gained: float) -> void:
	if _is_player(vehicle) and clean and duration > Tuning.DRIFT_CLEAN_MIN_S:
		_voice(&"drift_perfect", Tuning.VOICE_PRIORITY_QUEUED)


func _on_hop(vehicle: VehicleBase, kind: StringName) -> void:
	if not _is_player(vehicle):
		return
	_sfx(&"hop_release", Tuning.HOP_RELEASE_MIX_DB, Tuning.HOP_RELEASE_PITCH)
	_voice(&"big_hop" if kind == &"big_hop" else &"hop", Tuning.VOICE_PRIORITY_DROP)


func _on_landed(vehicle: VehicleBase, _airtime: float, impact_speed: float, quality: StringName) -> void:
	if not _is_player(vehicle):
		return
	var level := clampf(impact_speed / Tuning.LAND_LEVEL_SCALE, 0.0, 1.0)
	_sfx(&"land_whoomp", Tuning.LAND_MIX_DB - Tuning.LAND_MIX_DB * level,
		Tuning.LAND_PITCH_MIN + Tuning.LAND_PITCH_SPAN * level)
	if quality == &"clean":
		_voice(&"landing_perfect", Tuning.VOICE_PRIORITY_QUEUED)


func _on_barrel_roll(vehicle: VehicleBase, _direction: int) -> void:
	if _is_player(vehicle):
		_voice(&"barrel_roll", Tuning.VOICE_PRIORITY_QUEUED)


func _on_near_miss(vehicle: VehicleBase, other: VehicleBase) -> void:
	if other == null or not is_instance_valid(other):
		return
	_sfx_3d(&"near_miss_whoosh", other.global_position, Tuning.NEAR_MISS_MIX_DB)
	if _is_player(vehicle):
		_voice(&"near_miss", Tuning.VOICE_PRIORITY_DROP)


func _on_stunt(kind: StringName, _points: int, _label: String) -> void:
	_voice(STUNT_VOICES.get(kind, &""), Tuning.VOICE_PRIORITY_QUEUED)


func _on_sky_lane_launch(vehicle: VehicleBase, _lane: SkyLane) -> void:
	if not _is_player(vehicle):
		return
	_sfx(&"boost_ignite", Tuning.SKY_LANE_MIX_DB, Tuning.SKY_LANE_PITCH)
	_voice(&"sky_lane_open", Tuning.VOICE_PRIORITY_QUEUED)


func _on_flight_changed(vehicle: VehicleBase, active: bool, _lane: SkyLane) -> void:
	if not _is_player(vehicle) or active:
		return
	# the cold-gas puff when the car leaves the sky lane
	_sfx(&"hop_release", Tuning.HOP_EXIT_MIX_DB, Tuning.HOP_EXIT_PITCH)


func _on_n2_ring(vehicle: VehicleBase, _lane: SkyLane) -> void:
	if _is_player(vehicle):
		_sfx(&"charge_chime", Tuning.RING_CHIME_MIX_DB, Tuning.RING_CHIME_PITCH)


func _on_charge_started(vehicle: VehicleBase, _station: Area3D) -> void:
	if _is_player(vehicle):
		_sfx(&"charge_zap", Tuning.CHARGE_ZAP_MIX_DB)


func _on_charge_finished(vehicle: VehicleBase, _station: Area3D, amount: float) -> void:
	if not _is_player(vehicle):
		return
	if amount > Tuning.CHARGE_FULL_AMOUNT:
		_sfx(&"charge_chime", Tuning.CHARGE_CHIME_MIX_DB)
	_voice(&"charge_done", Tuning.VOICE_PRIORITY_QUEUED)


func _on_takedown(victim: VehicleBase, _kind: StringName) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	_sfx_3d(&"impact_heavy", victim.global_position, Tuning.TAKEDOWN_MIX_DB)
	_voice(&"takedown", Tuning.VOICE_PRIORITY_QUEUED)


# --- per frame -----------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	_clock += delta
	_watch_n2()
	_watch_battery(delta)
	_watch_scrape(delta)


## "氮气就绪" when the N2 crosses a full slot (100 or 200).
func _watch_n2() -> void:
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	var tier := int(player.telemetry.n2 / Tuning.N2_TIER_AMOUNT)
	if not _n2_initialised:
		# the tier is read from the telemetry, so a car that spawns with a full tank
		# does not announce itself
		_n2_initialised = true
		_last_n2_tier = tier
		return
	if tier > _last_n2_tier:
		_voice(&"boost_ready", Tuning.VOICE_PRIORITY_QUEUED)
		_sfx(&"charge_chime", Tuning.BOOST_READY_MIX_DB, Tuning.BOOST_READY_PITCH)
	_last_n2_tier = tier


## The battery warning: edge triggered, then a beep every few seconds.
func _watch_battery(delta: float) -> void:
	var player := Game.player
	if player == null or not is_instance_valid(player):
		return
	var battery := player.telemetry.battery
	if not _battery_low:
		if battery <= Tuning.BATTERY_LOW_ON:
			_battery_low = true
			_battery_beep_timer = 0.0
			_battery_beep()
		return
	if battery >= Tuning.BATTERY_LOW_OFF:
		_battery_low = false
		return
	_battery_beep_timer += delta
	if _battery_beep_timer >= Tuning.BATTERY_BEEP_INTERVAL_S:
		_battery_beep_timer = 0.0
		_battery_beep()


## The battery beep (the voice line is throttled by the voice queue).
func _battery_beep() -> void:
	_voice(&"battery_low", Tuning.VOICE_PRIORITY_DROP)
	_sfx(&"battery_low", Tuning.BATTERY_BEEP_MIX_DB)


## The scrape loop fades out when the contact is over.
func _watch_scrape(delta: float) -> void:
	if _scrape_vehicle != 0:
		_scrape_age += delta
		if _scrape_age >= Tuning.SCRAPE_FADE_S:
			_scrape_vehicle = 0
			_scrape_impulse = 0.0
			if _audio != null:
				_audio.release_scrape()
	if _scrape_3d_id != 0:
		_scrape_3d_age += delta
		if _scrape_3d_age >= Tuning.SCRAPE_FADE_S:
			_scrape_3d_id = 0
			_scrape_3d_impulse = 0.0
			_scrape_3d_dist = 0.0
			if _audio != null:
				_audio.release_scrape_3d()
