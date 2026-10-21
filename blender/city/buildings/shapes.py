"""Geometry helpers for the city block builder (city space in, Blender bmesh out).

City space is the data/city frame: X east, Z south, Y up (Godot).  Blender is Z up,
+Y forward, so a city point (x, z) becomes Blender (x, -z, h).
"""
import math

import bmesh
from mathutils import Vector


def to_blender(x, z, h=0.0):
    """City (x, z, height) -> Blender (x, -z, height)."""
    return Vector((x, -z, h))


def dir_to_blender(x, z):
    """City direction -> Blender direction (x, -z)."""
    return Vector((x, -z, 0.0))


def face_normal(face):
    """The outward normal of a face, computed from its winding (Newell).

    bmesh does not compute a normal for a face until `bm.normal_update()` is called,
    so `face.normal` of a freshly created face is (0, 0, 0).  Every read of a normal
    in this builder used that zero vector: the prism sides kept their creation
    winding (which comes out inward), and the UV projection always picked axis 0, so
    84 % of the textured area had zero-area UVs.  The Newell normal is exact and
    costs nothing.
    """
    loops = face.loops
    m = len(loops)
    if m == 0:
        return Vector((0.0, 0.0, 0.0))
    n = Vector((0.0, 0.0, 0.0))
    for i in range(m):
        a = loops[i].vert.co
        b = loops[(i + 1) % m].vert.co
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    if n.length < 1e-12:
        return n
    return n.normalized()


def ensure_normal(faces, expected):
    """Flip the winding of faces so their normal points along `expected` (a Vector)."""
    for f in faces:
        n = face_normal(f)
        if n.length < 1e-9:
            continue
        if n.dot(expected) < 0.0:
            f.normal_flip()
    return faces


def poly_centroid(poly):
    n = len(poly)
    return (sum(p[0] for p in poly) / n, sum(p[1] for p in poly) / n)


def signed_area(poly_xz):
    """The signed area of a city-space polygon; positive = counter-clockwise in (x, z)."""
    total = 0.0
    n = len(poly_xz)
    for i in range(n):
        ax, az = poly_xz[i]
        bx, bz = poly_xz[(i + 1) % n]
        total += ax * bz - bx * az
    return total * 0.5


def edge_outward(poly_xz, i, ccw):
    """The outward normal of edge i of a city polygon (unit, city space)."""
    n = len(poly_xz)
    ax, az = poly_xz[i]
    bx, bz = poly_xz[(i + 1) % n]
    dx, dz = bx - ax, bz - az
    length = math.hypot(dx, dz)
    if length < 1e-9:
        return None
    if ccw:
        return (dz / length, -dx / length)
    return (-dz / length, dx / length)


def add_prism(bm, poly_xz, h0, h1, cap=True, cap_bottom=True):
    """Extrude a city-space polygon [(x, z), ...] between two heights. Returns the side faces.

    The side faces are wound OUTWARD.  The city frame (x east, z south) is left-handed
    once z is negated into Blender's y, so a polygon that is counter-clockwise in (x, z)
    has to be reversed to get an outward normal: the outward normal of the edge
    (dx, dz) is (dz, -dx) for a counter-clockwise ring and (-dz, dx) for a clockwise
    one.  The signed area decides which case a polygon is - that works for concave and
    L-shaped footprints too, where the centroid test was wrong.
    """
    pts = [to_blender(x, z, h0) for x, z in poly_xz]
    n = len(pts)
    verts = [bm.verts.new(p) for p in pts]
    top = [bm.verts.new(to_blender(x, z, h1)) for x, z in poly_xz]
    ccw = signed_area(poly_xz) > 0.0
    faces = []
    for i in range(n):
        j = (i + 1) % n
        if ccw:
            # counter-clockwise in (x, z): the outward winding is lower -> upper -> next
            faces.append(bm.faces.new((verts[i], top[i], top[j], verts[j])))
        else:
            faces.append(bm.faces.new((verts[i], verts[j], top[j], top[i])))
    for i in range(n):
        out = edge_outward(poly_xz, i, ccw)
        if out is None:
            continue
        ensure_normal([faces[i]], Vector((out[0], -out[1], 0.0)))
    if cap:
        if ccw:
            topf = bm.faces.new(list(reversed(top)))
        else:
            topf = bm.faces.new(top)
        ensure_normal([topf], Vector((0.0, 0.0, 1.0)))
        if cap_bottom:
            if ccw:
                bottom = bm.faces.new(verts)
            else:
                bottom = bm.faces.new(list(reversed(verts)))
            ensure_normal([bottom], Vector((0.0, 0.0, -1.0)))
    return faces


