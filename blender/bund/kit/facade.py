"""Facade generation for the Bund buildings (bund unit).

Local frame of a building: +X = the facade normal (towards the river), +Y = south along the
row, +Z = up, origin at the centre of the facade on the ground. The facade wall is 0.35 m
thick, so every window is a real opening with a reveal; the mass behind the four walls is
inset far enough that no pane of glass is ever buried inside it.
"""
from .. import data
from . import profiles, walls

WALL_T = walls.WALL_T          # the facade wall thickness = the window reveal depth
MASS_INSET_X = 0.40            # the core sits this far behind the front / rear wall face
MASS_INSET_Y = 0.75            # ... and behind the side wall faces
TINT_STEP = 1.5                # the tint is diced at this cell size (the lead: 1.5 m)
BASE_BLOCK = 1.2               # the width of a rusticated block
SHOP_GLASS_X = 0.05            # the shopfront glass, 0.3 m inside the base course


def _solid_spans(a, b, holes):
    """The parts of [a, b] that are not inside one of the `holes` (a, b) ranges."""
    spans = []
    cur = a
    for ha, hb in sorted(holes):
        ha = max(a, ha)
        hb = min(b, hb)
        if hb <= ha:
            continue
        if ha > cur:
            spans.append((cur, ha))
        cur = max(cur, hb)
    if cur < b:
        spans.append((cur, b))
    return spans


