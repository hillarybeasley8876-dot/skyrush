extends RefCounted
## The gameplay checks of the audio unit (the event mapping, the collisions, the battery warning,
## the game pause and the world hooks). They need a running tree, so the entry point is
## game/audio/tests/test_audio.gd.

const Tuning := preload("res://audio/audio_tuning.gd")
const AudioDirectorScript := preload("res://audio/audio_director.gd")

## The callback that prints the result of a check.
var ok: Callable
## The node the test nodes are added to (the test itself).
var host: Node
## The director under test.
var director: Node
## The player's car.
var player: VehicleBase
## The one-shots that were played since the last reset.
var played: Array[StringName] = []


func run() -> void:
	await _setup()
	await _test_event_mapping()
	await _test_impacts()
	await _test_scrape_repeat()
	await _test_battery()
	await _test_pause()
	await _test_pause_leaks()
	await _test_hooks()
	await _test_laps_and_heat()
	await _test_crossfade()
	await _teardown()


func _check(cond: bool, label: String) -> void:
	if ok.is_valid():
		ok.call(cond, label)


## The director and a stub car as the player.
func _setup() -> void:
	director = (load("res://audio/audio_director.tscn") as PackedScene).instantiate()
	host.add_child(director)
	director.connect("sfx_played", func(id: StringName) -> void: played.append(id))
	player = (load("res://core/stubs/stub_car.tscn") as PackedScene).instantiate() as VehicleBase
	host.add_child(player)
	# the stub car is a physics body: it must not fall, the emitters measure the distance
	player.freeze = true
	player.global_position = Vector3.ZERO
	Game.player = player


func _teardown() -> void:
	if director != null:
		director.call("stop_all_sounds")
		director.free()
		director = null
	if player != null and is_instance_valid(player):
		player.free()
	player = null
	Game.player = null


## The event mapping: every event the brief lists has to produce a sound or a voice line.
func _test_event_mapping() -> void:
	played.clear()
	Events.boost_started.emit(player, &"nitro")
	Events.hop.emit(player, &"hop")
	Events.landed.emit(player, 1.2, 12.0, &"clean")
	Events.charge_started.emit(player, null)
	Events.charge_finished.emit(player, null, 1.0)
	Events.sky_lane_launch.emit(player, null)
	Events.n2_ring.emit(player, null)
	Events.race_countdown.emit(3)
	Events.race_countdown.emit(0)
	Events.stunt.emit(&"fly_over_gas", 800, "飞跃加油站!")
	Events.horn.emit(player)
	_check(played.size() >= 6, "the event mapping plays the one-shots (%d)" % played.size())
	_check(played.has(&"horn_traffic_double"), "horn plays the horn of the player's car")
	_check(played.has(&"boost_ignite"), "boost_started plays the boost ignition")
	_check(played.has(&"land_whoomp"), "landed plays the landing thump")
	_check(played.has(&"charge_zap"), "charge_started plays the zap")
	_check(played.has(&"countdown_beep"), "race_countdown plays the countdown beep")


## The collisions are rate limited: 120 contacts spread over a second of physics frames play
## one impact per cooldown (6 or 7), not one per contact.
func _test_impacts() -> void:
	played.clear()
	var other := (load("res://core/stubs/stub_car.tscn") as PackedScene).instantiate() as VehicleBase
	host.add_child(other)
	# one contact per physics frame for a second
	for i in 120:
		Events.vehicle_collided.emit(other, player, 8000.0, Vector3.ZERO, Vector3.UP)
		await host.get_tree().physics_frame
	var impacts := 0
	for id in played:
		if String(id).begins_with("impact"):
			impacts += 1
	_check(impacts >= 5 and impacts <= 8,
		"120 contacts over a second play 6 or 7 impacts (%d)" % impacts)
	# the player: the same contact rate
	played.clear()
	for i in 120:
		Events.vehicle_collided.emit(player, other, 8000.0, Vector3.ZERO, Vector3.UP)
		await host.get_tree().physics_frame
	impacts = 0
	for id in played:
		if String(id).begins_with("impact"):
			impacts += 1
	_check(impacts >= 5 and impacts <= 8,
		"120 contacts of the player over a second play 6 or 7 impacts (%d)" % impacts)
	other.free()


