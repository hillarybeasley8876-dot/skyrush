extends RefCounted
## The checks of the world emitters: the level of the sirens and the traffic hum, the fade in and
## out, the river bed and the siren alternation.
##
## These are the regression net of review round 3: the emitters used to sit at -30 dB (inaudible),
## the river bed was never created and the sirens of the second patrol car restarted every 0.5 s.

const Tuning := preload("res://audio/audio_tuning.gd")
const RiverWorld := preload("res://audio/tests/audio_test_river_world.gd")

## The callback that prints the result of a check.
var ok: Callable
## The node the test nodes are added to (the test itself).
var host: Node
## The player car (the emitters measure the distance to it).
var player: VehicleBase
## The emitters under test.
var emitters: Node


func run() -> void:
	await _setup()
	await _test_emitter_levels()
	await _test_emitter_fade()
	await _test_river()
	await _test_siren_switches()
	_teardown()


func _check(cond: bool, label: String) -> void:
	if ok.is_valid():
		ok.call(cond, label)


## The emitters under test and the player car.
func _setup() -> void:
	var emitters_script: GDScript = load("res://audio/world_emitters.gd")
	emitters = emitters_script.new()
	emitters.name = "Emitters"
	host.add_child(emitters)
	player = (load("res://core/stubs/stub_car.tscn") as PackedScene).instantiate() as VehicleBase
	host.add_child(player)
	player.freeze = true
	player.global_position = Vector3.ZERO
	Game.player = player
	emitters.set("heat", 4)


func _teardown() -> void:
	Game.player = null
	if player != null and is_instance_valid(player):
		player.free()
	player = null
	if emitters != null and is_instance_valid(emitters):
		emitters.call("stop_all")
		emitters.free()
	emitters = null


## A patrol car at the given distance. The sirens of the cars closer than
## POLICE_YELP_RANGE_M always play the yelp, so the level checks use a distant car.
func _police_car(distance: float) -> Node3D:
	var car := (load("res://core/stubs/stub_car.tscn") as PackedScene).instantiate() as VehicleBase
	host.add_child(car)
	car.freeze = true
	car.global_position = Vector3(distance, 0.0, 0.0)
	car.add_to_group(&"police")
	return car


## The voice of the first emitter of a kind (the test reads its level and its players).
func _voice_of(kind: StringName) -> Object:
	for e in emitters.get("_emitters"):
		var voice: Variant = e["voice"]
		if voice == null or not is_instance_valid(voice):
			continue
		if StringName(voice.get("id")) == kind:
			return voice
	return null


## The level of the voice (dB).
func _voice_level(voice: Object) -> float:
	if voice == null:
		return -120.0
	return float(voice.get("level"))


## The emitters have to be audible: the siren of a patrol car carries the mix trim and a big
## enough audio sphere (the old -30 dB trim made it inaudible under the player's car).
func _test_emitter_levels() -> void:
	var car := _police_car(60.0)
	emitters.call("_scan_world")
	var sirens := int(emitters.call("emitter_count_for", &"siren_wail"))
	_check(sirens == 1, "the patrol car carries a siren (%d)" % sirens)
	# the fade has to bring the siren up to its mix trim
	for i in 40:
		await host.get_tree().physics_frame
	var voice := _voice_of(&"siren_wail")
	var unit := 0.0
	if voice != null:
		var player_node: AudioStreamPlayer3D = voice.get("player")
		unit = player_node.unit_size
	_check(_voice_level(voice) >= Tuning.SIREN_EMITTER_DB - 0.5,
		"the siren reaches its mix level (%.1f dB, the trim is %.1f dB)" % [
			_voice_level(voice), Tuning.SIREN_EMITTER_DB])
	_check(absf(unit - Tuning.SIREN_UNIT_SIZE_M) <= 0.01,
		"the siren has the audio sphere of %.0f m (%.1f m)" % [Tuning.SIREN_UNIT_SIZE_M, unit])
	car.free()


