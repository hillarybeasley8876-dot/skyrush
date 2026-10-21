extends RefCounted
## Tuning block for the fx unit. Every magic number of an effect lives here (one block per
## effect) so the logic files stay readable and the numbers can be reviewed in one place.
## Units: metres, seconds, radians unless stated. Colours live in fx_palette.gd.

# --- distances (metres) ------------------------------------------------------------------------
## A car closer than this runs the full effect set.
const FULL_RANGE := 60.0
## Beyond this a car runs no effect at all.
const OFF_RANGE := 150.0
## The player and this many other cars always run the full effect set.
const NEAR_CARS := 3
## Simultaneously active smoke / fire emitters (gameplay DOSSIER §7.7).
const MAX_ACTIVE_EMITTERS := 8
## How many REDUCED cars may run the wet spray at the same time (the spray is counted apart).
const MAX_SPRAY_CARS := 12

# --- tyre smoke --------------------------------------------------------------------------------
## The puffs of one rear tyre. The rate is per metre, not per second: a drift at 300 km/h needs
## more than 2.5 puffs per metre per tyre, or the plume reads as a dotted line of cotton balls.
const SMOKE_AMOUNT := 380
## The puffs fade fast: a long life stacks them into a grey wall (lead F-INT2).
const SMOKE_LIFETIME := 1.4
const SMOKE_SPEED_MIN := 1.1
const SMOKE_SPEED_MAX := 2.6
## The puffs rise at this speed (m/s): they hang over the road and drift back.
const SMOKE_RISE := 0.55
const SMOKE_SPREAD_DEG := 26.0
## The alpha of one puff. The lead's F-INT4 caps it at 0.35; three or four puffs have to
## overlap into one plume, so it stays below that.
const SMOKE_ALPHA := 0.26
## The birth size of a puff (metres).
const SMOKE_SIZE_MIN := 0.6
const SMOKE_SIZE_MAX := 0.9
## The puff grows by this factor over its life.
const SMOKE_GROW := 3.0
## The soft particle fade distance (metres): the puff melts into the road instead of cutting it.
const SMOKE_SOFT_DISTANCE := 0.5
## Drift below this (rear_slip) does not smoke.
const SMOKE_SLIP := 0.25
## Below this speed (km/h) the tyres do not smoke at all (lead F-INT2).
const SMOKE_MIN_SPEED := 10.0
## The density reaches its maximum at this rear_slip value.
const SMOKE_FULL_SLIP := 1.0
## Hard cap on the smoke density: the puffs may never fill the screen (lead F-INT2).
const SMOKE_MAX_RATIO := 0.8
## How much a hard brake contributes to the smoke density (it is a light effect).
const SMOKE_BRAKE_WEIGHT := 0.35
## The smoke is emitted at the rear contact patches, not under the axle centre. It is lifted
## half a sprite: the soft proximity fade of the shared smoke eats a sprite on the ground.
const SMOKE_EMIT_HEIGHT := 0.28
## How much of the speed of the car the puff keeps in world space (the rest is inherited).
const SMOKE_INHERIT := 0.2
## The density of the smoke is at its maximum at this speed (m/s, 300 km/h).
const SMOKE_FULL_SPEED_MPS := 83.0
## The ambient floor of the smoke: the puffs keep a dim blue-grey glow of their own, so they
## read on an unlit road (the lit-only smoke of the shared material renders black at night).
const SMOKE_AMBIENT := Color(0.227, 0.251, 0.314)
## How strong the ambient floor is. An unlit puff has to read as #343A48 or brighter.
const SMOKE_AMBIENT_ENERGY := 0.8

