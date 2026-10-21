extends RefCounted
## SKYRUSH UI palette (ART.md §3, ref/art/DOSSIER.md §2.1, ref/gameplay/DOSSIER.md §8.3).
## Shared by the HUD and the menu unit. Static only — never instantiate.

# --- core UI ---------------------------------------------------------------------------------------
const CYAN := Color("00e5ff")           ## HUD primary (N2, route, sky lanes).
const MAGENTA := Color("ff2bd6")         ## boost / flight accents.
const AMBER := Color("ffb300")           ## takedown banner, warnings, hop prompt.
const RED := Color("ff3355")             ## police, danger, busted.
const POLICE_BLUE := Color("2f6bff")     ## police, evading bar.
const GREEN := Color("39ff88")           ## escaped / success.
const TEXT := Color("f2f6ff")            ## primary text.
const TEXT_DIM := Color("9aa6c4")        ## secondary text, sub-labels.
const WHITE := Color("ffffff")
const BLACK := Color("0a0a0a")
const PANEL := Color(0.043, 0.059, 0.102, 0.70)  ## #0B0F1A @ 70 % glass panel.
const EDGE := Color(0.0, 0.898, 1.0, 0.55)       ## 1 px cyan edge on panels.

# --- scene neon (reference only, do not use for UI chrome) ------------------------------------------
const NEON_CYAN := Color("19e6ff")
const NEON_PINK := Color("ff2bd6")
const NEON_BLUE := Color("3d5cff")
const NEON_VIOLET := Color("9b5cff")
const NEON_AMBER := Color("ffb000")
const NEON_RED := Color("ff2a3a")
const NIGHT := Color("05060f")

# --- gauge value arcs (roadster dossier 6.4) --------------------------------------------------------
const GAUGE_VALUE := Color("ffffff")     ## the lit part of a 270 deg gauge arc.
const GAUGE_REST := Color("5a5a5a")      ## the dim remainder.


## Colour for a boost / toast style name used by Events.toast.
static func for_style(style: StringName) -> Color:
	match style:
		&"good":
			return GREEN
		&"great":
			return CYAN
		&"danger":
			return RED
		&"police":
			return POLICE_BLUE
		_:
			return TEXT


## Colour of the speed arc at a normalised position 0..1 (cyan -> magenta).
static func speed_ramp(t: float) -> Color:
	return CYAN.lerp(MAGENTA, clampf(t, 0.0, 1.0))
