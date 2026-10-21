extends RefCounted
## Battery (the EV pack) and the charge bay (申城闪充). The battery drains with motor use and
## caps the top speed when it is nearly flat; a charge bay refills everything (dossier 3.4).

const BoostTuning := preload("res://vehicle/tuning/boost_tuning.gd")
const PowerTuning := preload("res://vehicle/tuning/power_tuning.gd")

## 0..1.
var battery: float = 1.0
## Seconds left of the running charge effect.
var charge_time: float = 0.0


## Drains the battery with motor use.
func tick(dt: float, throttle: float) -> void:
	var drain: float = PowerTuning.BATTERY_DRAIN_IDLE
	if throttle > PowerTuning.BATTERY_DRIVE_ON:
		drain = lerpf(PowerTuning.BATTERY_DRAIN_IDLE, PowerTuning.BATTERY_DRAIN_THROTTLE, throttle)
	battery = clampf(battery - drain * dt, 0.0, 1.0)
	if charge_time > 0.0:
		charge_time = maxf(charge_time - dt, 0.0)


## The speed cap in m/s allowed by the current battery charge.
func speed_cap(base: float) -> float:
	if battery < PowerTuning.BATTERY_LOW:
		return minf(base, PowerTuning.BATTERY_LOW_TOP)
	return base


## Flash charge: battery full, charge boost running.
func charge() -> void:
	battery = 1.0
	charge_time = BoostTuning.CHARGE_TIME


## True while the charge effect is running.
func charging() -> bool:
	return charge_time > 0.0