## A single hit is an impact, not a scrape: the scrape loop needs a repeated contact.
func _test_scrape_repeat() -> void:
	played.clear()
	var other := (load("res://core/stubs/stub_car.tscn") as PackedScene).instantiate() as VehicleBase
	host.add_child(other)
	# the scrape of the previous test has to be over before the single hit is measured
	await host.get_tree().create_timer(0.4).timeout
	# one single hit: no scrape
	Events.vehicle_collided.emit(player, other, 8000.0, Vector3.ZERO, Vector3.UP)
	await host.get_tree().process_frame
	_check(float(director.call("scrape_level_db")) <= Tuning.SILENT_DB + 1.0,
		"a single impact does not start the scrape (%.1f dB)" % float(director.call("scrape_level_db")))
	# a contact every physics frame for half a second: the scrape runs
	for i in 60:
		Events.vehicle_collided.emit(player, other, 8000.0, Vector3.ZERO, Vector3.UP)
		await host.get_tree().physics_frame
	_check(float(director.call("scrape_level_db")) > Tuning.SILENT_DB + 5.0,
		"a repeated contact starts the scrape loop (%.1f dB)" % float(director.call("scrape_level_db")))
	# the scrape fades out after the last contact
	await host.get_tree().create_timer(0.4).timeout
	_check(float(director.call("scrape_level_db")) <= Tuning.SILENT_DB + 1.0,
		"the scrape is silent 0.4 s after the last contact (%.1f dB)" % float(director.call("scrape_level_db")))
	other.free()


## The game pause must not leak: no one-shot is played and no emitter runs un-paused, but the
## ui sounds of the pause menu still play.
func _test_pause_leaks() -> void:
	var emitters: Node = director.get_node_or_null(^"WorldEmitters")
	var cop := (load("res://core/stubs/stub_car.tscn") as PackedScene).instantiate() as VehicleBase
	host.add_child(cop)
	cop.freeze = true
	cop.global_position = player.global_position + Vector3(30.0, 0.0, 0.0)
	cop.add_to_group(&"police")
	if emitters != null:
		emitters.set("heat", 4)
		emitters.call("_scan_world")
	player.telemetry.battery = 0.10
	Game.set_paused(true)
	played.clear()
	# the timer runs while the tree is paused (the last argument)
	await host.get_tree().create_timer(1.5, true, false, true).timeout
	var beeps := played.count(&"battery_low")
	_check(beeps == 0, "no battery beep during the pause (%d)" % beeps)
	var unpaused := 0
	if emitters != null:
		for e in emitters.get("_emitters"):
			var pv: AudioStreamPlayer3D = e["player"]
			print("   ", str(e["id"]), " mode=", pv.process_mode, " playing=", pv.playing,
				" paused=", pv.stream_paused)
			var p: Variant = e["player"]
			if is_instance_valid(p) and (p as AudioStreamPlayer3D).playing \
					and not (p as AudioStreamPlayer3D).stream_paused:
				unpaused += 1
	_check(unpaused == 0, "no emitter plays un-paused during the pause (%d)" % unpaused)
	# the ui sounds of the pause menu still play
	played.clear()
	director.call("play_sfx", &"ui_click")
	await host.get_tree().process_frame
	_check(played.has(&"ui_click"), "the ui sound of the pause menu still plays")
	Game.set_paused(false)
	await host.get_tree().process_frame
	player.telemetry.battery = 1.0
	if is_instance_valid(cop):
		cop.free()


