"""Roadster body shell from ref/roadster/roadster_loft.json (core-owned, written by the lead).

    from lib import roadster_body
    body, glass = roadster_body.build(col)          # objects "Body" (paint + black trim) and "Glass"

Method (ref/roadster/DOSSIER.md §4.3, §8.1): the 15 JSON sections (10 key points K0..K9 each, right
half) are linearly interpolated every STEP metres along Y (ruled surfaces stay planar → no faceting
artefacts), mirrored into closed 18-point rings and bridged; nose fan + flat tail cap; wheel wells
cut with exact booleans; materials from the section bands, with the glass decided by the canopy plan
and side-window (DLO) polygons; every K-row is a sharp crease (smooth shading inside each strip),
bevel 4 mm + weighted normals. Frame: X right, Y forward, Z up, origin ground centre between axles.
"""
import json
import math
import os

import bmesh
from mathutils import Vector

from . import common, mats, uv, wells

LOFT = os.path.join(common.ROOT, "ref", "roadster", "roadster_loft.json")
STEP = 0.08          # max section spacing along Y (m)
NOSE_TIP_Y = 2.29


def load():
    with open(LOFT) as f:
        return json.load(f)


def _interp(secs):
    """Sections front (high y) → rear, interpolated every ≤ STEP m. Bands come from the front section."""
    out = []
    for a, b in zip(secs, secs[1:]):
        n = max(1, math.ceil((a["y"] - b["y"]) / STEP))
        for i in range(n):
            t = i / n
            k = [((1 - t) * pa[0] + t * pb[0], (1 - t) * pa[1] + t * pb[1]) for pa, pb in zip(a["K"], b["K"])]
            out.append({"y": (1 - t) * a["y"] + t * b["y"], "K": k, "bands": a["bands"]})
    last = secs[-1]
    out.append({"y": last["y"], "K": [tuple(p) for p in last["K"]], "bands": last["bands"]})
    return out


def _add_tbar_split(sec, x_split=0.12):
    """Insert K8b on the K8→K9 roof segment at |x| = x_split (T-bar edge) → 11 key points."""
    k = list(sec["K"])
    k8, k9 = k[8], k[9]
    t = 0.5 if k8[0] <= x_split else (k8[0] - x_split) / max(k8[0] - k9[0], 1e-6)
    k8b = (k8[0] + (k9[0] - k8[0]) * t, k8[1] + (k9[1] - k8[1]) * t)
    return {"y": sec["y"], "K": k[:9] + [k8b, k9], "bands": sec["bands"] + sec["bands"][8]}


def _ring11(sec):
    """22-point ring for 11 key points: K0, K1..K10 right, K9'..K1' left (K0/K10 on the centre line)."""
    y, k = sec["y"], sec["K"]
    right = [Vector((x, y, z)) for (x, z) in k]
    left = [Vector((-x, y, z)) for (x, z) in reversed(k[1:10])]
    return right + left


def _edge_strip(k, n_right=10):
    """Strip index between key k and k+1 for the 2*n_right ring (right side 0..9, left mirrored)."""
    return k if k < n_right else 2 * n_right - 1 - k


def _shell(data):
    secs = [_add_tbar_split(s) for s in _interp(data["sections"])]
    tip = {"y": NOSE_TIP_Y, "K": [(0.0, z) for (_, z) in secs[0]["K"]], "bands": secs[0]["bands"]}
    secs = [tip] + secs
    n = len(_ring11(secs[0]))
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in _ring11(s)] for s in secs]
    strip_l = bm.faces.layers.int.new("strip")
    band_l = bm.faces.layers.int.new("band")
    sharp_pairs = []
    for i in range(len(rings) - 1):
        ra, rb = rings[i], rings[i + 1]
        for k in range(n):
            k2 = (k + 1) % n
            sharp_pairs.append((ra[k], rb[k]))
            try:
                f = bm.faces.new((ra[k], ra[k2], rb[k2], rb[k]))
            except ValueError:
                continue
            j = _edge_strip(k)
            f[strip_l] = j
            f[band_l] = ord(secs[i]["bands"][j])  # a strip takes the band of the section it starts from
    tail = bm.faces.new(rings[-1])
    tail[strip_l] = -1
    tail[band_l] = ord("W")
    _split_tail(bm, tail, strip_l, band_l)
    return bm, rings, sharp_pairs


TAIL_BLACK_Z = 0.59   # rear face: black valance below, white bumper band above (dossier §3 Rear)


def _split_tail(bm, tail, strip_l, band_l):
    """Cut the flat tail cap at TAIL_BLACK_Z; the lower part becomes black trim."""
    geom = [tail] + list(tail.edges) + list(tail.verts)
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0.0, 0.0, TAIL_BLACK_Z), plane_no=(0.0, 0.0, 1.0))
    for f in bm.faces:
        if f[strip_l] == -1:
            f[band_l] = ord("B") if f.calc_center_median().z < TAIL_BLACK_Z else ord("W")


