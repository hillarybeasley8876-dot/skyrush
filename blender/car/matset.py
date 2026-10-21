"""The complete material set of the hero Roadster (dossier §7, ART.md §5).

One place for every surface so no material is created twice and every map is
named in one place. build_all() must run BEFORE any object is created: the lead's
shell builder (lib/roadster_body.py) looks materials up by name, so the four
shell materials have to exist already.

`tile` is the physical size of one texture repeat in metres; `uv_m` is how many
metres one UV unit covers in that material's UV space (the normalised box
projection covers the whole car, so uv_m = paths.UV_EXTENT).
"""
from car import materials, paths

# shell materials (also used by lib/roadster_body.py)
SHELL = ("SH_car_paint", "M_BlackTrim", "SH_glass_gold", "M_TBar")
EXT = paths.UV_EXTENT


def build_all():
    """Create every material once; returns the name -> material dict."""
    _shell()
    _trim()
    _metals()
    _wheels()
    _interior()
    _lamps()
    return {name: materials.get(name) for name in SHELL}


def _shell():
    """The paint, the black trim, the canopy and the T-bar."""
    m = materials
    m.pbr("SH_car_paint", paths.WHITE, rough=0.28, clearcoat=0.6,
          base_map=paths.tex("body_panel_base.png"),
          normal_map=paths.tex("body_panel_nor.png"),
          rough_map=paths.tex("body_rough.png"), uv="UVMap")
    m.pbr("M_BlackTrim", paths.BLACK_TRIM, rough=0.55, uv_m=EXT, tile=0.50,
          normal_map=paths.tex("blacktrim_nor.png"), normal_strength=0.55,
          rough_map=paths.tex("blacktrim_rough.png"), uv="UVMap")
    m.pbr("M_ArchLip", paths.BLACK_TRIM, rough=0.35, uv_m=EXT, tile=0.50,
          normal_map=paths.tex("blacktrim_nor.png"), normal_strength=0.55,
          rough_map=paths.tex("blacktrim_rough.png"), uv="UVMap")
    m.pbr("M_InnerDark", paths.INNER_DARK, rough=0.80, uv_m=EXT, tile=0.15,
          normal_map=paths.tex("innerdark_nor.png"), uv="UVMap", specular=0.15)
    # the canopy reads as one dark bronze shell (photo 03); the game's shader
    # uses its own tint_color, so only the preview depends on this map
    m.pbr("SH_glass_gold", paths.GLASS_GOLD, rough=0.04, metal=0.6, alpha=0.95,
          clearcoat=1.0, base_map=paths.tex("glass_base.png"),
          normal_map=paths.tex("glass_nor.png"), uv="UVMap")
    m.pbr("M_TBar", "#08090B", rough=0.12, clearcoat=0.8, uv_m=EXT, tile=0.10,
          normal_map=paths.tex("blacktrim_nor.png"), uv="UVMap")


def _trim():
    """The carbon and the suspension steel."""
    m = materials
    m.pbr("M_Carbon", paths.CARBON, rough=0.35, clearcoat=0.8, uv_m=EXT, tile=0.10,
          base_map=paths.tex("carbon_base.png"),
          normal_map=paths.tex("carbon_nor.png"),
          rough_map=paths.tex("carbon_rough.png"), uv="UVMap")
    m.pbr("M_Suspension", "#3A3A3C", rough=0.45, metal=0.7, uv_m=EXT, tile=0.20,
          normal_map=paths.tex("wheel_nor.png"), uv="UVMap")


def _metals():
    """The machined metals (their UVs are polar)."""
    m = materials
    m.pbr("M_Titanium", paths.TITANIUM, rough=0.30, metal=1.0,
          normal_map=paths.tex("titanium_nor.png"), uv="UVMap")
    # cold gas does not glow: the gold throat is metal and a depth gradient
    m.pbr("M_NozzleGold", paths.GOLD, rough=0.25, metal=1.0,
          base_map=paths.tex("nozzle_gold.png"),
          normal_map=paths.tex("gold_nor.png"), uv="UVMap")
    m.pbr("M_GoldWheel", paths.GOLD, rough=0.32, metal=1.0,
          normal_map=paths.tex("gold_nor.png"), uv="UVMap")
    m.pbr("M_CaliperBronze", paths.CALIPER, rough=0.40, metal=0.6,
          normal_map=paths.tex("gold_nor.png"), uv="UVMap")
    m.pbr("M_Disc", paths.DISC, rough=0.45, metal=0.2,
          base_map=paths.tex("disc_base.png"), normal_map=paths.tex("disc_nor.png"),
          rough_map=paths.tex("disc_rough.png"), uv="UVMap")


