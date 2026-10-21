extends RefCounted
## Maps the telemetry of the player's car onto the two synth voices and the looping beds.
##
## The helper is a plain object: the director owns it and calls update() every frame. It knows
## the drivetrain of the Roadster: the motor rpm follows the road speed (a standing start still
## whines on the idle throttle), the thruster level is the normalised sum of the nozzle groups
## and the road, the wind, the squeal and the roar follow the car.

const Tuning := preload("res://audio/audio_tuning.gd")
const LoopPlayersScript := preload("res://audio/loop_players.gd")

## The drive voice (the motor whine and the fan whine).
var ev_voice: AudioStreamPlayer3D
## The cold-gas thruster voice.
var thruster_voice: AudioStreamPlayer3D
## The looping beds (the road, the wind, the squeal, the roar and the scrapes).
var loops: LoopPlayersScript


## Stores the voices the helper drives.
func setup(ev: AudioStreamPlayer3D, thruster: AudioStreamPlayer3D, loop_players: LoopPlayersScript) -> void:
	ev_voice = ev
	thruster_voice = thruster
	loops = loop_players


## Drives the voices from the telemetry of the car.
func update(player: VehicleBase, delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var t := player.telemetry
	var speed := absf(t.speed_kmh)
	# motor: the rpm follows the road speed, a standing start still whines
	var rpm := maxf(speed * Tuning.RPM_PER_KMH, t.throttle * Tuning.RPM_IDLE)
	if ev_voice != null:
		ev_voice.motor_rpm = clampf(rpm, 0.0, Tuning.RPM_MAX)
		ev_voice.motor_load = clampf(t.motor_load, 0.0, 1.0)
		ev_voice.speed_kmh = speed
		ev_voice.downforce_kg = t.downforce_kg
	# thrusters: the nozzle groups are normalised, not clamped
	var rear := group_level(t.thrusters, "Nozzle_R", Tuning.REAR_NOZZLE_COUNT)
	var perimeter := group_level(t.thrusters, "Nozzle_P", Tuning.PERIMETER_NOZZLE_COUNT)
	if thruster_voice != null:
		thruster_voice.thrust_rear = rear
		thruster_voice.thrust_perimeter = perimeter
		thruster_voice.hop_charge = clampf(t.hop_charge, 0.0, 1.0)
	# the beds (the road, the wind, the squeal and the roar) follow the car
	if loops != null:
		loops.update(speed, t.rear_slip, rear, delta)


## Falls silent: the two synth voices and the beds.
func silence() -> void:
	if ev_voice != null:
		ev_voice.motor_rpm = 0.0
		ev_voice.motor_load = 0.0
		ev_voice.downforce_kg = 0.0
	if thruster_voice != null:
		thruster_voice.thrust_rear = 0.0
		thruster_voice.thrust_perimeter = 0.0
		thruster_voice.hop_charge = 0.0
	if loops != null:
		loops.silence()


## Normalised group level: the sum of the nozzles of a group, divided by the nozzle count and
## square-rooted for loudness. One nozzle is therefore much quieter than all of them.
static func group_level(thrusters: Dictionary, prefix: String, count: float) -> float:
	var total := 0.0
	for key in thrusters:
		if String(key).begins_with(prefix):
			total += clampf(float(thrusters[key]), 0.0, 1.0)
	return clampf(sqrt(total / count), 0.0, 1.0)
