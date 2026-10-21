extends Node
## Unit test for the audio module (the lead rule: tests extend Node and run through the core
## test host).
##   tools/godot.sh test res://audio/tests/test_audio.gd
##
## The static checks live in audio_test_checks.gd, the spectral ones in audio_test_spectrum.gd,
## the runtime ones in audio_test_runtime.gd and the gameplay ones in audio_test_gameplay.gd.

const ChecksScript := preload("res://audio/tests/audio_test_checks.gd")
const RuntimeScript := preload("res://audio/tests/audio_test_runtime.gd")
const EmittersScript := preload("res://audio/tests/audio_test_emitters.gd")
const GameplayScript := preload("res://audio/tests/audio_test_gameplay.gd")
const SfxLibrary := preload("res://audio/sfx_library.gd")

var _failed := 0
var _checks := 0


func _ready() -> void:
	var checks := ChecksScript.new()
	checks.ok = _ok
	checks.run()
	await _run_runtime()
	await _run_emitters()
	await _run_gameplay()
	await _finish()


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("PASS ", label)
	else:
		_failed += 1
		print("FAIL ", label)


## The checks that need a running tree (the pool, the emitters, the voice channels).
func _run_runtime() -> void:
	var runtime := RuntimeScript.new()
	runtime.ok = _ok
	runtime.host = self
	await runtime.run()


## The checks of the world emitters (the levels, the fades, the river and the siren switches).
func _run_emitters() -> void:
	var emitters := EmittersScript.new()
	emitters.ok = _ok
	emitters.host = self
	await emitters.run()


## The checks that need the game (the events, the collisions, the pause, the world hooks).
func _run_gameplay() -> void:
	var gameplay := GameplayScript.new()
	gameplay.ok = _ok
	gameplay.host = self
	await gameplay.run()


func _finish() -> void:
	# stop every player and let the audio server flush, so the engine reports no leaked
	# stream resources
	SfxLibrary.clear_cache()
	# the audio server releases the playbacks a few frames later
	for i in 180:
		await get_tree().process_frame
	print("AUDIO TEST %d checks, %d failed" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