## The fade of an emitter must be smooth: no step of more than 6 dB between two frames when it
## is attached or dropped.
func _test_emitter_fade() -> void:
	var car := _police_car(60.0)
	var handle: AudioStreamPlayer3D = emitters.call("attach_loop", &"siren_wail", car,
			Tuning.SIREN_EMITTER_DB, 1.0)
	_check(handle != null, "the emitter is attached")
	var previous := handle.volume_db
	var worst := 0.0
	for i in 40:
		await host.get_tree().physics_frame
		if i > 0:
			worst = maxf(worst, absf(handle.volume_db - previous))
		previous = handle.volume_db
	_check(worst <= 6.0, "the fade in of the emitter is smooth (%.1f dB per frame)" % worst)
	_check(handle.volume_db >= Tuning.SIREN_EMITTER_DB - 0.5,
		"the emitter is at its mix level after the fade (%.1f dB)" % handle.volume_db)
	# the drop: the emitter fades out before it is freed
	var voice := _voice_of(&"siren_wail")
	if voice != null:
		voice.call("fade_out")
		previous = handle.volume_db
		worst = 0.0
		for i in 40:
			await host.get_tree().physics_frame
			if not is_instance_valid(handle):
				break
			if i > 0:
				worst = maxf(worst, absf(handle.volume_db - previous))
			previous = handle.volume_db
		_check(worst <= 6.0, "the fade out of the emitter is smooth (%.1f dB per frame)" % worst)
	car.free()


## The river bed: a world that publishes a "river" point of interest gets a river emitter.
func _test_river() -> void:
	var world: Node = RiverWorld.new()
	host.add_child(world)
	world.call("set_pois", [{"kind": &"river", "position": Vector3(0.0, 0.0, 50.0), "label": "黄浦江"}])
	Game.world = world
	emitters.call("_scan_world")
	var rivers := int(emitters.call("emitter_count_for", &"river_ambience"))
	_check(rivers == 1, "the river 50 m away has a bed (%d emitters)" % rivers)
	var voice := _voice_of(&"river_ambience")
	_check(_voice_level(voice) > Tuning.SILENT_DB,
		"the river bed is audible (%.1f dB)" % _voice_level(voice))
	# the bed goes away when the player leaves the river
	player.global_position = Vector3(0.0, 0.0, 500.0)
	emitters.call("_scan_world")
	await host.get_tree().physics_frame
	_check(int(emitters.call("emitter_count_for", &"river_ambience")) <= 1,
		"the river bed fades out when the player leaves the river")
	player.global_position = Vector3.ZERO
	Game.world = null
	world.free()


## The sirens of the patrol cars alternate: every car has its own countdown, so no two cars
## switch in the same scan and every car switches four times in twelve seconds.
func _test_siren_switches() -> void:
	var cars: Array[Node3D] = []
	for d in [60.0, 80.0, 100.0]:
		cars.append(_police_car(d))
	emitters.call("_scan_world")
	_check(int(emitters.call("emitter_count_for", &"siren_wail")) == 3,
		"the three patrol cars carry a siren (%d)" % int(emitters.call("emitter_count_for", &"siren_wail")))
	var switches: Array[PackedInt32Array] = []
	var previous := PackedStringArray()
	for step in 24:
		emitters.call("_update_sirens")
		var states: PackedStringArray = emitters.call("siren_states")
		if previous.is_empty():
			previous = states
			for i in states.size():
				switches.append(PackedInt32Array())
			continue
		for i in mini(states.size(), previous.size()):
			if states[i] != previous[i]:
				switches[i].append(step)
		previous = states
	for i in switches.size():
		_check(switches[i].size() == 4,
			"the siren %d switches 4 times in 12 s (%d)" % [i, switches[i].size()])
	var clash := false
	for i in switches.size():
		for j in range(i + 1, switches.size()):
			for a in switches[i]:
				for b in switches[j]:
					if a == b:
						clash = true
	_check(not clash, "no two sirens switch in the same scan")
	for car in cars:
		if is_instance_valid(car):
			car.free()
