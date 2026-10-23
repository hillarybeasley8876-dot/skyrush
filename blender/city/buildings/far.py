"""Far LOD: the merged masses the city shows beyond ~350 m.

Each building becomes a podium, a tower and a setback step, with a lit crown strip in
the district colour, an aviation light on the tall ones and the odd rooftop
billboard.  The walls use the window atlas, whose lit cells are at FULL value with an
emission strength of 1.0: the far city must read at night without blooming.

The night rules of ART.md 11 are honoured here (the far city is most of what a
120 m capture shows):
  * the atlas lights whole BANDS of floors, not a polka dot (texgen/atlas_windows);
  * every building offsets the atlas, so two towers never share a pattern;
  * half of the generic towers wear cool white LED crown and edge lines;
  * a red aviation beacon on every roof above 100 m;
  * the top of a tower is a mechanical floor, a setback and a mast - never a cone.

A tile may not blow its far triangle budget (40 000 per 512 m tile), and the far
city is what the player sees from the sky lanes: the detail of a building is
therefore a LEVEL of a ladder (see LEVELS).  Level 0 is the committed look; every
level below it drops a little more of the tiny detail and keeps the mass boxes, so
the silhouette survives to the last level.  `far_budget.far_levels` picks the level
of every building of a tile so the tile fits its budget: the short buildings lose
their detail first, the towers of the skyline keep theirs.
"""
import math
from collections import namedtuple

import bmesh
from mathutils import Vector

from . import shapes

# the atlas cell size in metres and the number of cells across the atlas
PRESETS = {
    "office": {"cell_m": (1.5, 3.9), "cols": 31, "rows": 12},
    "resi": {"cell_m": (3.3, 2.95), "cols": 12, "rows": 14},
}

# the crown colour per district (the brief: white / cyan / magenta per district)
DISTRICT_CROWN = {
    "D7": "emissive_cyan",
    "D5": "emissive_warm",
    "D3": "emissive_magenta",
    "D2": "emissive_magenta",
}
DEFAULT_CROWN = "emissive_cyan"
LED_CROWN = "emissive_white"   # the cool white LED crown of a generic tower
CROWN_H = 0.9
AVIATION_MIN_H = 100.0         # a red beacon on every roof above this (ART.md 11)
MECHANICAL_H = 6.0             # the height of the mechanical floor band
BILLBOARD_MIN_H = 25.0
BILLBOARD_STYLES = ("midrise", "office_tower", "neon_street")

# --- the far-LOD detail ladder -------------------------------------------------
# tol            the Douglas-Peucker tolerance of the lot outline (0 = keep it)
# edge_lines     the cool white LED lines up the corners of a tower
# billboard      the rooftop billboard
# mast_min_h     the mast is kept for the buildings taller than this
# podium_merge_h the podium merges into the shaft for the buildings shorter than this
# setback_min_h  the setback box is kept for the buildings taller than this
# vent_step      the distance between two lit vents on the mechanical floor
# mech_min_h     the mechanical floor is kept for the buildings taller than this
# crown_min_h    the lit crown is kept for the buildings taller than this
Detail = namedtuple("Detail", "tol edge_lines billboard mast_min_h podium_merge_h "
                               "setback_min_h vent_step mech_min_h crown_min_h")

LEVELS = [
    Detail(0.0, True, True, 60.0, 0.0, 40.0, 4.0, 40.0, 0.0),      # 0: the committed look
    Detail(1.5, False, False, 90.0, 25.0, 40.0, 4.0, 40.0, 0.0),    # 1: the base rule
    Detail(1.5, False, False, 90.0, 25.0, 40.0, 8.0, 40.0, 0.0),    # 2: fewer lit vents
    Detail(1.5, False, False, 90.0, 25.0, 80.0, 8.0, 40.0, 0.0),    # 3: no setback under 80 m
    Detail(1.5, False, False, 90.0, 1e9, 80.0, 8.0, 40.0, 0.0),     # 4: the podium merges
    Detail(1.5, False, False, 90.0, 1e9, 80.0, 16.0, 40.0, 0.0),    # 5: one vent per edge
    Detail(1.5, False, False, 90.0, 1e9, 80.0, 16.0, 100.0, 0.0),   # 6: no band under 100 m
    Detail(1.5, False, False, 90.0, 1e9, 80.0, 16.0, 100.0, 40.0),  # 7: no crown under 40 m
    Detail(3.0, False, False, 90.0, 1e9, 80.0, 16.0, 100.0, 40.0),  # 8: a harder outline
]
MAX_LEVEL = len(LEVELS) - 1


