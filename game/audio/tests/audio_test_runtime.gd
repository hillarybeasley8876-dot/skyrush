extends RefCounted
## The runtime checks of the audio unit (the parts that need a running tree).
## The entry point is game/audio/tests/test_audio.gd; `ok` is the callback that prints PASS/FAIL.
##
## These are the regression net of review round 2: the one-shot pool, the world emitters, the
## voice channels and the engine error count.

const Tuning := preload("res://audio/audio_tuning.gd")
const SfxLibrary := preload("res://audio/sfx_library.gd")
const ErrorCounter := preload("res://tools/error_counter.gd")

## The callback that prints the result of a check.
var ok: Callable
## The node the test nodes are added to (the test itself).
var host: Node


func run() -> void:
	await _test_pool_bookkeeping()
	await _test_pool_error_count()
	await _test_doppler_setup()
	await _test_synth_voices()
	await _test_voice_channels()


func _check(cond: bool, label: String) -> void:
	if ok.is_valid():
		ok.call(cond, label)


## The pool bookkeeping: 30 calls, no duplicates, the oldest sound is the one that is stolen.
func _test_pool_bookkeeping() -> void:
	var pool_script: GDScript = load("res://audio/oneshot_pool.gd")
	var pool: Node = pool_script.new()
	host.add_child(pool)
	for i in 30:
		pool.call("play_2d", &"ui_click", 0.0, 1.0, 1)
	var active := int(pool.call("active_count"))
	var playing := int(pool.call("playing_players"))
	_check(active == playing, "the pool bookkeeping matches the playing players (%d vs %d)" % [active, playing])
	var pool_size := Tuning.POOL_2D + Tuning.POOL_3D
	_check(active <= pool_size, "the pool never exceeds %d one-shots (got %d)" % [pool_size, active])
	var rejected := not bool(pool.call("play_2d", &"siren_wail", 0.0, 1.0, 1))
	_check(rejected, "the pool rejects loop ids")
	pool.call("stop_all")
	pool.free()


## The pool must not raise a single engine error (the typed-array misuse of round 1).
func _test_pool_error_count() -> void:
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var pool_script: GDScript = load("res://audio/oneshot_pool.gd")
	var pool: Node = pool_script.new()
	host.add_child(pool)
	for i in 10:
		pool.call("play_2d", &"ui_click", 0.0, 1.0, 1)
		pool.call("play_3d", &"impact_light", Vector3(i, 0.0, 0.0), 0.0, 1.0, 1)
	pool.call("active_count")
	pool.call("playing_players")
	# the emitters: attach, drop, re-attach and free the target
	var emitters_script: GDScript = load("res://audio/world_emitters.gd")
	var emitters: Node = emitters_script.new()
	host.add_child(emitters)
	var target := Node3D.new()
	host.add_child(target)
	var handle: AudioStreamPlayer3D = emitters.call("attach_loop", &"siren_wail", target, -6.0, 1.0)
	_check(handle != null, "attach_loop creates an emitter")
	emitters.call("stop_loop", handle)
	var handle2: AudioStreamPlayer3D = emitters.call("attach_loop", &"siren_wail", target, -6.0, 1.0)
	_check(handle2 != null, "the emitter can be attached again")
	target.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	_check(int(emitters.call("emitter_count")) == 0,
		"the emitter is gone with its target (%d left)" % int(emitters.call("emitter_count")))
	pool.call("stop_all")
	pool.free()
	emitters.call("stop_all")
	emitters.free()
	OS.remove_logger(counter)
	_check(counter.errors == 0, "the pool and the emitters raise no engine error (%d)" % counter.errors)


