extends RefCounted
## The impact report and the wall glance assist.
## SI units: metres, kilograms, seconds, m/s (km/h only for the HUD).
## Every hard-coded number of the arcade car lives in one of the files of vehicle/tuning/:
## change a value here and write the reason in status/vehicle.md - never inline a number in a
## logic file.
##
## Axis convention (lead decision): forward is -Z, right is +X, up is +Y.


# --- the wall glance assist (dossier 7.2)

## A scrape (impact below this) keeps 95 % of the tangential speed.
const SCRAPE_KEEP := 0.95

## The yaw that pulls the car along the wall over SCRAPE_TIME.
const SCRAPE_YAW := 0.5

const SCRAPE_TIME := 0.15

## The torque that applies the scrape yaw.
const SCRAPE_TORQUE := 8000.0

## A contact below this normal speed is a floor touch, not a crash.
const IMPACT_FLOOR_MIN := 14.0

## A contact whose normal points more than this up is a floor touch.
const FLOOR_CONTACT_NORMAL := 0.7

## The contact history is pruned after this time.
const IMPACT_REPORT_PRUNE := 1.0

## Below this tangential speed a scrape is not worth the assist.
const SCRAPE_MIN_TANGENT := 0.05

# --- impacts (dossier 7.2, 7.3)

## Minimum velocity change (m/s) in one tick that counts as a hit.
const IMPACT_MIN_DV := 0.8

## Same contact pair is reported at most this often (s).
const IMPACT_COOLDOWN := 0.15

## Above this the impact cancels the drift (dirty exit).
const IMPACT_CLEAN := 0.30

## A scrape (impact below this) is a glance, not a crash.
const IMPACT_SCRAPE := 0.35

## A hit keeps (1 - 0.45 * impact) of the tangential speed and bounces off at 0.25.
const HIT_TANGENTIAL_KEEP := 0.45

const HIT_BOUNCE := 0.25

## The shortest relative velocity the impact module looks at.
const IMPACT_MIN_REL := 0.1

## The contact score of a contact that does not explain the hit.
const IMPACT_SCORE_MIN := -2.0

# --- the solver spike guard

## A spike: more than this speed (m/s) away from the ground, given to a car that stands on its wheels by a contact of its
## box. The edge of a kerb gave 10 m/s in the first tick and 31 m/s in the third (the car flew 30 m high and landed on its
## roof). The small pushes of two cars that overlap (2-5 m/s) are no spike.
const SOLVER_SPIKE := 6.0

## After a spike the speed away from the ground is cut to this (m/s) ...
const SOLVER_KICK_UP := 1.5

## ... for this long (s): the solver goes on pushing for a few ticks.
const SOLVER_HOLD := 0.3

## The spin (rad/s) the car keeps after such a tick (the spike gave it 25 rad/s). A barrel roll is 9 rad/s
## and is never read here: it has no contact.
const SOLVER_SPIN := 3.5