def add_box(bm, center_xz, size_xz, h0, h1, rot_deg=0.0):
    """Axis box in city space; `size_xz` = (width, depth) in the box's own frame."""
    cx, cz = center_xz
    w, d = size_xz
    c = math.cos(math.radians(rot_deg))
    s = math.sin(math.radians(rot_deg))
    poly = []
    for dx, dz in ((-w * 0.5, -d * 0.5), (w * 0.5, -d * 0.5), (w * 0.5, d * 0.5), (-w * 0.5, d * 0.5)):
        poly.append((cx + dx * c - dz * s, cz + dx * s + dz * c))
    return add_prism(bm, poly, h0, h1)


def add_ground_quad(bm, poly_xz, h):
    """A flat horizontal quad at the height `h` (the ground cover of a block).

    A slab per paving tile was a fifth of the geometry of the city; the ground is
    never seen from the side, so one quad is enough.
    """
    pts = [bm.verts.new(to_blender(x, z, h)) for x, z in poly_xz]
    face = bm.faces.new(pts)
    ensure_normal([face], Vector((0.0, 0.0, 1.0)))
    return face


def set_uvs(bm, face, vert_uvs):
    """Assign UVs to a face by vertex, so a later winding flip cannot mirror them."""
    uv_layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
    for loop in face.loops:
        u = vert_uvs.get(loop.vert)
        if u is not None:
            loop[uv_layer].uv = u
    return face


def add_quad(bm, corners, uvs=None, flip=False):
    """One quad from 4 city-space (x, z, h) corners. `uvs` = 4 (u, v) pairs for atlas faces."""
    verts = [bm.verts.new(to_blender(*c)) for c in corners]
    face = bm.faces.new(tuple(reversed(verts)) if flip else tuple(verts))
    if uvs is not None:
        set_uvs(bm, face, dict(zip(verts, uvs)))
    return face


def add_uv_box(bm, center_xz, size_xz, h0, h1, rot_deg=0.0, uv_rect=(0.0, 0.0, 1.0, 1.0)):
    """A box whose faces are all mapped to a rectangle of an atlas (the prop sheet)."""
    cx, cz = center_xz
    w, d = size_xz
    c = math.cos(math.radians(rot_deg))
    s = math.sin(math.radians(rot_deg))
    corners = []
    for dx, dz in ((-w * 0.5, -d * 0.5), (w * 0.5, -d * 0.5), (w * 0.5, d * 0.5),
                   (-w * 0.5, d * 0.5)):
        corners.append((cx + dx * c - dz * s, cz + dx * s + dz * c))
    lower = [bm.verts.new(to_blender(x, z, h0)) for x, z in corners]
    upper = [bm.verts.new(to_blender(x, z, h1)) for x, z in corners]
    u0, v0, u1, v1 = uv_rect
    quad_uv = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    ccw = signed_area(corners) > 0.0
    faces = []
    face_uvs = []
    for i in range(4):
        j = (i + 1) % 4
        if ccw:
            faces.append(bm.faces.new((lower[i], upper[i], upper[j], lower[j])))
        else:
            faces.append(bm.faces.new((lower[i], lower[j], upper[j], upper[i])))
        # the UVs follow the vertex, not the loop order: a flip cannot mirror them
        face_uvs.append({lower[i]: quad_uv[0], lower[j]: quad_uv[1],
                         upper[j]: quad_uv[2], upper[i]: quad_uv[3]})
    if ccw:
        faces.append(bm.faces.new(list(reversed(upper))))
        faces.append(bm.faces.new(lower))
    else:
        faces.append(bm.faces.new(upper))
        faces.append(bm.faces.new(list(reversed(lower))))
    cap_uv = {upper[k]: quad_uv[k] for k in range(4)}
    face_uvs.append(cap_uv)
    cap_uv = {lower[k]: quad_uv[k] for k in range(4)}
    face_uvs.append(cap_uv)
    for f, uvs in zip(faces, face_uvs):
        set_uvs(bm, f, uvs)
    return faces


