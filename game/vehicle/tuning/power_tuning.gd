extends RefCounted
## The battery (the EV pack) and its speed cap.
## SI units: metres, kilograms, seconds, m/s (km/h only for the HUD).
## Every hard-coded number of the arcade car lives in one of the files of vehicle/tuning/:
## change a value here and write the reason in status/vehicle.md - never inline a number in a
## logic file.
##
## Axis convention (lead decision): forward is -Z, right is +X, up is +Y.


# --- power (battery)

const BATTERY_DRAIN_THROTTLE := 0.004   # 0.4 %/s at full throttle

const BATTERY_DRAIN_IDLE := 0.0005       # 0.05 %/s idle

const BATTERY_LOW := 0.15

const BATTERY_LOW_TOP := 50.0           # 180 km/h

## Above this throttle the battery drains with the motor load (below it, the idle drain).
const BATTERY_DRIVE_ON := 0.05
