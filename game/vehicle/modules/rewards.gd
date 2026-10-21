extends RefCounted
## The N2 rewards of dossier 5.2: takedowns, near misses and clean trick landings.
## Only the player's car earns them (the AI cars do not need a tank).

const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")
const BodyTuning := preload("res://vehicle/tuning/body_tuning.gd")
const RewardTuning := preload("res://vehicle/tuning/reward_tuning.gd")
const BoostMod := preload("res://vehicle/modules/boost.gd")

var boost: BoostMod = null
## The takedown streak: how many takedowns in a row (the window is 10 s).
var streak: int = 0
## The time of the last takedown.
var last_takedown: float = BodyTuning.TIME_NEVER

var _clock: float = 0.0


func setup(boost_module: BoostMod) -> void:
	boost = boost_module


## Advances the streak timer.
func tick(dt: float) -> void:
	_clock += dt
	if streak > 0 and _clock - last_takedown > RewardTuning.TAKEDOWN_STREAK_WINDOW:
		streak = 0


## A takedown: +50 N2 and +25 more per streak step (dossier 3.5 and 5.2).
func on_takedown(vehicle: VehicleBase, _kind: StringName) -> void:
	if boost == null or Game.player != vehicle:
		return
	if _clock - last_takedown > RewardTuning.TAKEDOWN_STREAK_WINDOW:
		streak = 0
	streak += 1
	last_takedown = _clock
	var gain: float = RewardTuning.TAKEDOWN_N2 + RewardTuning.TAKEDOWN_STREAK_N2 * float(streak - 1)
	grant(gain)


## A near miss: traffic within 1.2 m at 60 km/h or more (dossier 5.2).
func on_near_miss(vehicle: VehicleBase) -> void:
	if boost == null or Game.player != vehicle:
		return
	grant(RewardTuning.NEAR_MISS_N2)


## A clean landing after a Big Hop or a barrel roll (dossier 5.2 and 5.4).
## The score goes through the stunt event, so the HUD shows it once ("+15").
func on_trick(vehicle: VehicleBase) -> void:
	if boost == null or Game.player != vehicle:
		return
	grant(RewardTuning.TRICK_N2)
	Events.stunt.emit(&"trick", int(RewardTuning.TRICK_N2), "特技 TRICK!")


## Puts N2 into the tank.
func grant(amount: float) -> void:
	boost.n2 = minf(boost.n2 + amount, BoostTuning.N2_MAX)
