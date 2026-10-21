"""Assemble the 25 Bund buildings (bund unit).

Every building is built in its own local frame (+X = the facade normal towards the river,
+Y = south along the row, +Z = up) and then placed on the Bund road with the yaw of the
road at its Z, so the row follows the curve of Zhongshan East 1st Road.
"""
import math
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

from lib import common, geo

from . import ao, data, wash
from .kit import assembly, columns, crowns, facade, profiles, roofs, trim, walls


def roles_for(s, mats):
    """Role -> material for one building (the kit speaks in roles: stone, glass, ...)."""
    fam, hue = s["stone_family"], s["colour"]
    stone = (mats["stone_granite_%s_v%d" % (hue, s["no"] % 3)] if fam == "granite"
             else mats["stone_%s_%s" % (fam, hue)])
    r = {
        "stone": stone,
        "glassdark": mats["glassdark"],
        "glasslit": mats["glasslit"],
        "iron": mats["iron"],
        "roof": mats["roof"],
        "dome": mats["dome"],
        "rooflit": mats["rooflit"],
        "tileteal": mats["tileteal"],
        "clock": mats["clock"],
        "red": mats["red"],
        "goldstrip": mats["goldstrip"],
        "trim": mats["trim"],
        "brick": mats["stone_brick_brick_band"],
        "wash": mats["wash"],
        "washcrown": mats["washcrown"],
    }
    if s["roof"] == "clock_tower":
        # the clock stage is the brightest thing on the row: it glows like the domes
        r["clockstone"] = mats["clockstone"]
    band = s["opts"].get("bands")
    if band == "white":
        r["band"] = mats["stone_granite_white_v0"]
    elif band == "brick_band":
        r["band"] = mats["stone_brick_brick_band"]
    return r


def build_one(s, col, mats, seed, cell=None):
    """Build one Bund building; returns its parent node."""
    rng = random.Random(seed)
    roles = roles_for(s, mats)
    asm = assembly.Assembly(s["node"])
    mass_h = 40.0 if s["roof"] == "ziggurat" else s["cornice"]
    facade.shell(asm, s, rng, mass_h=mass_h)
    facade.front_wall(asm, s, rng, band="band" if "band" in roles else None, mass_h=mass_h)
    trim.cornice(asm, s)
    trim.entrance(asm, s)
    _style(asm, s, rng)
    _roof(asm, s, rng)
    # the AO / dirt / macro variation and the per-building hue go into COLOR_0
    hue = s["colour"]
    asm.tint("stone", lambda co: ao.facade_tint(s, co, hue))
    asm.tint("band", lambda co: ao.facade_tint(s, co, "white"))
    asm.tint("dome", lambda co: ao.facade_tint(s, co, hue))
    asm.tint("trim", lambda co: ao.facade_tint(s, co, hue))
    # the flag on the roof (kept inside the building's dossier height)
    flag_h = max(1.5, min(9.0, s["height"] - s["cornice"] - 0.6))
    trim.flag(asm, -s["depth"] * 0.45, s["frontage"] * 0.32, s["cornice"] + 0.4, flag_h)
    # the far-field wash: the facade card that samples the baked light map
    wash.build(asm, s, cell)
    parent = bpy.data.objects.new(s["node"], None)
    parent.empty_display_type = "PLAIN_AXES"
    parent.empty_display_size = 1.5
    yaw = data.facade_yaw(s["z"])
    bx, by = data.to_blender(s["front_x"], s["z"])
    parent.matrix_world = (Matrix.Translation(Vector((bx, by, 0.0)))
                            @ Matrix.Rotation(yaw, 4, "Z"))
    common.link(parent, col)
    bpy.context.view_layer.update()
    asm.to_objects(col, roles, parent)
    _collider(s, col, parent)
    return parent


def _collider(s, col, parent):
    """A convex collider box for the building mass (front wall + depth)."""
    bm = bmesh.new()
    w, d, h = s["frontage"], s["depth"], s["height"]
    geo.box(bm, (-d * 0.5, 0.0, h * 0.5), (d, w, h))
    obj = common.mesh_object("%s-convcolonly" % s["node"], bm, col)
    obj.parent = parent
    return obj


