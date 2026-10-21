"""Bmesh helpers shared by the road generators.

Everything here is pure geometry: coloured strips, swept profiles, boxes and a
per-tile builder that groups geometry by material so a 512 m tile exports as a
handful of draw calls instead of hundreds.
"""
import bpy
import bmesh
from mathutils import Vector

from lib import common, geo

UP = Vector((0.0, 0.0, 1.0))


def colour_layer(bm):
    """Return (creating if needed) the float-colour corner layer used for road vertex colours."""
    return bm.loops.layers.float_color.get("Col") or bm.loops.layers.float_color.new("Col")


def strip(bm, path, frames, template, z=0.0, flip=False, layer=None, uv_fn=None):
    """Add a quad strip along `path` following `template` = [(across, r, g, b), ...].

    `across` is metres to the right of the travel direction, `z` is a vertical
    offset. Vertex colours drive the road shader (R = wheel paths, G = gutters).
    `uv_fn(i, k)` optionally returns the UV of column k of path sample i.
    """
    lay = layer or colour_layer(bm)
    uv = None
    if uv_fn is not None:
        uv = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    m = len(template)
    rows = []
    for i, p in enumerate(path):
        r = frames[i][1]
        rows.append([bm.verts.new(p + r * x + UP * z) for (x, _c, _g, _b) in template])
    for i in range(len(rows) - 1):
        a, b = rows[i], rows[i + 1]
        for k in range(m - 1):
            quad = (a[k], a[k + 1], b[k + 1], b[k])
            face = bm.faces.new(tuple(reversed(quad)) if flip else quad)
            cols = (template[k], template[k + 1], template[k + 1], template[k])
            for loop, col in zip(face.loops, cols):
                loop[lay] = (col[1], col[2], col[3], 1.0)
            if uv is not None:
                u0, v0 = uv_fn(i, k)
                u1, v1 = uv_fn(i, k + 1)
                for loop, uvv in zip(face.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))):
                    loop[uv].uv = uvv
    return rows


def strip_columns(bm, path, frames, columns, vs, along=None):
    """A strip of (across, z) columns with per-column v coordinates.

    The columns must increase in `across` so the faces point down (the soffit).
    `vs` holds the v coordinate of each column, `along` the u (metres) per sample.
    """
    uv = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    rows = []
    for i, p in enumerate(path):
        r = frames[i][1]
        rows.append([bm.verts.new(p + r * x + UP * z) for (x, z) in columns])
    for n in range(len(rows) - 1):
        a, b = rows[n], rows[n + 1]
        for c in range(len(columns) - 1):
            face = bm.faces.new((a[c], b[c], b[c + 1], a[c + 1]))
            u0 = along[n] if along else float(n)
            u1 = along[n + 1] if along else float(n + 1)
            for loop, uvv in zip(face.loops, ((u0, vs[c]), (u1, vs[c]),
                                              (u1, vs[c + 1]), (u0, vs[c + 1]))):
                loop[uv].uv = uvv
    return rows


def uv_from_attributes(bm, u_scale=1.0, v_scale=1.0, name="UVMap"):
    """Set UVs from the 'along'/'across' attributes geo.sweep stores (metres)."""
    along = bm.verts.layers.float.get("along")
    across = bm.verts.layers.float.get("across")
    if along is None or across is None:
        raise ValueError("uv_from_attributes: mesh has no along/across attributes")
    bm.verts.index_update()
    layer = bm.loops.layers.uv.get(name) or bm.loops.layers.uv.new(name)
    for face in bm.faces:
        for loop in face.loops:
            vert = loop.vert
            loop[layer].uv = (vert[along] * u_scale, vert[across] * v_scale)
    return bm