def _mark_sharp(bm, sharp_pairs):
    """K-rows are creases (sharp); coplanar seams (interpolation rows, the T-bar material split) stay soft."""
    for a, b in sharp_pairs:
        e = bm.edges.get((a, b))
        if e is not None:
            e.smooth = False
    for e in bm.edges:
        if len(e.link_faces) == 2 and e.calc_face_angle(0.0) < math.radians(2.0):
            e.smooth = True  # coplanar interpolation seams stay smooth


# --- materials -------------------------------------------------------------------------------------
PAINT, TRIM, GLASS, TBAR = 0, 1, 2, 3


def _materials():
    return [
        mats.pbr("SH_car_paint", color=(0.84, 0.85, 0.86), roughness=0.28),   # #ECEDEF sRGB, swapped in Godot
        mats.pbr("M_BlackTrim", color=(0.0056, 0.0056, 0.0065), roughness=0.55),  # #111113
        mats.pbr("SH_glass_gold", color=(0.042, 0.021, 0.0093), roughness=0.04, metallic=0.6, alpha=0.95),
        mats.pbr("M_TBar", color=(0.003, 0.0034, 0.004), roughness=0.12),       # gloss black T-bar
    ]


def _poly_contains(poly, p):
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        (xi, yi), (xj, yj) = poly[i], poly[j]
        if (yi > p[1]) != (yj > p[1]) and p[0] < (xj - xi) * (p[1] - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def _canopy_half_width(data, y):
    pts = sorted(data["canopy_glass_plan_right"], key=lambda q: q[1])
    if y < pts[0][1] or y > pts[-1][1]:
        return 0.0
    for (xa, ya), (xb, yb) in zip(pts, pts[1:]):
        if ya <= y <= yb and yb > ya:
            return xa + (xb - xa) * (y - ya) / (yb - ya)
    return 0.0


def _classify(data, bm):
    """Material index per face from bands + canopy plan + side-window (DLO) polygon + roof rules."""
    strip_l, band_l = bm.faces.layers.int["strip"], bm.faces.layers.int["band"]
    sp, roof = data["side_profile"], data["roof"]
    dlo = [(y, z) for y, z in sp["dlo_top"]] + [(y, z) for y, z in reversed(sp["dlo_bottom"])]
    for f in bm.faces:
        c, j, band = f.calc_center_median(), f[strip_l], chr(f[band_l])
        ax, in_ttop = abs(c.x), roof["t_top_rear_y"] <= c.y <= roof["t_top_front_y"]
        mat = TRIM if band == "B" else PAINT
        if j in (7, 8, 9) and ax < _canopy_half_width(data, c.y) - 0.004:
            mat = GLASS
            if in_ttop and ax < roof["t_bar_half_width"]:
                mat = TBAR
        if j in (6, 7) and _poly_contains(dlo, (c.y, c.z)) and abs(f.normal.x) > 0.3:
            mat = GLASS
        f.material_index = mat


# --- wheel wells -----------------------------------------------------------------------------------
WELL_X = {"front": (0.60, 0.935), "rear": (0.62, 0.985)}   # (pocket inner wall, body side at the arch)


def _well_spec(data):
    out = []
    for key, (x_in, x_side) in WELL_X.items():
        w = data["wheels"][key]
        out.append(wells.Well(y=w["centre"][1], z=w["centre"][2], r=w["arch_radius"], x_in=x_in, x_side=x_side))
    return out


# --- assembly --------------------------------------------------------------------------------------
def _split_glass(body, col):
    me = body.data
    bm = bmesh.new()
    bm.from_mesh(me)
    glass_bm = bm.copy()
    bmesh.ops.delete(glass_bm, geom=[f for f in glass_bm.faces if f.material_index != GLASS], context="FACES")
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index == GLASS], context="FACES")
    bm.to_mesh(me)
    bm.free()
    glass = common.mesh_object("Glass", glass_bm, col)
    for m in me.materials:
        glass.data.materials.append(m)
    return glass


def _finish(obj):
    for poly in obj.data.polygons:
        poly.use_smooth = True
    bev = obj.modifiers.new("Bevel", "BEVEL")
    bev.width, bev.segments, bev.limit_method = 0.004, 2, "ANGLE"
    bev.angle_limit, bev.harden_normals = math.radians(25.0), True
    wn = obj.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    wn.keep_sharp, wn.mode = True, "FACE_AREA"
    uv.smart_project(obj)


def build(col=None):
    """Build Body (paint/trim/T-bar slots), Glass and ArchLiners. Returns (body, glass, liners)."""
    data = load()
    bm, _rings, sharp_pairs = _shell(data)
    _mark_sharp(bm, sharp_pairs)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    _classify(data, bm)
    materials = _materials()
    body = common.mesh_object("Body", bm, col)
    for m in materials:
        body.data.materials.append(m)
    well_spec = _well_spec(data)
    wells.cut(body, well_spec, materials[TRIM])
    glass = _split_glass(body, col)
    liners = wells.liners("ArchLiners", well_spec, col, materials[TRIM])
    for obj in (body, glass):
        _finish(obj)
    print("roadster_body: body %d faces, glass %d faces" % (len(body.data.polygons), len(glass.data.polygons)))
    return body, glass, liners
