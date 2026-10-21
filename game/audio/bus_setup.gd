extends RefCounted
## The bus setup of the audio unit: the music sub-bus, the duck effect, the master limiter
## and the slow-motion effects on the SFX bus.
##
## The setup is idempotent: a second director (the tests build one) finds the buses and the
## effects that are already there.

const Tuning := preload("res://audio/audio_tuning.gd")


## Creates the buses and the effects. It returns the duck effect of the music bed.
static func setup() -> AudioEffectAmplify:
	for bus in Settings.BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, &"Master")
	var music := AudioServer.get_bus_index(&"Music")
	if music < 0:
		AudioServer.add_bus()
		music = AudioServer.bus_count - 1
		AudioServer.set_bus_name(music, &"Music")
		AudioServer.set_bus_send(music, &"Master")
	# our own sub-bus so ducking never touches anything the player is not hearing
	var bed := AudioServer.get_bus_index(Tuning.MUSIC_BUS)
	if bed < 0:
		AudioServer.add_bus()
		bed = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bed, Tuning.MUSIC_BUS)
		AudioServer.set_bus_send(bed, &"Music")
	# the duck effect is added once, even if a second director shows up
	var duck_index := _find_named_effect(bed, "AudioDuck")
	var duck: AudioEffectAmplify
	if duck_index >= 0:
		duck = AudioServer.get_bus_effect(bed, duck_index) as AudioEffectAmplify
	else:
		duck = AudioEffectAmplify.new()
		duck.resource_name = "AudioDuck"
		duck.volume_db = 0.0
		AudioServer.add_bus_effect(bed, duck, 0)
	# a hard limiter on Master keeps the mix under the ceiling (acceptance: peak <= -1 dBFS)
	var master := AudioServer.get_bus_index(&"Master")
	if master >= 0 and _find_effect(master, &"AudioEffectHardLimiter") < 0:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = Tuning.LIMITER_CEILING_DB
		limiter.release = Tuning.LIMITER_RELEASE_S
		AudioServer.add_bus_effect(master, limiter, 0)
	# the slow-motion effect on the SFX bus (the takedown cam)
	var sfx := AudioServer.get_bus_index(&"SFX")
	if sfx >= 0:
		if pitch_effect(sfx) == null:
			var pitch := AudioEffectPitchShift.new()
			pitch.resource_name = "SFXPitch"
			AudioServer.add_bus_effect(sfx, pitch)
		if lowpass_effect(sfx) == null:
			var lowpass := AudioEffectLowPassFilter.new()
			lowpass.resource_name = "SFXLowPass"
			lowpass.cutoff_hz = Tuning.SLOWMO_LOWPASS_HZ_MAX
			AudioServer.add_bus_effect(sfx, lowpass)
	return duck


## The slow-motion takedown cam: the SFX bus is pitched down and low-passed.
static func set_slow_mo(active: bool) -> void:
	var bus := AudioServer.get_bus_index(&"SFX")
	if bus < 0:
		return
	var pitch := pitch_effect(bus)
	var lowpass := lowpass_effect(bus)
	if active:
		if pitch != null:
			pitch.pitch_scale = Tuning.SLOWMO_PITCH
		if lowpass != null:
			lowpass.cutoff_hz = Tuning.SLOWMO_LOWPASS_HZ
		return
	if pitch != null:
		pitch.pitch_scale = 1.0
	if lowpass != null:
		lowpass.cutoff_hz = Tuning.SLOWMO_LOWPASS_HZ_MAX


## The pitch-shift effect of a bus (null when it has none).
static func pitch_effect(bus: int) -> AudioEffectPitchShift:
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectPitchShift:
			return AudioServer.get_bus_effect(bus, i) as AudioEffectPitchShift
	return null


## The low-pass effect of a bus (null when it has none).
static func lowpass_effect(bus: int) -> AudioEffectLowPassFilter:
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectLowPassFilter:
			return AudioServer.get_bus_effect(bus, i) as AudioEffectLowPassFilter
	return null


## The index of the bus effect with the given class, or -1.
static func _find_effect(bus: int, type_name: StringName) -> int:
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i).get_class() == type_name:
			return i
	return -1


## The index of the bus effect with the given name, or -1.
static func _find_named_effect(bus: int, effect_name: String) -> int:
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectAmplify:
			var amp := AudioServer.get_bus_effect(bus, i) as AudioEffectAmplify
			if amp.resource_name == effect_name:
				return i
	return -1