# --- wet road spray ----------------------------------------------------------------------------
const SPRAY_AMOUNT := 64
const SPRAY_LIFETIME := 0.55
const SPRAY_SPEED_MIN := 3.0
const SPRAY_SPEED_MAX := 7.0
const SPRAY_GRAVITY := 12.0
## The spray is a fine mist: it has to stay apart from the smoke of the tyre.
const SPRAY_ALPHA := 0.18
## The spray fans backwards and inherits part of the car's speed: the mist fan is 3-8 m long.
const SPRAY_INHERIT := 0.25
## Speed at which the spray is at full strength (km/h).
const SPRAY_FULL_SPEED := 150.0
## Below this speed there is no spray at all (km/h).
const SPRAY_MIN_SPEED := 30.0
## The fan of the spray, in degrees, and how far it is tilted upwards.
const SPRAY_FAN_DEG := 25.0
const SPRAY_TILT_DEG := 15.0
## The spray starts behind the contact patch of the tyre.
const SPRAY_BACK_OFFSET := 0.25
## The height of the spray emitter above the road (lifted half a sprite, see the smoke).
const SPRAY_EMIT_HEIGHT := 0.16
## How much of the car's speed the spray keeps in world space (the rest is inherited).
const SPRAY_SPEED_FACTOR := 0.4
## The birth size of a spray sprite (metres) and the factor it grows by over its life: the
## mist ends up 1.1-1.6 m wide.
const SPRAY_SIZE_MIN := 0.35
const SPRAY_SIZE_MAX := 0.5
const SPRAY_GROW := 3.2
## Droplets thrown off the tyre.
const DROPLET_AMOUNT := 60
const DROPLET_GRAVITY := 14.0
## The droplets are stretched along their velocity.
const DROPLET_STREAK := 0.06
## The length of a droplet streak (metres): the width comes from the thin line of the texture.
const DROPLET_LENGTH := 0.25

# --- skid marks --------------------------------------------------------------------------------
## A ribbon point is only added after this much travel (metres). The ribbon is a pool of 400
## quads, so a point every 0.9 m keeps the whole trail of a fast drift on the road.
const SKID_MIN_STEP := 0.9
## Half width of a tyre track (metres).
const SKID_HALF_WIDTH := 0.12
## The track texture repeats every this many metres.
const SKID_UV_METRES := 1.2
## How long a mark stays (seconds).
const SKID_FADE := 20.0
## The mark is lifted this far along the surface normal (metres).
const SKID_LIFT := 0.015
## Maximum number of ribbon quads in the pool.
const SKID_MAX_QUADS := 400
## How many frames the wheels may be off the road before the ribbon is cut.
const SKID_AIRBORNE_GRACE := 6
## A gap this long between two contact points means a new strip (the wheel was lifted).
const SKID_MAX_GAP := 3.0
## The gap grows with the speed: the car may move this many seconds of travel between two
## points of the same strip.
const SKID_GAP_SECONDS := 3.0
## The end of a strip fades out over this time (seconds).
const SKID_END_FADE := 0.4
## The first metres of a strip are darker: the tyre bites into the road.
const SKID_BITE_METRES := 1.5
const SKID_BITE_DARK := 1.3
## Braking counts as sliding above this forward speed (km/h). Reversing is not braking.
const SKID_BRAKE_SPEED := 25.0

# --- rain --------------------------------------------------------------------------------------
## Hard cap on the rain streaks (brief: ≤ 6k).
const RAIN_MAX := 6000
const RAIN_LIFETIME := 1.6
const RAIN_SPEED := 17.0
const RAIN_BOX := Vector3(34.0, 26.0, 34.0)
## The rain volume is pushed this far ahead of the camera (seconds of travel).
const RAIN_LEAD := 0.4
## Splash rings.
const SPLASH_AMOUNT := 300
const SPLASH_LIFETIME := 0.4
const SPLASH_SIZE_MIN := 0.12
const SPLASH_SIZE_MAX := 0.35
## The ring grows by this factor over its life.
const SPLASH_GROW := 1.8
## How often the ground under the camera is probed (seconds).
const SPLASH_PROBE_INTERVAL := 0.25
## Rays per probe (8 x 8 grid).
const SPLASH_GRID := 8
## The size of the probed area around the camera (metres).
const SPLASH_BOX := 24.0
## The share of the probe points that land in front of the camera, this close to it (metres).
const SPLASH_NEAR_SHARE := 0.7
const SPLASH_NEAR_DISTANCE := 8.0
## The grid of rays is jittered by this much on every probe (metres), so the rings are not
## always in the same place.
const SPLASH_JITTER := 0.7
## The rings hover this far above the road.
const SPLASH_LIFT := 0.02
## The energy of a splash ring: it has to catch the street lamps.
const SPLASH_ENERGY := 2.0
## The little crown that jumps up from a ring.
const SPLASH_CROWN_AMOUNT := 90
const SPLASH_CROWN_LIFETIME := 0.3
const SPLASH_CROWN_SPEED_MIN := 1.0
const SPLASH_CROWN_SPEED_MAX := 2.4
const SPLASH_CROWN_GRAVITY := 9.0
const SPLASH_CROWN_SIZE_MIN := 0.03
const SPLASH_CROWN_SIZE_MAX := 0.09