def _wall_quad(bm, a, b, normal, h0, h1, preset, offset=(0.0, 0.0)):
    """A vertical wall quad with atlas UVs (u along the wall in metres, v = height).

    `offset` shifts the atlas in (u, v) so two buildings do not share a pattern; the
    v offset is a whole number of floor rows, so the lit bands stay on floor lines.
    """
    length = math.hypot(b[0] - a[0], b[1] - a[1])
    info = PRESETS[preset]
    span_u = info["cols"] * info["cell_m"][0]
    span_v = info["rows"] * info["cell_m"][1]
    corners = []
    for u, h in ((0.0, h0), (length, h0), (length, h1), (0.0, h1)):
        corners.append((a[0] + (b[0] - a[0]) * u / length, a[1] + (b[1] - a[1]) * u / length, h))
    verts = [bm.verts.new(shapes.to_blender(*c)) for c in corners]
    face = bm.faces.new(tuple(verts))
    shapes.ensure_normal([face], Vector((normal[0], -normal[1], 0.0)))
    du, dv = offset
    uvs = [(du, h0 / span_v + dv), (du + length / span_u, h0 / span_v + dv),
           (du + length / span_u, h1 / span_v + dv), (du, h1 / span_v + dv)]
    # the UVs follow the vertex, so a winding flip cannot mirror the lit bands
    shapes.set_uvs(bm, face, dict(zip(verts, uvs)))
    return face


def add_far_box(wall_bm, roof_bm, poly, h0, h1, preset, offset=(0.0, 0.0)):
    """A rectangular mass: window-atlas walls and a dark roof cap."""
    n = len(poly)
    ccw = shapes.signed_area(poly) > 0.0
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        if length < 0.2:
            continue
        out = shapes.edge_outward(poly, i, ccw)
        if out is None:
            continue
        _wall_quad(wall_bm, a, b, out, h0, h1, preset, offset)
    # the roof cap in the dark roof material
    top = [roof_bm.verts.new(shapes.to_blender(x, z, h1)) for x, z in poly]
    face = roof_bm.faces.new(top)
    shapes.ensure_normal([face], Vector((0.0, 0.0, 1.0)))
    shapes.set_uvs(roof_bm, face, {v: (0.5, 0.5) for v in top})


def shrink(poly, factor):
    """A rectangle shrunk towards its centre (a setback step)."""
    cx = sum(p[0] for p in poly) / len(poly)
    cz = sum(p[1] for p in poly) / len(poly)
    return [(cx + (x - cx) * factor, cz + (z - cz) * factor) for x, z in poly]


def preset_for(style):
    """Which facade preset a building style uses in the far LOD."""
    return "office" if style == "office_tower" else "resi"


def _crown(buckets, poly, h, key, height=CROWN_H):
    """An emissive edge line around the top of a tower."""
    bm = buckets.setdefault(key, bmesh.new())
    n = len(poly)
    ccw = shapes.signed_area(poly) > 0.0
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        if length < 0.3:
            continue
        ux, uz = (b[0] - a[0]) / length, (b[1] - a[1]) / length
        out = shapes.edge_outward(poly, i, ccw)
        if out is None:
            continue
        nx, nz = out
        mx, mz = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
        p = (mx + nx * 0.3, mz + nz * 0.3)
        shapes.add_box(bm, p, (length, 0.5), h, h + height,
                       rot_deg=math.degrees(math.atan2(uz, ux)))