def uv_planar(bm, scale=1.0, name="UVMap"):
    """UVs in metres, projected on the plane of every face.

    The parts that are not swept (a planter pot, a pier column, an expansion
    joint) have no along/across attributes, so their texture is projected on
    the plane their face lies in.
    """
    layer = bm.loops.layers.uv.get(name) or bm.loops.layers.uv.new(name)
    for face in bm.faces:
        normal = face.normal
        axis = max(range(3), key=lambda i: abs(normal[i]))
        axes = [i for i in range(3) if i != axis]
        for loop in face.loops:
            co = loop.vert.co
            loop[layer].uv = (co[axes[0]] * scale, co[axes[1]] * scale)
    return bm


def ensure_uv(bm, scale=1.0):
    """Give a mesh a UV layer if it has none.

    A swept mesh gets the along/across UVs of the sweep (metres), everything
    else a planar projection. A mesh that already has UVs (the soffit strips)
    keeps them: their v coordinate carries the shader's own layout.
    """
    if bm.loops.layers.uv.get("UVMap") is not None:
        return bm
    if bm.verts.layers.float.get("along") is not None:
        return uv_from_attributes(bm)
    return uv_planar(bm, scale)


def sweep(bm, profile, path, closed_profile=True, offset=0.0):  # noqa: D401
    """Sweep a 2D profile along a path with a global-distance offset (for tapers)."""
    if callable(profile):
        prof = lambda i, a: profile(i, a + offset)  # noqa: E731
    else:
        prof = profile
    sub = geo.sweep(prof, path, closed_profile=closed_profile)
    me = bpy.data.meshes.new("tmp_sweep")
    sub.to_mesh(me)
    sub.free()
    bm.from_mesh(me)
    bpy.data.meshes.remove(me)
    return bm


def face_up(bm):
    """Make every face of a flat-ish surface point up.

    A triangle fan has no winding of its own, and recalc_face_normals may pick
    the downward direction: the surface would then be invisible from above and
    its one-sided collider would not catch a car.
    """
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    total = 0.0
    for f in bm.faces:
        total += f.normal.z
    if total < 0.0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    return bm


def clip_rect(poly, x0, x1, y0, y1):
    """Clip a 2D polygon to an axis-aligned rectangle (Sutherland-Hodgman).

    The pieces of a polygon that is cut into a grid of rectangles tile the
    original exactly: the neighbours meet on the border and no gap is left.
    """
    edges = (("x", x0, True), ("x", x1, False), ("y", y0, True), ("y", y1, False))
    out = list(poly)
    for (axis, value, keep_greater) in edges:
        if not out:
            return []
        result = []
        for i, cur in enumerate(out):
            nxt = out[(i + 1) % len(out)]
            c = cur[0] if axis == "x" else cur[1]
            n = nxt[0] if axis == "x" else nxt[1]
            inside_c = c >= value if keep_greater else c <= value
            inside_n = n >= value if keep_greater else n <= value
            if inside_c:
                result.append(cur)
            if inside_c != inside_n:
                t = (value - c) / (n - c) if abs(n - c) > 1e-12 else 0.0
                result.append((cur[0] + (nxt[0] - cur[0]) * t,
                               cur[1] + (nxt[1] - cur[1]) * t))
        out = result
    return out


def barycentric(tri, point):
    """The (u, v) weights of a point in a triangle (a, b, c) in the XY plane."""
    (ax, ay), (bx, by), (cx, cy) = tri
    px, py = point
    den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
    if abs(den) < 1e-12:
        return (0.0, 0.0)
    u = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
    v = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
    return (u, v)


def merge(target, source):
    """Merge a bmesh into another bmesh (BMesh.from_mesh only takes a Mesh)."""
    if len(source.verts) == 0:
        source.free()
        return target
    me = bpy.data.meshes.new("tmp_merge")
    source.to_mesh(me)
    target.from_mesh(me)
    bpy.data.meshes.remove(me)
    source.free()
    return target


def box(bm, centre, size, rot_z=0.0):
    """Axis box (optionally rotated about Z) added to an existing bmesh."""
    return geo.box(bm, centre, size, rot_z)