def _style(asm, s, rng):
    """Style-specific facade features."""
    o = s["opts"]
    style = s["style"]
    if o.get("portico"):
        trim.portico(asm, s, o.get("columns", "ionic"))
    if o.get("columns") and not o.get("portico"):
        _colonnade(asm, s, o)
    if style == "gothic":
        crowns.gables(asm, s, 3)
        crowns.arcade(asm, s)
    if style == "deco":
        crowns.deco_fins(asm, s)
    if o.get("attic"):
        trim.attic(asm, s, rng, o["attic"])
    if style == "baroque" and s["roof"] == "attic_pediment":
        crowns.attic_pediment(asm, s)
    if o.get("balcony"):
        crowns.balcony_run(asm, s, floors=(1, 2))
    if style in ("neoclassic", "classic") and not o.get("portico"):
        _corner_pilasters(asm, s)
    if s["style"] == "jwest":
        _corner_pilasters(asm, s, 0.9)


def _colonnade(asm, s, o):
    """A row of free-standing columns across the facade."""
    n = o.get("col_bays", 4)
    w = s["frontage"]
    span = w * 0.62
    y0 = -span * 0.5
    order = o.get("columns", "ionic")
    asm.box("stone", (1.5, 0.0, 0.35), (3.6, span + 4.0, 0.7))
    ch = s["base_h"] * 0.95
    for i in range(n):
        y = y0 + i * (span / max(1, n - 1))
        columns.column(asm, "stone", 1.6, y, 0.7, ch, order, fluted=True)
    prof = profiles.cornice(1.1, 0.85)
    asm.prism("stone", prof, y0 - 1.6, y0 + span + 1.6, x_off=1.6, z_off=0.7 + ch)


def _corner_pilasters(asm, s, width=1.5):
    """Pilasters at the two ends of the facade, framing the elevation."""
    w = s["frontage"]
    for sy in (-1.0, 1.0):
        columns.pilaster(asm, "stone", 0.0, sy * (w * 0.5 - width * 0.5), s["base_h"],
                         s["cornice"], width, 0.42)


def _crown(s, pos, aim):
    """Record a crown flood: where it stands and what it washes.

    The crown's own form carries the far-field wash (a shell, 2 % bigger): a flat card
    would float outside the silhouette of a dome and read as a halo."""
    s.setdefault("crown", []).append({"pos": pos, "aim": aim})


def _shell(s, prims):
    """Record the shell of a crown form (the wash that follows its shape)."""
    s.setdefault("shell", []).extend(prims)


