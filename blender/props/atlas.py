"""Shared texture-atlas layout for the props unit.

Same pattern as the npc_cars unit: one layout module that both the PIL generator
(`tools/signs/prop_atlas.py`) and the Blender builders read, so the UV rects can
never drift apart.

Rects are (x0, y0, x1, y1) in image pixels with y measured downwards from the top.
`uv_rect(rect, size)` converts one to the GL UV box (v flipped).

  SURFACE table - every surface of every prop is one of four TILEABLE families
    (metal, mineral, panel, bark).  A family is a 1024 px texture set that
    covers FAMILY_METRES metres of surface, and the UV of a part is its metre
    coordinates divided by that, so the texture repeats without a seam and the
    detail density (512 px/m) never changes with the size of the part.
    The colour of a part comes from its VERTEX TINT: the family texture is a
    neutral light grey and the tint carries the sRGB target colour.
  SIGN atlas    - every printed board, shelf packed from the list below.
"""
import os

TEX_DIR = os.path.expanduser("~/m/skyrush/game/assets/props/textures")

# ----------------------------------------------------------------- surfaces
# One family tile = FAMILY_METRES metres of surface at 512 px/m.
FAMILY_METRES = 2.0
FAMILY_PX = 1024

# The mean LINEAR luminance every family texture is normalised to.  The tints
# below divide by it, so a tint of 1.0 keeps the texture's own brightness.
BASE_LINEAR = {"metal": 0.75, "mineral": 0.75, "panel": 0.75, "bark": 0.75,
               "paint": 0.85}

# name -> (family, target sRGB hex, material key)
# The material key is the family, except for the surfaces that need their own
# material (the lit canopy soffit) or a different FINISH: the `paint` family
# is a dielectric (metallic 0.0) with its own texture set, so a painted booth
# does not mirror the night sky the way a bare metal one does.
SURFACE = {
    "galv":         ("metal", "#8E9297", "metal"),
    "steel_dark":   ("metal", "#3A3D42", "metal"),
    "steel":        ("metal", "#5A5F66", "metal"),
    "black":        ("metal", "#111113", "metal"),
    "hi_vis":       ("metal", "#F2C200", "metal"),
    "cast_iron":    ("metal", "#1C1C1E", "metal"),
    "alu":          ("metal", "#D7DADD", "metal"),
    "silver":       ("metal", "#A7ACB1", "metal"),
    "rusty":        ("metal", "#7A5240", "metal"),
    "scuffed":      ("metal", "#9C9890", "metal"),
    "chrome":       ("metal", "#C8CCD2", "metal"),
    "plastic":      ("metal", "#22242A", "metal"),
    # painted finishes: dielectric, with chips that show the grey primer
    "white_paint":  ("paint", "#EDEDE8", "paint"),
    "red_paint":    ("paint", "#E60012", "paint"),
    "orange":       ("paint", "#D85A10", "paint"),
    "yellow":       ("paint", "#E6B800", "paint"),
    "green":        ("paint", "#2A4A32", "paint"),
    "teal":         ("paint", "#2FA898", "paint"),
    "gold":         ("paint", "#D8A81E", "paint"),
    "blue":         ("paint", "#3A6BB0", "paint"),
    "charge_teal":  ("paint", "#00A6A6", "paint"),
    "white_plastic": ("paint", "#EDEDE8", "paint"),
    "black_plastic": ("paint", "#22242A", "paint"),
    "rubber":       ("paint", "#191A1D", "paint"),
    "concrete":     ("mineral", "#BDB7AA", "mineral"),
    "pavement":     ("mineral", "#BDB9B1", "mineral"),
    "asphalt":      ("mineral", "#3A3C42", "mineral"),
    "kerb":         ("mineral", "#B9BBB6", "mineral"),
    "soil":         ("mineral", "#3A2C20", "mineral"),
    "bay_green":    ("mineral", "#1E9E5A", "mineral"),
    "bay_line":     ("mineral", "#EDEDE8", "mineral"),
    "forecourt":    ("mineral", "#8F8C86", "mineral"),
    "polish":       ("mineral", "#7E7B76", "mineral"),
    "stain":        ("mineral", "#3A3833", "mineral"),
    "pot_white":    ("mineral", "#EDEDE8", "mineral"),
    "acp":          ("panel", "#C9CCD1", "panel"),
    "canopy":       ("panel", "#AEB4BA", "panel"),
    "soffit":       ("panel", "#E8E8E6", "soffit"),
    "facade":       ("panel", "#D8D4CC", "panel"),
    "bark":         ("bark", "#FFFFFF", "bark"),
}