def wall_tangent(normal):
    """Tangent along a wall, pointing to the viewer's right when facing the wall."""
    nx, nz = normal
    return (nz, -nx)


def add_wall_quad(bm, base, normal, length, h0, h1, u0=0.0, u1=None, uv=None):
    """Vertical wall quad. `base` = city (x, z) of the left edge; runs `length` along the wall
    tangent; `u0`/`u1` clip it. The face normal points along `normal` (out of the wall)."""
    t = wall_tangent(normal)
    if u1 is None:
        u1 = length
    corners = []
    for a, h in ((u0, h0), (u1, h0), (u1, h1), (u0, h1)):
        corners.append((base[0] + t[0] * a, base[1] + t[1] * a, h))
    face = add_quad(bm, corners, uv)
    ensure_normal([face], Vector((normal[0], -normal[1], 0.0)))
    return face


def add_wall_panel(bm, base, normal, length, h0, h1, uv=None):
    """Alias kept for readability at call sites."""
    return add_wall_quad(bm, base, normal, length, h0, h1, uv=uv)


def add_gable_roof(bm, poly_xz, h_eave, h_ridge, ridge_edge=0, overhang=0.35):
    """Pitched roof over an arbitrary (rotated) rectangle. The ridge runs parallel to the
    edge `ridge_edge`; the two slopes fall away towards the opposite edges."""
    cx, cz = poly_centroid(poly_xz)
    ring = []
    for x, z in poly_xz:
        dx, dz = x - cx, z - cz
        d = math.hypot(dx, dz)
        if d < 1e-6:
            ring.append((x, z))
        else:
            ring.append((x + dx / d * overhang, z + dz / d * overhang))
    p = [ring[(ridge_edge + i) % 4] for i in range(4)]
    a0, a1, a2, a3 = p
    m_a = ((a3[0] + a0[0]) * 0.5, (a3[1] + a0[1]) * 0.5)
    m_b = ((a1[0] + a2[0]) * 0.5, (a1[1] + a2[1]) * 0.5)
    va = [bm.verts.new(to_blender(x, z, h)) for x, z, h in
          ((a0[0], a0[1], h_eave), (a1[0], a1[1], h_eave), (m_b[0], m_b[1], h_ridge),
           (m_a[0], m_a[1], h_ridge))]
    vb = [bm.verts.new(to_blender(x, z, h)) for x, z, h in
          ((a2[0], a2[1], h_eave), (a3[0], a3[1], h_eave), (m_a[0], m_a[1], h_ridge),
           (m_b[0], m_b[1], h_ridge))]
    f1 = bm.faces.new(va)
    f2 = bm.faces.new(vb)
    # the two gable ends: the triangle over the edge a3-a0 and the one over a1-a2
    g1 = bm.faces.new((va[0], vb[1], va[3]))
    g2 = bm.faces.new((va[1], vb[0], vb[2]))
    c = Vector((cx, -cz, 0.0))
    ensure_normal([f1], (Vector((va[0].co.x, va[0].co.y, 0)) + Vector((va[2].co.x, va[2].co.y, 0))
                        - 2 * c).normalized())
    ensure_normal([f2], (Vector((vb[0].co.x, vb[0].co.y, 0)) + Vector((vb[2].co.x, vb[2].co.y, 0))
                        - 2 * c).normalized())
    ccw = signed_area(p) > 0.0
    for g, edge in ((g1, 3), (g2, 1)):
        out = edge_outward(p, edge, ccw)
        if out is not None:
            ensure_normal([g], Vector((out[0], -out[1], 0.0)))
    return [f1, f2, g1, g2]


def bm_extent(bm):
    """(min_xyz, max_xyz) of a bmesh in Blender space."""
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for v in bm.verts:
        for i in range(3):
            lo[i] = min(lo[i], v.co[i])
            hi[i] = max(hi[i], v.co[i])
    return lo, hi


def merge_into(dst, src):
    """Move all geometry of `src` into `dst` (src is freed)."""
    dst.from_mesh(src)
    src.free()
    return dst


def add_blob(bm, center_xz, h, radius, h_scale=1.0, subdivisions=1):
    """A low-poly blob (tree canopy) in city space."""
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    c = to_blender(center_xz[0], center_xz[1], h)
    for v in res["verts"]:
        v.co = Vector((c.x + v.co.x, c.y + v.co.y, c.z + v.co.z * h_scale))
    return res["verts"]