def _roof(asm, s, rng):
    """The roof cue of the building (dossier 5.3 'roof cue' column).

    Every roof also records its crown floods: the lights that wash the attic, the dome,
    the tower or the pyramid, mounted on the roof behind the parapet (见光不见灯), and
    the shell that carries the far-field wash on the crown's own form."""
    r = s["roof"]
    d, w = s["depth"], s["frontage"]
    if r == "dome_drum":
        x = -min(8.0, d * 0.15)
        roofs.dome_drum(asm, s, x, 0.0)
        trim.balustrade_run(asm, 0.0, -w * 0.5, w * 0.5, s["cornice"] + 0.2, mat="stone")
        z0 = s["cornice"] + 2.4
        zd = z0 + 5.5 + 0.75
        _shell(s, [("cyl", x, 0.0, z0, 6.55, 6.25, 0.0, 0.30),
                   ("dome", x, 0.0, zd, 6.40, 7.04, 0.30, 1.0)])
        for sy in (-1.0, 1.0):
            pos = (x + 7.0, sy * 5.0, s["cornice"] + 6.0)
            _crown(s, pos, (x, 0.0, s["cornice"] + 12.0))
    elif r == "clock_tower":
        x = -d * 0.35
        roofs.clock_tower(asm, s, x, 0.0)
        z = s["cornice"]
        _shell(s, [("box", x, 0.0, z, 12.8, 12.8, 19.2, 0.0, 0.55),
                   ("box", x, 0.0, z + 19.2, 11.6, 11.6, 6.6, 0.92, 1.0),
                   ("box", x, 0.0, z + 25.8, 5.1, 5.1, 10.4, 0.55, 0.88)])
        for sy in (-1.0, 1.0):
            pos = (x + 6.0, sy * 5.0, s["cornice"] + 18.0)
            _crown(s, pos, (x, 0.0, s["cornice"] + 22.5))
        # the shaft of the tower is gold from the roof to the clock stage: four floods
        # stand at its foot, one per face, and wash it up (review r3, Customs House)
        hx = 6.4
        for face in range(4):
            a = face * math.pi * 0.5
            pos = (x + (hx + 0.9) * math.cos(a), (hx + 0.9) * math.sin(a), z + 1.0)
            aim = (x + hx * math.cos(a), hx * math.sin(a), z + 22.0)
            _crown(s, pos, aim)
    elif r == "pyramid":
        # the Peace Hotel: a narrow stepped tower with the copper pyramid on top
        half = 8.0
        tx = -min(10.0, d * 0.12)
        tower_h = s["opts"].get("tower_h", 13.0)
        py_h = s["opts"]["pyramid"]
        roofs.stepped_tower(asm, s, tx, 0.0, s["cornice"], s["cornice"] + tower_h, half)
        roofs.pyramid_roof(asm, s, tx, 0.0, s["cornice"] + tower_h, py_h, half, half)
        # the shaft under the pyramid is gold stone like the rest of the row
        _shell(s, [("box", tx, 0.0, s["cornice"], 16.0, 16.0, tower_h, 0.10, 0.55)])
        for sy in (-1.0, 1.0):
            pos = (tx + 7.0, sy * 5.0, s["cornice"] + tower_h - 1.0)
            # the pyramid carries its own teal glow (the copper's emission map), so it
            # gets no gold wash shell - the crown has to stay green
            _crown(s, pos, (tx, 0.0, s["cornice"] + tower_h + 7.0))
    elif r == "chinese_hip":
        # the Bank of China: the roof sits just behind the facade, clear of the parapet
        rh = s["opts"]["chinese_roof"]
        roofs.chinese_roof(asm, s, -4.0, 0.0, s["cornice"] + 1.8, rh, 8.0, 11.0)
        crowns.deco_crown(asm, s, -4.0, 0.0, s["cornice"])
        _shell(s, [("box", -4.0, 0.0, s["cornice"], 3.6, w, 2.6, 0.20, 0.60)])
        for sy in (-1.0, 1.0):
            pos = (-1.0, sy * 7.0, s["cornice"] + 1.0)
            # the blue-green tile roof keeps its colour: no gold wash on it
            _crown(s, pos, (-4.0, 0.0, s["cornice"] + 6.0))
    elif r == "cupolas":
        ch = max(2.0, min(4.2, s["height"] - s["cornice"] - 0.8))
        for sy in (-1.0, 1.0):
            roofs.cupola(asm, -d * 0.3, sy * w * 0.33, s["cornice"], height=ch)
        trim.roof_clutter(asm, s, rng)
        for sy in (-1.0, 1.0):
            yc = sy * w * 0.33
            pos = (-d * 0.3 + 3.0, yc, s["cornice"] + 0.8)
            _crown(s, pos, (-d * 0.3, yc, s["cornice"] + ch + 1.0))
            _shell(s, [("dome", -d * 0.3, yc, s["cornice"] + ch + 0.6, 1.26, 1.40,
                        0.25, 1.0)])
    elif r == "dome_small":
        gh = max(2.0, min(3.1, s["height"] - s["cornice"] - 0.8))
        roofs.drum(asm, "stone", -d * 0.3, 0.0, s["cornice"], 2.7, gh * 0.8, 16, 8)
        roofs.dome(asm, "dome", -d * 0.3, 0.0, s["cornice"] + gh * 1.05, 2.7, gh * 0.9, 16, 6)
        trim.roof_clutter(asm, s, rng)
        _shell(s, [("cyl", -d * 0.3, 0.0, s["cornice"], 3.0, gh * 0.8, 0.0, 0.30),
                   ("dome", -d * 0.3, 0.0, s["cornice"] + gh * 1.05, 2.7, gh * 0.9,
                    0.30, 1.0)])
        for sy in (-1.0, 1.0):
            pos = (-d * 0.3 + 3.0, sy * 2.4, s["cornice"] + 0.8)
            _crown(s, pos, (-d * 0.3, 0.0, s["cornice"] + gh * 1.6))
    elif r == "towers2":
        crowns.roof_towers(asm, s, s["opts"].get("towers", 2))
        trim.roof_clutter(asm, s, rng)
        th = max(3.0, min(6.0, s["height"] - s["cornice"] - 1.0))
        for sy in (-1.0, 1.0):
            yc = sy * 0.28 * w
            pos = (-d * 0.45 + 3.4, yc, s["cornice"] + 0.8)
            _crown(s, pos, (-d * 0.45, yc, s["cornice"] + th + 2.0))
            _shell(s, [("box", -d * 0.45, yc, s["cornice"], 6.0, 5.0, th, 0.15, 1.0)])
    elif r == "ziggurat":
        _ziggurat(asm, s, rng)
    elif r == "hip_low":
        crowns.hip_low(asm, s)
    else:
        gap = s["height"] - s["cornice"]
        if gap > 1.5:
            asm.box("stone", (-0.4, 0.0, s["cornice"] + gap * 0.5), (0.8, w, gap))
        trim.roof_clutter(asm, s, rng)
    # every building gets a pair of crown floods at the parapet line, washing the attic
    if r not in ("dome_drum", "clock_tower", "pyramid", "chinese_hip", "cupolas",
                 "dome_small", "towers2", "ziggurat"):
        for sy in (-1.0, 1.0):
            pos = (-0.9, sy * w * 0.30, s["cornice"] + 0.7)
            _crown(s, pos, (-0.4, sy * w * 0.30, s["cornice"] + 4.0))


