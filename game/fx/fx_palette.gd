extends RefCounted
## FX colour tokens (ART.md §3 palette, ref/art/DOSSIER.md §2.3 emission tiers).
## Kept in one place so every effect in game/fx/ speaks the same colour language.

# --- tyres / road ---------------------------------------------------------------------------
## Tyre smoke body: grey-white, slightly cool (art DOSSIER §2.1 "smoke" family).
const SMOKE := Color(0.788, 0.800, 0.824)
## The smoke as it reads on screen under a street lamp (lead F-INT4: grey-blue, never black,
## never pure white).
const SMOKE_SCREEN := Color(0.604, 0.639, 0.706)
## Wet-road spray mist: same family, pushed towards the cold street-light blue.
const SPRAY_MIST := Color(0.686, 0.769, 0.816)
## Rubber left on the road (brief: #151515, alpha 0.6).
const RUBBER := Color(0.082, 0.082, 0.082)

# --- impacts -------------------------------------------------------------------------------
## Hot spark core (E5 tier, blooms hard): nearly white.
const SPARK_HOT := Color(1.0, 0.985, 0.940)
## Spark tail, cooling to amber.
const SPARK_COOL := Color(1.0, 0.470, 0.120)
## Glass shard: cold, near-white with a cyan cast.
const GLASS := Color(0.780, 0.900, 0.960)
## Plastic bodywork bits: dark, slightly warm.
const PLASTIC := Color(0.230, 0.230, 0.250)

# --- energy --------------------------------------------------------------------------------
## 闪充 charge cyan (ART.md §3 neon cyan).
const CHARGE := Color(0.098, 0.902, 1.0)
## Electric arc of an EV wreck: white-blue.
const ARC := Color(0.800, 0.930, 1.0)
## N2 (nitrogen) vapour: the Roadster's cold-gas plume.
const VAPOUR := Color(0.812, 0.910, 1.0)

# --- damage / wreck ------------------------------------------------------------------------
## Wreck smoke column (brief: #2A2A2E).
const WRECK_SMOKE := Color(0.165, 0.165, 0.180)
## The column of an EV wreck: cold white-grey.
const WRECK_SMOKE_EV := Color(0.812, 0.839, 0.871)
## The ramp of a flame: the white-hot core lives in the texture, so the ramp only carries the
## body of the lick. #FFD27A -> #FF7A1A -> #B83A0C -> #3A1A0E.
const FIRE_RAMP_0 := Color(1.0, 0.824, 0.478)
const FIRE_RAMP_1 := Color(1.0, 0.478, 0.102)
const FIRE_RAMP_2 := Color(0.722, 0.227, 0.047)
const FIRE_RAMP_3 := Color(0.227, 0.102, 0.055)
## The light of a fire.
const FIRE_LIGHT := Color(1.0, 0.690, 0.290)

# --- rain ----------------------------------------------------------------------------------
const RAIN := Color(0.722, 0.800, 0.878)
## Road splash ring.
const SPLASH := Color(0.780, 0.860, 0.930)
## The rim of a splash ring: it has to catch the street lamps.
const SPLASH_RIM := Color(0.780, 0.859, 0.929)
## The ribbons of displaced air of a near miss: cold white-blue, never orange.
const AIR := Color(0.851, 0.910, 1.0)
## The water droplets thrown off a wet tyre.
const DROPLET := Color(0.851, 0.910, 1.0)
