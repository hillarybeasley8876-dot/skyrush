extends RefCounted
## The QQ drift: the state machine, the speed loss and the gauge (集气).
## SI units: metres, kilograms, seconds, m/s (km/h only for the HUD).
## Every hard-coded number of the arcade car lives in one of the files of vehicle/tuning/:
## change a value here and write the reason in status/vehicle.md - never inline a number in a
## logic file.
##
## Axis convention (lead decision): forward is -Z, right is +X, up is +Y.


# --- drift (dossier 4.6)

const DRIFT_MIN_SPEED := 15.0

const DRIFT_MIN_STEER := 0.3

const DRIFT_MIN_WHEELS := 3

## How fast the velocity direction chases the nose while drifting.
const DRIFT_VEL_LAMBDA := 2.0

## Yaw torque authority: I_yaw * DRIFT_TORQUE_K * (target - current).
const DRIFT_TORQUE_K := 6.0

## Slip-angle correction (added to the dossier controller so beta stays in 26-52 deg).
const DRIFT_BETA_K := 1.5

## The yaw kick that starts the drift (in units of the yaw inertia).
const DRIFT_YAW_KICK := 1.5

## Speed loss while drifting: (1.5 + 8 sin beta) m/s^2.
const DRIFT_LOSS_BASE := 1.5

const DRIFT_LOSS_SIN := 8.0

## Maintain-speed assist: cancels this share of the drift loss inside the sweet band.
const DRIFT_MAINTAIN := 0.60

const DRIFT_MAINTAIN_LO := 10.0

const DRIFT_MAINTAIN_HI := 55.0

## Lateral assist ceiling (m/s^2). The dossier says 50, but at 200 km/h a drift needs
## v * omega = 100 m/s^2 of lateral force to hold the arc; with the 50 cap the slip angle ran
## past 66 deg and the car spun out. 200 m/s^2 (20 g) is the arcade cheat that keeps the
## 26-52 deg band across the whole speed range.
const DRIFT_ASSIST_MAX := 200.0

## The slip angle the drift controller aims for, in radians (26-52 deg): the counter steer
## asks for the shallow end, the full steer for the deep end (dossier 4.6).
const DRIFT_BETA_CMD_MIN := 0.50

const DRIFT_BETA_CMD_MAX := 0.90

## The lateral acceleration the tyres can add to the assist (mu * g).
const DRIFT_TYRE_ACCEL := 14.2

## Slip clamp and the spin-out guard.
const DRIFT_SLIP_CLAMP_DEG := 66.0

## The torque that pulls the nose back when the slip passes the clamp.
const DRIFT_SLIP_CLAMP_K := 10.0

const DRIFT_SPIN_LIMIT := 2.4

const DRIFT_SPIN_DAMP := 8.0

const DRIFT_REAR_MU_FADE := 0.08

## The recover: the yaw rate is damped with this factor (1/factor = the time constant), the
## velocity chases the nose with DRIFT_RECOVER_LAMBDA and the tyres fade back to full grip
## over DRIFT_RECOVER_FADE. The recover has to straighten the nose before the 小喷 window is
## useful (dossier 4.6, the RECOVER row).
const DRIFT_RECOVER_YAW := 8.0

const DRIFT_RECOVER_LAMBDA := 8.0

const DRIFT_RECOVER_FADE := 0.45

## The lateral acceleration ceiling of the recover (m/s^2). The recover is a short transient,
## so it may pull harder than the drift itself.
const DRIFT_RECOVER_ASSIST_MAX := 300.0

## Gauge (集气) in slots per second: max(0.015 * km/h lost, 0.10 * dt).
const GAUGE_PER_KMH_LOST := 0.015

const GAUGE_FLOOR_PER_S := 0.10

## Clean exit needs a drift of at least this long and no impact above IMPACT_CLEAN.
const DRIFT_MIN_TIME := 0.40

## Drift cut (断位): release and re-press within this window snaps the car straight.
const DRIFT_CUT_WINDOW := 0.25

const DRIFT_CUT_LAMBDA := 5.2

const DRIFT_CUT_TIME := 0.20

## The drift assist only works above this speed.
const DRIFT_ASSIST_MIN_SPEED := 0.5

## The counter steer of the front wheels during a drift (a share of the slip angle).
const DRIFT_COUNTER_FACTOR := 0.8

## The drift ends when the slip falls below this angle.
const DRIFT_EXIT_BETA_DEG := 12.0

## The counter steer that ends the drift.
const DRIFT_EXIT_COUNTER := -0.3

## The yaw rate of the drift, in rad/s.
const DRIFT_OMEGA_MIN := 0.5

const DRIFT_OMEGA_MAX := 2.4

## The yaw rate unwinds over this time when the drift button is released and the steer does
## not hold the arc any more (the factor is persistent, so a released drift really ends).
const DRIFT_UNWIND_TIME := 0.20

## A dirty exit keeps this share of the gauge.
const DRIFT_DIRTY_GAUGE := 0.5

## The speed below which the drift is lost.
const DRIFT_LOST_SPEED := 0.5