def _ziggurat(asm, s, rng):
    """Broadway Mansions: the Art Deco setbacks above the 11th floor.

    Every stage is a real building: four walls with windows and the vertical brick piers
    that make the Bund Mansions read as a brick Deco slab. The four walls face outwards
    - the back wall stands at the back of the stage and the flanks at its sides - so
    none of the glass is turned into the building."""
    w, d = s["frontage"], s["depth"]
    for z0, z1, wsc, dsc in ((40.0, 56.0, 0.72, 0.70), (56.0, 70.0, 0.50, 0.52),
                              (70.0, 77.0, 0.34, 0.36)):
        hw, hd = w * 0.5 * wsc, d * dsc
        # the solid core, inset so that no pane of glass is buried inside it
        asm.box("stone", (-hd * 0.5, 0.0, (z0 + z1) * 0.5),
                (hd - 0.9, hw * 2.0 - 0.9, z1 - z0))
        floors = max(1, int((z1 - z0) / 3.6))
        fh = (z1 - z0) / floors
        for f in range(floors):
            zc = z0 + f * fh + fh * 0.5
            n = max(3, int(hw * 2.0 / 2.4))
            holes = []
            for i in range(n):
                yc = -hw + (i + 0.5) * (hw * 2.0 / n)
                holes.append((yc, 0.52, zc - fh * 0.34, zc + fh * 0.34))
            m = max(3, int(hd / 2.4))
            holes_x = []
            for i in range(m):
                xc = -hd + (i + 0.5) * (hd / m)
                holes_x.append((xc, 0.52, zc - fh * 0.34, zc + fh * 0.34))
            walls.opening_wall(asm, "stone", "glasslit", 0.0, "X", 1.0, -hw, hw,
                               z0 + f * fh, z0 + (f + 1) * fh, holes,
                               rng=rng, lit_fraction=data.SETBACK_LIT_FRACTION,
                               cell_base=6)
            walls.opening_wall(asm, "stone", "glasslit", -hd, "X", -1.0, -hw, hw,
                               z0 + f * fh, z0 + (f + 1) * fh, holes,
                               rng=rng, lit_fraction=data.SETBACK_LIT_FRACTION,
                               cell_base=6)
            walls.opening_wall(asm, "stone", "glasslit", -hw, "Y", -1.0, -hd, 0.0,
                               z0 + f * fh, z0 + (f + 1) * fh, holes_x,
                               rng=rng, lit_fraction=data.SETBACK_LIT_FRACTION,
                               cell_base=6)
            walls.opening_wall(asm, "stone", "glasslit", hw, "Y", 1.0, -hd, 0.0,
                               z0 + f * fh, z0 + (f + 1) * fh, holes_x,
                               rng=rng, lit_fraction=data.SETBACK_LIT_FRACTION,
                               cell_base=6)
            # the vertical brick piers between the windows
            for i in range(n + 1):
                yc = -hw + i * (hw * 2.0 / n)
                asm.box("brick", (0.22, yc, zc), (0.44, 0.34, fh * 0.98))
        asm.prism("stone", profiles.cornice(0.8, 0.6), -hw, hw, z_off=z1)
    # the wash shells of the three setbacks: the glow follows the stepped form
    # only the ledge of every step is washed: a full shell would turn the whole
    # ziggurat into a flat cream slab and its windows would disappear
    _shell(s, [("boxb", -14.0, 0.0, 40.0, 60.0, 43.2, 16.0, 0.30, 0.10, 0.42),
               ("boxb", -10.4, 0.0, 56.0, 60.0, 30.0, 14.0, 0.30, 0.42, 0.74),
               ("boxb", -7.2, 0.0, 70.0, 60.0, 20.8, 7.0, 0.34, 0.74, 1.0)])
    for sy in (-1.0, 1.0):
        pos = (-d * 0.2, sy * w * 0.22, 41.0)
        yc = sy * w * 0.22
        _crown(s, pos, (-d * 0.2, yc, 56.0))
