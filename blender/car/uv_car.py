"""UV layouts for the Roadster.

Every mesh carries exactly ONE uv layer ("UVMap"), so the glTF exporter never
has to make a second material for a second UV set - that is what produced the
"M_BlackTrim.001" duplicates in the earlier build. The layer is a per-face
projection:
  * the body, the glass and the panels keep the lead's smart projection
    (lib/roadster_body.py); the 4 mm panel-gap normal map and the canopy frit
    band are drawn in that space (car/texmaps.py);
  * the faces of a tiling material (the black trim, the carbon, the interior)
    get a normalised box projection instead, so the grain keeps a constant
    texel density;
  * the wheels, the brake discs and the nozzle rings get a polar projection.
"""
import math

import bmesh
from mathutils import Vector

from car import paths

# materials that sample a tiling map: they need the normalised box projection
BOX_MATS = ("M_BlackTrim", "M_ArchLip", "M_InnerDark", "M_Carbon", "M_CaliperBronze",
            "M_SeatWhite", "M_Microsuede", "M_CabinBlack", "M_Copv", "M_RedAccent",
            "M_AmberMarker", "M_RedReflector", "M_TBar", "M_WheelWhite", "M_WheelDark",
            "M_GoldWheel")


def _extent():
    """The model's extents (from the JSON) used to normalise the box projection."""
    d = paths.loft()
    sp = d["side_profile"]
    width = d["dims"]["width_body_max"]
    y_from = sp["tail_face"]["y"]          # the tail
    y_to = sp["nose_face"]["y"]           # the nose
    return (width / 2.0, -y_from, y_to - y_from)


def box_uv(ob, name="UVMap", tiling=None):
    """Box projection normalised to 0..1 over the model, for the tiling faces."""
    me = ob.data
    layer = me.uv_layers.get(name) or me.uv_layers.new(name=name)
    ox, oy, ext = _extent()
    off = (ox, oy, 0.0)
    for poly in me.polygons:
        if tiling is not None and poly.material_index not in tiling:
            continue
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            # the raw axes (no mirroring): every value stays inside 0..1
            if ax == 0:
                a, b = co.y, co.z
                oa, ob_ = off[1], off[2]
            elif ax == 1:
                a, b = co.x, co.z
                oa, ob_ = off[0], off[2]
            else:
                a, b = co.x, co.y
                oa, ob_ = off[0], off[1]
            layer.data[li].uv = ((a + oa) / ext, (b + ob_) / ext)
    return ob


def disc_uv(ob, r_in, r_out, name="UVMap"):
    """Polar UVs for the brake disc (u = angle, v = radius)."""
    me = ob.data
    layer = me.uv_layers.get(name) or me.uv_layers.new(name=name)
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            r = (co.y ** 2 + co.z ** 2) ** 0.5
            a = 0.0 if abs(co.z) < 1e-9 and abs(co.y) < 1e-9 else math.atan2(co.z, co.y)
            layer.data[li].uv = ((a / (2 * math.pi) + 0.5) % 1.0,
                                 (r - r_in) / max(r_out - r_in, 1e-6))
    return ob


def radial_uv(ob, name="UVMap"):
    """Radial UVs around the wheel axis (u = angle, v = radius) for the rim."""
    me = ob.data
    layer = me.uv_layers.get(name) or me.uv_layers.new(name=name)
    r_max = 1e-6
    for v in me.vertices:
        r_max = max(r_max, (v.co.y ** 2 + v.co.z ** 2) ** 0.5)
    for poly in me.polygons:
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            r = (co.y ** 2 + co.z ** 2) ** 0.5
            a = 0.0 if abs(co.z) < 1e-9 and abs(co.y) < 1e-9 else math.atan2(co.z, co.y)
            layer.data[li].uv = ((a / (2 * math.pi)) % 1.0, r / r_max)
    return ob


def cube_uv(ob, name="UVMap"):
    """One 0..1 square per face (the small lamp and screen parts)."""
    me = ob.data
    layer = me.uv_layers.get(name) or me.uv_layers.new(name=name)
    for poly in me.polygons:
        xs = [me.vertices[me.loops[li].vertex_index].co for li in poly.loop_indices]
        lo = [min(v[i] for v in xs) for i in range(3)]
        hi = [max(v[i] for v in xs) for i in range(3)]
        ax = max(range(3), key=lambda i: abs(poly.normal[i]))
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            if ax == 0:
                u, v = co.y, co.z
            elif ax == 1:
                u, v = co.x, co.z
            else:
                u, v = co.x, co.y
            du = (hi[1 if ax == 0 else 0] - lo[1 if ax == 0 else 0]) or 1.0
            dv = (hi[2] - lo[2]) or 1.0
            layer.data[li].uv = ((u - lo[1 if ax == 0 else 0]) / du,
                                 (v - lo[2]) / dv)
    return ob


def apply(ob):
    """Give the object the one UV layer its materials expect.

    A mesh without any UV layer would make the glTF exporter emit a second
    material for the same surface, so every mesh gets a "UVMap".
    """
    me = ob.data
    tiling = {i for i, m in enumerate(me.materials) if m and m.name in BOX_MATS}
    if me.uv_layers.get("UVMap") is None:
        me.uv_layers.new(name="UVMap")
        box_uv(ob, "UVMap")
    elif tiling:
        box_uv(ob, "UVMap", tiling)
    return ob
