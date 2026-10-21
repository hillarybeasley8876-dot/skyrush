"""Smooth lofted NPC car body (core-owned, written by the lead) from an npc_cars `car` spec dict.

    from lib import car_body
    parts = car_body.build(spec, col, materials)   # {"body", "glass", "liners", "anchors"}

Spec keys (npc_cars/spec.py, N-ART5): L W H wb wr ww track clear nose_z hood_z cowl_y roof_front_y
roof_z roof_rear_y deck_y deck_z tail_z belt_front belt_rear tumble rc_front rc_rear bulge doors,
optional crown_y roof_drop dlo_front dlo_rear dlo_rail_end arch_clad wrap. The profile functions
keep the semantics of npc_cars/profile.py, so details placed with those functions still fit.

Method: a Catmull-Clark cage lofted through stations along Y. Every glass boundary (cowl, roof
front/rear, deck, daylight-opening ends, B pillar) is a station and the section rows include the
daylight-opening bottom/top and the roof edge, so every panel is a band of whole cage faces and the
window edges come out as clean curves after subdivision (no staircase). Creases keep the shoulder,
belt and glass edges crisp; both ends are closed with inset caps; wheel wells are exact boolean
pockets lined in black (lib.wells). Frame: X right, Y forward (nose +L/2), Z up, ground z = 0.
"""

import bmesh
from mathutils import Vector

from . import common, mats, uv, wells
from .car_profile import Profile

PAINT, TRIM, GLASS, PILLAR = 0, 1, 2, 3
MAX_STEP = 0.20       # max cage station spacing (m)
ROWS = 12             # half-section rows, bottom centre (0) .. top centre (11)
ROW_CREASE = {3: 0.3, 5: 0.5, 6: 1.0, 7: 0.5, 8: 0.5, 9: 0.75}
END_RING_CREASE = 0.6
GLASS_EDGE_CREASE = 0.5
CAP_SCALES = ((0.92, 0.025), (0.55, 0.045))   # inset ring (scale, forward offset) at each end


def default_materials(paint="SH_car_paint_npc"):
    return [
        mats.pbr(paint, color=(0.8, 0.8, 0.8), roughness=0.3),
        mats.pbr("M_BlackTrim", color=(0.0056, 0.0056, 0.0065), roughness=0.55),
        mats.pbr("SH_glass_tinted", color=(0.02, 0.025, 0.03), roughness=0.05, metallic=0.2),
        mats.pbr("M_GlossBlack", color=(0.003, 0.0034, 0.004), roughness=0.12),
    ]


# --- cage ------------------------------------------------------------------------------------------
def _section(pr, y):
    """12-point half section (x >= 0) at station y: see the row table in car_profile.Profile.rows."""
    return [Vector((x, y, z)) for x, z in pr.rows(y)]


def _ring(half):
    """Closed ring: rows 0..11 on the right, then the left mirror 10..1 (centre rows shared)."""
    left = [Vector((-v.x, v.y, v.z)) for v in reversed(half[1:-1])]
    return half + left


def _strip_of(k, n_half=ROWS):
    """Row strip index (0..10) of ring segment k -> k+1, mirrored for the left half."""
    return k if k < n_half - 1 else 2 * (n_half - 1) - 1 - k


def _face_material(pr, strip, y_mid):
    if strip in (0, 1):
        return TRIM
    if strip == 2:
        return TRIM if pr.p.get("arch_clad") else PAINT
    if strip == 7 and pr.in_dlo(y_mid):
        return PILLAR if pr.in_b_pillar(y_mid) else GLASS
    if strip == 8 and pr.in_sail(y_mid):
        return PILLAR      # mirror sail: the A-pillar band ahead of the side glass
    if strip in (9, 10) and pr.in_top_glass(y_mid):
        return GLASS
    return PAINT


def _cap(bm, ring, direction, mat_l, crease):
    """Close an end ring with two inset rings and a centre n-gon (a slightly domed fascia)."""
    centre = sum((v.co for v in ring), Vector()) / len(ring)
    prev, faces = ring, []
    for scale, ahead in CAP_SCALES:
        cur = [bm.verts.new(centre + (v.co - centre) * scale + Vector((0.0, direction * ahead, 0.0))) for v in ring]
        n = len(ring)
        for k in range(n):
            q = (prev[k], prev[(k + 1) % n], cur[(k + 1) % n], cur[k])
            faces.append(bm.faces.new(q if direction > 0 else tuple(reversed(q))))
        prev = cur
    faces.append(bm.faces.new(prev if direction > 0 else list(reversed(prev))))
    for f in faces:
        f[mat_l] = PAINT
    n = len(ring)
    for k in range(n):
        e = bm.edges.get((ring[k], ring[(k + 1) % n]))
        if e is not None:
            e[crease] = END_RING_CREASE
    return faces