def quad_strip_poly(bm, poly, z=0.0):
    """Add a flat n-gon face (the polygon must be convex or near-convex) at height z."""
    verts = [bm.verts.new((p[0], p[1], z)) for p in poly]
    return bm.faces.new(verts)


SURFACE_TYPES = {
    "SH_wet_asphalt": "asphalt",
    "SH_road_marking_white": "paint",
    "SH_road_marking_yellow": "paint",
    "Road_Steel_Girder": "steel",
    "Road_Expansion_Joint": "steel",
    "Road_Tunnel_Enamel": "concrete",
    "Road_Tunnel_Dark": "concrete",
    "Road_Tunnel_Stripe": "paint",
}


class Builder:
    """Accumulates geometry per material for one tile, then emits one object per material."""

    def __init__(self):
        self.groups = {}
        self.named = {}
        self.named_meta = {}
        self.objects = []
        self.props = {}

    def add(self, material, bm):
        """Merge a bmesh into the group for `material`."""
        if bm is None or len(bm.verts) == 0:
            bm.free()
            return
        ensure_uv(bm)
        if material not in self.groups:
            self.groups[material] = bmesh.new()
        merge(self.groups[material], bm)

    def add_named(self, name, bm, material=None, surface="concrete", props=None, origin=None):
        """Merge a bmesh into a named group (emitted with this exact object name).

        `props` are written into the object's extras (the world unit reads the
        visibility range from them) and `origin` moves the object's origin to
        that point, so a distance range is measured from there and not from the
        world origin.
        """
        if bm is None or len(bm.verts) == 0:
            bm.free()
            return
        if not name.endswith("-colonly"):
            # a collider is never seen: it does not need a texture
            ensure_uv(bm)
        if name not in self.named:
            self.named[name] = bmesh.new()
            self.named_meta[name] = {"material": material, "surface": surface,
                                     "props": dict(props or {}), "origin": origin}
        merge(self.named[name], bm)

    def add_object(self, name, obj, props=None):
        """Adopt a finished object (emitted verbatim into the tile)."""
        self.props[name] = dict(props or {})
        self.objects.append(obj)
        return obj

    def empty(self, name, location, direction=(0.0, 1.0, 0.0), props=None):
        """Marker empty (cable anchors, sign sockets) for the tile."""
        obj = common.empty(name, location, direction)
        for k, v in (props or {}).items():
            obj[k] = v
        return self.add_object(name, obj, props)

    def finish(self, col, prefix="tile"):
        """Create one mesh object per material group; returns the list of objects."""
        objects = list(self.objects)
        for name, group in self.groups.items():
            if len(group.verts) == 0:
                group.free()
                continue
            obj = common.mesh_object("%s_%s" % (prefix, name), group, col)
            mat = bpy.data.materials.get(name)
            if mat is not None:
                obj.data.materials.append(mat)
            obj["surface"] = SURFACE_TYPES.get(name, "concrete")
            objects.append(obj)
        for name, group in self.named.items():
            if len(group.verts) == 0:
                group.free()
                continue
            meta = self.named_meta.get(name, {})
            origin = meta.get("origin")
            if origin is not None:
                # the object's origin is the centre of its chunk: the visibility
                # range is measured from there, not from the world origin. The
                # mesh keeps the world position, so the offset has to be baked
                # into the bmesh before it becomes a mesh.
                for v in group.verts:
                    v.co -= origin
            obj = common.mesh_object("%s_%s" % (prefix, name), group, col)
            mat = bpy.data.materials.get(meta.get("material") or "")
            if mat is not None:
                obj.data.materials.append(mat)
            obj["surface"] = meta.get("surface", "concrete")
            for k, v in (meta.get("props") or {}).items():
                obj[k] = v
            if origin is not None:
                obj.location = origin
            objects.append(obj)
        self.groups = {}
        self.named = {}
        self.named_meta = {}
        self.objects = []
        return objects