def _srgb_to_linear(c):
    """sRGB 0..1 -> linear 0..1."""
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _tint(hex_colour):
    """#RRGGBB -> sRGB triple in 0..1."""
    h = hex_colour.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def surface_family(name):
    """The tileable family a surface belongs to ("metal", "mineral", ...)."""
    return SURFACE[name][0]


def surface_material(name):
    """The material key of a surface (the family, or "soffit" for the lit one)."""
    return SURFACE[name][2]


def surface_tint(name):
    """The vertex tint of a surface: the linear target colour over the family base.

    The family texture is a neutral light grey (BASE_LINEAR), so the tint is
    the ratio between the wanted linear colour and that base.
    """
    family, hex_colour, _ = SURFACE[name]
    if family == "bark":
        return (1.0, 1.0, 1.0)          # the bark texture carries its own colour
    base = BASE_LINEAR[family]
    return tuple(min(1.0, _srgb_to_linear(c) / base) for c in _tint(hex_colour))


# ----------------------------------------------------------------- foliage
FOLIAGE_SIZE = 1024
FOLIAGE = {
    "plane":        (0, 0, 512, 512),
    "bougainvillea": (512, 0, 1024, 512),
    "privet":       (0, 512, 512, 1024),
    "rose":         (512, 512, 1024, 1024),
}


def foliage_uv(quad, u0, v0, u1, v1):
    """A random sub-rect of a foliage quadrant, in atlas UV."""
    x0, y0, x1, y1 = FOLIAGE[quad]
    w = (x1 - x0)
    h = (y1 - y0)
    du = (u1 - u0) * w / float(FOLIAGE_SIZE)
    dv = (v1 - v0) * h / float(FOLIAGE_SIZE)
    return (x0 / float(FOLIAGE_SIZE) + u0 * du, y0 / float(FOLIAGE_SIZE) + v0 * dv,
            x0 / float(FOLIAGE_SIZE) + u1 * du, y0 / float(FOLIAGE_SIZE) + v1 * dv)


# ----------------------------------------------------------------- markings
# The UV boxes of the two cells of the road-marking sheet (1024 x 256, the
# cells 512 x 240 with an 8 px guard): a lane arrow and the green ETC marking.
MARK_V0 = 8.0 / 256.0
MARK_V1 = 248.0 / 256.0
ARROW_UV = (0.0, MARK_V0, 0.5, MARK_V1)
ETC_UV = (0.5, MARK_V0, 1.0, MARK_V1)


# ----------------------------------------------------------------- signs
# name -> (pixel width, pixel height) of the board inside the atlas. The panel size
# in metres is in SIGNS_M; the ratio fixes the texel density.
SIGN_W, SIGN_H = 4096, 2560