def _edge_lines(buckets, poly, h0, h1, key, size=0.45):
    """A cool white LED line up every corner of a tower."""
    bm = buckets.setdefault(key, bmesh.new())
    for (x, z) in poly:
        shapes.add_box(bm, (x, z), (size, size), h0, h1)


def _mechanical_floor(buckets, poly, h, key, vent_step=4.0):
    """The mechanical floor: a dark service band with a row of lit vents."""
    roof = buckets.setdefault("roof", bmesh.new())
    lit = buckets.setdefault(key, bmesh.new())
    n = len(poly)
    ccw = shapes.signed_area(poly) > 0.0
    for i in range(n):
        a = poly[i]
        b = poly[(i + 1) % n]
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        if length < 0.3:
            continue
        ux, uz = (b[0] - a[0]) / length, (b[1] - a[1]) / length
        out = shapes.edge_outward(poly, i, ccw)
        if out is None:
            continue
        nx, nz = out
        mx, mz = (a[0] + b[0]) * 0.5, (a[1] + b[1]) * 0.5
        rot = math.degrees(math.atan2(uz, ux))
        p = (mx + nx * 0.25, mz + nz * 0.25)
        shapes.add_box(roof, p, (length, 0.5), h, h + MECHANICAL_H, rot_deg=rot)
        # the lit vents, one every `vent_step` metres
        count = max(1, int(length / vent_step))
        for k in range(count):
            t = (k + 0.5) / count
            q = (a[0] + (b[0] - a[0]) * t + nx * 0.55, a[1] + (b[1] - a[1]) * t + nz * 0.55)
            shapes.add_box(lit, q, (1.6, 0.3), h + MECHANICAL_H * 0.55,
                           h + MECHANICAL_H * 0.55 + 0.8, rot_deg=rot)


def _mast(buckets, poly, h, key="beacon"):
    """The antenna mast on a tall roof, with a red light on top."""
    bm = buckets.setdefault("roof", bmesh.new())
    lit = buckets.setdefault(key, bmesh.new())
    n = len(poly)
    cx = sum(p[0] for p in poly) / n
    cz = sum(p[1] for p in poly) / n
    shapes.add_box(bm, (cx, cz), (0.7, 0.7), h, h + 12.0)
    shapes.add_box(lit, (cx, cz), (1.0, 1.0), h + 12.0, h + 12.8)


def _atlas_offset(rec, preset):
    """The atlas offset of one building: no two buildings share a lit pattern."""
    seed = int(rec.get("seed", 0))
    info = PRESETS[preset]
    du = ((seed * 37) % 997) / 997.0
    dv = ((seed * 13) % info["rows"]) / float(info["rows"])
    return (du, dv)


def is_white_crown(rec):
    """True when the building wears the cool white LED crown (and its edge lines)."""
    crown = rec.get("crown") or DISTRICT_CROWN.get(rec.get("district", ""), DEFAULT_CROWN)
    return crown == LED_CROWN