## The last lap is announced when the player has finished total - 1 laps (the finish line is a
## different line), and the pursuit line is only for a rising heat.
func _test_laps_and_heat() -> void:
	var queue: Node = director.get_node_or_null(^"VoiceQueue")
	director.call("set_total_laps", 2)
	# the finish line of a two lap race is not the last lap
	_clear_voice_throttle(queue)
	director.call("stop_all_sounds")
	Events.lap_completed.emit(player, 2, 61.0)
	await host.get_tree().process_frame
	_check(String(director.get("last_voice_id")) != "final_lap",
		"the finish line of a two lap race is not announced as the last lap")
	# the last lap is announced
	_clear_voice_throttle(queue)
	director.call("stop_all_sounds")
	Events.lap_completed.emit(player, 1, 60.0)
	await host.get_tree().process_frame
	_check(String(director.get("last_voice_id")) == "final_lap",
		"the last lap of a two lap race is announced")
	# the heat that goes down is not announced
	_clear_voice_throttle(queue)
	director.call("stop_all_sounds")
	Events.heat_changed.emit(4)
	await host.get_tree().process_frame
	_clear_voice_throttle(queue)
	director.call("stop_all_sounds")
	Events.heat_changed.emit(3)
	await host.get_tree().process_frame
	_check(String(director.get("last_voice_id")) != "heat_up",
		"a falling heat is not announced")
	# the heat that rises is
	_clear_voice_throttle(queue)
	director.call("stop_all_sounds")
	Events.heat_changed.emit(4)
	await host.get_tree().process_frame
	_check(String(director.get("last_voice_id")) == "heat_up",
		"a rising heat is announced")
	Events.heat_changed.emit(0)


## The voice queue throttles the repeating lines; the test clears it, so the check measures the
## decision of the mapper and not the throttle.
func _clear_voice_throttle(queue: Node) -> void:
	if queue == null:
		return
	var last: Variant = queue.get("_last_played")
	if last is Dictionary:
		(last as Dictionary).clear()


## The battery warning is edge triggered and then repeats every few seconds.
func _test_battery() -> void:
	played.clear()
	player.telemetry.battery = 0.10
	await host.get_tree().create_timer(1.0).timeout
	var beeps := 0
	for id in played:
		if id == &"battery_low":
			beeps += 1
	_check(beeps == 1, "a low battery beeps once in the first second (%d)" % beeps)
	await host.get_tree().create_timer(3.6).timeout
	beeps = 0
	for id in played:
		if id == &"battery_low":
			beeps += 1
	_check(beeps == 2, "a low battery beeps every 4 s (%d in 4.6 s)" % beeps)
	# the warning re-arms when the battery is charged again
	player.telemetry.battery = 0.5
	await host.get_tree().create_timer(0.2).timeout
	played.clear()
	player.telemetry.battery = 0.10
	await host.get_tree().create_timer(0.5).timeout
	beeps = 0
	for id in played:
		if id == &"battery_low":
			beeps += 1
	_check(beeps == 1, "the battery warning re-arms after a charge (%d)" % beeps)
	player.telemetry.battery = 1.0


## The game pause silences the gameplay sounds and puts the bed into the menu state.
func _test_pause() -> void:
	Game.set_paused(true)
	# the timer runs while the tree is paused (the last argument)
	await host.get_tree().create_timer(0.8, true, false, true).timeout
	_check(bool(director.call("gameplay_paused")), "the gameplay players are paused")
	_check(float(director.call("bed_cutoff_hz")) <= Tuning.MENU_LOWPASS_HZ * 2.0,
		"the music bed is filtered while the game is paused (%.0f Hz)" % float(director.call("bed_cutoff_hz")))
	Game.set_paused(false)
	await host.get_tree().process_frame
	_check(not bool(director.call("gameplay_paused")), "the gameplay players run again after the pause")