# --- charge flash ------------------------------------------------------------------------------
const CHARGE_DURATION := 1.0
## The number of short arcs that jump over the body during the flash.
const CHARGE_ARCS := 8
## The energy ribbons around the car (the "闪充" look of brief §6).
const CHARGE_RIBBONS := 3
## The width of one ribbon (metres).
const CHARGE_RIBBON_WIDTH := 0.15
## The heights of the three ribbons above the road (metres).
const CHARGE_RIBBON_HEIGHTS := [0.3, 0.7, 1.1]
## How far the ribbons rise while they turn one full turn (metres).
const CHARGE_RIBBON_RISE := 0.4
## The ribbon is pushed this far out from the body shell (metres).
const CHARGE_RIBBON_MARGIN := 0.3
## The flash light peaks at this energy (E4 tier, art DOSSIER §2.3).
const CHARGE_LIGHT_ENERGY := 9.0
## The range of the flash light (metres).
const CHARGE_LIGHT_RANGE := 6.0
## The energy of the bloom flash. It must not white out the frame from above.
const CHARGE_FLASH_ENERGY := 3.5
## The width of the hot core of the flash (metres).
const CHARGE_FLASH_SIZE := 1.0
## The flash quad is pushed towards the camera so the car body does not clip it (metres).
const CHARGE_FLASH_PUSH := 0.6
## The flash is scaled down when the camera is further away than this (metres).
const CHARGE_FLASH_FAR := 6.0
const CHARGE_RING_MIN := 1.6
const CHARGE_RING_MAX := 6.5
## The ground ring is lifted this far along the ground normal (metres).
const CHARGE_RING_LIFT := 0.03
## The flash light hangs this far above the road (metres).
const CHARGE_LIGHT_HEIGHT := 1.2
## The flash peaks at this time and is gone by twice that (seconds).
const CHARGE_FLASH_PEAK := 0.08
const CHARGE_FLASH_END := 0.25

# --- electric arcs -----------------------------------------------------------------------------
## A bolt is never longer than this (metres).
const ARC_MAX_LENGTH := 0.8
## A bolt never leaves the body shell by more than this (metres).
const ARC_SURFACE_OFFSET := 0.15
## The recursion levels of the midpoint displacement.
const ARC_DEPTH := 4
## The displacement of the last recursion level (metres).
const ARC_DISPLACEMENT := 0.12
## The length of a branch (metres).
const ARC_BRANCH_LENGTH := 0.3
## The number of surface points cached on the body.
const ARC_SURFACE_POINTS := 200
## The width of the hot core of an arc (metres).
const ARC_WIDTH := 0.03
## The arcs of a wrecked EV only show below this health.
const ARC_HEALTH_LIMIT := 0.3

# --- sparks ------------------------------------------------------------------------------------
const SPARK_MAX := 220
const SPARK_LIFE := 0.28
const SPARK_GRAVITY := 18.0
const SPARK_DRAG := 0.55
const SPARK_BOUNCE := 0.42
const SPARK_TANGENTIAL_LOSS := 0.72
const SPARK_THICKNESS_MIN := 0.012
const SPARK_THICKNESS_MAX := 0.025
const SPARK_LENGTH_MIN := 0.08
const SPARK_LENGTH_MAX := 0.2
## A fast spark stretches into a streak of this factor of its speed.
const SPARK_STRETCH := 0.01
const SPARK_STRETCH_MAX := 0.2
## A scrape throws sparks on every contact: a shower, not a dashed line of clumps.
const SPARK_SCRAPE_INTERVAL := 0.0
## The number of sparks of one scrape.
const SPARK_SCRAPE_COUNT := 3
## A scrape trail: the sparks follow the car, they do not fly off along the normal.
const SPARK_TRAIL_FACTOR := 0.5
const SPARK_NORMAL_SPEED := 1.5
const SPARK_UP_SPEED := 1.0
## The sparks of an impact keep this part of the car's speed.
const SPARK_CARRY := 0.8
## The burst is thrown in a cone of this many degrees around the reflection.
const SPARK_CONE_DEG := 45.0
## Impact severity thresholds, measured as delta-v (m/s).
const DV_SCRAPE := 0.35
const DV_HIT := 4.0
## The impact light.
const IMPACT_LIGHT_ENERGY := 8.0
const IMPACT_LIGHT_TIME := 0.12
const IMPACT_LIGHT_RANGE := 5.0
## The sparks start just outside the surface, otherwise they hide inside the panel.
const IMPACT_SURFACE_OFFSET := 0.03

