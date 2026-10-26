extends RefCounted
## The suspension: the spring, the dampers, the anti roll bars and the wheel probes.
## SI units: metres, kilograms, seconds, m/s (km/h only for the HUD).
## Every hard-coded number of the arcade car lives in one of the files of vehicle/tuning/:
## change a value here and write the reason in status/vehicle.md - never inline a number in a
## logic file.
##
## Axis convention (lead decision): forward is -Z, right is +X, up is +Y.


# --- suspension (dossier 4.4)

const SPRING_K := 70000.0

const DAMP_BUMP := 4600.0

const DAMP_REBOUND := 6300.0

## Anchor -> wheel centre distance with the spring unloaded.
const REST_LEN := 0.41

## Maximum compression before the bump stop.
const TRAVEL := 0.20

const BUMPSTOP_K := 300000.0

## The damper of the bump stop, as a time (s): the damping coefficient is BUMPSTOP_K * this (N*s/m). It acts in both directions
## while the stop is engaged, so the energy of a hard landing is lost and not given back as a bounce.
const BUMPSTOP_DAMP_TIME := 0.06

## Static sag of the 1.9 t car: 4659.75 N per corner / 70 000 N/m. Every car keeps this sag
## (its spring rate is mass * g / 4 / sag), so a heavy car does not sit on its bump stops.
const STATIC_SAG := 0.0665679

const ARB_FRONT := 28000.0

const ARB_REAR := 20000.0

## Suspension force ceiling per wheel.
const SUSP_MAX := 60000.0

## Landing damper multiplier and how long it lasts after a touchdown.
const LAND_DAMP_MULT := 2.0

const LAND_DAMP_TIME := 0.25

## Wheel probe geometry: a small sphere cast down from the mount.
const PROBE_RADIUS := 0.06

const PROBE_CAST := 0.90

## How far inside the side of the collision box the probe sphere stays (m). A probe that reaches past the box meets what the
## box leans on: the Roadster's mounts stood 0.976 m out with a box 0.95 m wide a side, so a car that scraped a parapet had
## the probes of that side over the wall; lifted 0.3 m they stood on its top and the bump stop threw the car over it (the
## random viaduct drives: every fall that was left came that way). The force still acts at the mount.
const PROBE_INSET := 0.05

## The steepest surface a tyre can stand on: the contact normal has to point up at least this much
## (0.35 = a slope of 70 degrees). A wall, a ceiling or the back face of a surface is not ground. Without
## the rule a car that leans against a building has its wheels on the wall: the suspension pushes it
## along the wall, the upright torque aligns it to the wall and it drives up the facade.
const MIN_GROUND_NORMAL_Y := 0.35

## The lowest the floor of the collision box may be above the road at rest (m). The wheels climb a kerb with their springs;
## the box has to stay clear of the kerbs of the city (15 cm) with the sag and the pitch of a car at 250 km/h, or the lower
## edge of the box meets the kerb like a wall: the car stops dead or is thrown.
const MIN_BOX_BOTTOM := 0.34

## The gravity of the world (m/s^2): the static sag of a car is mass * g / 4 / k.
const GRAVITY := 9.81

## The mass of the reference car (the roadster): the dampers and the bars are scaled with it.
const REFERENCE_MASS := 1900.0