SIGN_SOURCES = {
    "guide_yanan":         (768, 440),
    "guide_bund":          (768, 440),
    "guide_exit_xizang":   (768, 440),
    "guide_bridges":       (768, 440),
    "guide_airport":       (768, 440),
    "guide_tunnel":        (768, 440),
    "guide_skid":          (768, 440),
    "toll_fascia":         (2048, 205),
    "gas_fascia":          (2048, 128),
    "gas_logo":            (256, 96),
    "gas_pylon_crown":     (512, 296),
    "skylane_gantry_sign": (1024, 307),
    "skylane_pad_arrow":   (128, 366),
    "billboard_ad":        (1024, 512),
    "vms_congestion":      (1024, 320),
    "neon_blade":          (192, 640),
    "roadname_xianggang":  (640, 213),
    "gas_store_band":      (768, 77),
    "toll_lane_etc":       (512, 160),
    "toll_lane_mixed":     (512, 160),
    "toll_etc_strip":      (384, 64),
    "toll_signal_red":     (256, 256),
    "toll_signal_green":   (256, 256),
    "barrier_arm":         (512, 24),
    "billboard_led":       (64, 64),        # solid white LED bar
    "warm_led":            (64, 64),        # warm white LED panel
    "billboard_cyan":      (64, 64),        # solid cyan LED line
    "billboard_magenta":   (64, 64),        # solid magenta LED line
    "billboard_green":     (64, 64),        # solid green LED line
    "billboard_amber":     (64, 64),        # solid amber LED bar
    "billboard_red":       (64, 64),        # solid red LED bar
    "billboard_blue":      (64, 64),        # solid blue LED bar
    "bus_ad":              (384, 576),
    "bus_route":           (352, 512),
    "metro_totem":         (256, 768),
    "police_board":        (384, 256),
    "countdown_23":        (256, 154),
    "countdown_08":        (256, 154),
    "gas_price_board":     (256, 341),
    "charge_totem":        (128, 747),
    "charge_bolt":         (256, 400),
    "charge_post_volta":   (256, 170),
    "charge_kw_500":       (512, 233),
    "digital_battery":     (192, 115),
    "fuel_price":          (256, 151),
    "projector_screen":    (512, 363),
    "bin_label":           (256, 163),
    "spike_label":         (256, 68),
}
for _i in range(1, 13):
    SIGN_SOURCES["bay_number_%02d" % _i] = (128, 128)


SIGN_PAD = 8          # guard band so the mip levels never pull in a neighbour


def pack_rects(sources, width, height, pad=2, guard=SIGN_PAD):
    """Shelf-pack `sources` (name -> (w, h)) into a `width` x `height` atlas.

    Each item gets a `guard` band of its own edge colour around it, so the mip
    levels of a small board cannot pull in the board next to it. The returned rect
    is the board itself, not the padded cell.

    Returns {name: (x0, y0, x1, y1)}. Deterministic: the items are packed in the
    order they are given, tallest first within each shelf.
    """
    order = sorted(sources.items(), key=lambda kv: (-kv[1][1], -kv[1][0], kv[0]))
    rects = {}
    cells = {}
    x = y = shelf = 0
    for name, (w, h) in order:
        cw, ch = w + 2 * guard, h + 2 * guard
        if x + cw + pad > width:
            x = 0
            y += shelf + pad
            shelf = 0
        if y + ch + pad > height:
            raise ValueError("prop sign atlas overflow at %s" % name)
        cells[name] = (x, y, x + cw, y + ch)
        rects[name] = (x + guard, y + guard, x + guard + w, y + guard + h)
        x += cw + pad
        shelf = max(shelf, ch)
    return rects, cells


SIGN_RECTS, SIGN_CELLS = pack_rects(SIGN_SOURCES, SIGN_W, SIGN_H)


def uv_rect(rect, size):
    """Image-pixel rect -> (u0, v0, u1, v1) with v pointing up.

    `size` is either a single number (square atlas) or a (width, height) pair.
    """
    x0, y0, x1, y1 = rect
    w, h = size if isinstance(size, (tuple, list)) else (size, size)
    if x1 <= x0 or y1 <= y0:
        return (0.0, 0.0, 0.0, 0.0)
    # The rect is given in image space (y downwards from the top), but a UV box
    # has V pointing up: the board would come out mirrored, so the V range is
    # flipped here. The exporter and the importer each flip V once more, which
    # cancels out.
    return (x0 / w, 1.0 - y1 / h, x1 / w, 1.0 - y0 / h)


def family_uv(u, v, metres=FAMILY_METRES):
    """Metre coordinates -> the UV of a tileable family (no modulo, no atlas).

    The texture repeats by itself, so the UV is simply the position in tile
    units.  This is what keeps the texel density at 512 px/m on every part,
    whatever its size: a 7 m arm samples 3.5 tiles, not one texel column.
    """
    return (u / metres, v / metres)


def sign_uv(name, size=(SIGN_W, SIGN_H)):
    """UV box of one board inside the sign atlas."""
    return uv_rect(SIGN_RECTS[name], size)