def add_far_from_record(buckets, rec, level=0):
    """The far-LOD mass of one building record: podium, tower, setback, crown.

    `level` is a step of the detail ladder (see LEVELS): the lower the level, the
    less tiny detail the mass carries.  The mass boxes are never dropped, so the
    silhouette of the building is the same at every level.
    """
    p = LEVELS[level]
    poly = outline_of(rec, p)
    h = float(rec.get("height", 10.0))
    style = rec.get("style", "midrise")
    preset = preset_for(style)
    offset = _atlas_offset(rec, preset)
    wall = buckets["wall_%s" % preset]
    roof = buckets["roof"]
    podium_h = min(h * 0.12, 9.0)
    merged = h < p.podium_merge_h
    if not merged:
        add_far_box(wall, roof, shrink(poly, 1.12), 0.0, podium_h, preset, offset)
    base = 0.0 if merged else podium_h
    shaft_h = h * 0.78
    add_far_box(wall, roof, poly, base, shaft_h, preset, offset)
    top_poly = poly
    if h > p.setback_min_h:
        top_poly = shrink(poly, 0.78)
        add_far_box(wall, roof, top_poly, shaft_h, h, preset, offset)
    # the lit crown: half of the generic towers wear the cool white LED signature
    # (the near tower records its crown, so the hand-off does not pop)
    crown_key = rec.get("crown") or DISTRICT_CROWN.get(rec.get("district", ""), DEFAULT_CROWN)
    white = crown_key == LED_CROWN
    if white:
        crown_key = LED_CROWN
    if h > p.crown_min_h:
        _crown(buckets, top_poly, h, crown_key)
    if white and p.edge_lines:
        _edge_lines(buckets, top_poly, base, h, LED_CROWN)
    if h > p.mech_min_h:
        # the top of a tower is a service band, not a pale cone
        _mechanical_floor(buckets, top_poly, h - MECHANICAL_H, crown_key, p.vent_step)
    if h > p.mast_min_h:
        _mast(buckets, top_poly, h)
    if h > AVIATION_MIN_H:
        bm = buckets.setdefault("beacon", bmesh.new())
        cx = sum(p[0] for p in top_poly) / len(top_poly)
        cz = sum(p[1] for p in top_poly) / len(top_poly)
        shapes.add_box(bm, (cx, cz), (0.9, 0.9), h, h + 0.9)
    # a rooftop billboard on the tall blocks
    if p.billboard and h > BILLBOARD_MIN_H and style in BILLBOARD_STYLES:
        bm = buckets.setdefault("led", bmesh.new())
        cx = sum(p[0] for p in top_poly) / len(top_poly)
        cz = sum(p[1] for p in top_poly) / len(top_poly)
        shapes.add_box(bm, (cx, cz), (7.0, 0.4), h + 1.0, h + 4.0)


# --- the outline of the far mass ------------------------------------------------
def _seg_dist(p, a, b):
    """The distance of a point from a segment."""
    dx, dz = b[0] - a[0], b[1] - a[1]
    span = dx * dx + dz * dz
    if span < 1e-12:
        return math.hypot(p[0] - a[0], p[1] - a[1])
    t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / span
    t = max(0.0, min(1.0, t))
    return math.hypot(p[0] - a[0] - dx * t, p[1] - a[1] - dz * t)


def _dp_chain(points, tol):
    """Douglas-Peucker on an open chain of points."""
    n = len(points)
    if n < 3:
        return list(points)
    keep = [False] * n
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        i, j = stack.pop()
        if j <= i + 1:
            continue
        a, b = points[i], points[j]
        far, k = 0.0, -1
        for m in range(i + 1, j):
            d = _seg_dist(points[m], a, b)
            if d > far:
                far, k = d, m
        if k >= 0 and far > tol:
            keep[k] = True
            stack.append((i, k))
            stack.append((k, j))
    return [p for p, k in zip(points, keep) if k]


def _farthest_pair(poly):
    """The indices of the two points of a ring that are the furthest apart."""
    n = len(poly)
    best, pair = 0.0, (0, 1)
    for i in range(n):
        for j in range(i + 1, n):
            d = math.hypot(poly[j][0] - poly[i][0], poly[j][1] - poly[i][1])
            if d > best:
                best, pair = d, (i, j)
    return pair


def simplify_ring(poly, tol):
    """A closed lot outline simplified with Douglas-Peucker.

    A ring has no ends, so it is cut at its longest diagonal and the two chains
    are simplified on their own.  The ring never drops below four points: a
    building with three walls is not a building.
    """
    n = len(poly)
    if tol <= 0.0 or n <= 4:
        return list(poly)
    i, j = _farthest_pair(poly)
    if j < i:
        i, j = j, i
    chain_a = poly[i:j + 1]
    chain_b = poly[j:] + poly[:i + 1]
    out = _dp_chain(chain_a, tol)[:-1] + _dp_chain(chain_b, tol)[:-1]
    if len(out) < 4:
        return list(poly)
    return out


def outline_of(rec, p):
    """The lot outline of a building, simplified for the far mass."""
    poly = [(q[0], q[1]) for q in rec["poly"]]
    return simplify_ring(poly, p.tol)