## The music crossfade must not dip by more than 3 dB.
func _test_crossfade() -> void:
	var bed: Node = director.get_node_or_null(^"MusicBed")
	if bed == null:
		_check(false, "the music bed exists")
		return
	bed.call("set_state", &"cruise")
	await host.get_tree().process_frame
	var before := float(bed.call("bed_gain"))
	bed.call("set_state", &"pursuit")
	var minimum := before
	for i in 120:
		await host.get_tree().process_frame
		minimum = minf(minimum, float(bed.call("bed_gain")))
	var dip := 20.0 * log(maxf(minimum, 1e-6) / maxf(before, 1e-6)) / log(10.0)
	_check(dip <= 3.0, "the music crossfade does not dip by more than 3 dB (%.1f dB)" % dip)


## The world hooks: the heat, the sirens, the traffic hum and the horn.
func _test_hooks() -> void:
	var emitters: Node = director.get_node_or_null(^"WorldEmitters")
	_check(emitters != null, "the director owns the world emitters")
	if emitters == null:
		return
	# two police cars and one traffic car
	var police: Array[VehicleBase] = []
	for i in 2:
		var car := (load("res://core/stubs/stub_car.tscn") as PackedScene).instantiate() as VehicleBase
		host.add_child(car)
		car.freeze = true
		car.global_position = player.global_position
		car.add_to_group(&"police")
		police.append(car)
	var traffic: RigidBody3D = load("res://audio/tests/audio_test_horn_car.gd").new()
	host.add_child(traffic)
	traffic.global_position = player.global_position
	# heat 0: no siren at all
	emitters.heat = 0
	emitters.call("_scan_world")
	_check(int(emitters.call("emitter_count_for", &"siren_wail")) == 0,
		"no siren at heat 0 (%d sirens)" % int(emitters.call("emitter_count_for", &"siren_wail")))
	# heat 2: the wail on both patrol cars
	emitters.heat = 2
	emitters.call("_scan_world")
	_check(int(emitters.call("emitter_count")) == 3,
		"the sirens and the traffic hum are placed (%d emitters)" % int(emitters.call("emitter_count")))
	var sirens := int(emitters.call("emitter_count_for", &"siren_wail"))
	_check(sirens == 2, "both patrol cars carry a siren (%d)" % sirens)
	_check(int(emitters.call("emitter_count_for", &"traffic_ev_hum")) == 1,
		"the traffic car carries the hum (%d)" % int(emitters.call("emitter_count_for", &"traffic_ev_hum")))
	# heat 4: the wail and the yelp alternate
	emitters.heat = 4
	var switched := 0
	for i in 40:
		emitters.call("_update_sirens")
		await host.get_tree().physics_frame
		switched = int(emitters.call("yelp_count"))
		if switched > 0:
			break
	_check(switched >= 1, "the sirens switch to the yelp at a high heat (%d)" % switched)
	# the traffic hum follows the speed of the car
	var hum: AudioStreamPlayer3D = null
	for child in emitters.get_children():
		if child is AudioStreamPlayer3D and (child as AudioStreamPlayer3D).stream != null:
			if (child as AudioStreamPlayer3D).stream.resource_path.ends_with("traffic_ev_hum.ogg"):
				hum = child as AudioStreamPlayer3D
	var telemetry: CarTelemetry = traffic.get("telemetry")
	telemetry.speed_kmh = 0.0
	emitters.call("_physics_process", 0.016)
	var slow := hum.pitch_scale if hum != null else 0.0
	telemetry.speed_kmh = 200.0
	emitters.call("_physics_process", 0.016)
	var fast := hum.pitch_scale if hum != null else 0.0
	_check(fast > slow, "the traffic hum follows the speed of the car (%.2f -> %.2f)" % [slow, fast])
	# the traffic horn
	played.clear()
	traffic.call("horn")
	_check(played.has(&"horn_traffic"), "the traffic horn is played (%s)" % str(played))
	for car in police:
		if is_instance_valid(car):
			car.free()
	if is_instance_valid(traffic):
		traffic.free()