# --- debris ------------------------------------------------------------------------------------
const DEBRIS_GLASS := 96
const DEBRIS_PLASTIC := 72
const DEBRIS_GRAVITY := 16.0
const DEBRIS_BOUNCE := 0.32
const DEBRIS_SIZE_MIN := 0.02
const DEBRIS_SIZE_MAX := 0.06
## The debris of an impact keeps this part of the car's speed.
const DEBRIS_CARRY := 0.8
## A takedown is the show piece (gameplay DOSSIER §3.3): oversized parts, twice the counts.
const TAKEDOWN_SPARKS := 140
const TAKEDOWN_GLASS := 26
const TAKEDOWN_PLASTIC := 16
const TAKEDOWN_SPEED := 12.0
const TAKEDOWN_SCALE := 2.2

# --- N2 boost ----------------------------------------------------------------------------------
const VAPOUR_AMOUNT := 36
const VAPOUR_LIFETIME := 0.45
const VAPOUR_SPEED_MIN := 12.0
const VAPOUR_SPEED_MAX := 26.0
## The width of the vapour trail behind the car (metres).
const VAPOUR_WIDTH := 0.9
## The white puffs of a nitro ignition.
const IGNITION_PUFFS := 8
const IGNITION_LIFETIME := 0.6
## The radius of the shock ring when it appears and when it is gone (metres).
const IGNITION_SCALE_MIN := 0.3
const IGNITION_SCALE_MAX := 1.6
const IGNITION_ALPHA := 0.3
## The shock ring of a nitro ignition.
const IGNITION_RING_TIME := 0.15
## The wheel arch glow light.
const ARCH_LIGHT_ENERGY := 2.0
const ARCH_LIGHT_RANGE := 0.8
## The arch lights sit this far out from the wheel and this far above the road (metres).
const ARCH_LIGHT_OUT := 0.1
const ARCH_LIGHT_UP := 0.15
## How fast the arch glow ramps (per second).
const ARCH_FADE_SPEED := 4.0

# --- wreck -------------------------------------------------------------------------------------
## The smoke column of a wrecked car.
const WRECK_SMOKE_AMOUNT := 80
const WRECK_SMOKE_LIFETIME := 5.5
## The size the column grows to (metres).
const WRECK_SMOKE_SCALE := 4.5
## The alpha of one puff of the column: it must stay thin enough to read against the sky.
const WRECK_SMOKE_ALPHA := 0.3
## The column drifts with the wind (m/s^2 sideways).
const WRECK_SMOKE_WIND := 0.2
## The column rises at this speed (m/s).
const WRECK_SMOKE_RISE_MIN := 2.0
const WRECK_SMOKE_RISE_MAX := 2.6
## The cone of the column (degrees): a column, not a fountain.
const WRECK_SMOKE_SPREAD := 10.0
## The buoyancy of the column (m/s^2).
const WRECK_SMOKE_BUOYANCY := 0.6
## The fire licks of an ICE car.
const WRECK_FIRE_AMOUNT := 36
const WRECK_FIRE_LIFETIME := 0.65
const WRECK_FIRE_RISE_MIN := 1.5
const WRECK_FIRE_RISE_MAX := 3.0
## The size of a flame lick: it grows to its size and shrinks away again (metres).
const WRECK_FIRE_SIZE := 0.9
const WRECK_FIRE_SIZE_MIN := 0.35
const WRECK_FIRE_SIZE_END := 0.25
## The energy of a flame lick: the white-hot core lives in the texture, not in the HDR.
const WRECK_FIRE_ENERGY := 2.0
## A wreck that still slides faster than this (m/s) does not show its fire.
const WRECK_FIRE_MAX_SLIDE := 2.0
## The fire light flickers between these energies.
const WRECK_LIGHT_MIN := 2.0
const WRECK_LIGHT_MAX := 5.0
const WRECK_LIGHT_RANGE := 5.0
## The fire light hangs this far above the road (metres).
const WRECK_LIGHT_HEIGHT := 1.2

# --- near miss ---------------------------------------------------------------------------------
const NEAR_MISS_STREAKS := 6
const NEAR_MISS_LIFETIME := 0.6
## The length of a ribbon of displaced air (metres).
const NEAR_MISS_LENGTH := 5.0
## The speed of the air of a near miss (m/s): the air is dragged slowly across the gap, so the
## ribbon hangs between the two cars instead of crossing it in a flash.
const NEAR_MISS_SPEED := 9.0
const NEAR_MISS_WIDTH := 0.8
## The height of the ribbons of displaced air (metres): above the belt line of the cars, so
## the ribbon is not hidden by them.
const NEAR_MISS_HEIGHT := 1.0
## The length of a ribbon is the relative speed times this (seconds).
const NEAR_MISS_SPEED_TIME := 0.12