def _wheels():
    """The rims and the two tyres."""
    m = materials
    m.pbr("M_WheelWhite", paths.WHEEL_WHITE, rough=0.45,
          normal_map=paths.tex("wheel_nor.png"), rough_map=paths.tex("wheel_rough.png"),
          uv="UVMap")
    m.pbr("M_WheelDark", paths.WHEEL_DARK, rough=0.40, metal=0.8,
          normal_map=paths.tex("wheel_nor.png"), rough_map=paths.tex("wheel_rough.png"),
          uv="UVMap")
    for tag in ("F", "R"):
        m.pbr("M_Tyre_" + tag, paths.RUBBER, rough=0.85,
              base_map=paths.tex("tyre_base_%s.png" % tag.lower()),
              normal_map=paths.tex("tyre_nor_%s.png" % tag.lower()),
              rough_map=paths.tex("tyre_rough_%s.png" % tag.lower()), uv="UVMap")


def _interior():
    """The cabin: the seat, the trim, the tank and the ambient strips."""
    m = materials
    m.pbr("M_SeatWhite", paths.SEAT_WHITE, rough=0.80, uv_m=EXT, tile=0.25,
          normal_map=paths.tex("seat_weave_nor.png"), uv="UVMap")
    m.pbr("M_Microsuede", paths.MICROSUEDE, rough=0.95, uv_m=EXT, tile=0.10,
          normal_map=paths.tex("microsuede_nor.png"), uv="UVMap")
    m.pbr("M_CabinBlack", paths.CABIN_BLACK, rough=0.60, uv_m=EXT, tile=0.12,
          normal_map=paths.tex("cabin_nor.png"), uv="UVMap")
    m.pbr("M_Copv", "#E8E8EA", rough=0.35, uv_m=EXT, tile=0.40,
          normal_map=paths.tex("copv_nor.png"), uv="UVMap")
    m.pbr("M_RedAccent", paths.RED, rough=0.40, emission=paths.RED,
          emission_strength=0.5, uv_m=EXT, tile=0.20,
          base_map=paths.tex("redstrip.png"), uv="UVMap")


def _lamps():
    """The lamps, the plate, the grille and the cockpit screen."""
    m = materials
    m.pbr("M_AmberMarker", paths.AMBER, rough=0.30, emission=paths.AMBER,
          emission_strength=2.0, uv_m=EXT, tile=0.03,
          normal_map=paths.tex("lens_nor.png"), uv="UVMap")
    m.pbr("M_RedReflector", "#B00012", rough=0.20, uv_m=EXT, tile=0.03,
          normal_map=paths.tex("lens_nor.png"), uv="UVMap")
    # the strength is the brief's 10: the lens (linear 0.155) reaches 1.55 and
    # the 6 mm core reaches 10, so both bloom (ART §4: the HDR threshold is 1.1)
    # the strength is the brief's 10: the lens (linear 0.155) reaches 1.55 and
    # the 6 mm core reaches 10, so both bloom (ART §4: the HDR threshold is
    # 1.1): the lens stays a saturated red and the core goes pink-white, which
    # is what photo 19 shows.
    m.pbr("M_LightBarRear", paths.RED_BAR, rough=0.20, emission=paths.RED_BAR,
          emission_strength=10.0, base_map=paths.tex("lightbar_rear.png"))
    m.pbr("M_LightBarFront", paths.WHITE_BAR, rough=0.20, emission=paths.WHITE_BAR,
          emission_strength=8.0, base_map=paths.tex("lightbar_front.png"))
    m.pbr("M_Jewel", paths.WHITE_BAR, rough=0.20, emission=paths.WHITE_BAR,
          emission_strength=8.0, base_map=paths.tex("lightbar_front.png"))
    # the brake light is 1 mm proud of the bar (no z-fighting) and keeps a weak
    # red emission of its own, so the middle of the bar still reads as red
    m.pbr("M_BrakeLight", paths.RED_BAR, rough=0.20, emission=paths.RED_BAR,
          emission_strength=2.5, base_map=paths.tex("brakelight.png"))
    m.pbr("M_Plate", "#E8E8E8", rough=0.35, base_map=paths.tex("plate.png"),
          normal_map=paths.tex("plate_nor.png"))
    m.pbr("M_Grille", "#0B0B0C", rough=0.50, base_map=paths.tex("fan_grille.png"),
          alpha_from_map=True)
    m.pbr("M_Screen", "#120608", rough=0.15, emission="#FF2A2A", emission_strength=2.0,
          base_map=paths.tex("screen_ui.png"))