def _cage(pr):
    stations = pr.stations(MAX_STEP)
    bm = bmesh.new()
    mat_l = bm.faces.layers.int.new("mat")
    crease = bm.edges.layers.float.get("crease_edge") or bm.edges.layers.float.new("crease_edge")
    rings = [[bm.verts.new(p) for p in _ring(_section(pr, y))] for y in stations]
    n = len(rings[0])
    glass_ys = pr.glass_stations()
    for i in range(len(rings) - 1):
        ra, rb = rings[i], rings[i + 1]
        y_mid = 0.5 * (stations[i] + stations[i + 1])
        for k in range(n):
            k2 = (k + 1) % n
            f = bm.faces.new((ra[k2], ra[k], rb[k], rb[k2]))
            f[mat_l] = _face_material(pr, _strip_of(k), y_mid)
    bm.edges.ensure_lookup_table()
    for i, ring in enumerate(rings):
        for k in range(n):
            row = k if k < ROWS else 2 * (ROWS - 1) - k
            if i + 1 < len(rings) and row in ROW_CREASE:
                e = bm.edges.get((ring[k], rings[i + 1][k]))
                if e is not None:
                    e[crease] = ROW_CREASE[row]
            if _strip_of(k) in (9, 10) and any(abs(stations[i] - g) < 1e-6 for g in glass_ys):
                e = bm.edges.get((ring[k], ring[(k + 1) % n]))
                if e is not None:
                    e[crease] = GLASS_EDGE_CREASE
    _cap(bm, rings[0], 1, mat_l, crease)
    _cap(bm, rings[-1], -1, mat_l, crease)
    for f in bm.faces:
        f.material_index = f[mat_l]
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm


# --- assembly --------------------------------------------------------------------------------------
def _subdivide(obj, levels):
    mod = obj.modifiers.new("Subsurf", "SUBSURF")
    mod.levels = mod.render_levels = levels
    mod.use_creases = True
    mod.uv_smooth = "PRESERVE_BOUNDARIES"
    wells.bake_modifiers(obj)
    for poly in obj.data.polygons:
        poly.use_smooth = True


def _triangulate_ngons(obj):
    """The boolean leaves n-gons around the wells; glTF tangents need tris/quads."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.to_mesh(obj.data)
    bm.free()


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
    for poly in glass.data.polygons:
        poly.use_smooth = True
    return glass


def _wells(pr):
    p = pr.p
    out = []
    for y in (p["wb"] * 0.5, -p["wb"] * 0.5):
        side = pr.half_width(y) + p.get("bulge", 0.0)
        out.append(wells.Well(y=y, z=p["wr"], r=p["wr"] + 0.035,
                              x_in=max(0.2, p["track"] - p["ww"] * 0.5 - 0.05), x_side=side))
    return out


def build(spec, col=None, materials=None, levels=2):
    """Body (paint/trim/glass/gloss-black slots), Glass and ArchLiners for one `car` spec."""
    pr = Profile(spec)
    materials = materials or default_materials()
    body = common.mesh_object("Body", _cage(pr), col)
    for m in materials:
        body.data.materials.append(m)
    _subdivide(body, levels)
    well_spec = _wells(pr)
    wells.cut(body, well_spec, materials[TRIM])
    _triangulate_ngons(body)
    glass = _split_glass(body, col)
    clad = 0.06 if spec.get("arch_clad") else 0.0
    liners = wells.liners("ArchLiners", well_spec, col, materials[TRIM], clad=clad)
    uv.smart_project(body)
    uv.smart_project(glass)
    print("car_body %s: body %d faces, glass %d faces" % (spec.get("name", "?"), len(body.data.polygons),
                                                         len(glass.data.polygons)))
    return {"body": body, "glass": glass, "liners": liners, "anchors": pr.anchors(well_spec)}