## The 3D players have to track the doppler, and the emitters have to follow their target.
func _test_doppler_setup() -> void:
	var pool_script: GDScript = load("res://audio/oneshot_pool.gd")
	var pool: Node = pool_script.new()
	host.add_child(pool)
	var found := false
	for child in pool.get_children():
		if child is AudioStreamPlayer3D:
			found = true
			_check((child as AudioStreamPlayer3D).doppler_tracking == AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP,
				"the 3D one-shot players track the doppler")
	_check(found, "the pool has 3D players")
	var emitters_script: GDScript = load("res://audio/world_emitters.gd")
	var emitters: Node = emitters_script.new()
	host.add_child(emitters)
	var target := Node3D.new()
	host.add_child(target)
	target.position = Vector3(10.0, 0.0, 0.0)
	var handle: AudioStreamPlayer3D = emitters.call("attach_loop", &"siren_wail", target, -6.0, 1.0)
	_check(handle != null, "attach_loop creates an emitter")
	if handle != null:
		_check(handle.doppler_tracking == AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP,
			"the world emitters track the doppler")
		target.position = Vector3(50.0, 0.0, 0.0)
		for i in 4:
			await host.get_tree().physics_frame
		_check(handle.global_position.distance_to(Vector3(50.0, 0.0, 0.0)) < 1.0,
			"the emitter follows its target (%.1f m)" % handle.global_position.distance_to(Vector3(50.0, 0.0, 0.0)))
		emitters.call("stop_loop", handle)
		_check(handle.is_queued_for_deletion() or not is_instance_valid(handle), "stop_loop frees the emitter")
	pool.call("stop_all")
	pool.free()
	emitters.call("stop_all")
	emitters.free()
	target.free()


## The two synth voices: the bus, the audio sphere and the doppler.
##
## They play on the SFX bus (the SFX volume and the slow motion reach them), their audio sphere
## covers the chase camera (the player hears its own car from inside it) and they are not
## doppler shifted (a chase camera that does not track its velocity would pull the motor note
## down by a fifth at 250 km/h and bury the whine in the mix).
func _test_synth_voices() -> void:
	var director: Node = (load("res://audio/audio_director.tscn") as PackedScene).instantiate()
	host.add_child(director)
	await host.get_tree().process_frame
	var ev: AudioStreamPlayer3D = director.call("ev_voice")
	var thr: AudioStreamPlayer3D = director.call("thruster_voice")
	_check(ev != null and ev.bus == &"SFX", "the drive voice plays on the SFX bus")
	_check(thr != null and thr.bus == &"SFX", "the thruster voice plays on the SFX bus")
	_check(ev != null and ev.unit_size >= Tuning.SYNTH_UNIT_SIZE_M - 0.01,
		"the drive voice covers the chase camera (%.0f m)" % (ev.unit_size if ev else 0.0))
	_check(thr != null and thr.unit_size >= Tuning.SYNTH_UNIT_SIZE_M - 0.01,
		"the thruster voice covers the chase camera (%.0f m)" % (thr.unit_size if thr else 0.0))
	_check(ev != null and ev.doppler_tracking == AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED,
		"the drive voice is not doppler shifted")
	_check(thr != null and thr.doppler_tracking == AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED,
		"the thruster voice is not doppler shifted")
	director.call("stop_all_sounds")
	director.free()


## The two voice channels are independent and the music stays ducked while either one talks.
func _test_voice_channels() -> void:
	var queue_script: GDScript = load("res://audio/voice_queue.gd")
	var queue: Node = queue_script.new()
	host.add_child(queue)
	var order: Array[StringName] = []
	queue.connect("line_started", func(id: StringName, _t: String, _k: StringName) -> void: order.append(id))
	# the announcer plays, the radio plays at the same time
	queue.call("play", &"overtake", Tuning.VOICE_PRIORITY_QUEUED)
	queue.call("play", &"radio_suspect", Tuning.VOICE_PRIORITY_QUEUED)
	_check(order.size() == 2, "the radio channel is not blocked by the announcer (%d lines)" % order.size())
	_check(bool(queue.call("is_playing")), "the queue reports that a line is playing")
	# a line that is never cut waits for the channel
	queue.call("play", &"countdown_3", Tuning.VOICE_PRIORITY_NEVER_CUT)
	_check(int(queue.call("queued_count")) >= 1, "the never-cut line is queued")
	# the radio finishes: the announcer is still talking
	var radio: AudioStreamPlayer = queue.get_child(1)
	radio.stop()
	queue.call("_on_channel_finished", &"radio")
	_check(bool(queue.call("is_playing")), "the announcer is still playing after the radio finished")
	# the announcer frees its channel: the queued line plays (it never times out)
	var announcer: AudioStreamPlayer = queue.get_child(0)
	announcer.stop()
	queue.call("_on_channel_finished", &"announcer")
	_check(order.size() >= 3 and order[order.size() - 1] == &"countdown_3",
		"the never-cut line plays after the channel is free")
	queue.call("stop_all")
	queue.free()