def shell(asm, s, rng, mass_h=None, portal=True, shopfronts=True):
    """Main mass, rusticated base, side and rear elevations."""
    w, d = s["frontage"], s["depth"]
    mass_h = mass_h if mass_h is not None else s["height"]
    base_h = s["base_h"]
    pw = min(5.0, w * 0.22)
    # the solid core behind the four walls: inset so that no glass is buried inside it
    asm.box("stone", (-d * 0.5, 0.0, mass_h * 0.5),
            (d - 2 * MASS_INSET_X, w - 2 * MASS_INSET_Y, mass_h))
    # the ground floor: a rusticated base with tall shopfront openings
    openings = []
    if portal:
        openings.append((-pw * 0.5, pw * 0.5))
    if shopfronts:
        n = max(2, int((w - pw) / 4.6))
        step = (w - pw) / n
        for i in range(n):
            yc = -w * 0.5 + pw + (i + 0.5) * step
            if abs(yc) < pw:
                continue
            openings.append((yc - 1.3, yc + 1.3))
    _rustication(asm, s, openings)
    # the shopfronts: a lit lobby behind the reveal. The ground floor of the Bund is
    # banks, hotels and shops, so the glazing is warm and never a black hole (B-ART4).
    for k, (a, b) in enumerate(openings):
        if portal and abs((a + b) * 0.5) < 0.01:
            continue
        lit = rng.random() < 0.62
        role = "glasslit" if lit else "glassdark"
        # the shopfronts show a lobby, not a shelf: the lamp cells of the atlas
        cell = (2, 6, 11, 15)[k % 4]
        u0 = (cell % 4) * 0.25
        v0 = (cell // 4) * 0.25
        asm.quad_uv(role, [(SHOP_GLASS_X, a, 0.12), (SHOP_GLASS_X, b, 0.12),
                           (SHOP_GLASS_X, b, base_h * 0.86),
                           (SHOP_GLASS_X, a, base_h * 0.86)],
                    [(u0, v0), (u0 + 0.25, v0), (u0 + 0.25, v0 + 0.25), (u0, v0 + 0.25)])
        # the stall riser under the glass and the transom over it
        asm.box("stone", (0.16, (a + b) * 0.5, base_h * 0.55), (0.24, b - a + 0.3, 0.3))
        asm.box("stone", (0.10, (a + b) * 0.5, base_h * 0.90), (0.30, b - a + 0.3, 0.24))
    _side_wall(asm, s, rng, 1.0, mass_h)
    _side_wall(asm, s, rng, -1.0, mass_h)
    _rear_wall(asm, s, rng, mass_h)
    # roof deck
    asm.box("roof", (-d * 0.5, 0.0, mass_h - 0.1), (d, w, 0.2))


def _rustication(asm, s, openings):
    """The base course: 1.2 m blocks with 0.15 m V-grooves between them.

    The arris of every block is chamfered at 45 deg, so the joint reads as a groove with
    a real shadow instead of a hairline crack (B-ART2 asks for 0.15 m grooves)."""
    w = s["frontage"]
    base_h = s["base_h"]
    z, course = 0.0, data.BASE_COURSE_H
    while z < base_h - 0.01:
        hgt = min(course, base_h - z)
        out = data.BASE_PROJ_A if int(round(z / course)) % 2 == 0 else data.BASE_PROJ_B
        for a, b in _solid_spans(-w * 0.5, w * 0.5, openings):
            n = max(1, int(round((b - a) / BASE_BLOCK)))
            step = (b - a) / n
            for k in range(n):
                y0 = a + k * step
                y1 = a + (k + 1) * step
                if y1 - y0 < 0.25:
                    continue
                asm.chamfered_box("stone", ((out - WALL_T) * 0.5, (y0 + y1) * 0.5, z + hgt * 0.5),
                                   (out + WALL_T, y1 - y0, hgt),
                                   chamfer=data.BASE_V_GROOVE * 0.5, depth=data.BASE_V_DEPTH)
        z += hgt


def _floor_holes(s, mass_h, along, pitch, half, z0, z1):
    """The window openings of one storey along an elevation."""
    holes = []
    n = max(1, int(round(along / pitch)))
    for i in range(n):
        c = -along * 0.5 + (i + 0.5) * (along / n)
        holes.append((c, half, z0, z1))
    return holes


def _side_wall(asm, s, rng, sign, mass_h):
    """The flank elevation: a real wall with the floor rhythm of the front."""
    w, d = s["frontage"], s["depth"]
    fh, base_h = s["floor_h"], s["base_h"]
    plane = sign * w * 0.5
    # the plinth of the flank
    asm.gbox("stone", (-d * 0.5, sign * (w * 0.5 - 0.10), base_h * 0.5),
             (d, 0.50, base_h), TINT_STEP)
    holes = []
    for f in range(s["floors"]):
        z0 = base_h + f * fh
        if z0 > mass_h - 1.4:
            break
        z1 = min(z0 + fh, mass_h)
        sz = z0 + data.WIN_SILL
        hz = sz + min(data.WIN_H, (z1 - z0) - data.WIN_SILL - 0.35)
        if hz - sz < 0.8:
            continue
        holes += _floor_holes(s, mass_h, d - 4.0, 4.4, 0.78, sz, hz)
    for i, h in enumerate(holes):
        h = (h[0] - (d - 4.0) * 0.5 - 2.0, h[1], h[2], h[3])
        holes[i] = h
    walls.opening_wall(asm, "stone", "glasslit", plane, "Y", sign, -d, 0.0, base_h, mass_h,
                       holes, proud=0.14, rng=rng, lit_fraction=data.SIDE_LIT_FRACTION,
                       cell_base=3 if sign > 0 else 7)
    # a cornice band on the flank so the mass reads as a building from the side street
    asm.gbox("stone", (-d * 0.5, sign * (w * 0.5 + 0.20), s["cornice"] - 0.45),
             (d, 0.5, 0.9), TINT_STEP)


def _rear_wall(asm, s, rng, mass_h):
    """The rear elevation: simpler than the front, but a real wall with windows."""
    w, d = s["frontage"], s["depth"]
    fh, base_h = s["floor_h"], s["base_h"]
    holes = []
    for f in range(s["floors"]):
        z0 = base_h + f * fh
        if z0 > mass_h - 1.4:
            break
        z1 = min(z0 + fh, mass_h)
        sz = z0 + data.WIN_SILL
        hz = sz + min(data.WIN_H, (z1 - z0) - data.WIN_SILL - 0.35)
        if hz - sz < 0.8:
            continue
        holes += _floor_holes(s, mass_h, w - 2 * WALL_T, 3.2, 0.7, sz, hz)
    walls.opening_wall(asm, "stone", "glasslit", -d, "X", -1.0,
                       -(w * 0.5 - WALL_T), w * 0.5 - WALL_T, base_h, mass_h,
                       holes, proud=0.12, rng=rng, lit_fraction=data.SIDE_LIT_FRACTION,
                       cell_base=11)
    asm.gbox("stone", (-d - 0.15, 0.0, s["cornice"] - 0.45), (0.6, w + 0.5, 0.9), TINT_STEP)


def front_wall(asm, s, rng, band=None, mass_h=None):
    """The elevation itself: spandrels, piers, window openings, surrounds and sills."""
    w = s["frontage"]
    base_h, fh = s["base_h"], s["floor_h"]
    mass_h = mass_h if mass_h is not None else s["cornice"]
    bays = s["bays"]
    pitch = w / bays
    win_w = min(pitch * 0.45, data.WIN_W)
    classical = s["style"] in ("baroque", "classic", "renaissance", "neoclassic", "eclectic",
                               "gothic", "jwest", "colonial")
    n = s["floors"]
    while n > 1 and base_h + n * fh > mass_h + 0.01:
        n -= 1
    for f in range(n):
        z0 = base_h + f * fh
        z1 = base_h + (f + 1) * fh if f < n - 1 else mass_h
        span = z1 - z0
        win_h = min(data.WIN_H, span - data.WIN_SILL - 0.30)
        sz = z0 + data.WIN_SILL
        hz = sz + win_h
        asm.gbox("stone", (-WALL_T * 0.5, 0.0, (z0 + sz) * 0.5), (WALL_T, w, sz - z0), TINT_STEP)
        asm.gbox("stone", (-WALL_T * 0.5, 0.0, (hz + z1) * 0.5), (WALL_T, w, z1 - hz), TINT_STEP)
        if band:
            asm.gbox(band, (-0.18, 0.0, z0 + 0.26), (0.44, w, 0.52), TINT_STEP)
        edges = [-w * 0.5]
        for i in range(bays):
            yc = -w * 0.5 + (i + 0.5) * pitch
            edges.append(yc - win_w * 0.5)
            edges.append(yc + win_w * 0.5)
        edges.append(w * 0.5)
        for i in range(0, len(edges) - 1, 2):
            a, b = edges[i], edges[i + 1]
            if b - a > 0.02:
                asm.gbox("stone", (-WALL_T * 0.5, (a + b) * 0.5, (sz + hz) * 0.5),
                         (WALL_T, b - a, hz - sz), TINT_STEP)
        for i in range(bays):
            yc = -w * 0.5 + (i + 0.5) * pitch
            _window(asm, s, rng, yc, win_w, sz, hz, classical, cell=(f * bays + i) % 16)
        if f > 0 and classical:
            asm.prism_trim("trim", profiles.string_course(0.30, 0.20), -w * 0.5, w * 0.5,
                           profiles.BAND_STRING, tile=1.5, z_off=z0 - 0.15)
    if classical:
        # the pilasters between the bays: the vertical rhythm of the elevation
        s.setdefault("pilasters", [])
        for i in range(1, bays):
            yc = -w * 0.5 + i * pitch
            s["pilasters"].append((yc, 0.45))
            asm.gbox("stone", (0.18, yc, (base_h + mass_h) * 0.5),
                     (0.36, 0.8, mass_h - base_h), TINT_STEP)
            asm.box("stone", (0.20, yc, base_h + 0.30), (0.42, 1.0, 0.6))
            asm.box("stone", (0.21, yc, mass_h - 0.45), (0.44, 1.05, 0.5))
            asm.box("stone", (0.22, yc, mass_h - 0.15), (0.48, 1.15, 0.3))


def _window(asm, s, rng, yc, win_w, sz, hz, classical, cell=0):
    """One window: the glass (an interior-atlas cell), the glazing bars, the surround, the
    sill and - on the piano nobile - a pediment."""
    lit = rng.random() < data.LIT_FRACTION
    mat = "glasslit" if lit else "glassdark"
    x = -data.WIN_RECESS
    y0, y1 = yc - win_w * 0.5, yc + win_w * 0.5
    u0 = (cell % 4) * 0.25
    v0 = (cell // 4) * 0.25
    asm.quad_uv(mat, [(x, y0, sz), (x, y1, sz), (x, y1, hz), (x, y0, hz)],
                [(u0, v0), (u0 + 0.25, v0), (u0 + 0.25, v0 + 0.25), (u0, v0 + 0.25)])
    # the dark bronze glazing bars: two mullions and a transom
    m = data.MULLION
    for f in (1.0 / 3.0, 2.0 / 3.0):
        asm.box("iron", (x + 0.02, y0 + win_w * f, (sz + hz) * 0.5), (0.05, m, hz - sz))
    asm.box("iron", (x + 0.02, yc, sz + (hz - sz) * 0.62), (0.05, win_w, m))
    if not classical:
        return
    jw = data.JAMB
    asm.box("stone", (0.09, y0 - jw * 0.5, (sz + hz) * 0.5), (0.18, jw, hz - sz))
    asm.box("stone", (0.09, y1 + jw * 0.5, (sz + hz) * 0.5), (0.18, jw, hz - sz))
    asm.box("stone", (0.10, yc, hz + 0.17), (0.20, win_w + jw * 2.0, 0.34))
    asm.prism_trim("trim", profiles.sill(0.34, 0.17, 0.12), y0 - 0.34, y1 + 0.34,
                   profiles.BAND_SILL, tile=1.5, z_off=sz - 0.17)
    if win_w > 1.3:
        asm.box("stone", (0.14, yc, hz + 0.40), (0.24, 0.42, 0.26))   # the keystone
        if (hz - sz) > 2.0:
            _pediment(asm, yc, win_w, hz, int(abs(yc) * 10) % 2 == 0)


def _pediment(asm, yc, win_w, hz, triangular):
    """The window head: a real triangular pediment alternating with a segmental arch.

    The tympanum is a solid wedge in the (y, z) plane with a raking cornice around it -
    not a painted box."""
    half = win_w * 0.5 + 0.34
    if triangular:
        outline = [(yc - half, hz + 0.30), (yc + half, hz + 0.30),
                   (yc, hz + 0.30 + half * 0.42)]
        cornice = [(yc - half - 0.18, hz + 0.22), (yc + half + 0.18, hz + 0.22),
                   (yc, hz + 0.22 + (half + 0.18) * 0.42)]
        asm.prism_x("stone", cornice, -0.02, 0.16)
        asm.prism_x("stone", outline, 0.10, 0.30)
    else:
        rise = 0.34
        band = profiles.segmental_band(yc - half, yc + half, hz + 0.24, rise, 0.20)
        tymp = profiles.segmental_fill(yc - half, yc + half, hz + 0.24, rise)
        asm.prism_x("stone", band, -0.02, 0.18)
        asm.prism_x("stone", tymp, 0.12, 0.30)
    asm.box("stone", (0.16, yc, hz + 0.44), (0.26, 0.40, 0.30))     # the keystone
